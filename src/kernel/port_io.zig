//! This is some really basic Port I/O stuff.
//! Kernels have access to various ports where they can read and write data.
//! For example, there is a keyboard port that is wired to the default PS/2
//! keyboard.

/// This function returns a byte it got as result from an input to a port.
pub fn inb(port: u16) u8 {
    // We do this using the assembly instruction "in".
    return asm volatile ("in %[port], %[ret]"
        // Our return value should be an 8bit unsigned integer and it should be
        // saved in the register "al".
        : [ret] "={al}" (-> u8),
          // The port is already specified in the function argument (so Zig
          // knows it is 16bit wide) and it should be in the register "dx".
        : [port] "{dx}" (port),
    );
}

/// This function puts a byte to a specific port.
pub fn outb(port: u16, val: u8) void {
    // So, again our assembly.
    asm volatile ("out %[val], %[port]"
        // No return value
        :
        // But two arguments
        : [val] "{al}" (val),
          [port] "{dx}" (port),
    );
}
