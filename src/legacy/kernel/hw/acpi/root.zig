//! Advanced Configuration and Power Interface
//! Not architecture-specific
//! 2024 by Samuel Fiedler

const std = @import("std");
const builtin = @import("builtin");
const log = std.log.scoped(.acpi);

pub const header = @import("header.zig");
pub const madt = @import("madt.zig");
pub const rsdp = @import("rsdp.zig");
pub const xsdt = @import("xsdt.zig");

const MADT = madt.MADT;
const RSDP = rsdp.RSDP;
const XSDT = xsdt.XSDT;

pub var rsdp_opt: ?*RSDP = null;
pub var madt_ptr: *MADT = undefined;
pub var xsdt_ptr: *XSDT = undefined;

pub const ACPIError = error{
    InvalidSignature,
} || rsdp.ChecksumError || header.ChecksumError || xsdt.FindError;

/// Parse ACPI static tables (RSDP -> XSDT -> MADT). Firmware-format
/// specific, not CPU-arch specific (some arm64 servers use ACPI too).
/// Populates rsdp_opt/xsdt_ptr/madt_ptr for arch code to interpret --
/// e.g. ioapic.zig reads madt_ptr for its own entry type; this doesn't
/// care what any entry means.
///
/// Caller already decided this platform has ACPI (see
/// `HardwareDescription` in src/common/boot_info.zig) before calling.
pub fn init(rsdp_ptr: *anyopaque) ACPIError!void {
    log.info("ACPI initialization... ", .{});
    log.debug("RSDP Address: 0x{x}", .{@as(u64, @intFromPtr(rsdp_ptr))});
    const rsdp_resolved: *RSDP = @ptrCast(rsdp_ptr);
    rsdp_opt = rsdp_resolved;
    if (std.mem.eql(u8, rsdp_resolved.signature[0..], "RSD PTR ")) {
        log.debug("RSDP Signature is valid!", .{});
    } else {
        log.err("RSDP Signature is invalid!", .{});
        return error.InvalidSignature;
    }
    rsdp_resolved.verifyChecksum() catch |err| {
        log.err("RSDP Checksum is invalid (expected 0, found {})!", .{rsdp_resolved.checksum});
        return err;
    };
    log.debug("RSDP Checksum is valid!", .{});
    switch (rsdp_resolved.revision) {
        0 => {
            log.debug("RSDT Address is 0x{x}", .{rsdp_resolved.rsdt_addr});
        },
        2 => {
            log.debug("XSDT Address is 0x{x}", .{rsdp_resolved.xsdt_addr});
            // xsdt_addr is always 64-bit (spec-mandated); truncates on
            // 32-bit archs, fine since those are compile-only stubs with
            // no real ACPI path yet
            xsdt_ptr = @ptrFromInt(@as(usize, @intCast(rsdp_resolved.xsdt_addr)));
            if (std.mem.eql(u8, xsdt_ptr.header.signature[0..], "XSDT")) {
                log.debug("XSDT Signature is valid!", .{});
            } else {
                log.err("XSDT Signature is invalid!", .{});
                return error.InvalidSignature;
            }
            xsdt_ptr.header.verifyChecksum() catch |err| {
                log.err("XSDP Checksum is invalid!", .{});
                return err;
            };
            log.debug("XSDT Checksum is valid!", .{});
            log.debug("XSDT has {} entries", .{((xsdt_ptr.header.length - @sizeOf(header.Header)) / xsdt.xsdt_entry_size)});

            // needed by arch code afterward, e.g. x86_64's I/O APIC driver
            const madt_hdr = xsdt_ptr.findEntry("APIC") catch |err| {
                log.err("No MADT found!", .{});
                return err;
            };
            log.debug("Found MADT at 0x{x}", .{@intFromPtr(madt_hdr)});
            madt_hdr.verifyChecksum() catch |err| {
                log.err("MADT Checksum is invalid!", .{});
                return err;
            };
            log.debug("MADT Checksum is valid!", .{});
            madt_ptr = @ptrCast(madt_hdr);
        },
        // safe: verifyChecksum above rejects any revision other than 0/2
        else => unreachable,
    }
    log.info("ACPI initialization successful! ", .{});
}
