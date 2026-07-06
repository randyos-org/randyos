//! Multiple APIC Descriptor Table (MADT)
//! 2024 by Samuel Fiedler

const std = @import("std");
const Header = @import("header.zig").Header;
const log = std.log.scoped(.acpi_madt);
const expect = std.testing.expect;

/// MADT Entry
pub const Entry = union(EntryType) {
    /// Processor Local APIC
    lapic: *LAPIC,
    /// I/O APIC
    io_apic: *IOAPIC,
    /// I/O APIC Interrupt Source Override
    io_apic_int_src_override: *IOAPICSourceOverride,
    /// I/O APIC Non-maskable interrupt source
    io_apic_int_src_no_mask: *IOAPICNonMaskable,
    /// Local APIC Non-maskable interrupts
    lapic_int_no_mask: *LAPICNonMaskable,
    /// Local APIC Address Override
    lapic_addr_override: *LAPICAddressOverride,
    /// Processor Local x2APIC
    local_x2apic: *Lx2APIC,
};

/// MADT Entry Header
pub const EntryHeader = extern struct {
    /// Entry Type
    entry_type: EntryType align(1),
    /// Record Length
    record_length: u8 align(1),
};

/// MADT Entry Types
pub const EntryType = enum(u8) {
    /// Processor Local APIC
    lapic = 0,
    /// I/O APIC
    io_apic = 1,
    /// I/O APIC Interrupt Source Override
    io_apic_int_src_override = 2,
    /// I/O APIC Non-maskable interrupt source
    io_apic_int_src_no_mask = 3,
    /// Local APIC Non-maskable interrupts
    lapic_int_no_mask = 4,
    /// Local APIC Address Override
    lapic_addr_override = 5,
    /// Processor Local x2APIC
    local_x2apic = 9,
};

/// Multiple APIC Descriptor Table
pub const MADT = extern struct {
    /// The standard ACPI Table header
    header: Header align(1),
    /// Local APIC Address
    lapic_addr: u32 align(1),
    /// Flags (bit 0 [first bit] = PCAT_COMPAT: legacy dual-8259 PICs are
    /// present and must be disabled before using the APIC)
    flags: u32 align(1),
    // TODO: implement flag struct

    pub const FindError = error{
        NoMatchingEntry,
    };

    /// Find an entry in the MADT
    pub fn findEntry(self: *MADT, entry_type: EntryType) FindError!Entry {
        var addr = @intFromPtr(self) + @sizeOf(MADT);
        // iterate over everything except for the base table
        while (addr < (@intFromPtr(self) + self.header.length)) {
            const hdr: *EntryHeader = @ptrFromInt(addr);
            // directly increment the address by two because sizeof(header) is two
            addr += 2;
            log.debug("MADT Entry tag is {s}", .{@tagName(hdr.entry_type)});
            // TODO: comptime?
            switch (hdr.entry_type) {
                .lapic => {
                    if (hdr.entry_type == entry_type) {
                        return .{ .lapic = @ptrFromInt(addr) };
                    } else {
                        addr += @sizeOf(LAPIC);
                    }
                },
                .io_apic => {
                    if (hdr.entry_type == entry_type) {
                        return .{ .io_apic = @ptrFromInt(addr) };
                    } else {
                        addr += @sizeOf(IOAPIC);
                    }
                },
                .io_apic_int_src_override => {
                    if (hdr.entry_type == entry_type) {
                        return .{ .io_apic_int_src_override = @ptrFromInt(addr) };
                    } else {
                        addr += @sizeOf(IOAPICSourceOverride);
                    }
                },
                .io_apic_int_src_no_mask => {
                    if (hdr.entry_type == entry_type) {
                        return .{ .io_apic_int_src_no_mask = @ptrFromInt(addr) };
                    } else {
                        addr += @sizeOf(IOAPICNonMaskable);
                    }
                },
                .lapic_int_no_mask => {
                    if (hdr.entry_type == entry_type) {
                        return .{ .lapic_int_no_mask = @ptrFromInt(addr) };
                    } else {
                        addr += @sizeOf(LAPICNonMaskable);
                    }
                },
                .lapic_addr_override => {
                    if (hdr.entry_type == entry_type) {
                        return .{ .lapic_addr_override = @ptrFromInt(addr) };
                    } else {
                        addr += @sizeOf(LAPICAddressOverride);
                    }
                },
                .local_x2apic => {
                    if (hdr.entry_type == entry_type) {
                        return .{ .local_x2apic = @ptrFromInt(addr) };
                    } else {
                        addr += @sizeOf(Lx2APIC);
                    }
                },
            }
        }
        return error.NoMatchingEntry;
    }

    /// Register I/O APIC redirection entries
    pub fn registerRedirectionEntries(self: *MADT, callback: *const fn (*IOAPICSourceOverride) void) void {
        var addr = @intFromPtr(self) + @sizeOf(MADT);
        // iterate over everything except for the base table
        while (addr < (@intFromPtr(self) + self.header.length)) {
            const hdr: *EntryHeader = @ptrFromInt(addr);
            // directly increment the address by two because sizeof(header) is two
            addr += 2;
            log.debug("MADT Entry tag is {s}", .{@tagName(hdr.entry_type)});
            switch (hdr.entry_type) {
                .io_apic_int_src_override => {
                    callback(@ptrFromInt(addr));
                    addr += @sizeOf(IOAPICSourceOverride);
                },
                else => {
                    addr += hdr.record_length - 2;
                },
            }
        }
    }
};

