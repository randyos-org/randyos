const sysinfo = @import("builtin");
const build_options = @import("build_options");

const std = @import("std");
const log = std.log.scoped(.logging);

const Terminal = @import("Terminal.zig");
const ansi = @import("ansi.zig");

/// Platform-specific default logging terminal
pub var log_term: ?*Terminal = null;

/// Platform-specific hook for getting a "seconds since boot" timestamp for
/// log lines
pub var get_time: ?*const fn () f64 = null;

/// timestamp, start_color, level, end_color, scope (then caller's own format string/args)
const log_prefix_fmt = "{d:.4} [{s}{s}{s}]({s}): ";

/// Guards against re-entrant logging. Terminals that parse their own output
/// (e.g. the framebuffer console's ANSI/SGR handling) can call back into
/// `std.log` while a log line is still being written; without this guard,
/// printing the very first color code would recurse into itself forever.
var logging_in_progress: bool = false;

/// std.log callback (wired up via `std_options.logFn`); silently drops the
/// line if `log_term` isn't set yet (e.g. before platform init or after
/// `stopLogging()`).
pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    if (logging_in_progress) return;
    logging_in_progress = true;
    defer logging_in_progress = false;
    const scope_name = @tagName(scope);
    if (log_term) |term| {
        logToTerm(term, level, scope_name, format, args);
    }
}

/// Formats and writes a single log line to `term` (scope filtering + color).
/// Split out from `logFn` so callers can log directly to a specific terminal
/// without going through `log_term`/the reentrancy guard.
pub fn logToTerm(
    term: *Terminal,
    comptime level: std.log.Level,
    scope_name: []const u8,
    comptime format: []const u8,
    args: anytype,
) void {
    for (build_options.logger_scopes_ignore) |ignore| {
        if (std.mem.eql(u8, ignore, scope_name)) {
            return;
        }
    }
    const default_color = ansi.CSI ++ ansi.SgrCode.reset ++ ansi.SGR;
    const color = comptime switch (level) {
        .debug => ansi.CSI ++ ansi.SgrCode.fg_dark_green ++ ansi.SGR, // green
        .info => ansi.CSI ++ ansi.SgrCode.fg_dark_cyan ++ ansi.SGR, // cyan
        .warn => ansi.CSI ++ ansi.SgrCode.fg_dark_yellow ++ ansi.SGR, // yellow
        .err => ansi.CSI ++ ansi.SgrCode.fg_dark_red ++ ansi.SGR, // red
    };
    const level_name = comptime level.asText();
    // const level_char = comptime level_name[0..1];

    const use_color = term.supports_color;
    const start_color = if (use_color) color else "";
    const end_color = if (use_color) default_color else "";
    const time: f64 = if (get_time) |f| f() else -1;

    term.writer.print(log_prefix_fmt ++ format ++ ansi.CRLF, .{ time, start_color, level_name, end_color, scope_name } ++ args) catch @panic("log print failed");
    // Flush explicitly: buffering the whole line lets
    // it go out as a single `puts`/`render` pair instead of one per
    // formatting fragment, but we still want it on screen immediately --
    // e.g. if the kernel panics before ever returning to the idle loop.
    term.writer.flush() catch @panic("log flush failed");
}
