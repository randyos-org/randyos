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
const uart = @import("../../terminal/uart.zig");

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
pub var global_idt: [256]Entry = @splat(.{});
pub var descriptor: Descriptor = .{ .size = @sizeOf(@TypeOf(global_idt)) - 1, .offset = undefined };
pub var got_interrupt: bool = false;

/// Initialize the IDT
pub fn init() void {
    log.info("IDT initialization...", .{});
    // make descriptor point to global idt
    descriptor.offset = @intFromPtr(&global_idt);
    // construct the gdt generically
    inline for (0..255) |i| {
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
        49 => ps2.keyboardHandler(),
        else => {
            log.debug("Frame contents: {}", .{frame});
        },
    }
}
