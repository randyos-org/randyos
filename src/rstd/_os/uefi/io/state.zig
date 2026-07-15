const std = @import("std");
const uefi = std.os.uefi;

const time = @import("time.zig");
const log = std.log.scoped(.iostate);

/// Set by `init()`, cleared by `stop()`. When null, console output is
/// dropped (same behavior as logging before the console exists).
pub var con_out: ?*uefi.protocol.SimpleTextOutput = null;

/// Set by `stop()`. Guards every Boot Services use in this file, so that a
/// late `std.debug.print`/panic after `exitBootServices()` degrades to
/// dropped output instead of a wild call into reclaimed firmware memory.
/// Deliberately not derived from `uefi.system_table.boot_services == null`:
/// the firmware is supposed to null that pointer on exit, but this must not
/// depend on the firmware getting that right.
pub var stopped: bool = false;

/// The opened boot-volume root directory (see `dir.openRootDir`). A single
/// slot rather than a table because `std.Io.Dir` carries no handle bits on
/// UEFI targets (`posix.fd_t` is `void`), so `Io.Dir` values cannot be told
/// apart -- there is exactly one directory this implementation can mean.
pub var root_dir: ?*uefi.protocol.File = null;

/// The single open-file slot backing `Io.File`, with the same
/// zero-handle-bits story as `root_dir`: at most one file can be open at a
/// time, and every `Io.File` value refers to it.
pub var open_file: ?*uefi.protocol.File = null;

/// Wire the UEFI console and tick clock into this `Io` implementation.
/// Call once, before anything logs; in case of a bootloader error we want
/// output working before all else.
pub fn init() void {
    if (con_out == null) {
        if (uefi.system_table.con_out) |out| {
            out.reset(false) catch {};
            con_out = out;
        }
    }
    time.init() catch |err| {
        // an error, but not fatal: log lines just won't have a monotonic
        // clock behind them. The console is already up, so this is loggable.
        log.err("starting bootloader timer failed: {s}", .{@errorName(err)});
    };
}

/// Sever this `Io` implementation from Boot Services. Must be called as soon
/// as `exitBootServices()` succeeds: `con_out`, `stall`, and the RNG protocol
/// all live in Boot Services-owned memory that the firmware is free to
/// reclaim at that point.
pub fn stop() void {
    con_out = null;
    // No close() calls here: these protocols are Boot Services-owned and
    // already gone; all that's left to do is drop the dangling pointers.
    root_dir = null;
    open_file = null;
    stopped = true;
}

pub fn bootServices() ?*uefi.tables.BootServices {
    if (stopped) return null;
    return uefi.system_table.boot_services;
}
