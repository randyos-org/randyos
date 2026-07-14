const std = @import("std");
const log = std.log.scoped(.bootuefi);

pub const loader = @import("loader/__root__.zig");
pub const memory = @import("memory.zig");
pub const logging = @import("logging.zig");
pub const graphics = @import("graphics.zig");
pub const bootinfomod = @import("bootinfo.zig");
pub const filesys = @import("filesys.zig");
pub const watchdog = @import("watchdog.zig");
pub const term = @import("term.zig");
pub const time = @import("time.zig");

/// Standard Library Options
pub const std_options = std.Options{
    .log_level = .info,
    .logFn = logging.logFn,
};

pub const main = @import("__main__.zig").main;
