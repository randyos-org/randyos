//! ACPI Root System Descriptor Pointer
//! 2024 by Samuel Fiedler

const std = @import("std");
const log = std.log.scoped(.acpi_rsdp);

pub const ChecksumError = error{
    InvalidChecksum,
};

/// Size of ACPI 1.0 RSDP (bytes 0-19) -- what a rev-0 checksum covers.
/// Later fields (length/xsdt_addr/ext_checksum/res1) don't exist in rev 0.
const acpi_v1_rsdp_size: usize = 20;

pub const RSDP = extern struct {
    /// "RSD PTR " (trailing blank required)
    signature: [8]u8 align(1),
    /// ACPI 1.0 checksum: first 20 bytes must sum to zero
    checksum: u8 align(1),
    /// OEM id string
    oem_id: [6]u8 align(1),
    /// struct revision; 0 = ACPI 1.0 (first 20 bytes only), current is 2
    revision: u8 align(1),
    /// 32bit phys addr of RSDT
    rsdt_addr: u32 align(1),
    /// table length in bytes incl header; rev 2+ only
    length: u32 align(1),
    /// 64bit phys addr of XSDT; rev 2+ only
    xsdt_addr: u64 align(1),
    /// checksum of entire table; rev 2+ only
    ext_checksum: u8 align(1),
    /// reserved; rev 2+ only
    res1: [3]u8 align(1),

    pub fn verifyChecksum(self: *RSDP) ChecksumError!void {
        var sum: u8 = 0;
        const arr: [*]u8 = @ptrCast(self);
        switch (self.revision) {
            0 => for (arr[0..acpi_v1_rsdp_size]) |val| {
                sum +%= val;
            },
            2 => for (arr[0..self.length]) |val| {
                sum +%= val;
            },
            else => {
                log.err("Invalid ACPI RSDP revision!", .{});
                return error.InvalidChecksum;
            },
        }
        if (sum != 0) {
            return error.InvalidChecksum;
        }
    }
};

test "compile" {
    try std.testing.expect(@sizeOf(RSDP) == 36);
}
