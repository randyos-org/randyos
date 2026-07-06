//! Provides a "seconds since boot" clock for the bootloader.
//!
//! `RuntimeServices.getTime()` reads a real hardware RTC, which only ever
//! tracks whole seconds -- OVMF (and real firmware) reports `nanosecond = 0`
//! unconditionally, there's no sub-second data to extract there no matter
//! how much print precision is used.
//!
//! A raw cycle counter (e.g. x86_64's `rdtsc`) would give real sub-second
//! precision, but it's architecture-specific and UEFI itself is not --
//! this project's bootloader only targets x86_64 today, but there's no
//! reason to bake that assumption into this module.
//!
//! Instead, this uses a periodic Boot Services timer event (1ms), which is
//! plain Boot Services API available on every UEFI architecture.

const std = @import("std");
const uefi = std.os.uefi;
const log = std.log.scoped(.uefi_time);
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
