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

/// Errors that may occur during the initialization of the ACPI
pub const ACPIError = error{
    InvalidSignature,
} || rsdp.ChecksumError || header.ChecksumError || xsdt.FindError;

/// Validate and parse the ACPI static tables (RSDP -> XSDT -> MADT):
/// firmware-format-specific, but *not* CPU-architecture-specific (ACPI's
/// table formats don't change based on which CPU is reading them -- some
/// arm64 servers use ACPI too). Populates `rsdp_opt`/`xsdt_ptr`/`madt_ptr`
/// for arch-specific code to interpret afterward -- e.g. `ioapic.zig`
/// reads `madt_ptr` directly to find *its own* MADT entry type -- this
/// deliberately doesn't itself know or care what any particular MADT
/// entry means, since that interpretation is architecture-specific.
///
/// `rsdp_ptr` is the RSDP -- deciding *whether* this platform even has
/// ACPI (vs. a devicetree, or nothing) is the caller's job (see
/// `HardwareDescription` in `src/common/boot_info.zig`); by the time this
/// is called, that decision has already been made.
pub fn init(rsdp_ptr: *anyopaque) ACPIError!void {
    log.info("ACPI initialization... ", .{});
    log.debug("RSDP Address: 0x{x}", .{@as(u64, @intFromPtr(rsdp_ptr))});
    const rsdp_resolved: *RSDP = @ptrCast(rsdp_ptr);
    rsdp_opt = rsdp_resolved;
    // check signature
    if (std.mem.eql(u8, rsdp_resolved.signature[0..], "RSD PTR ")) {
        log.debug("RSDP Signature is valid!", .{});
    } else {
        log.err("RSDP Signature is invalid!", .{});
        return error.InvalidSignature;
    }
    // verify checksum
    rsdp_resolved.verifyChecksum() catch |err| {
        log.err("RSDP Checksum is invalid (expected 0, found {})!", .{rsdp_resolved.checksum});
        return err;
    };
    log.debug("RSDP Checksum is valid!", .{});
    // further processing
    switch (rsdp_resolved.revision) {
        0 => {
            log.debug("RSDT Address is 0x{x}", .{rsdp_resolved.rsdt_addr});
        },
        2 => {
            log.debug("XSDT Address is 0x{x}", .{rsdp_resolved.xsdt_addr});
            // `xsdt_addr` is always a 64-bit ACPI physical address
            // (spec-mandated, regardless of target width); `usize` is only
            // 32 bits on 32-bit archs, so this truncates there -- fine for
            // now since 32-bit targets (arm/powerpc) are compile-only
            // stubs with no real ACPI-parsing call path yet.
            xsdt_ptr = @ptrFromInt(@as(usize, @intCast(rsdp_resolved.xsdt_addr)));
            // check signature
            if (std.mem.eql(u8, xsdt_ptr.header.signature[0..], "XSDT")) {
                log.debug("XSDT Signature is valid!", .{});
            } else {
                log.err("XSDT Signature is invalid!", .{});
                return error.InvalidSignature;
            }
            // verify checksum
            xsdt_ptr.header.verifyChecksum() catch |err| {
                log.err("XSDP Checksum is invalid!", .{});
                return err;
            };
            log.debug("XSDT Checksum is valid!", .{});
            log.debug("XSDT has {} entries", .{((xsdt_ptr.header.length - @sizeOf(header.Header)) / xsdt.xsdt_entry_size)});

            // Find MADT (needed by arch-specific code afterward -- e.g.
            // x86_64's I/O APIC driver -- see this function's doc comment).
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
        // Safe: rsdp.verifyChecksum() (called above) returns
        // error.InvalidChecksum for any revision other than 0/2, so
        // control never reaches here with an unrecognized revision.
        else => unreachable,
    }
    log.info("ACPI initialization successful! ", .{});
}
