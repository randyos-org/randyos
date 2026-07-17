//! PIC (8259)
//! 2024 by Samuel Fiedler

const std = @import("std");
const log = std.log.scoped(.arch_pic);

const port_io = @import("port_io.zig");

pub const pic1: u16 = 0x20;
pub const pic2: u16 = 0xa0;
pub const pic1_command: u16 = pic1;
pub const pic1_data: u16 = pic1 + 1;
pub const pic2_command: u16 = pic2;
pub const pic2_data: u16 = pic2 + 1;

/// ICW4 will be present
pub const icw1_icw4: u8 = 0x01;
/// single (cascade) mode
pub const icw1_single: u8 = 0x02;
/// call address interval 4 (8)
pub const icw1_interval4: u8 = 0x04;
/// level triggered (edge) mode
pub const icw1_level: u8 = 0x08;
pub const icw1_init: u8 = 0x10;

/// 8086/88 (MCS-80/85) mode
pub const icw4_8086: u8 = 0x01;
/// auto (normal) EOI
pub const icw4_auto: u8 = 0x02;
/// buffered mode (slave)
pub const icw4_buf_slave: u8 = 0x08;
/// buffered mode (master)
pub const icw4_buf_master: u8 = 0x0c;
/// special fully nested (not)
pub const icw4_sfnm: u8 = 0x10;

/// tells master PIC a slave is cascaded on IRQ2 (bit 2 set)
const master_slave_on_irq2: u8 = 0b0000_0100;
/// slave's cascade identity; must match IRQ line (2) master expects it on
const slave_cascade_identity: u8 = 2;
/// disables all 8 IRQ lines on a PIC
const mask_all_irqs: u8 = 0xff;

pub fn remap(offset_master: u8, offset_slave: u8) void {
    // save masks
    var mask_master: u8 = 0;
    var mask_slave: u8 = 0;
    mask_master = port_io.inb(pic1_data);
    mask_slave = port_io.inb(pic2_data);
    // start initialization sequence
    port_io.outb(pic1_command, icw1_init | icw1_icw4);
    port_io.ioWait();
    port_io.outb(pic2_command, icw1_init | icw1_icw4);
    port_io.ioWait();
    // set PIC vector offsets
    port_io.outb(pic1_data, offset_master);
    port_io.ioWait();
    port_io.outb(pic2_data, offset_slave);
    port_io.ioWait();
    // tell master PIC that there is a slave PIC at IRQ2
    port_io.outb(pic1_data, master_slave_on_irq2);
    port_io.ioWait();
    // tell slave PIC its cascade identity
    port_io.outb(pic2_data, slave_cascade_identity);
    port_io.ioWait();
    // have the PICs use 8086 mode (and not 8080 mode)
    port_io.outb(pic1_data, icw4_8086);
    port_io.ioWait();
    port_io.outb(pic2_data, icw4_8086);
    port_io.ioWait();
    // restore saved masks
    port_io.outb(pic1_data, mask_master);
    port_io.outb(pic2_data, mask_slave);
}

pub fn disable() void {
    port_io.outb(pic1_data, mask_all_irqs);
    port_io.outb(pic2_data, mask_all_irqs);
}
