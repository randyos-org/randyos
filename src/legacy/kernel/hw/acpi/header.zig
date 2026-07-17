//! ACPI Table Header
//! 2024 by Samuel Fiedler

const std = @import("std");
const expect = std.testing.expect;
const log = std.log.scoped(.acpi_header);

pub const ChecksumError = error{
    InvalidChecksum,
};

pub const Header = extern struct {
    /// table id (ASCII)
    signature: [4]u8 align(1),
    /// table length in bytes, incl header
    length: u32 align(1),
    /// struct revision; higher = backward compat
    revision: u8 align(1),
    /// table bytes must sum to zero
    checksum: u8 align(1),
    /// OEM id string
    oem_id: [6]u8 align(1),
    /// OEM's table id string
    oem_table_id: [8]u8 align(1),
    /// OEM revision; higher = newer
    oem_revision: u32 align(1),
    /// creator util vendor ID
    creator_id: u32 align(1),
    /// creator util revision
    creator_revision: u32 align(1),

    pub fn verifyChecksum(self: *Header) ChecksumError!void {
        var sum: u8 = 0;
        var arr: [*]u8 = @ptrCast(self);
        for (arr[0..self.length]) |val| {
            sum +%= val;
        }
        if (sum != 0) {
            return error.InvalidChecksum;
        }
    }
};

test "compile" {
    try expect(@sizeOf(Header) == 36);
}
