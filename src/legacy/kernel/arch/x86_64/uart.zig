//! UART (serial). Bytes written here go to the serial device, not the
//! screen -- our run script wires that to console stdio via QEMU's
//! `-serial mon:stdio`, so escape sequences can still clear the screen.

const std = @import("std");
const log = std.log.scoped(.uart);

const common = @import("common");
const Terminal = common.Terminal;

const port_io = @import("port_io.zig");

pub const com1_base = 0x3f8;
pub const data_port = com1_base;
pub const interrupt_enable_port = com1_base + 1;
pub const fifo_command_port = com1_base + 2;
pub const line_command_port = com1_base + 3;
pub const modem_command_port = com1_base + 4;
pub const line_status_port = com1_base + 5;
pub var uart_ready: bool = false;

/// disables all UART interrupts (we poll line status instead)
const interrupts_disabled: u8 = 0x00;
/// line_command_port bit 7 (DLAB): while set, data_port/+1 address the
/// baud divisor LSB/MSB instead of transmitting
const dlab_enable: u8 = 0x80;
/// baud divisor for 38400 (115200/3), LSB
const baud_38400_divisor_lsb: u8 = 0x03;
/// baud divisor for 38400, MSB (fits in one byte)
const baud_38400_divisor_msb: u8 = 0x00;
/// 8N1, DLAB clear
const line_config_8n1: u8 = 0x03;
/// enable FIFO, clear rx/tx FIFOs, 14-byte trigger level (irrelevant,
/// interrupts stay off, but wastes least controller-side work)
const fifo_enable_clear_14byte: u8 = 0xc7;
/// DTR + RTS asserted, OUT2 enabled (PC IRQ-line pin)
const modem_dtr_rts_out2: u8 = 0x0b;
/// line_status_port bit 5: transmitter holding register empty
const transmit_buffer_empty_bit: u8 = 0x20;

const bits_per_nibble = 4;
/// shift to reach the top nibble of a 64-bit value
const top_nibble_shift: u6 = 64 - bits_per_nibble;

pub fn uartInitialize() void {
    port_io.outb(interrupt_enable_port, interrupts_disabled);
    port_io.outb(line_command_port, dlab_enable);
    // DLAB lets us write the baud rate (38400) to data_port without printing
    port_io.outb(data_port, baud_38400_divisor_lsb);
    port_io.outb(data_port + 1, baud_38400_divisor_msb);
    port_io.outb(line_command_port, line_config_8n1);
    port_io.outb(fifo_command_port, fifo_enable_clear_14byte);
    port_io.outb(modem_command_port, modem_dtr_rts_out2);
    uart_ready = true;
}

/// Inlined: may be called thousands of times/sec, skip the stack frame
pub inline fn uart_is_transmit_buffer_empty() bool {
    return (port_io.inb(line_status_port) & transmit_buffer_empty_bit) != 0;
}

/// Inlined: may be called hundreds of times/sec
pub inline fn uart_putchar(char: u8) void {
    while (!uart_is_transmit_buffer_empty()) {}
    port_io.outb(data_port, char);
}

pub fn uartPuts(str: []const u8) void {
    for (str) |char| {
        uart_putchar(char);
    }
}

/// Zero-padded 64-bit hex, straight to COM1, no buffering/formatting/alloc.
/// Last-resort primitive for fault handlers where stack/heap/Terminal
/// state may be corrupted -- only touches hardware I/O ports.
pub fn uartPutHex(value: u64) void {
    const digits = "0123456789abcdef";
    var shift: u6 = top_nibble_shift;
    uartPuts("0x");
    while (true) {
        const nibble: u4 = @truncate((value >> shift) & 0xf);
        uart_putchar(digits[nibble]);
        if (shift == 0) break;
        shift -= bits_per_nibble;
    }
}

pub fn uartTermInit(term: *Terminal, args: ?*const anyopaque) void {
    _ = args;
    if (!uart_ready) {
        uartInitialize();
    }
    if (uart_ready and !term.ready) {
        term.defaultInit(null);
    }
    term.ready = uart_ready;
}

pub fn uartTermPuts(term: *Terminal, s: []const u8) void {
    if (term.ready) {
        uartPuts(s);
    }
}

pub const UartVTable = Terminal.VTable{
    .puts = &uartTermPuts,
    .init = &uartTermInit,
};

pub var uart_term = Terminal{
    .vtable = &UartVTable,
    .supports_color = true,
};
