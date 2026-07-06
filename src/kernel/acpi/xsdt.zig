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

/// Extended System Description Table
pub const XSDT = extern struct {
    header: Header align(1),

    /// Find XSDT Entry
    pub fn findEntry(self: *XSDT, entry_signature: []const u8) FindError!*Header {
        const len: u32 = (self.header.length - @sizeOf(Header)) / 8;
        const ptr_addr: usize = @intFromPtr(self) + @sizeOf(Header);
        const entries: [*]align(1) u64 = @ptrFromInt(ptr_addr);

        for (entries[0..len]) |entry| {
            const item_ptr: *Header = @ptrFromInt(entry);
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
