//! PS/2 Keyboard Controller
//! 2024 by Samuel Fiedler

const log = @import("std").log.scoped(.arch_ps2);

const idt = @import("idt.zig");
const port_io = @import("port_io.zig");
const ioapic = @import("ioapic.zig");
const lapic = @import("lapic.zig");

/// Scancode ring buffer, ISR (producer) to `processPending` (consumer).
/// SPSC, so plain non-atomic indices are fine here (word r/w already
/// atomic on x86, no SMP to race with yet -- revisit if SMP lands).
const ring_size = 64;
var ring: [ring_size]u8 = undefined;
var ring_head: usize = 0;
var ring_tail: usize = 0;

/// PS/2 controller data port (scan code in/out)
const ps2_data_port: u16 = 0x60;

/// scan code set 1: codes below this are "make" (press); high bit set
/// (>= 128) marks the "break" (release) code for the same key
const scancode_break_threshold: u8 = 128;

/// Top-half ISR. Must stay fast (runs with interrupts disabled): ack, read
/// reg, queue byte, defer everything else to `processPending`.
pub fn keyboardHandler() void {
    // edge-triggered, so EOI before reading the byte
    lapic.eoi();
    const scan_code = port_io.inb(ps2_data_port);
    const next_head = (ring_head + 1) % ring_size;
    if (next_head != ring_tail) {
        ring[ring_head] = scan_code;
        ring_head = next_head;
    } else {
        log.warn("scancode ring buffer full, dropping byte", .{});
    }
}

/// Bottom half: drains scancodes piled up since last call. Called from the
/// idle loop today; becomes an input task's body once a scheduler exists.
pub fn processPending() void {
    while (ring_tail != ring_head) {
        const scan_code = ring[ring_tail];
        ring_tail = (ring_tail + 1) % ring_size;
        if (scan_code < scancode_break_threshold) {
            log.info("The interrupt seems to be a key press. Scan code: {}", .{scan_code});
        } else {
            log.info("The interrupt seems to be a key release. Scan code: {}", .{scan_code});
        }
    }
}
