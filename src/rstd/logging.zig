//! Project-wide log formatting: a `std.log` callback that prefixes every
//! line with a seconds-since-boot timestamp and the (colored) level/scope,
//! e.g. `12.3456 [info](kmain): ...`. That prefix is the whole reason this
//! exists instead of `std.log.defaultLog`.
//!
//! Output goes through `std.Options.debug_io` (the same stderr lock
//! `std.debug.print` and the panic handler use), exactly like std's default
//! logger -- each platform provides its `Io` implementation via
//! `std_options_debug_io` and this module needs no per-platform wiring
//! beyond the `get_time` hook. `logToTerm` remains for writing directly to
//! an rstd `Terminal` instance, bypassing `debug_io` (e.g. mirroring log
//! lines to a secondary console).

// const sysinfo = @import("builtin");
const build_options = @import("build_options");

const std = @import("std");
const log = std.log.scoped(.logging);

const Terminal = @import("Terminal.zig");
// const ansi = @import("ansi.zig");

/// Platform-specific default logging terminal for `logToTerm` callers.
/// The std.log path (`logFn`) does not use this: it writes to whatever
/// `std.Options.debug_io` provides instead.
pub var log_term: ?*Terminal = null;

/// Platform-specific hook for getting a "seconds since boot" timestamp for
/// log lines
pub var get_time: ?*const fn () f64 = null;

/// timestamp, start_color, level, end_color, scope (then caller's own format string/args)
// const log_prefix_fmt = "{d:.4} [{s}{s}{s}]({s}): ";

/// Guards against re-entrant logging. Terminals that parse their own output
/// (e.g. the framebuffer console's ANSI/SGR handling) can call back into
/// `std.log` while a log line is still being written; without this guard,
/// printing the very first color code would recurse into itself forever.
var logging_in_progress: bool = false;

/// std.log callback (wired up via `std_options.logFn`). Writes through
/// `std.Options.debug_io` the same way `std.log.defaultLog` does -- taking
/// the shared stderr lock so log lines can't tear against `std.debug.print`
/// or a panic dump -- but with this project's own line format.
pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    if (logging_in_progress) return;
    logging_in_progress = true;
    defer logging_in_progress = false;

    const io = std.Options.debug_io;
    const prev = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(prev);
    var buffer: [64]u8 = undefined;
    const stderr = std.debug.lockStderr(&buffer).terminal();
    defer std.debug.unlockStderr();
    logToTerminal(stderr, level, @tagName(scope), format, args, true) catch @panic("log print failed");
}

/// Formats and writes a single log line (scope filtering, timestamp prefix,
/// colored level tag) to any `std.Io.Terminal`. Shared by `logFn` (the
/// debug_io stderr terminal) and `logToTerm` (an rstd `Terminal` wrapped in
/// one); color degrades to plain text wherever the terminal mode is
/// `.no_color`.
pub fn logToTerminal(
    t: std.Io.Terminal,
    comptime level: std.log.Level,
    scope_name: []const u8,
    comptime format: []const u8,
    args: anytype,
    use_color: bool,
) std.Io.Writer.Error!void {
    for (build_options.logger_scopes_ignore) |ignore| {
        if (std.mem.eql(u8, ignore, scope_name)) {
            return;
        }
    }
    const color: std.Io.Terminal.Color = comptime switch (level) {
        .debug => .green,
        .info => .cyan,
        .warn => .yellow,
        .err => .red,
    };
    const time: f64 = if (get_time) |f| f() else -1;

    try t.writer.print("{d:.4} [", .{time});
    if (use_color) t.setColor(color) catch {};
    try t.writer.writeAll(level.asText());
    if (use_color) t.setColor(.reset) catch {};
    try t.writer.print("]({s}): " ++ format ++ "\n", .{scope_name} ++ args);

    // Flush explicitly: buffering the whole line lets
    // it go out as a single `puts`/`render` pair instead of one per
    // formatting fragment, but we still want it on screen immediately --
    // e.g. if the kernel panics before ever returning to the idle loop.
    t.writer.flush() catch @panic("log flush failed");
}
