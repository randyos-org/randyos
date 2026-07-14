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
const log = std.log.scoped(.boottime);
const BootServices = uefi.tables.BootServices;

/// Nanoseconds elapsed since `init()` was called, updated by `tick` every
/// time the periodic timer event fires.
var elapsed_ns: u64 = 0;

const tick_period_ns: u64 = 100_000; // 100us
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
pub fn init(boot_services: *BootServices) !void {
    const event = try boot_services.createEvent(
        .{ .timer = true, .signal = true },
        .{ .tpl = .notify, .function = &tick },
    );
    try boot_services.setTimer(event, .periodic, tick_period_100ns);
}

/// Seconds elapsed since `init()` was called. Matches the signature
/// `common.logging.get_time` expects. Reads as 0 (rather than crashing) if
/// `init()` was never called or failed.
pub fn getTime() f64 {
    const ns = @atomicLoad(u64, &elapsed_ns, .seq_cst);
    return @as(f64, @floatFromInt(ns)) / 1_000_000_000.0;
}
