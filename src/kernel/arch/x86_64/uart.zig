//! This implements the UART (Universal Asynchronous Receiver-Transmitter)
//! functionality.
//! UART is a serial interface. So if we put out bytes here, they will not
//! appear on our screen, but instead on a serial device connected to our UART
//! port. Here, this is the console standard input / output (in our run script
//! we have the qemu command: "qemu-system-x86_64 [...] -serial mon:stdio"), so
//! we can use escape sequences to clear the screen.

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

/// `interrupt_enable_port` value that disables all UART interrupts (we poll
/// the line status register instead).
const interrupts_disabled: u8 = 0x00;
/// `line_command_port` bit 7 (DLAB): while set, `data_port`/`data_port + 1`
/// address the baud rate divisor's LSB/MSB instead of transmitting data.
const dlab_enable: u8 = 0x80;
/// Baud rate divisor for 38400 baud (115200 / 3), LSB.
const baud_38400_divisor_lsb: u8 = 0x03;
/// Baud rate divisor for 38400 baud, MSB (0 -- the divisor fits in one byte).
const baud_38400_divisor_msb: u8 = 0x00;
/// `line_command_port` value for 8 data bits, no parity, 1 stop bit (8N1),
/// with DLAB clear (back to normal data-port behavior).
const line_config_8n1: u8 = 0x03;
/// `fifo_command_port` value: enable FIFO buffers, clear the receive and
/// transmit FIFOs, 14-byte interrupt trigger level (irrelevant here since
/// interrupts stay disabled, but the maximum threshold wastes the least
/// controller-side computation).
const fifo_enable_clear_14byte: u8 = 0xc7;
/// `modem_command_port` value: DTR and RTS asserted, OUT2 enabled (the
/// hardware pin PC platforms wire to the IRQ line).
const modem_dtr_rts_out2: u8 = 0x0b;
/// `line_status_port` bit 5: Transmitter Holding Register Empty.
const transmit_buffer_empty_bit: u8 = 0x20;

/// Bits per hex digit.
const bits_per_nibble = 4;
/// Shift to reach the topmost nibble of a 64-bit value.
const top_nibble_shift: u6 = 64 - bits_per_nibble;

/// This is how to initialize the UART device.
pub fn uartInitialize() void {
    port_io.outb(interrupt_enable_port, interrupts_disabled);
    port_io.outb(line_command_port, dlab_enable);
    // DLAB enables us to send data to the data port without printing,
    // which we use now to set the baud rate (38400)
    port_io.outb(data_port, baud_38400_divisor_lsb);
    port_io.outb(data_port + 1, baud_38400_divisor_msb);
    port_io.outb(line_command_port, line_config_8n1);
    // Using this, we set some things in the FIFO (First In First Out) Control
    // register:
    //   - the first bit enables FIFO buffers
    //   - the second bit clears the receive FIFO buffer
    //   - the third bit clears the transmit FIFO buffer
    //     - Those both bits will clear them by themselves after they cleared
    //       their FIFO buffer
    //   - the fourth bit is not used by me
    //   - the fifth and sixth bit is reserved
    //   - the seventh and eighth bit sets the interrupt trigger level (which
    //     specifies how much data must be received in the FIFO receive buffer
    //     before triggering a Received Data Available Interrupt). We want this
    //     to be the maximum as we don't want any interrupts (which we just
    //     disabled), so the least possible computation even on the UART
    //     controller is wasted.
    port_io.outb(fifo_command_port, fifo_enable_clear_14byte);
    // This sets some bits in the Modem Control Register.
    //   - the first bit controls the Data Terminal Ready pin
    //   - the second bit controls the Request to Send pin
    //   - the third bit is unused in PC implementations
    //   - the fourth bit controls a hardware pin which is used to enable the
    //     IRQ in PC implementations.
    //   - the fifth bit provides a local loopback feature for diagnostic
    //     testing of the UART
    //   - the sixth to eighth bytes are unused
    port_io.outb(modem_command_port, modem_dtr_rts_out2);
    uart_ready = true;
}

/// Check whether the transmit buffer is empty or not
/// This function is inlined because it may get called thousand times per
/// second, so we don't need a stack frame for each call.
pub inline fn uart_is_transmit_buffer_empty() bool {
    // We ask the line status register and if the sixth bit (Transmitter
    // Holding Register Empty) is set, the transmit buffer is empty and
    // ready to accept another byte.
    return (port_io.inb(line_status_port) & transmit_buffer_empty_bit) != 0;
}

/// Put out a single char to COM1
/// This function is inlined too because it may get called a hundred times per
/// second
pub inline fn uart_putchar(char: u8) void {
    // We wait until the transmit buffer is empty
    while (!uart_is_transmit_buffer_empty()) {}
    port_io.outb(data_port, char);
}

/// Put out multiple chars to COM1
pub fn uartPuts(str: []const u8) void {
    for (str) |char| {
        uart_putchar(char);
    }
}

/// Write a zero-padded 64bit hex value directly to COM1, bypassing all
/// buffering, formatting, and allocation. Meant as a last-resort primitive
/// for fault handlers, where the stack, heap, or higher-level terminal state
/// might be corrupted -- this only touches hardware I/O ports.
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
