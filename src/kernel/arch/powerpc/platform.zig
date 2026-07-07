//! Arch PowerPC (32-bit) main platform
//!
//! STUB: this is a roadmap placeholder, not a working port. Nothing below
//! `setup()` should be assumed to work -- `init()` panics immediately.
//!
//! Targets 32-bit big-endian PowerPC (e.g. the 750FX/G3 in classic iBooks),
//! not little-endian variants. Classic PowerPC Macs boot via Open Firmware,
//! not UEFI -- see src/bootloader/ofw/ for that side of the story; there is
//! no `boot-powerpc` build step because of it.

/// Do some essential work (where the processor can't continue without that work)
///
/// Points the stack pointer (r1, per the PowerPC ABI convention) at the
/// linker-provided `__stack_top` and branches to `_main`. This has to be
/// real, correct assembly -- there's no such thing as a "stub" entry point,
/// since it's the literal code the linker script's `ENTRY(_start)` lands on.
pub inline fn setup() void {
    asm volatile (
        \\lis 1, __stack_top@ha
        \\addi 1, 1, __stack_top@l
        \\li 0, 0
        \\mtlr 0
        \\b _main
    );
}

/// Platform-specific init
///
/// TODO: not implemented. Deliberately takes no parameters yet -- x86_64's
/// `init()` takes ACPI/IOAPIC-shaped params, but those are x86-specific
/// concepts; classic PowerPC Macs discover hardware via Open Firmware's
/// device tree instead, so a real signature should wait for that work.
pub fn init() void {
    @panic("TODO: platform init not yet implemented for powerpc");
}
