const std = @import("std");
const uefi = std.os.uefi;
const log = std.log.scoped(.bootlog);

const common = @import("common");
const logging = common.logging;

pub const uefi_time = @import("uefi_time.zig");
pub const uefi_term_mod = @import("uefi_term.zig");

pub const logFn = logging.logFn;

pub fn initLogging() void {
    const term = &uefi_term_mod.uefi_term;
    logging.log_term = term;
    term.init(.{});
    // make terminal connection first so we can log if there's an error starting the clock
    uefi_time.init(uefi.system_table.boot_services.?) catch |err| {
        // an error, but not fatal, no need to panic
        log.err("starting bootloader timer failed: {s}", .{@errorName(err)});
    };
    logging.get_time = &uefi_time.getTime;
}

pub fn stopLogging() void {
    logging.log_term = null;
    logging.get_time = null;
}
