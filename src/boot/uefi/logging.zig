const std = @import("std");
const uefi = std.os.uefi;
const log = std.log.scoped(.bootlog);

const rstd = @import("rstd");
const logging = rstd.logging;

pub const uefi_time = @import("time.zig");
pub const uefi_term_mod = @import("term.zig");

pub const logFn = logging.logFn;

pub fn initLogging() void {
    const term = &uefi_term_mod.uefi_term;
    logging.log_term = term;
    term.init(.{});

    // make terminal connection first so we can log if there's an error starting the clock
    uefi_time.init(uefi.system_table.boot_services.?) catch |err| {
        // an error, but not fatal, no need to panic.
        // ...not sure where this log message would go if the terminal isn't
        // working, but we can at least try to log it
        log.err("starting bootloader timer failed: {s}", .{@errorName(err)});
    };
    logging.get_time = &uefi_time.getTime;
}

pub fn stopLogging() void {
    logging.log_term = null;
    logging.get_time = null;
}
