const std = @import("std");
const log = std.log.scoped(.bootuefi);

const rstd = @import("rstd");
const rio = rstd.io;

pub const loader = @import("loader/__root__.zig");
pub const memory = @import("memory.zig");
pub const logging = @import("logging.zig");
pub const graphics = @import("graphics.zig");
pub const bootinfomod = @import("bootinfo.zig");
pub const watchdog = @import("watchdog.zig");

pub const zigconfig = @import("zigconfig.zig");
pub const main = @import("__main__.zig").main;
