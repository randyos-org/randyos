//! This is some really basic Port I/O stuff.
//! Kernels have access to various ports where they can read and write data.
//! For example, there is a keyboard port that is wired to the default keyboard.

/// This function returns a byte it got as result from an input to a port.
pub fn inb(port: u16) u8 {
    // We do this using the assembly instruction "inb".
    return asm volatile ("inb %[port], %[ret]"
        // Our return value should be an 8bit unsigned integer and it should be saved in the register "al".
        : [ret] "={al}" (-> u8),
          // The port is already specified in the function argument (so Zig knows it is 16bit wide) and it should be in the register "dx".
        : [port] "{dx}" (port),
          // For this operation, we use the "dx" and "al" registers.
        : "dx", "al"
    );
}

/// This function puts a byte to a specific port.
pub fn outb(port: u16, val: u8) void {
    // So, again our assembly.
    asm volatile ("outb %[val], %[port]"
        // No return value
        :
        // But two arguments
        : [val] "{al}" (val),
          [port] "{dx}" (port),
          // And again, we use the "dx" and "al" registers.
        : "dx", "al"
    );
}
