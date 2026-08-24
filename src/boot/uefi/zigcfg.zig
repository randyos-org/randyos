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
// pub const std_options_debug_io = rstd.zigconfig.std_options_debug_io;
// pub const std_options_cwd = rstd.zigconfig.std_options_cwd;
pub const std_os_options = rstd.zigcfg.std_os_options;
pub const log_module_name = "boot";
