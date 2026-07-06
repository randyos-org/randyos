//! System time.
//!
//! `arch.platform.tsc` already gives a monotonic "seconds since boot" clock
//! for log timestamps, but that's not wall-clock time. UEFI Runtime Services
//! remain callable after `ExitBootServices` and can report the real
//! date/time from the platform's RTC, so `init()` captures that once at boot
//! and combines it with the TSC's elapsed-seconds count afterward -- that
//! avoids repeated firmware calls (slow, and of dubious safety once our own
//! GDT/paging are active) while still tracking wall-clock time.
//!
//! This also provides `sleep`, a busy-wait built on the same TSC clock.
//! There's no scheduler yet, so busy-waiting is the only option.

const std = @import("std");
const log = std.log.scoped(.time);
const uefi = std.os.uefi;
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
/// `init()` was never called or the firmware refused to report the time.
var boot_epoch_seconds: ?i64 = null;

/// Convert a UEFI `Time` (a local date/time plus a UTC offset) to Unix
/// epoch seconds.
fn toEpochSeconds(t: uefi.Time) i64 {
    var days: i64 = 0;
    var year: epoch.Year = epoch.epoch_year;
    while (year < t.year) : (year += 1) {
        days += epoch.getDaysInYear(year);
    }
    var month: u4 = 1;
    while (month < t.month) : (month += 1) {
        days += epoch.getDaysInMonth(t.year, @enumFromInt(month));
    }
    days += t.day - 1;

    var secs: i64 = days * @as(i64, epoch.secs_per_day);
    secs += @as(i64, t.hour) * 3600 + @as(i64, t.minute) * 60 + t.second;
    if (t.timezone != uefi.Time.unspecified_timezone) {
        // `timezone` is minutes offset from UTC; subtract to normalize.
        secs -= @as(i64, t.timezone) * 60;
    }
    return secs;
}

/// Capture the wall-clock time from UEFI Runtime Services. Call this once,
/// early in kernel init, after `arch.platform.tsc.init()`.
pub fn init(runtime_services: *uefi.tables.RuntimeServices) void {
    const result = runtime_services.getTime() catch |err| {
        log.warn("could not read wall-clock time from firmware: {s}", .{@errorName(err)});
        return;
    };
    const t = result[0];
    boot_epoch_seconds = toEpochSeconds(t);
    log.info("wall clock at boot: {}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2} UTC", .{
        t.year, t.month, t.day, t.hour, t.minute, t.second,
    });
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
