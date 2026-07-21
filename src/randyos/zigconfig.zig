const std = @import("std");
const constants = @import("constants.zig");

pub const os = struct {
    pub const PATH_MAX = constants.PATH_MAX;
    pub const NAME_MAX = constants.NAME_MAX;
    pub const heap = struct {
        // pub const page_allocator: std.mem.Allocator = std.heap.page_allocator;
    };
};
