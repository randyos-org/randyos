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

/// Number of entries in an x86_64 IDT -- one slot per possible
/// interrupt/exception vector (0-255).
const idt_entry_count: usize = 256;

/// I/O APIC redirection vector the PS/2 keyboard's IRQ (1) lands on, given
/// the vector `offset` `ioapic.init` is called with in platform.zig
/// (`keyboard_irq` (1) + 48 = 49).
const keyboard_vector: u64 = 49;

/// I/O APIC redirection vector legacy IRQ0 (the PIT) lands on. Not the
/// pin the PIT is actually wired to -- the near-universal PC MADT
/// Interrupt Source Override remaps IRQ0 from I/O APIC pin 0 to pin 2 (see
/// `ioapic.zig`'s `redEntryMADT`) -- but that override computes its
/// *vector* from the original legacy IRQ number (`irq_src` (0) +
/// `ioapic_vector_offset` (48) = 48) precisely so legacy-IRQ-keyed
/// handlers like this one still work regardless of which physical pin the
/// override actually lands the interrupt on.
const timer_vector: u64 = 48;

/// Frame-dump logging for interrupts on `timer_vector` uses its own scope,
/// separate from this file's default `arch_idt` scope, so it can be
/// silenced independently (see the `arch_idt_frame` entry in
/// `default_no_log_scopes`, src/build/options.zig). At the PIT's real
/// tick rate this would otherwise flood the terminal and burn CPU time in
/// the render pipeline -- a frame dump isn't cheap to draw -- badly enough
/// to starve the rest of the kernel of forward progress.
const frame_log = std.log.scoped(.arch_idt_frame);

/// Entry in the Interrupt Descriptor Table
pub const Entry = packed struct(u128) {
    /// First part of a pointer to handler code
    offset_low: u16 = 0,
    /// Segment Selector (for example gdt.Selector.kernel_code)
    selector: u16 = @intFromEnum(gdt.Selector.kernel_code),
    /// A 3-bit value which is an offset into the Interrupt Stack Table, which is stored in the Task State Segment
    ist: u3 = 0,
    /// Reserved
    res1: u5 = 0,
    /// Gate Type
    gate_type: enum(u4) {
        interrupt_64bit = 14,
        trap_64bit = 15,
        _,
    } = .interrupt_64bit,
    /// Reserved
    res2: u1 = 0,
    /// CPU Privilege Levels allowed to access this interrupt
    dpl: enum(u2) {
        kernel = 0,
        user = 3,
        _,
    } = .kernel,
    /// Present bit
    /// Must be set for the descriptor to be valid
    p: bool = true,
    /// Second part of a pointer to handler code
    offset_high: u48 = 0,
    /// Reserved
    res3: u32 = 0,

    /// Get the offset
    pub fn getOffset(self: Entry) u64 {
        return (@as(u64, self.offset_high) << 16) | self.offset_low;
    }

    /// Set the offset
    pub fn setOffset(self: *Entry, offset: u64) void {
        self.offset_low = @truncate(offset);
        self.offset_high = @truncate(offset >> 16);
    }
};

/// IDT Descriptor
pub const Descriptor = packed struct(u80) {
    /// Size
    /// IDT Byte Length - 1
    size: u16,
    /// Offset
    offset: u64,
};

/// Interrupt Function Type
pub const InterruptFunction = *const fn () callconv(.naked) noreturn;

/// Global IDT
pub var global_idt: [idt_entry_count]Entry = @splat(.{});
pub var descriptor: Descriptor = .{ .size = @sizeOf(@TypeOf(global_idt)) - 1, .offset = undefined };
pub var got_interrupt: bool = false;

