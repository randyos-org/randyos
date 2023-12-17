const boot_info = @import("./boot_info.zig");
const uart = @import("./uart.zig");

export fn kmain(kernel_boot_info: boot_info.KernelInfo) void {
    _ = kernel_boot_info;
    uart.uart_initialize();
    uart.uart_puts("\x1b[2J");
    uart.uart_puts("Hello World from kernel!\n");
    while (true) {}
}
