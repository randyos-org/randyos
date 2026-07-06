//! ACPI Root System Descriptor Pointer
//! 2024 by Samuel Fiedler

const std = @import("std");
const log = std.log.scoped(.acpi_rsdp);

pub const ChecksumError = error{
    InvalidChecksum,
};

/// Root System Descriptor Pointer
pub const RSDP = extern struct {
    /// "RSD PTR " (Notice that this signature must contain a trailing blank character)
    signature: [8]u8 align(1),
    /// This is the checksum of the fields defined in the ACPI 1.0 specification.
    /// This includes only the first 20 bytes of this table, bytes 0 to 19, including the checksum field.
    /// These bytes must sum to zero.
    checksum: u8 align(1),
    /// An OEM-supplied string that identifies the OEM.
    oem_id: [6]u8 align(1),
    /// The revision of this structure.
    /// Larger revision numbers are backward compatible to lower revision numbers.
    /// The ACPI version 1.0 revision number of this table is zero.
    /// The ACPI version 1.0 RSDP Structure only includes the first 20 bytes of this table, bytes 0 to 19. It does not include the Length field and beyond.
    /// The current value for this field is 2.
    revision: u8 align(1),
    /// 32bit physical address of the RSDT
    rsdt_addr: u32 align(1),
    /// The length of the table, in bytes, including the header, starting from offset 0.
    /// This field is used to record the size of the entire table.
    /// This field is not available in the ACPI version 1.0 RSDP Structure.
    length: u32 align(1),
    /// 64bit physical address of the XSDT.
    /// This field is not available in the ACPI version 1.0 RSDP Structure.
    xsdt_addr: u64 align(1),
    /// This is a checksum of the entire table, including both checksum fields.
    /// This field is not available in the ACPI version 1.0 RSDP Structure.
    ext_checksum: u8 align(1),
    /// Reserved field
    /// This field is not available in the ACPI version 1.0 RSDP Structure.
    res1: [3]u8 align(1),

    /// Verify the checksum
    pub fn verifyChecksum(self: *RSDP) ChecksumError!void {
        var sum: u8 = 0;
        const arr: [*]u8 = @ptrCast(self);
        switch (self.revision) {
            0 => for (arr[0..20]) |val| {
                sum +%= val;
            },
            2 => for (arr[0..self.length]) |val| {
                sum +%= val;
            },
            else => log.err("Invalid ACPI RSDP revision!", .{}),
        }
        if (sum != 0) {
            return error.InvalidChecksum;
        }
    }
};

test "compile" {
    try std.testing.expect(@sizeOf(RSDP) == 36);
}
