//! Advanced Configuration and Power Interface
//! Not architecture-specific
//! 2024 by Samuel Fiedler

const builtin = @import("builtin");
const std = @import("std");

const common = @import("common");
const KernelBootInfo = common.boot_info.KernelBootInfo;

pub const header = @import("acpi/header.zig");
pub const madt = @import("acpi/madt.zig");
pub const rsdp = @import("acpi/rsdp.zig");
pub const xsdt = @import("acpi/xsdt.zig");

const MADT = madt.MADT;
const RSDP = rsdp.RSDP;
const XSDT = xsdt.XSDT;
const log = std.log.scoped(.acpi);

/// Kernel-relevant information returned from ACPI
pub const ACPIInfo = struct {
    /// I/O APIC Address
    ioapic_addr: u32,
    /// Global System Interrupt Base
    glob_sys_int_base: u32,
};

pub var rsdp_opt: ?*RSDP = null;
pub var madt_ptr: *MADT = undefined;
pub var xsdt_ptr: *XSDT = undefined;

/// Errors that may occur during the initialization of the ACPI
pub const ACPIError = error{
    InvalidSignature,
    NoRSDP,
} || rsdp.ChecksumError || header.ChecksumError || xsdt.FindError || MADT.FindError;

/// Initialize the ACPI
pub fn init(kernel_boot_info: *KernelBootInfo) ACPIError!ACPIInfo {
    log.info("ACPI initialization... ", .{});
    var ioapic_addr: u32 = undefined;
    var glob_sys_int_base: u32 = undefined;
    // get rsdp from bootloader
    if (kernel_boot_info.*.rsdp_10) |rsdp_10_ptr| {
        log.debug("RSDP 1.0 Address: 0x{x}", .{@as(u64, @intFromPtr(rsdp_10_ptr))});
        rsdp_opt = @as(*RSDP, @ptrCast(rsdp_10_ptr));
    }
    if (kernel_boot_info.*.rsdp_20) |rsdp_20_ptr| {
        log.debug("RSDP 2.0 Address: 0x{x}", .{@as(u64, @intFromPtr(rsdp_20_ptr))});
        rsdp_opt = @as(*RSDP, @ptrCast(rsdp_20_ptr));
    }
    // actually ensure there is any rsdp
    if (rsdp_opt) |rsdp_resolved| {
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
                xsdt_ptr = @ptrFromInt(rsdp_resolved.xsdt_addr);
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

                // find MADT (needed for I/O APIC => Keyboards)
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
                const entry = madt_ptr.findEntry(.io_apic) catch |err| {
                    log.err("No I/O APIC Entry in the MADT found!", .{});
                    return err;
                };
                log.debug("I/O APIC Entry is {}", .{entry.io_apic});
                ioapic_addr = entry.io_apic.ioapic_addr;
                glob_sys_int_base = entry.io_apic.glob_sys_int_base;
            },
            // Safe: rsdp.verifyChecksum() (called above) returns
            // error.InvalidChecksum for any revision other than 0/2, so
            // control never reaches here with an unrecognized revision.
            else => unreachable,
        }
    } else {
        log.err("No RSDP found, looks like you don't have any ACPI!", .{});
        return error.NoRSDP;
    }
    log.info("ACPI initialization successful! ", .{});
    return .{
        .ioapic_addr = ioapic_addr,
        .glob_sys_int_base = glob_sys_int_base,
    };
}
