//! Port I/O functionality
//! 2023 by Samuel Fiedler

/// Input bytes
pub fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[ret]"
        : [ret] "={al}" (-> u8),
        : [port] "{dx}" (port),
        : "dx", "al"
    );
}

/// Output bytes
pub fn outb(port: u16, val: u8) void {
    asm volatile ("outb %[val], %[port]"
        :
        : [val] "{al}" (val),
          [port] "{dx}" (port),
        : "dx", "al"
    );
}
