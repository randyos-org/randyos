//! I/O APIC
//! 2024 by Samuel Fiedler

const std = @import("std");
const builtin = @import("builtin");
const log = std.log.scoped(.arch_ioapic);

const lapic = @import("lapic.zig");
const acpi = @import("../../hw/acpi/root.zig");

pub var global_ioapic = IOApic{
    .base = undefined,
    .glob_sys_int_base = 0,
};

/// Offset of IOREDTBL0 in indirect register space. Each redirection entry
/// spans 2 dwords, so entry `n` is at `ioredtbl_base + n*2` (low) / `+1` (high)
const ioredtbl_base: u32 = 0x10;

/// xAPIC ID field's bit position in raw LAPIC ID register (bits 24-31)
const lapic_id_shift: u5 = 24;

/// legacy IRQ line PS/2 keyboard is wired to
const keyboard_irq: usize = 1;

pub const DeliveryMode = enum(u3) {
    normal = 0,
    low_priority = 1,
    system_management = 2,
    non_maskable = 4,
    init = 5,
    external = 7,
};

pub const DestinationMode = enum(u1) {
    physical = 0,
    logical = 1,
};

pub const Polarity = enum(u1) {
    high_active = 0,
    low_active = 1,
};

pub const TriggerMode = enum(u1) {
    edge = 0,
    level = 1,
};

pub const RedirectionEntry = packed struct(u64) {
    vector: u8,
    delivery_mode: DeliveryMode = .normal,
    destination_mode: DestinationMode = .physical,
    /// set when interrupt is pending send
    interrupt_busy: bool = false,
    polarity: Polarity = .high_active,
    /// TODO find a better field name
    interrupt_status: u1 = 0,
    trigger_mode: TriggerMode = .edge,
    masked: bool,
    /// Reserved
    res1: u39 = 0,
    destination: u8,
};

/// I/O APIC indirect registers
pub const IndirectRegister = union(enum(u32)) {
    /// id, bits 24-27, rest reserved
    ioapic_id = 0,
    /// version bits 0-7, max redir entries bits 16-23; read only
    ioapic_version = 1,
    /// arbitration priority bits 24-27; read only
    ioapic_arbitration = 2,
    redirection: u16,
};

/// I/O APIC direct registers
pub const DirectRegister = enum(usize) {
    selector = 0x0,
    data = 0x10,
    irq_pin_assertion = 0x20,
    eoi = 0x40,
};

pub const APICRegisterType = union(enum) {
    information: u32,
    redirection_entry: RedirectionEntry,
};

pub const Info = packed struct(u32) {
    version: u8,
    /// Reserved
    res1: u8,
    /// max redir entries, zero-based (actual count = max_entries + 1, see
    /// `IOApic.init`)
    max_entries: u8,
    /// Reserved
    res2: u8,
};

pub const IOApic = struct {
    base: usize,
    glob_sys_int_base: u32,
    /// vector `init()` was given for GSI/IRQ 0 on this chip; stashed so
    /// `redEntryMADT` (a plain fn-ptr callback, no access to init's locals)
    /// can reuse the same `irq + offset` scheme
    vector_offset: u8 = 0,

    pub fn enableVector(self: *IOApic, irq: u8, vector: u8) void {
        log.debug("Enabling IRQ {} => VEC {}", .{ irq, vector });
        const lapic_id = lapic.global_apic.read(.local_apic_id);
        var red_entry = self.indirectRead(.{ .redirection = irq }).redirection_entry;
        red_entry.vector = vector;
        // xAPIC ID: bits 24-31 of raw LAPIC ID reg
        red_entry.destination = @truncate((lapic_id >> lapic_id_shift) & 0xff);
        red_entry.masked = false;
        self.indirectWrite(.{ .redirection = irq }, .{
            .redirection_entry = red_entry,
        });
    }

    pub fn disableVector(self: *IOApic, irq: u8, vector: u8) void {
        log.debug("Disabling IRQ {} => VEC {}", .{ irq, vector });
        const lapic_id = lapic.global_apic.read(.local_apic_id);
        var red_entry = self.indirectRead(.{ .redirection = irq }).redirection_entry;
        red_entry.vector = vector;
        // xAPIC ID: bits 24-31 of raw LAPIC ID reg
        red_entry.destination = @truncate((lapic_id >> lapic_id_shift) & 0xff);
        red_entry.masked = true;
        self.indirectWrite(.{ .redirection = irq }, .{
            .redirection_entry = red_entry,
        });
    }

    pub fn indirectRead(self: *IOApic, register: IndirectRegister) APICRegisterType {
        const offset: u32 = switch (register) {
            .ioapic_id, .ioapic_version, .ioapic_arbitration => @intFromEnum(register),
            .redirection => |index| {
                // 2 32-bit words per entry: low then high
                var values: [2]u32 = .{ 0, 0 };
                self.directWrite(.selector, ioredtbl_base + index * 2);
                values[0] = self.directRead(.data);
                self.directWrite(.selector, ioredtbl_base + index * 2 + 1);
                values[1] = self.directRead(.data);
                return .{ .redirection_entry = @bitCast(values) };
            },
        };

        self.directWrite(.selector, offset);
        return .{ .information = self.directRead(.data) };
    }

    pub fn indirectWrite(self: *IOApic, register: IndirectRegister, value: APICRegisterType) void {
        const offset: u32 = switch (register) {
            .ioapic_id => 0,
            .ioapic_version => 1,
            .ioapic_arbitration => 2,
            .redirection => |index| {
                // 2 32-bit words per entry: low then high
                const values: [2]u32 = @bitCast(value.redirection_entry);
                self.directWrite(.selector, ioredtbl_base + index * 2);
                self.directWrite(.data, values[0]);
                self.directWrite(.selector, ioredtbl_base + index * 2 + 1);
                self.directWrite(.data, values[1]);
                return;
            },
        };
        self.directWrite(.selector, offset);
        self.directWrite(.data, value.information);
    }

    pub inline fn directWrite(self: *IOApic, register: DirectRegister, value: u32) void {
        const reg: *volatile u32 = @ptrFromInt(self.base + @intFromEnum(register));
        reg.* = value;
    }

    pub inline fn directRead(self: *IOApic, register: DirectRegister) u32 {
        const reg: *volatile u32 = @ptrFromInt(self.base + @intFromEnum(register));
        return reg.*;
    }
};

