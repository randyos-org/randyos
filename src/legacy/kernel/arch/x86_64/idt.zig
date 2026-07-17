//! Interrupt Descriptor Table
//! 2024 by Samuel Fiedler

const std = @import("std");
const root = @import("root");
const log = std.log.scoped(.arch_idt);

const gdt = @import("gdt.zig");
const registers = @import("registers.zig");
const lapic = @import("lapic.zig");
const ioapic = @import("ioapic.zig");
const port_io = @import("port_io.zig");
const ps2 = @import("ps2.zig");
const uart = @import("uart.zig");

/// IDT slots: one per vector (0-255)
const idt_entry_count: usize = 256;

/// I/O APIC vector for PS/2 keyboard IRQ1 (irq 1 + offset 48 = 49, see
/// `ioapic.init` call in platform.zig)
const keyboard_vector: u64 = 49;

/// I/O APIC vector for legacy IRQ0 (PIT). Not the physical pin (MADT ISO
/// remaps IRQ0 to pin 2, see `ioapic.zig`'s `redEntryMADT`), but the
/// override still keys its vector off the original IRQ number (0 + 48 =
/// 48), so legacy-IRQ-keyed handlers work regardless of pin.
const timer_vector: u64 = 48;

/// Separate scope for `timer_vector` frame dumps so it can be silenced
/// independently (`arch_idt_frame` in `default_no_log_scopes`,
/// src/build/options.zig) -- at PIT tick rate this would otherwise flood
/// the terminal and starve the kernel.
const frame_log = std.log.scoped(.arch_idt_frame);

/// IDT entry
pub const Entry = packed struct(u128) {
    /// Handler ptr low
    offset_low: u16 = 0,
    /// Segment selector (e.g. gdt.Selector.kernel_code)
    selector: u16 = @intFromEnum(gdt.Selector.kernel_code),
    /// Offset into the IST (in the TSS)
    ist: u3 = 0,
    /// Reserved
    res1: u5 = 0,
    /// Gate type
    gate_type: enum(u4) {
        interrupt_64bit = 14,
        trap_64bit = 15,
        _,
    } = .interrupt_64bit,
    /// Reserved
    res2: u1 = 0,
    /// Privilege levels allowed to invoke this interrupt
    dpl: enum(u2) {
        kernel = 0,
        user = 3,
        _,
    } = .kernel,
    /// Present bit; must be set for a valid descriptor
    p: bool = true,
    /// Handler ptr high
    offset_high: u48 = 0,
    /// Reserved
    res3: u32 = 0,

    /// Get offset
    pub fn getOffset(self: Entry) u64 {
        return (@as(u64, self.offset_high) << 16) | self.offset_low;
    }

    /// Set offset
    pub fn setOffset(self: *Entry, offset: u64) void {
        self.offset_low = @truncate(offset);
        self.offset_high = @truncate(offset >> 16);
    }
};

/// IDT descriptor
pub const Descriptor = packed struct(u80) {
    /// IDT byte length - 1
    size: u16,
    /// Offset
    offset: u64,
};

pub const InterruptFunction = *const fn () callconv(.naked) noreturn;

pub var global_idt: [idt_entry_count]Entry = @splat(.{});
pub var descriptor: Descriptor = .{ .size = @sizeOf(@TypeOf(global_idt)) - 1, .offset = undefined };
pub var got_interrupt: bool = false;

/// Init IDT
pub fn init() void {
    log.info("IDT initialization...", .{});
    descriptor.offset = @intFromPtr(&global_idt);
    // build idt generically
    inline for (0..idt_entry_count - 1) |i| {
        if (getVector(i)) |vector| {
            switch (Exception.is(i)) {
                true => {
                    global_idt[i] = .{ .gate_type = .trap_64bit };
                    global_idt[i].setOffset(@intFromPtr(vector));
                },
                else => {
                    global_idt[i] = .{ .gate_type = .interrupt_64bit };
                    global_idt[i].setOffset(@intFromPtr(vector));
                },
            }
            if (usesTrapStack(i)) {
                global_idt[i].ist = @truncate(gdt.getISTVec());
            }
        } else {
            global_idt[i].p = false;
        }
    }
    asm volatile ("lidt (%[addr])"
        :
        : [addr] "{rax}" (&descriptor),
    );
    asm volatile ("sti");
    log.info("IDT initialization successful! ", .{});
}

