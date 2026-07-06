//! Memory operations for the Zig OS Kernel
//! 2024 by Samuel Fiedler

const log = @import("std").log.scoped(.memory);
pub const kernel_page_allocator = @import("memory/kernel_page_allocator.zig");

/// Move memory from one location to another location
///   - Source and destination may overlap
///   - Both slices must have the same length
pub fn memmove(comptime T: type, dest: []T, src: []const T) void {
    if (dest.len != src.len) {
        log.err("Destination and source slices have different lengths, cannot move properly! ", .{});
        return;
    }
    const len = src.len;
    if (@intFromPtr(dest.ptr) < @intFromPtr(src.ptr)) {
        // dest starts before src: copying front-to-back never overwrites a
        // src element before it's been read.
        var index: usize = 0;
        while (index < len) : (index += 1) {
            dest[index] = src[index];
        }
    } else {
        // dest starts at/after src: mirror the above by copying back-to-front.
        var index: usize = len;
        while (index > 0) {
            index -= 1;
            dest[index] = src[index];
        }
    }
}

/// Move memory from one location to another location (volatile)
///   - Source and destination may overlap
///   - Both slices must have the same length
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
