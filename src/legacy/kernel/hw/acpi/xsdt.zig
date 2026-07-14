//! Extended System Description Table
//! 2024 by Samuel Fiedler

const std = @import("std");
const Header = @import("header.zig").Header;

const assert = std.debug.assert;
const log = std.log.scoped(.acpi_xsdt);

/// Errors that may occur during finding an entry
pub const FindError = error{
    NoMatchingEntry,
};

/// Size, in bytes, of a single XSDT entry -- an 8-byte (64-bit) table
/// pointer, unlike the RSDT's 4-byte ones.
pub const xsdt_entry_size: u32 = 8;

/// Extended System Description Table
pub const XSDT = extern struct {
    header: Header align(1),

    /// Find XSDT Entry
    pub fn findEntry(self: *XSDT, entry_signature: []const u8) FindError!*Header {
        const len: u32 = (self.header.length - @sizeOf(Header)) / xsdt_entry_size;
        const ptr_addr: usize = @intFromPtr(self) + @sizeOf(Header);
        const entries: [*]align(1) u64 = @ptrFromInt(ptr_addr);

        for (entries[0..len]) |entry| {
            // `entry` is always a 64-bit ACPI physical address
            // (spec-mandated XSDT entry width, regardless of target width);
            // truncates on 32-bit archs, where it's a compile-only stub
            // concern only (see `hw/acpi/root.zig`'s equivalent cast).
            const item_ptr: *Header = @ptrFromInt(@as(usize, @intCast(entry)));
            log.debug("Entry is {s}", .{item_ptr.signature});
            if (std.mem.eql(u8, item_ptr.signature[0..], entry_signature)) {
                return item_ptr;
            }
        }
        return error.NoMatchingEntry;
    }
};

test "compile" {
    try std.testing.expect(@sizeOf(XSDT) == 36);
}