/// EOI to interrupt source. Unlike LAPIC's EOI reg, I/O APIC's EOIR
/// matches on vector, not IRQ pin -- so read the pin's current vector
/// back out of its redirection entry first.
pub inline fn eoi(irq: u8) void {
    const vector = global_ioapic.indirectRead(.{ .redirection = irq }).redirection_entry.vector;
    log.debug("Sending EOI to IRQ {} (vector {})", .{ irq, vector });
    global_ioapic.directWrite(.eoi, vector);
}

/// Register redirection entry from ACPI MADT info
pub fn redEntryMADT(entry: *acpi.madt.IOAPICSourceOverride) void {
    log.debug("I/O APIC Source Override: 0x{x:0>16}", .{std.mem.readVarInt(u64, std.mem.asBytes(entry), builtin.cpu.arch.endian())});
    // only applies if GSI routes through our (only) I/O APIC
    if (entry.glob_sys_int >= global_ioapic.glob_sys_int_base) {
        const lapic_id = lapic.global_apic.read(.local_apic_id);
        const redir_entry = RedirectionEntry{
            // xAPIC ID: bits 24-31 of raw LAPIC ID reg
            .destination = @truncate((lapic_id >> 24) & 0xff),
            // same vector the identity-mapped IRQ would get, since that's
            // what drivers/IDT handlers for that IRQ expect
            .vector = @truncate(@as(usize, entry.irq_src) + global_ioapic.vector_offset),
            .trigger_mode = switch (entry.flags.trigger_mode) {
                .edge_triggered => .edge,
                .level_triggered => .level,
                else => .edge,
            },
            .polarity = switch (entry.flags.polarity) {
                .active_high => .high_active,
                .active_low => .low_active,
                else => .high_active,
            },
            .masked = false,
        };
        // redir table indexed by local pin (GSI - glob_sys_int_base), not legacy IRQ #
        const pin: u16 = @truncate(entry.glob_sys_int - global_ioapic.glob_sys_int_base);
        global_ioapic.indirectWrite(.{ .redirection = pin }, .{ .redirection_entry = redir_entry });
    }
}

/// Init I/O APIC; reads base/GSI base from MADT (already validated by
/// hw/acpi/root.zig's init, which leaves arch-specific interpretation to us)
pub fn init(offset: u8) void {
    log.info("I/O APIC Initialization... ", .{});
    const entry = acpi.madt_ptr.findEntry(.io_apic) catch @panic("No I/O APIC Entry in the MADT found!");
    log.debug("I/O APIC Entry is {}", .{entry.io_apic});
    global_ioapic.base = entry.io_apic.ioapic_addr;
    global_ioapic.glob_sys_int_base = entry.io_apic.glob_sys_int_base;
    global_ioapic.vector_offset = offset;
    const info: Info = @bitCast(global_ioapic.indirectRead(.ioapic_version).information);

    for (0..info.max_entries + 1) |i| {
        switch (i) {
            keyboard_irq => global_ioapic.enableVector(@truncate(i), @truncate(i + offset)),
            // default: disable
            else => global_ioapic.disableVector(@truncate(i), @truncate(i + offset)),
        }
    }
    // apply MADT overrides; must run after base/glob_sys_int_base are set above
    acpi.madt_ptr.registerRedirectionEntries(redEntryMADT);
    log.debug("I/O APIC Version: 0x{x}", .{global_ioapic.indirectRead(.ioapic_version).information});
    log.info("I/O APIC Initialization successful! ", .{});
}
