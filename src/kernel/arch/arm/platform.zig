//! Arch ARM (32-bit) main platform
//!
//! STUB: this is a roadmap placeholder, not a working port. Nothing below
//! `setup()` should be assumed to work -- `init()` panics immediately.
//!
//! Real target: Raspberry Pi 3 running a 32-bit (armv7/armhf) OS. The Pi 3's
//! SoC is aarch64-capable and does have real UEFI firmware (pftf), but that
//! firmware runs the board in 64-bit mode -- it doesn't provide a boot path
//! for a 32-bit OS (ARM UEFI has no real "32-bit compat mode" equivalent to
//! x86's CSM). So this is not the same target as `src/kernel/arch/aarch64/`
//! even though it can run on the same physical board; see
//! src/bootloader-rpi/ for the (unimplemented) non-UEFI boot story that
//! actually applies here.
//!
//! Note: this targets plain `arm` (ARM instruction set), not `thumb`. If
//! whatever hands off to this code does so in Thumb state, the entry
//! sequence below will need an interworking branch (`bx`) to switch
//! processor state; not addressed here.

/// Do some essential work (where the processor can't continue without that work)
///
/// Points the stack pointer at the linker-provided `__stack_top` and
/// branches to `_main`. This has to be real, correct assembly -- there's no
/// such thing as a "stub" entry point, since it's the literal code the
/// linker script's `ENTRY(_start)` lands on.
pub inline fn setup() void {
    asm volatile (
        \\ldr sp, =__stack_top
        \\mov lr, #0
        \\b _main
    );
}

/// Platform-specific init
///
/// TODO: not implemented. Deliberately takes no parameters yet -- x86_64's
/// `init()` takes ACPI/IOAPIC-shaped params, but those are x86-specific
/// concepts; arm boards mostly discover hardware via a device tree instead,
/// so a real signature should wait for that work.
pub fn init() void {
    @panic("TODO: platform init not yet implemented for arm");
}
