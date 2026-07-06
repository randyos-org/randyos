//! I/O Advanced Programmable Interrupt Controller
//! 2024 by Samuel Fiedler

const std = @import("std");
const builtin = @import("builtin");
const log = std.log.scoped(.arch_ioapic);

const lapic = @import("lapic.zig");
const acpi = @import("../../acpi.zig");

pub var global_ioapic = IOApic{
    .base = undefined,
    .glob_sys_int_base = 0,
};

/// I/O APIC Delivery Mode Type
pub const DeliveryMode = enum(u3) {
    /// Normal Interrupt
    normal = 0,
    /// Low-priority Interrupt
    low_priority = 1,
    /// System Management Interrupt
    system_management = 2,
    /// Non-maskable Interrupt
    non_maskable = 4,
    /// INIT Interrupt
    init = 5,
    /// External Interrupt
    external = 7,
};

/// Destination Mode
pub const DestinationMode = enum(u1) {
    /// Physical Mode
    physical = 0,
    /// Logical (virtual) Mode
    logical = 1,
};

/// Polarity of the Interrupt
pub const Polarity = enum(u1) {
    /// High is active
    high_active = 0,
    /// Low is active
    low_active = 1,
};

/// Trigger Mode
pub const TriggerMode = enum(u1) {
    /// Edge sensitive
    edge = 0,
    /// Level sensitive
    level = 1,
};

/// Redirection Entry
pub const RedirectionEntry = packed struct(u64) {
    /// The Interrupt Vector (number of interrupt)
    vector: u8,
    /// How the interrupt will be sent
    delivery_mode: DeliveryMode = .normal,
    /// How the destination field should be interpreted
    destination_mode: DestinationMode = .physical,
    /// Set if this interrupt is going to be sent
    interrupt_busy: bool = false,
    /// Polarity of the Interrupt
    polarity: Polarity = .high_active,
    /// Interrupt "status"
    /// TODO find a better field name
    interrupt_status: u1 = 0,
    /// Trigger Mode
    trigger_mode: TriggerMode = .edge,
    /// Interrupt Mask
    masked: bool,
    /// Reserved
    res1: u39 = 0,
    /// Destination Field
    destination: u8,
};

/// I/O APIC Indirect Registers
pub const IndirectRegister = union(enum(u32)) {
    /// Get/set the IO APIC's id in bits 24-27. All other bits are reserved.
    ioapic_id = 0,
    /// Get the version in bits 0-7. Get the maximum amount of redirection entries in bits 16-23. All other bits are reserved. Read only.
    ioapic_version = 1,
    /// Get the arbitration priority in bits 24-27. All other bits are reserved. Read only.
    ioapic_arbitration = 2,
    /// Redirection Entry
    redirection: u16,
};

/// I/O APIC Direct Registers
pub const DirectRegister = enum(usize) {
    /// Selector Register
    selector = 0x0,
    /// Data Register
    data = 0x10,
    /// IRQ Pin Assertion Register
    irq_pin_assertion = 0x20,
    /// EOI (End of Interrupt) Register
    eoi = 0x40,
};

/// APIC Register type
pub const APICRegisterType = union(enum) {
    /// Information
    information: u32,
    /// Redirection Entry
    redirection_entry: RedirectionEntry,
};

/// I/O APIC Information
pub const Info = packed struct(u32) {
    /// I/O APIC Version
    version: u8,
    /// 8 reserved bits
    res1: u8,
    /// Maximal amount of redirection entries, zero-based (actual entry
    /// count is `max_entries + 1`, see `IOApic.init`)
    max_entries: u8,
    /// 8 reserved bits
    res2: u8,
};

