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
/// Calibration window length (seconds). Comfortably inside the 16-bit
/// reload-value limit at the PIT's base frequency (~50ms of ticks).
const calibration_window_seconds: f64 = 0.050;
/// Calibration window, in PIT ticks.
const calibration_ticks: u16 = @intFromFloat(@round(pit_frequency * calibration_window_seconds));

/// I/O port for the PC speaker/NMI status-and-control register: bit 0 gates
/// PIT channel 2's clock input, bit 1 enables the speaker itself, bit 5
/// reflects channel 2's current OUT2 output level.
const pc_speaker_port: u16 = 0x61;
/// `pc_speaker_port` bit 0: PIT channel 2 gate enable.
const timer2_gate_bit: u8 = 0b0000_0001;
/// `pc_speaker_port` bit 1: PC speaker data enable.
const speaker_enable_bit: u8 = 0b0000_0010;
/// `pc_speaker_port` bit 5: PIT channel 2's OUT2 output, high once its count
/// reaches zero.
const timer2_output_bit: u8 = 0b0010_0000;

/// PIT command (mode/control) register port.
const pit_command_port: u16 = 0x43;
/// PIT channel 2 data port.
const pit_channel2_port: u16 = 0x42;
/// PIT command byte: channel 2, lobyte/hibyte access, mode 0 (interrupt on
/// terminal count), binary (not BCD) counting.
const pit_channel2_mode_cmd: u8 = 0b1011_0000;

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
    port_io.outb(pc_speaker_port, (port_io.inb(pc_speaker_port) & ~speaker_enable_bit) | timer2_gate_bit);
    port_io.outb(pit_command_port, pit_channel2_mode_cmd);
    port_io.outb(pit_channel2_port, @truncate(calibration_ticks));
    port_io.outb(pit_channel2_port, @truncate(calibration_ticks >> 8));

    const start = rdtsc();
    while (port_io.inb(pc_speaker_port) & timer2_output_bit == 0) {}
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
