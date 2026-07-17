//! Extended System Description Table
//! 2024 by Samuel Fiedler

const std = @import("std");
const Header = @import("header.zig").Header;

const assert = std.debug.assert;
const log = std.log.scoped(.acpi_xsdt);

pub const FindError = error{
    NoMatchingEntry,
};

/// XSDT entry size: 8-byte (64-bit) pointer, vs RSDT's 4-byte ones.
pub const xsdt_entry_size: u32 = 8;

pub const XSDT = extern struct {
    header: Header align(1),

    pub fn findEntry(self: *XSDT, entry_signature: []const u8) FindError!*Header {
        const len: u32 = (self.header.length - @sizeOf(Header)) / xsdt_entry_size;
        const ptr_addr: usize = @intFromPtr(self) + @sizeOf(Header);
        const entries: [*]align(1) u64 = @ptrFromInt(ptr_addr);

        for (entries[0..len]) |entry| {
            // entry is always 64-bit (spec-mandated); truncates on 32-bit
            // archs, compile-only-stub concern only (see hw/acpi/root.zig)
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
