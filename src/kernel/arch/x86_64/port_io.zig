//! Port I/O functionality
//! 2024 by Samuel Fiedler

const std = @import("std");
const log = std.log.scoped(.arch_port_io);

/// POST diagnostic-code port. Unused for its original purpose on modern
/// hardware; writing to it costs one bus I/O cycle with no side effects,
/// which is the classic cheap delay for chips (e.g. the PIC) that need a
/// breather between commands -- see `ioWait`.
const post_diagnostic_port: u16 = 0x80;

/// Input bytes
pub inline fn inb(port: u16) u8 {
    return in(u8, port);
}

/// Output bytes
pub inline fn outb(port: u16, val: u8) void {
    out(u8, port, val);
}

/// Input 8bit-, 16bit- or 32bit-wide unsigned integers
pub inline fn in(comptime T: type, port: u16) T {
    return switch (T) {
        u8 => asm volatile ("inb %[port], %[ret]"
            : [ret] "={al}" (-> u8),
            : [port] "{dx}" (port),
        ),
        u16 => asm volatile ("inw %[port], %[ret]"
            : [ret] "{=ax}" (-> u16),
            : [port] "{dx}" (port),
        ),
        u32 => asm volatile ("inl %[port], %[ret]"
            : [ret] "{=eax}" (-> u32),
            : [port] "{dx}" (port),
        ),
        else => @compileError("No port input instruction for that type"),
    };
}

/// Output 8bit-, 16bit- or 32bit-wide unsigned integers
pub inline fn out(comptime T: type, port: u16, val: T) void {
    switch (T) {
        u8 => asm volatile ("outb %[val], %[port]"
            :
            : [val] "{al}" (val),
              [port] "{dx}" (port),
        ),
        u16 => asm volatile ("outw %[val], %[port]"
            :
            : [val] "{ax}" (val),
              [port] "{dx}" (port),
        ),
        u32 => asm volatile ("outl %[val], %[port]"
            :
            : [val] "{eax}" (val),
              [port] "{dx}" (port),
        ),
        else => @compileError("No port output instruction for that type"),
    }
}

/// Wait a very small amount of time
pub inline fn ioWait() void {
    outb(post_diagnostic_port, 0);
}
