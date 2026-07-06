//! ACPI Table Header
//! 2024 by Samuel Fiedler

const std = @import("std");
const expect = std.testing.expect;
const log = std.log.scoped(.acpi_header);

/// ACPI Table Header Checksum Error
pub const ChecksumError = error{
    InvalidChecksum,
};

/// Standard ACPI Table Header
pub const Header = extern struct {
    /// The ASCII string representation of the table identifier.
    signature: [4]u8 align(1),
    /// The length of the table, in bytes, including the header, starting from offest 0. This field is used to record the size of the entire table.
    length: u32 align(1),
    /// The revision of the structure corresponding to the signature field for this table. Larger revision numbers are backward compatible to lower revision numbers with the same signature.
    revision: u8 align(1),
    /// The entire table, including the checksum field, must add to zero to be considered valid.
    checksum: u8 align(1),
    /// An OEM-supplied string that identifies the OEM.
    oem_id: [6]u8 align(1),
    /// An OEM-supplied string that the OEM uses to identify the particular data table.
    oem_table_id: [8]u8 align(1),
    /// An OEM-supplied revision number. Larger numbers are assumed to be newer revisions
    oem_revision: u32 align(1),
    /// Vendor ID of utility that created the table.
    creator_id: u32 align(1),
    /// Revision of utility that created the table.
    creator_revision: u32 align(1),

    /// Verify the checksum
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
