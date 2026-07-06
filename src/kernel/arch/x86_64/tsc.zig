//! TSC (Time Stamp Counter) based timekeeping.
//! There's no firmware/OS service left to ask for the time once we're
//! freestanding, so this calibrates the CPU's free-running cycle counter
//! against the PIT once at boot (polled via channel 2, so no IRQ wiring is
//! needed) and uses it afterwards as a monotonic "seconds since boot" clock.

const std = @import("std");
const log = std.log.scoped(.arch_tsc);
const port_io = @import("port_io.zig");

/// PIT base frequency (Hz)
/// https://wiki.osdev.org/Programmable_Interval_Timer#The_Oscillator
const pit_frequency: f64 = 1193182.0;
/// Calibration window, in PIT ticks (~50ms at the base frequency; comfortably
/// inside the 16-bit reload-value limit)
const calibration_ticks: u16 = @intFromFloat(@round(pit_frequency * 0.050));

var tsc_frequency: f64 = 1.0;
var boot_tsc: u64 = 0;

/// Read the Time Stamp Counter
pub inline fn rdtsc() u64 {
    var low: u32 = undefined;
    var high: u32 = undefined;
    asm volatile ("rdtsc"
        : [low] "={eax}" (low),
          [high] "={edx}" (high),
    );
    return (@as(u64, high) << 32) | low;
}

/// Busy-wait for `calibration_ticks` PIT ticks (channel 2, polled via the
/// PC speaker gate/status bits so no interrupt handling is needed), and
/// return the TSC delta observed over that window.
fn measureTscDelta() u64 {
    // Enable the channel 2 gate, keep the speaker itself off.
    port_io.outb(0x61, (port_io.inb(0x61) & 0xfd) | 0x1);
    // Channel 2, lobyte/hibyte access, mode 0 (interrupt on terminal
    // count), binary.
    port_io.outb(0x43, 0b10110000);
    port_io.outb(0x42, @truncate(calibration_ticks));
    port_io.outb(0x42, @truncate(calibration_ticks >> 8));

    const start = rdtsc();
    // OUT2 (port 0x61 bit 5) goes high once the count reaches zero.
    while (port_io.inb(0x61) & 0x20 == 0) {}
    return rdtsc() - start;
}

/// Calibrate the TSC frequency against the PIT and mark "now" as boot time.
/// Call this once, as early as possible in kernel init so log timestamps
/// are meaningful from the start.
pub fn init() void {
    const delta = measureTscDelta();
    const window_seconds: f64 = @as(f64, @floatFromInt(calibration_ticks)) / pit_frequency;
    tsc_frequency = @as(f64, @floatFromInt(delta)) / window_seconds;
    boot_tsc = rdtsc();
}

/// Seconds elapsed since `init()` was called. Matches the signature
/// `common.logging.get_time` expects.
pub fn getTime() f64 {
    const elapsed_ticks = rdtsc() - boot_tsc;
    return @as(f64, @floatFromInt(elapsed_ticks)) / tsc_frequency;
}