/// MPS INTI Flags
pub const MPSINTI = packed struct(u16) {
    /// Polarity of the APIC I/O Input signals
    pub const Polarity = enum(u2) {
        /// Conforms to the specifications of the bus
        spec_conformant = 0,
        /// Active High
        active_high = 1,
        /// Reserved
        reserved = 2,
        /// Active Low
        active_low = 3,
    };

    /// Trigger mode of the APIC I/O Input signals
    pub const TriggerMode = enum(u2) {
        /// Conforms to the specifications of the bus
        spec_conformant = 0,
        /// Edge-Triggered
        edge_triggered = 1,
        /// Reserved
        reserved = 2,
        /// Level-Triggered
        level_triggered = 3,
    };

    /// Polarity of the I/O APIC signals
    polarity: Polarity,
    /// Trigger Mode of the I/O APIC signals
    trigger_mode: TriggerMode,
    /// Reserved
    _0: u12 = 0,
};

/// Processor local APIC
pub const LAPIC = extern struct {
    /// ACPI Processor ID
    acpi_proc_id: u8 align(1),
    /// APIC ID
    apic_id: u8 align(1),
    /// Flags (bit 0 = processor enabled, bit 1 = online capable)
    flags: u32 align(1),
    // TODO: implement flag struct
};

/// I/O APIC
pub const IOAPIC = extern struct {
    /// I/O APIC's ID
    apic_id: u8 align(1),
    /// Reserved
    _0: u8 align(1) = 0,
    /// I/O APIC Address
    ioapic_addr: u32 align(1),
    /// Global System Interrupt Base
    glob_sys_int_base: u32 align(1),
};

/// I/O APIC Interrupt Source Override
pub const IOAPICSourceOverride = extern struct {
    /// Bus source
    bus_src: u8 align(1),
    /// IRQ source
    irq_src: u8 align(1),
    /// Global System Interrupt
    glob_sys_int: u32 align(1),
    /// Flags
    flags: MPSINTI align(1),
};

/// I/O APIC Non-maskable interrupt source
pub const IOAPICNonMaskable = extern struct {
    /// Non-maskable interrupt source
    nmi_source: u8 align(1),
    /// Reserved
    _0: u8 align(1) = 0,
    /// Flags
    flags: MPSINTI align(1),
    /// Global System Interrupt
    glob_sys_int: u32 align(1),
};

/// Local APIC Non-maskable interrupts
pub const LAPICNonMaskable = extern struct {
    /// ACPI Processor ID (0xff means all processors)
    acpi_proc_id: u8 align(1),
    /// Flags
    flags: MPSINTI align(1),
    /// LINT# (0 or 1)
    lint_num: u8 align(1),
};

/// Local APIC Address Override
pub const LAPICAddressOverride = extern struct {
    /// Reserved
    _0: [2]u8 align(1) = [_]u8{ 0, 0 },
    /// 64bit physical address of Local APIC
    apic_addr: u64 align(1),
};

/// Processor Local x2APIC
pub const Lx2APIC = extern struct {
    /// Reserved
    _0: [2]u8 align(1) = [_]u8{ 0, 0 },
    /// Processor's local x2APIC ID
    proc_lapic_id: u32 align(1),
    /// Flags
    flags: u32 align(1),
    // TODO: implement flag struct

    /// ACPI ID
    acpi_id: u32 align(1),
};
