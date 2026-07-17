//! Multiple APIC Descriptor Table (MADT)
//! 2024 by Samuel Fiedler

const std = @import("std");
const Header = @import("header.zig").Header;
const log = std.log.scoped(.acpi_madt);
const expect = std.testing.expect;

pub const Entry = union(EntryType) {
    lapic: *LAPIC,
    io_apic: *IOAPIC,
    io_apic_int_src_override: *IOAPICSourceOverride,
    io_apic_int_src_no_mask: *IOAPICNonMaskable,
    lapic_int_no_mask: *LAPICNonMaskable,
    lapic_addr_override: *LAPICAddressOverride,
    local_x2apic: *Lx2APIC,
};

pub const EntryHeader = extern struct {
    entry_type: EntryType align(1),
    record_length: u8 align(1),
};

pub const EntryType = enum(u8) {
    lapic = 0,
    io_apic = 1,
    io_apic_int_src_override = 2,
    io_apic_int_src_no_mask = 3,
    lapic_int_no_mask = 4,
    lapic_addr_override = 5,
    local_x2apic = 9,
};

pub const MADT = extern struct {
    header: Header align(1),
    lapic_addr: u32 align(1),
    /// bit0 PCAT_COMPAT: legacy 8259 PICs present, must disable
    flags: u32 align(1),
    // TODO: implement flag struct

    pub const FindError = error{
        NoMatchingEntry,
    };

    pub fn findEntry(self: *MADT, entry_type: EntryType) FindError!Entry {
        var addr = @intFromPtr(self) + @sizeOf(MADT);
        // skip base table
        while (addr < (@intFromPtr(self) + self.header.length)) {
            const hdr: *EntryHeader = @ptrFromInt(addr);
            addr += @sizeOf(EntryHeader);
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

    pub fn registerRedirectionEntries(self: *MADT, callback: *const fn (*IOAPICSourceOverride) void) void {
        var addr = @intFromPtr(self) + @sizeOf(MADT);
        // skip base table
        while (addr < (@intFromPtr(self) + self.header.length)) {
            const hdr: *EntryHeader = @ptrFromInt(addr);
            addr += @sizeOf(EntryHeader);
            log.debug("MADT Entry tag is {s}", .{@tagName(hdr.entry_type)});
            switch (hdr.entry_type) {
                .io_apic_int_src_override => {
                    callback(@ptrFromInt(addr));
                    addr += @sizeOf(IOAPICSourceOverride);
                },
                else => {
                    addr += hdr.record_length - @sizeOf(EntryHeader);
                },
            }
        }
    }
};

/// MPS INTI flags
pub const MPSINTI = packed struct(u16) {
    /// APIC I/O input polarity
    pub const Polarity = enum(u2) {
        /// bus default
        spec_conformant = 0,
        active_high = 1,
        reserved = 2,
        active_low = 3,
    };

    /// APIC I/O input trigger mode
    pub const TriggerMode = enum(u2) {
        /// bus default
        spec_conformant = 0,
        edge_triggered = 1,
        reserved = 2,
        level_triggered = 3,
    };

    polarity: Polarity,
    trigger_mode: TriggerMode,
    /// reserved
    _align1: u12 = 0,
};

pub const LAPIC = extern struct {
    acpi_proc_id: u8 align(1),
    apic_id: u8 align(1),
    /// bit0 enabled, bit1 online capable
    flags: u32 align(1),
    // TODO: implement flag struct
};

pub const IOAPIC = extern struct {
    apic_id: u8 align(1),
    /// reserved
    _align1: u8 align(1) = 0,
    ioapic_addr: u32 align(1),
    glob_sys_int_base: u32 align(1),
};

pub const IOAPICSourceOverride = extern struct {
    bus_src: u8 align(1),
    irq_src: u8 align(1),
    glob_sys_int: u32 align(1),
    flags: MPSINTI align(1),
};

pub const IOAPICNonMaskable = extern struct {
    nmi_source: u8 align(1),
    /// reserved
    _align1: u8 align(1) = 0,
    flags: MPSINTI align(1),
    glob_sys_int: u32 align(1),
};

pub const LAPICNonMaskable = extern struct {
    /// 0xff = all processors
    acpi_proc_id: u8 align(1),
    flags: MPSINTI align(1),
    /// LINT# (0 or 1)
    lint_num: u8 align(1),
};

pub const LAPICAddressOverride = extern struct {
    /// reserved
    _align1: [2]u8 align(1) = [_]u8{ 0, 0 },
    /// 64bit phys addr of local APIC
    apic_addr: u64 align(1),
};

pub const Lx2APIC = extern struct {
    /// reserved
    _align1: [2]u8 align(1) = [_]u8{ 0, 0 },
    proc_lapic_id: u32 align(1),
    flags: u32 align(1),
    // TODO: implement flag struct

    acpi_id: u32 align(1),
};