/// I/O APIC
pub const IOApic = struct {
    /// I/O APIC Base
    base: usize,
    /// Global System Interrupt Base
    glob_sys_int_base: u32,
    /// The vector `init()` was given for GSI/IRQ 0 on this chip (`offset`
    /// param) -- stashed here so `redEntryMADT`, a plain function-pointer
    /// callback with no access to `init`'s locals, can still compute the
    /// same `irq + offset` vector scheme it uses for everything else.
    vector_offset: u8 = 0,

    /// Enable interrupt vector
    pub fn enableVector(self: *IOApic, irq: u8, vector: u8) void {
        log.debug("Enabling IRQ {} => VEC {}", .{ irq, vector });
        const lapic_id = lapic.global_apic.read(.local_apic_id);
        var red_entry = self.indirectRead(.{ .redirection = irq }).redirection_entry;
        red_entry.vector = vector;
        // xAPIC ID lives in bits 24-31 of the raw LAPIC ID register value.
        red_entry.destination = @truncate((lapic_id >> 24) & 0xff);
        red_entry.masked = false;
        self.indirectWrite(.{ .redirection = irq }, .{
            .redirection_entry = red_entry,
        });
    }

    /// Disable interrupt vector
    pub fn disableVector(self: *IOApic, irq: u8, vector: u8) void {
        log.debug("Disabling IRQ {} => VEC {}", .{ irq, vector });
        const lapic_id = lapic.global_apic.read(.local_apic_id);
        var red_entry = self.indirectRead(.{ .redirection = irq }).redirection_entry;
        red_entry.vector = vector;
        // xAPIC ID lives in bits 24-31 of the raw LAPIC ID register value.
        red_entry.destination = @truncate((lapic_id >> 24) & 0xff);
        red_entry.masked = true;
        self.indirectWrite(.{ .redirection = irq }, .{
            .redirection_entry = red_entry,
        });
    }

    /// Read a value indirectly from the I/O Apic
    pub fn indirectRead(self: *IOApic, register: IndirectRegister) APICRegisterType {
        const offset: u32 = switch (register) {
            .ioapic_id, .ioapic_version, .ioapic_arbitration => @intFromEnum(register),
            .redirection => |index| {
                // values are 2 32bit integers
                var values: [2]u32 = .{ 0, 0 };
                // so we need to multiply the index by two
                self.directWrite(.selector, 0x10 + index * 2);
                values[0] = self.directRead(.data);
                // and add one for the second value
                self.directWrite(.selector, 0x10 + index * 2 + 1);
                values[1] = self.directRead(.data);
                return .{ .redirection_entry = @bitCast(values) };
            },
        };

        self.directWrite(.selector, offset);
        return .{ .information = self.directRead(.data) };
    }

    /// Write a value indirectly to the I/O Apic
    pub fn indirectWrite(self: *IOApic, register: IndirectRegister, value: APICRegisterType) void {
        const offset: u32 = switch (register) {
            .ioapic_id => 0,
            .ioapic_version => 1,
            .ioapic_arbitration => 2,
            .redirection => |index| {
                // values are 2 32bit integers
                const values: [2]u32 = @bitCast(value.redirection_entry);
                // so we need to multiply the index by two
                self.directWrite(.selector, 0x10 + index * 2);
                self.directWrite(.data, values[0]);
                // and add one for the second value
                self.directWrite(.selector, 0x10 + index * 2 + 1);
                self.directWrite(.data, values[1]);
                return;
            },
        };
        self.directWrite(.selector, offset);
        self.directWrite(.data, value.information);
    }

    /// Write a value directly to the I/O APIC
    pub inline fn directWrite(self: *IOApic, register: DirectRegister, value: u32) void {
        const reg: *volatile u32 = @ptrFromInt(self.base + @intFromEnum(register));
        reg.* = value;
    }

    /// Read a value directly from the I/O APIC
    pub inline fn directRead(self: *IOApic, register: DirectRegister) u32 {
        const reg: *volatile u32 = @ptrFromInt(self.base + @intFromEnum(register));
        return reg.*;
    }
};

/// Send EOI (End of Interrupt) to the interrupt source. Unlike the Local
/// APIC's EOI register, the I/O APIC's EOIR is matched against the
/// interrupt *vector*, not the IRQ pin -- so the pin's currently-programmed
/// vector is read back out of its redirection entry first.
pub inline fn eoi(irq: u8) void {
    const vector = global_ioapic.indirectRead(.{ .redirection = irq }).redirection_entry.vector;
    log.debug("Sending EOI to IRQ {} (vector {})", .{ irq, vector });
    global_ioapic.directWrite(.eoi, vector);
}

/// Register redirection entry based on ACPI MADT information
pub fn redEntryMADT(entry: *acpi.madt.IOAPICSourceOverride) void {
    log.debug("I/O APIC Source Override: 0x{x:0>16}", .{std.mem.readVarInt(u64, std.mem.asBytes(entry), builtin.cpu.arch.endian())});
    // Only applies if this override's GSI is actually routed through our
    // (only) I/O APIC -- glob_sys_int_base is the first GSI this chip owns.
    if (entry.glob_sys_int >= global_ioapic.glob_sys_int_base) {
        const lapic_id = lapic.global_apic.read(.local_apic_id);
        const redir_entry = RedirectionEntry{
            // xAPIC ID lives in bits 24-31 of the raw LAPIC ID register value.
            .destination = @truncate((lapic_id >> 24) & 0xff),
            // Route to the same vector the identity-mapped IRQ would have
            // gotten (irq_src + the offset init() uses for everything else),
            // since that's the vector drivers/IDT handlers for that IRQ
            // actually expect.
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
        // The redirection table is indexed by this IOAPIC's local pin
        // number (GSI relative to glob_sys_int_base), not by the legacy IRQ
        // number.
        const pin: u16 = @truncate(entry.glob_sys_int - global_ioapic.glob_sys_int_base);
        global_ioapic.indirectWrite(.{ .redirection = pin }, .{ .redirection_entry = redir_entry });
    }
}

/// Initialize the I/O APIC
pub fn init(base: usize, glob_sys_int_base: u32, offset: u8) void {
    log.info("I/O APIC Initialization... ", .{});
    global_ioapic.base = base;
    global_ioapic.glob_sys_int_base = glob_sys_int_base;
    global_ioapic.vector_offset = offset;
    const info: Info = @bitCast(global_ioapic.indirectRead(.ioapic_version).information);

    for (0..info.max_entries + 1) |i| {
        switch (i) {
            // keyboard
            1 => global_ioapic.enableVector(@truncate(i), @truncate(i + offset)),
            // default: disable
            else => global_ioapic.disableVector(@truncate(i), @truncate(i + offset)),
        }
    }
    // Apply any MADT-provided I/O APIC source overrides on top of the
    // defaults above. Must run after global_ioapic.base/glob_sys_int_base
    // are set (above), since redEntryMADT writes through them.
    acpi.madt_ptr.registerRedirectionEntries(redEntryMADT);
    log.debug("I/O APIC Version: 0x{x}", .{global_ioapic.indirectRead(.ioapic_version).information});
    log.info("I/O APIC Initialization successful! ", .{});
}