/// Generic interrupt caller
pub fn getVector(comptime number: u8) ?InterruptFunction {
    return switch (number) {
        // vectors 15, 22-31 are Intel-reserved; leave entries absent
        inline 15, 22...31 => null,
        else => blk: {
            break :blk struct {
                fn vector() callconv(.naked) noreturn {
                    const is_exception = Exception.is(number);
                    if (is_exception and @as(Exception, @enumFromInt(number)).hasErrorCode()) {
                        asm volatile (
                            \\push %[num]
                            \\jmp interruptCommon
                            :
                            : [num] "{rax}" (@as(u64, number)),
                        );
                    } else {
                        asm volatile (
                            \\push $0
                            \\push %[num]
                            \\jmp interruptCommon
                            :
                            : [num] "{rax}" (@as(u64, number)),
                        );
                    }
                }
            }.vector;
        },
    };
}

/// Interrupt frame
pub const InterruptFrame = extern struct {
    /// ES; pushed as full zero-extended 8-byte slot (not `gdt.Selector`'s
    /// 2-byte width) -- must stay `u64` or fields below misalign
    es: u64,
    /// DS (see `es` for why `u64`)
    ds: u64,
    r15: u64,
    r14: u64,
    r13: u64,
    r12: u64,
    r11: u64,
    r10: u64,
    r9: u64,
    r8: u64,
    /// string-op dest index
    rdi: u64,
    /// string-op src index
    rsi: u64,
    /// base pointer (stack frames)
    rbp: u64,
    rdx: u64,
    rcx: u64,
    rbx: u64,
    rax: u64,
    vector_number: u64,
    error_code: u64,
    rip: u64,
    /// CS; hw-pushed as full 8-byte slot in long mode (see `es`)
    cs: u64,
    rflags: registers.RFLAGS,
    rsp: u64,
    /// SS (see `cs` for why `u64`)
    ss: u64,
};

/// Common interrupt entry; call after pushing error code + vector number
export fn interruptCommon() callconv(.naked) void {
    asm volatile (
    // push GP regs
        \\push %%rax
        \\push %%rbx
        \\push %%rcx
        \\push %%rdx
        \\push %%rbp
        \\push %%rsi
        \\push %%rdi
        \\push %%r8
        \\push %%r9
        \\push %%r10
        \\push %%r11
        \\push %%r12
        \\push %%r13
        \\push %%r14
        \\push %%r15
        // push seg regs
        \\mov %%ds, %%rax
        \\push %%rax
        \\mov %%es, %%rax
        \\push %%rax
        \\mov %%rsp, %%rdi
        // switch to kernel data seg; not pushed, no pop needed
        \\mov %[kernel_data], %%ax
        \\mov %%ax, %%es
        \\mov %%ax, %%ds
        \\call interruptHandler
        // pop seg regs
        \\pop %%rax
        \\mov %%rax, %%es
        \\pop %%rax
        \\mov %%rax, %%ds
        // pop GP regs
        \\pop %%r15
        \\pop %%r14
        \\pop %%r13
        \\pop %%r12
        \\pop %%r11
        \\pop %%r10
        \\pop %%r9
        \\pop %%r8
        \\pop %%rdi
        \\pop %%rsi
        \\pop %%rbp
        \\pop %%rdx
        \\pop %%rcx
        \\pop %%rbx
        \\pop %%rax
        // pop error code
        \\add $16, %%rsp
        // return
        \\iretq
        :
        : [kernel_data] "i" (gdt.Selector.kernel_data),
    );
}

/// Exceptions
pub const Exception = enum(u8) {
    /// Divide Error
    DE = 0,
    /// Debug Exception
    DB = 1,
    /// Breakpoint
    BP = 3,
    /// Overflow
    OF = 4,
    /// BOUND Range Exceeded
    BR = 5,
    /// Invalid Opcode
    UD = 6,
    /// Device Not Available
    NM = 7,
    /// Double Fault
    DF = 8,
    /// Coprocessor Segment Overrun
    RES = 9,
    /// Invalid TSS
    TS = 10,
    /// Segment Not Present
    NP = 11,
    /// Stack-Segment Fault
    SS = 12,
    /// General Protection
    GP = 13,
    /// Page Fault
    PF = 14,
    /// x87 FP Error
    MF = 16,
    /// Alignment Check
    AC = 17,
    /// Machine Check
    MC = 18,
    /// SIMD Floating-Point Exception
    XM = 19,
    /// Virtualization Exception
    VE = 20,
    /// Control Protection Exception
    CP = 21,

    /// is interrupt an exception?
    pub inline fn is(interrupt: u8) bool {
        return switch (interrupt) {
            0, 1, 3...14, 15...21 => true,
            else => false,
        };
    }

    /// has error code?
    pub inline fn hasErrorCode(self: Exception) bool {
        return switch (self) {
            .DF, .TS, .NP, .SS, .GP, .PF, .AC, .CP => true,
            else => false,
        };
    }
};

