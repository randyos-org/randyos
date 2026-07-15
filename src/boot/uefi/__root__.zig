const std = @import("std");
const log = std.log.scoped(.bootuefi);

pub const loader = @import("loader/__root__.zig");
pub const memory = @import("memory.zig");
pub const uefi_io = @import("io/__root__.zig").uefi_io;
pub const logging = @import("logging.zig");
pub const graphics = @import("graphics.zig");
pub const bootinfomod = @import("bootinfo.zig");
pub const watchdog = @import("watchdog.zig");

/// Standard Library Options
pub const std_options = std.Options{
    // .log_level = .info,
    .log_level = .debug,
    .logFn = logging.logFn,
};

/// Routes `std.debug.print`, `std.log`, and the default panic handler
/// through the UEFI console.
pub const std_options_debug_io = uefi_io;

pub const main = @import("__main__.zig").main;
