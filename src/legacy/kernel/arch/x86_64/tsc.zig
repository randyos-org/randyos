//! TSC-based timekeeping. No firmware/OS time service once freestanding,
//! so calibrate the free-running cycle counter against the PIT once at
//! boot (polled via channel 2, no IRQ needed) and use it after as a
//! monotonic "seconds since boot" clock.

const std = @import("std");
const log = std.log.scoped(.arch_tsc);
const port_io = @import("port_io.zig");

/// PIT base freq (Hz), https://wiki.osdev.org/Programmable_Interval_Timer#The_Oscillator
const pit_frequency: f64 = 1193182.0;
/// calibration window; comfortably inside 16-bit reload limit (~50ms)
const calibration_window_seconds: f64 = 0.050;
/// calibration window, in PIT ticks
const calibration_ticks: u16 = @intFromFloat(@round(pit_frequency * calibration_window_seconds));

/// PC speaker/NMI status-control port: bit 0 gates PIT ch2 clock, bit 1
/// enables speaker, bit 5 reflects ch2's OUT2 output level
const pc_speaker_port: u16 = 0x61;
/// bit 0 of pc_speaker_port: PIT channel 2 gate enable
const timer2_gate_bit: u8 = 0b0000_0001;
/// bit 1 of pc_speaker_port: PC speaker data enable
const speaker_enable_bit: u8 = 0b0000_0010;
/// bit 5 of pc_speaker_port: ch2 OUT2, high once count hits zero
const timer2_output_bit: u8 = 0b0010_0000;

/// PIT command (mode/control) register port
const pit_command_port: u16 = 0x43;
/// PIT channel 2 data port
const pit_channel2_port: u16 = 0x42;
/// channel 2, lobyte/hibyte, mode 0 (interrupt on terminal count), binary
const pit_channel2_mode_cmd: u8 = 0b1011_0000;

var tsc_frequency: f64 = 1.0;
var boot_tsc: u64 = 0;

pub inline fn rdtsc() u64 {
    var low: u32 = undefined;
    var high: u32 = undefined;
    asm volatile ("rdtsc"
        : [low] "={eax}" (low),
          [high] "={edx}" (high),
    );
    return (@as(u64, high) << 32) | low;
}

/// Busy-wait `calibration_ticks` PIT ticks (ch2, polled via speaker
/// gate/status bits, no IRQ), return TSC delta over that window.
fn measureTscDelta() u64 {
    // gate channel 2, keep speaker off
    port_io.outb(pc_speaker_port, (port_io.inb(pc_speaker_port) & ~speaker_enable_bit) | timer2_gate_bit);
    port_io.outb(pit_command_port, pit_channel2_mode_cmd);
    port_io.outb(pit_channel2_port, @truncate(calibration_ticks));
    port_io.outb(pit_channel2_port, @truncate(calibration_ticks >> 8));

    const start = rdtsc();
    while (port_io.inb(pc_speaker_port) & timer2_output_bit == 0) {}
    return rdtsc() - start;
}

/// Calibrate TSC freq against PIT, mark "now" as boot time. Call once,
/// as early as possible, so log timestamps are meaningful from the start.
pub fn init() void {
    const delta = measureTscDelta();
    const window_seconds: f64 = @as(f64, @floatFromInt(calibration_ticks)) / pit_frequency;
    tsc_frequency = @as(f64, @floatFromInt(delta)) / window_seconds;
    boot_tsc = rdtsc();
}

/// Seconds since `init()`; matches `common.logging.get_time`'s signature
pub fn getTime() f64 {
    const elapsed_ticks = rdtsc() - boot_tsc;
    return @as(f64, @floatFromInt(elapsed_ticks)) / tsc_frequency;
}
