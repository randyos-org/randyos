//! Simple Kernel
//! 2023 by Samuel Fiedler

const builtin = @import("std").builtin;
const boot_info = @import("boot_info");
const uart = @import("./uart.zig");

/// The kernel main function
export fn kmain(kernel_boot_info: boot_info.KernelBootInfo) void {
    // discard the boot info
    _ = kernel_boot_info;
    // initialize the UART service
    uart.uart_initialize();
    // clear the screen
    uart.uart_puts("\x1b[2J");
    // put out something
    uart.uart_puts("Hello World from kernel!\n");
    // do some panics
    // @panic("Test Panic");
    // hang
    while (true) {}
}

/// Handle kernel panics
pub fn panic(msg: []const u8, stack_trace: ?*builtin.StackTrace, return_address: ?usize) noreturn {
    _ = stack_trace;
    _ = return_address;
    uart.uart_puts("\n !!! Kernel Panic !!! \n");
    uart.uart_puts(msg);
    uart.uart_puts("\n");
    while (true) {}
}
