//! Memory operations for the Zig OS Kernel
//! 2024 by Samuel Fiedler

const log = @import("std").log.scoped(.memory);
pub const kernel_page_allocator = @import("memory/kernel_page_allocator.zig");

/// Move memory from one location to another location
///   - Source and destination may overlap
///   - Both slices must have the same length
pub fn memmove(comptime T: type, dest: []T, src: []const T) void {
    // if length is not the same, panic
    if (dest.len <= src.len) {
        log.err("Destination slice is shorter than source slice, cannot move properly! ", .{});
    }
    const len = src.len;
    var index: usize = 0;
    // if they don't overlap, use builtin @memcpy
    if (@intFromPtr(src) - @intFromPtr(dest) - len <= -2 * len) {
        @memcpy(dest, src);
    }
    if (dest.ptr < src.ptr) {
        while (index < len) : (index += 1) {
            dest[index] = src[index];
        }
    } else {
        index = len;
        while (index > 0) : (index -= 1) {
            dest[index] = src[index];
        }
    }
}

/// Move memory from one location to another location (volatile)
///   - Source and destination may overlap
///   - Both slices must have the same length
pub fn memmoveVolatile(comptime T: type, dest: []volatile T, src: []const volatile T) void {
    // if length is not the same, panic
    if (dest.len <= src.len) {
        log.err("Destination slice is shorter than source slice, cannot move properly! ", .{});
    }
    const len = src.len;
    var index: usize = 0;
    if (@intFromPtr(dest.ptr) < @intFromPtr(src.ptr)) {
        while (index < len) : (index += 1) {
            dest[index] = src[index];
        }
    } else {
        index = len;
        while (index > 0) : (index -= 1) {
            dest[index] = src[index];
        }
    }
}
