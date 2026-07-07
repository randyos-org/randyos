//! System time.
//!
//! `arch.platform.tsc` already gives a monotonic "seconds since boot" clock
//! for log timestamps, but that's not wall-clock time. The bootloader reads
//! the platform's wall clock (however it does that -- UEFI Runtime
//! Services, a devicetree RTC, etc. -- is a bootloader/firmware concern) and
//! hands the kernel a plain Unix epoch-seconds snapshot in `KernelBootInfo`;
//! `init()` stores that and combines it with the TSC's elapsed-seconds count
//! afterward, avoiding repeated firmware calls (slow, and of dubious safety
//! once our own GDT/paging are active) while still tracking wall-clock time.
//!
//! This also provides `sleep`, a busy-wait built on the same TSC clock.
//! There's no scheduler yet, so busy-waiting is the only option.

const std = @import("std");
const log = std.log.scoped(.time);
const epoch = std.time.epoch;

const arch = @import("arch.zig");
const tsc = arch.platform.tsc;

/// Wall-clock date/time, as returned by `now()`.
pub const DateTime = struct {
    year: epoch.Year,
    month: epoch.Month,
    /// 1-31
    day: u8,
    /// 0-23
    hour: u8,
    /// 0-59
    minute: u8,
    /// 0-59
    second: u8,
};

/// Unix epoch seconds captured at the moment `init()` ran. `null` if
/// `init()` was never called or the bootloader couldn't determine the time.
var boot_epoch_seconds: ?i64 = null;

/// Record the wall-clock snapshot the bootloader captured at boot. Call
/// this once, early in kernel init, after `arch.platform.tsc.init()`.
pub fn init(epoch_seconds: ?i64) void {
    if (epoch_seconds == null) {
        log.warn("no wall-clock time available from bootloader", .{});
    }
    boot_epoch_seconds = epoch_seconds;
    logNow();
}

/// Current wall-clock date/time (UTC), derived from the boot-time snapshot
/// plus TSC-measured elapsed seconds. `null` if `init()` never captured a
/// valid snapshot.
pub fn now() ?DateTime {
    const boot = boot_epoch_seconds orelse return null;
    const secs = boot + @as(i64, @intFromFloat(tsc.getTime()));
    const epoch_seconds = epoch.EpochSeconds{ .secs = @intCast(secs) };
    const day_seconds = epoch_seconds.getDaySeconds();
    const year_day = epoch_seconds.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    return .{
        .year = year_day.year,
        .month = month_day.month,
        .day = @as(u8, month_day.day_index) + 1,
        .hour = day_seconds.getHoursIntoDay(),
        .minute = day_seconds.getMinutesIntoHour(),
        .second = day_seconds.getSecondsIntoMinute(),
    };
}

/// Busy-wait for approximately `seconds`, using the TSC-based monotonic
/// clock. There's no scheduler yet, so this simply spins the CPU -- fine for
/// spacing out boot-time test output, not for anything latency-sensitive or
/// power-conscious.
pub fn sleep(seconds: f64) void {
    const deadline = tsc.getTime() + seconds;
    while (tsc.getTime() < deadline) {}
}

/// Convenience wrapper around `sleep` for millisecond durations.
pub fn sleepMs(ms: u64) void {
    sleep(@as(f64, @floatFromInt(ms)) / 1000.0);
}

pub fn logNow() void {
    if (now()) |dt| {
        log.info("Current wall time: {}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2} UTC", .{
            dt.year, dt.month.numeric(), dt.day, dt.hour, dt.minute, dt.second,
        });
    }
}
