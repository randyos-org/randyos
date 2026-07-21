const std = @import("std");

const rstd = @import("rstd");
const rio = rstd.io;

const logging = @import("logging.zig");

/// Standard Library Options
pub const std_options = std.Options{
    // .log_level = .info,
    .log_level = .debug,
    .logFn = logging.logFn,
};

/// Routes `std.debug.print`, `std.log`, and the default panic handler
/// through the UEFI console.
pub const std_options_debug_io = rstd.zigconfig.std_options_debug_io;
pub const std_options_cwd = rstd.zigconfig.std_options_cwd;
pub const os = struct {
    pub const PATH_MAX = rstd.zigconfig.os.PATH_MAX;
    pub const NAME_MAX = rstd.zigconfig.os.NAME_MAX;
    pub const heap = struct {
        // pub const page_allocator: std.mem.Allocator = std.heap.page_allocator;
    };
};