/// Initialize the IDT
pub fn init() void {
    log.info("IDT initialization...", .{});
    // make descriptor point to global idt
    descriptor.offset = @intFromPtr(&global_idt);
    // construct the idt generically
    inline for (0..idt_entry_count - 1) |i| {
        if (getVector(i)) |vector| {
            switch (Exception.is(i)) {
                true => {
                    // trap
                    global_idt[i] = .{ .gate_type = .trap_64bit };
                    global_idt[i].setOffset(@intFromPtr(vector));
                },
                else => {
                    // normal
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
    // load the idt
    asm volatile ("lidt (%[addr])"
        :
        : [addr] "{rax}" (&descriptor),
    );
    // enable interrupts
    asm volatile ("sti");
    log.info("IDT initialization successful! ", .{});
}

/// Generic Interrupt Caller
pub fn getVector(comptime number: u8) ?InterruptFunction {
    return switch (number) {
        // vectors 15 and 22-31 are Intel-reserved (no exception is defined
        // for them), so leave those IDT entries absent (not present)
        inline 15, 22...31 => null,
        else => blk: {
            // normal or trap
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

/// Interrupt Frame
pub const InterruptFrame = extern struct {
    /// Extra Segment Selector
    /// Pushed via "mov %%es, %%rax; push %%rax", so it occupies a full
    /// zero-extended 8-byte stack slot, not the 2-byte width of
    /// `gdt.Selector` -- must stay `u64` or every field below is misaligned.
    es: u64,
    /// Data Segment Selector (see `es` for why this is `u64`, not `gdt.Selector`)
    ds: u64,
    /// General purpose register R15
    r15: u64,
    /// General purpose register R14
    r14: u64,
    /// General purpose register R13
    r13: u64,
    /// General purpose register R12
    r12: u64,
    /// General purpose register R11
    r11: u64,
    /// General purpose register R10
    r10: u64,
    /// General purpose register R9
    r9: u64,
    /// General purpose register R8
    r8: u64,
    /// Destination index for string operations
    rdi: u64,
    /// Source index for string operations
    rsi: u64,
    /// Base Pointer (meant for stack frames)
    rbp: u64,
    /// Data (commonly extends the A register)
    rdx: u64,
    /// Counter
    rcx: u64,
    /// Base
    rbx: u64,
    /// Accumulator
    rax: u64,
    /// Interrupt Number
    vector_number: u64,
    /// Error code
    error_code: u64,
    /// Instruction Pointer
    rip: u64,
    /// Code Segment
    /// Pushed by hardware as a full 8-byte slot in long mode (see `es` above
    /// for why this is `u64`, not `gdt.Selector`)
    cs: u64,
    /// RFLAGS
    rflags: registers.RFLAGS,
    /// Stack Pointer
    rsp: u64,
    /// Stack Segment (see `cs` for why this is `u64`, not `gdt.Selector`)
    ss: u64,
};

/// Common interrupt calling code
/// Should be called after pushing the error code and the interrupt number
export fn interruptCommon() callconv(.naked) void {
    asm volatile (
    // push general-purpose registers
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
        // push segment registers
        \\mov %%ds, %%rax
        \\push %%rax
        \\mov %%es, %%rax
        \\push %%rax
        \\mov %%rsp, %%rdi
        // set segment to run in
        // does not push so we don't need to pop
        \\mov %[kernel_data], %%ax
        \\mov %%ax, %%es
        \\mov %%ax, %%ds
        \\call interruptHandler
        // pop segment registers
        \\pop %%rax
        \\mov %%rax, %%es
        \\pop %%rax
        \\mov %%rax, %%ds
        // pop general-purpose registers
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
    /// Invalid Opcode (Undefined Opcode)
    UD = 6,
    /// Device Not Available (No Math Coprocessor)
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
    /// x87 FPU Floating-Point Error (Math Fault)
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

    /// Is the given interrupt number an exception?
    pub inline fn is(interrupt: u8) bool {
        return switch (interrupt) {
            0, 1, 3...14, 15...21 => true,
            else => false,
        };
    }

    /// Has the exception an error code?
    pub inline fn hasErrorCode(self: Exception) bool {
        return switch (self) {
            .DF, .TS, .NP, .SS, .GP, .PF, .AC, .CP => true,
            else => false,
        };
    }
};

/// Exceptions that must always run on the dedicated trap stack (IST1),
/// since they can be triggered by a stack that's already overflowed or
/// otherwise corrupted. Without this, entering the handler would push the
/// exception frame onto that same broken stack and fault again, cascading
/// into a double fault and then a triple fault (a silent reboot) instead of
/// a diagnosable stop.
fn usesTrapStack(number: u8) bool {
    return switch (number) {
        @intFromEnum(Exception.SS), @intFromEnum(Exception.GP), @intFromEnum(Exception.PF), @intFromEnum(Exception.DF) => true,
        else => false,
    };
}

/// Last-resort fault reporter. Writes straight to the UART hardware ports,
/// bypassing `std.log`, the `Terminal`/framebuffer console abstraction, and
/// any formatting or allocation -- all of which could themselves be broken
/// by whatever caused the fault (a blown stack, corrupted heap, a clobbered
/// `Terminal` sitting on that stack, ...). Always called before attempting
/// the normal (nicer, but less trustworthy) logging path below.
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

/// Interrupt Handler
export fn interruptHandler(frame: *InterruptFrame) void {
    // specific interrupt handling
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
        // IRQ1 (keyboard) remapped through the I/O APIC at offset 48 (see
        // `ioapic.init` call in platform.zig)
        keyboard_vector => ps2.keyboardHandler(),
        // Legacy IRQ0 (PIT) -- see `timer_vector`'s doc comment for why it
        // lands here despite `ioapic.init` disabling every non-keyboard
        // pin by default. We don't consume ticks from it yet (this kernel
        // uses the TSC for timekeeping -- see `tsc.zig`), but it still has
        // to be acknowledged every time it fires: without an EOI, the
        // LAPIC's in-service state for this vector never clears, which
        // blocks delivery of every other same-or-lower-priority interrupt
        // behind it (that's what silently broke keyboard input before
        // this vector got its own case here).
        timer_vector => {
            frame_log.debug("Frame contents: {}", .{frame});
            lapic.eoi();
        },
        else => {
            // A genuinely unanticipated vector (not an exception, not the
            // keyboard, not the timer) -- stays on the default, non-quiet
            // scope since this shouldn't normally happen and is worth
            // noticing, unlike the timer's expected, high-frequency ticks.
            log.warn("unhandled interrupt vector {}", .{frame.vector_number});
            log.debug("Frame contents: {}", .{frame});
            // Same reasoning as `timer_vector`: must EOI or this vector
            // (and everything same-or-lower-priority behind it) stops
            // being delivered after the first occurrence.
            lapic.eoi();
        },
    }
}