/// Exceptions that must run on the dedicated trap stack (IST1) since they
/// can fire on an already-broken stack; without this, entering the handler
/// re-faults on the same stack, cascading to a silent triple-fault reboot.
fn usesTrapStack(number: u8) bool {
    return switch (number) {
        @intFromEnum(Exception.SS), @intFromEnum(Exception.GP), @intFromEnum(Exception.PF), @intFromEnum(Exception.DF) => true,
        else => false,
    };
}

/// Last-resort fault reporter: raw UART writes, bypassing std.log/Terminal
/// and any alloc/formatting that the fault itself may have broken. Always
/// called before the nicer-but-less-trustworthy logging below.
fn emergencyReport(frame: *const InterruptFrame) void {
    uart.uartPuts("\r\n!!! EMERGENCY FAULT REPORT (raw UART) !!!\r\nvector = ");
    uart.uartPutHex(frame.vector_number);
    uart.uartPuts("  err = ");
    uart.uartPutHex(frame.error_code);
    uart.uartPuts("\r\nrip = ");
    uart.uartPutHex(frame.rip);
    uart.uartPuts("  rsp = ");
    uart.uartPutHex(frame.rsp);
    uart.uartPuts("  rbp = ");
    uart.uartPutHex(frame.rbp);
    uart.uartPuts("\r\ncr2 = ");
    uart.uartPutHex(@as(u64, @bitCast(registers.CR2.get())));
    uart.uartPuts("  cr3 = ");
    uart.uartPutHex(@as(u64, @bitCast(registers.CR3.get())));
    uart.uartPuts("\r\n");
}

export fn interruptHandler(frame: *InterruptFrame) void {
    switch (frame.vector_number) {
        0, 1, 3...14, 16...21 => {
            emergencyReport(frame);
            log.err("except = {s}", .{@tagName(@as(Exception, @enumFromInt(frame.vector_number)))});
            log.err("num = 0x{x:0>2}   err = 0x{x:0>16}", .{ frame.vector_number, frame.error_code });
            log.err("rax = 0x{x:0>16}   rbx = 0x{x:0>16}   rcx = 0x{x:0>16}   rdx = 0x{x:0>16}", .{
                frame.rax,
                frame.rbx,
                frame.rcx,
                frame.rdx,
            });
            log.err("rip = 0x{x:0>16}   rsp = 0x{x:0>16}   rbp = 0x{x:0>16}", .{ frame.rip, frame.rsp, frame.rbp });
            log.err("cr0 = 0x{x:0>16}   cr2 = 0x{x:0>16}   cr3 = 0x{x:0>16}   cr4 = 0x{x:0>16}", .{
                @as(usize, @bitCast(registers.CR0.get())),
                @as(usize, @bitCast(registers.CR2.get())),
                @as(usize, @bitCast(registers.CR3.get())),
                @as(usize, @bitCast(registers.CR4.get())),
            });
            @panic("reached unhandled error");
        },
        // IRQ1 (keyboard) via I/O APIC offset 48 (see ioapic.init in platform.zig)
        keyboard_vector => ps2.keyboardHandler(),
        // Legacy IRQ0 (PIT). Ticks unused (TSC does timekeeping, see
        // tsc.zig), but still needs EOI each fire or LAPIC blocks every
        // same-or-lower-priority interrupt behind it (silently broke
        // keyboard input before this case existed).
        timer_vector => {
            frame_log.debug("Frame contents: {}", .{frame});
            lapic.eoi();
        },
        else => {
            // unanticipated vector; worth noticing, unlike timer's expected ticks
            log.warn("unhandled interrupt vector {}", .{frame.vector_number});
            log.debug("Frame contents: {}", .{frame});
            // must EOI, same reasoning as timer_vector
            lapic.eoi();
        },
    }
}
