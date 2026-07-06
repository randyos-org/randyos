//! PS/2 Keyboard Controller
//! 2024 by Samuel Fiedler

const log = @import("std").log.scoped(.arch_ps2);

const idt = @import("idt.zig");
const port_io = @import("port_io.zig");
const ioapic = @import("ioapic.zig");
const lapic = @import("lapic.zig");

/// Pending-scancode ring buffer between the ISR (producer) and
/// `processPending` (consumer). Single-producer/single-consumer, so plain
/// (non-atomic) indices are fine on this single-core target -- word-sized
/// reads/writes are already atomic on x86, and there's no SMP yet to race
/// with. Revisit if SMP ever lands.
const ring_size = 64;
var ring: [ring_size]u8 = undefined;
var ring_head: usize = 0;
var ring_tail: usize = 0;

/// Interrupt Handler (top half)
/// Must stay fast: this runs with interrupts disabled for its entire
/// duration. Do the minimum required at interrupt time -- ack, read the
/// hardware register, queue the byte -- and defer everything else (logging,
/// eventually keymap translation) to `processPending`.
pub fn keyboardHandler() void {
    // trigger mode is edge, so we need to EOI before we read the byte
    lapic.eoi();
    const scan_code = port_io.inb(0x60);
    const next_head = (ring_head + 1) % ring_size;
    if (next_head != ring_tail) {
        ring[ring_head] = scan_code;
        ring_head = next_head;
    } else {
        log.warn("scancode ring buffer full, dropping byte", .{});
    }
}

/// Bottom half: drains and processes whatever scancodes have piled up since
/// the last call. Deliberately just an ordinary function -- meant to be
/// called from the idle loop today, and to become the body of a dedicated
/// input task once a scheduler exists, with no changes needed here.
pub fn processPending() void {
    while (ring_tail != ring_head) {
        const scan_code = ring[ring_tail];
        ring_tail = (ring_tail + 1) % ring_size;
        if (scan_code < 128) {
            log.info("The interrupt seems to be a key press. Scan code: {}", .{scan_code});
        } else {
            log.info("The interrupt seems to be a key release. Scan code: {}", .{scan_code});
        }
    }
}
