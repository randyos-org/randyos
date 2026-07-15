//! Provides a "seconds since boot" clock for the bootloader.
//!
//! `RuntimeServices.getTime()` reads a real hardware RTC, which may only ever
//! tracks whole seconds.  For example, OVMF reports `nanosecond = 0`
//! unconditionally, so there's no sub-second data to extract there no matter
//! how much print precision is used.
//!
//! A raw cycle counter (e.g. x86_64's `rdtsc`) would give real sub-second
//! precision, but it's architecture-specific and UEFI itself is not --
//! this project's bootloader only targets x86_64 today, but there's no
//! reason to bake that assumption into this module.
//!
//! Instead, this uses a periodic Boot Services timer event (100us), which is
//! plain Boot Services API available on every UEFI architecture.

const std = @import("std");
const uefi = std.os.uefi;
const Io = std.Io;
const log = std.log.scoped(.boottime);
const state = @import("state.zig");
// const BootServices = uefi.tables.BootServices;

/// Nanoseconds elapsed since `init()` was called, updated by `tick` every
/// time the periodic timer event fires.
var elapsed_ns: u64 = std.math.maxInt(u64); // "-1", as a sentinel for "never started"

/// Granularity of `getElapsedNanoseconds()`; pub so io.zig can report it as
/// the monotonic clock resolution.
pub const tick_period_ns: u64 = 100_000; // 100us
/// `setTimer`'s `trigger_time` is in units of 100ns.
const tick_period_100ns: u64 = tick_period_ns / 100;

fn tick(event: uefi.Event, context: ?*anyopaque) callconv(uefi.cc) void {
    _ = event;
    _ = context;
    _ = @atomicRmw(u64, &elapsed_ns, .Add, tick_period_ns, .seq_cst);
}

/// Start the periodic timer event backing `getTime()`. Call this once,
/// early in bootloader init.
///
/// Nothing needs to explicitly stop this later. The event's `tick`
/// callback is only ever invoked by Boot Services' own event-dispatch
/// loop, which is firmware code -- once `ExitBootServices` succeeds and
/// the OS owns the CPU, that loop simply never runs again, so `tick` can't
/// fire anymore either way. The event's backing memory is Boot
/// Services-owned and becomes reclaimable the moment `ExitBootServices`
/// succeeds (see the comment in bootloader `main.zig`), so there's nothing
/// to leak by not explicitly closing it. Tearing down whatever real
/// hardware timer backs this event is the firmware's own responsibility as
/// part of its `ExitBootServices` handling -- and also moot, since we
/// couldn't call `setTimer`/`closeEvent` after that point even if we
/// wanted to: Boot Services itself is torn down and unusable by then.
pub fn init() !void {
    const bs = state.bootServices() orelse return error.BootServicesUnavailable;
    const event = try bs.createEvent(
        .{ .timer = true, .signal = true },
        .{ .tpl = .notify, .function = &tick },
    );
    try bs.setTimer(event, .periodic, tick_period_100ns);
    elapsed_ns = 0;
}

/// Nanoseconds elapsed since `init()` was called, in the units `std.Io`'s
/// clock interface wants. Reads as `maxInt(u64)` (the "never started"
/// sentinel, rather than crashing) if `init()` was never called or failed.
pub fn getElapsedNanoseconds() u64 {
    return @atomicLoad(u64, &elapsed_ns, .seq_cst);
}

/// Seconds since `init()` as an f64, in the shape the `rstd.logging.get_time`
/// hook wants for log-line timestamps; -1 if the clock never started.
pub fn getTimeSeconds() f64 {
    const ns = getElapsedNanoseconds();
    if (ns == std.math.maxInt(u64)) return -1;
    return @as(f64, @floatFromInt(ns)) / std.time.ns_per_s;
}

fn monotonicNow() Io.Timestamp {
    const ns = getElapsedNanoseconds();
    // Map the "never started" sentinel to zero: a monotonic clock stuck at
    // zero is better behaved than one that starts at the end of time.
    return .{ .nanoseconds = if (ns == std.math.maxInt(u64)) 0 else ns };
}

pub fn now(_: ?*anyopaque, clock: Io.Clock) Io.Timestamp {
    switch (clock) {
        .real => {
            const result = uefi.system_table.runtime_services.getTime() catch return monotonicNow();
            return .{ .nanoseconds = result[0].toEpoch() };
        },
        // There are no other processes or threads to distinguish from wall
        // time, so every other clock is the since-boot tick counter.
        .awake, .boot, .cpu_process, .cpu_thread => return monotonicNow(),
    }
}

pub fn clockResolution(_: ?*anyopaque, clock: Io.Clock) Io.Clock.ResolutionError!Io.Duration {
    return switch (clock) {
        // The RTC behind getTime() only reliably tracks whole seconds (see
        // the doc comment in time.zig).
        .real => .fromSeconds(1),
        .awake, .boot, .cpu_process, .cpu_thread => .fromNanoseconds(tick_period_ns),
    };
}

pub fn sleep(_: ?*anyopaque, timeout: Io.Timeout) Io.Cancelable!void {
    const ns: i96 = switch (timeout) {
        // "No timeout" means block forever, which in a single-threaded world
        // with no cancellation would hang the machine; returning is the only
        // useful interpretation.
        .none => return,
        .duration => |d| d.raw.nanoseconds,
        .deadline => |ts| ts.raw.nanoseconds - now(null, ts.clock).nanoseconds,
    };
    if (ns <= 0) return;
    const bs = state.bootServices() orelse return;
    bs.stall(@intCast(@divTrunc(ns, std.time.ns_per_us))) catch {};
}
