//! Bootloader logging: hooks the project-wide `rstd.logging.logFn`
//! (timestamp/level/scope prefix) up to std.log. The output path itself is
//! `std.Options.debug_io` (see io/), so the only thing left to manage here
//! is the timestamp source for the log-line prefix.

const rstd = @import("rstd");
const logging = rstd.logging;
const io_time = rstd.io.time;

pub const logFn = logging.logFn;

/// Call after `io.init()` (which starts the tick clock backing
/// `getTimeSeconds`) so log lines carry real timestamps instead of -1.
pub fn initLogging() void {
    logging.get_time = &io_time.getTimeSeconds;
}

/// After this, any further log lines fall back to a -1 timestamp; the
/// output itself goes dark when `io.stop()` severs the console.
pub fn stopLogging() void {
    logging.get_time = null;
}
