//! System time.
//!
//! tsc gives monotonic seconds-since-boot, not wall-clock. Bootloader
//! reads wall clock (UEFI/devicetree RTC/etc, its concern) and hands
//! kernel a Unix epoch-seconds snapshot; init() stores it and adds TSC's
//! elapsed seconds after, avoiding repeated (slow, unsafe post-paging)
//! firmware calls.
//!
//! Also provides sleep, a TSC busy-wait -- no scheduler yet, so that's
//! the only option.

const std = @import("std");
const log = std.log.scoped(.time);
const epoch = std.time.epoch;

const arch = @import("../arch/root.zig");
const tsc = arch.platform.tsc;

/// wall-clock date/time from now()
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

/// epoch secs at init(); null if never called or unknown
var boot_epoch_seconds: ?i64 = null;

/// Record boot wall-clock snapshot. Call once, early, after tsc.init().
pub fn init(epoch_seconds: ?i64) void {
    if (epoch_seconds == null) {
        log.warn("no wall-clock time available from bootloader", .{});
    }
    boot_epoch_seconds = epoch_seconds;
    logNow();
}

/// Current UTC time: boot snapshot + TSC elapsed. null if never captured.
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

/// Busy-wait ~seconds via TSC. No scheduler yet, so it just spins the
/// CPU -- fine for boot output spacing, not latency/power-sensitive uses.
pub fn sleep(seconds: f64) void {
    const deadline = tsc.getTime() + seconds;
    while (tsc.getTime() < deadline) {}
}

/// sleep() wrapper for ms
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
