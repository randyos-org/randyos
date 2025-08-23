//! This is our main kernel
//! It is fairly minimal, but it is designed to be improved by *you*!

// This time, we import the built-in data structures (like a stack trace).
const builtin = @import("std").builtin;
// And we import the UART module for serial logging. If you want to know what
// this means, take a look at that file.
const uart = @import("./uart.zig");

/// This is our kernel main function.
/// As you may have seen in the linker script, it says "ENTRY(kmain)". We
/// export this function ("export fn"), so it is a public symbol that can be
/// included by the linker.
export fn kmain() void {
    // At the beginning, we initialize the UART service.
    uart.uart_initialize();
    // Then, we clear the screen of the UART target.
    uart.uart_puts("\x1b[2J");
    // And then, we put out a "Hello World!".
    uart.uart_puts("Hello World from kernel!\n");
    // Because the kernel should NEVER return somewhere, we have to loop
    // endlessly.
    while (true) {}
}

/// This function handles kernel panics, such as own panics (using "@panic()")
/// or safety panics (integer overflow or whatever).
pub fn panic(msg: []const u8, stack_trace: ?*builtin.StackTrace, return_address: ?usize) noreturn {
    // You can implement stack tracing if you want.
    _ = stack_trace;
    _ = return_address;
    // We just put out "Kernel Panic"…
    uart.uart_puts("\n !!! Kernel Panic !!! \n");
    // …then the message…
    uart.uart_puts(msg);
    // …and then a newline
    uart.uart_puts("\n");
    // And we hang.
    while (true) {}
}
