//! Bootloader logging: hooks `rstd.logging.logFn` up to std.log. Output
//! path is `std.Options.debug_io` (see io/); only the timestamp source
//! for the log-line prefix is managed here.

const rstd = @import("rstd");
const logging = rstd.logging;
const io_time = rstd.io.time;

pub const logFn = logging.logFn;

/// Call after `io.init()` so log lines get real timestamps instead of -1.
pub fn initLogging() void {
    logging.get_time = &io_time.getTimeSeconds;
}

/// After this, log lines fall back to a -1 timestamp; output goes dark
/// once `io.stop()` severs the console.
pub fn stopLogging() void {
    logging.get_time = null;
}
