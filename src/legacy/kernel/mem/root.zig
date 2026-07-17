//! Memory operations for the Zig OS Kernel
//! 2024 by Samuel Fiedler

const log = @import("std").log.scoped(.mem);
pub const kernel_page_allocator = @import("kernel_page_allocator.zig");

/// Move memory; may overlap, both slices same length.
pub fn memmove(comptime T: type, dest: []T, src: []const T) void {
    if (dest.len != src.len) {
        log.err("Destination and source slices have different lengths, cannot move properly! ", .{});
        return;
    }
    const len = src.len;
    if (@intFromPtr(dest.ptr) < @intFromPtr(src.ptr)) {
        // dest before src: front-to-back never overwrites unread src
        var index: usize = 0;
        while (index < len) : (index += 1) {
            dest[index] = src[index];
        }
    } else {
        // dest at/after src: mirror above, back-to-front
        var index: usize = len;
        while (index > 0) {
            index -= 1;
            dest[index] = src[index];
        }
    }
}

/// Move memory (volatile); may overlap, both slices same length.
pub fn memmoveVolatile(comptime T: type, dest: []volatile T, src: []const volatile T) void {
    if (dest.len != src.len) {
        log.err("Destination and source slices have different lengths, cannot move properly! ", .{});
        return;
    }
    const len = src.len;
    if (@intFromPtr(dest.ptr) < @intFromPtr(src.ptr)) {
        var index: usize = 0;
        while (index < len) : (index += 1) {
            dest[index] = src[index];
        }
    } else {
        var index: usize = len;
        while (index > 0) {
            index -= 1;
            dest[index] = src[index];
        }
    }
}
