//! Arch AArch64 main platform
//!
//! STUB: this is a roadmap placeholder, not a working port. Nothing below
//! `setup()` should be assumed to work -- `init()` panics immediately.
//!
//! Covers two real target machines with very different boot stories, even
//! though the CPU instruction set and this file are identical for both:
//! Raspberry Pi (aarch64 UEFI via pftf firmware -- see `boot-aarch64` in
//! build.zig) and Apple Silicon Mac (no native UEFI at all -- see
//! src/bootloader-asahi/). Which one applies is a `KernelBootInfo`/boot-info
//! concern (see the TODO in src/common/boot_info.zig), not something this
//! file needs to know about.

/// Do some essential work (where the processor can't continue without that work)
///
/// Points the stack pointer at the linker-provided `__stack_top` and
/// branches to `_main`. This has to be real, correct assembly -- there's no
/// such thing as a "stub" entry point, since it's the literal code the
/// linker script's `ENTRY(_start)` lands on.
pub inline fn setup() void {
    asm volatile (
        \\adrp x0, __stack_top
        \\add x0, x0, :lo12:__stack_top
        \\mov sp, x0
        \\mov x30, xzr
        \\b _main
    );
}

/// Platform-specific init
///
/// TODO: not implemented. Deliberately takes no parameters yet -- x86_64's
/// `init()` takes ACPI/IOAPIC-shaped params, but those are x86-specific
/// concepts; aarch64 boards mostly discover hardware via a device tree
/// instead, so a real signature should wait for that work.
pub fn init() void {
    @panic("TODO: platform init not yet implemented for aarch64");
}
