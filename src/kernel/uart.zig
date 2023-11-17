const port_io = @import("./port_io.zig");
pub const uart_port_com1 = 0x3f8;

pub fn uart_initialize() void {
    port_io.outb(uart_port_com1 + 1, 0x00); // disable all interrupts
    port_io.outb(uart_port_com1 + 3, 0x80); // enable DLAB (set baud rate divisor)
    port_io.outb(uart_port_com1 + 0, 0x03); // set divisor to 3 (lo byte) 38400 baud
    port_io.outb(uart_port_com1 + 1, 0x00); //                  (hi byte)
    port_io.outb(uart_port_com1 + 3, 0x03); // 8 bits, no parity, one stop bit
    port_io.outb(uart_port_com1 + 2, 0xc7); // enable FIFO, clear them, wth 14-byte threshold
    port_io.outb(uart_port_com1 + 4, 0x0b); // IRQs enabled, RTS/DSR set
}

pub fn uart_is_transmit_buffer_empty() bool {
    return (port_io.inb(uart_port_com1 + 5) & 0x20) != 0;
}

pub fn uart_putchar(char: u8) void {
    while (!uart_is_transmit_buffer_empty()) {}
    port_io.outb(uart_port_com1, char);
}

pub fn uart_puts(str: []const u8) void {
    for (str) |char| {
        uart_putchar(char);
    }
}
