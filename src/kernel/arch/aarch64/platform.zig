//! Arch AArch64 main platform
//!
//! STUB: this is a roadmap placeholder, not a working port. Nothing below
//! `setup()` should be assumed to work -- `init()` panics immediately.
//!
//! Covers two real target machines with very different boot stories, even
//! though the CPU instruction set and this file are identical for both:
//! Raspberry Pi (aarch64 UEFI via pftf firmware -- see `boot-aarch64` in
//! build.zig) and Apple Silicon Mac (no native UEFI at all -- see
//! src/bootloader/asahi/). Which one applies is a `KernelBootInfo`/boot-info
//! concern (see the TODO in src/common/boot_info.zig), not something this
//! file needs to know about.

const std = @import("std");
const log = std.log.scoped(.arch_aarch64);

const common = @import("common");
const KernelBootInfo = common.boot_info.KernelBootInfo;

/// Mirrors x86_64's `InitParams` shape so `src/kernel/main.zig`'s `kmain`
/// can call `arch.platform.init(allocator, .{...})` uniformly across every
/// arch without its own `builtin.cpu.arch` gate -- this stub's `init` just
/// panics immediately regardless of what it's given.
pub const InitParams = struct {
    kernel_boot_info: *KernelBootInfo,
    kernel_page_size: usize,
};

/// TSC-shaped stub: `src/kernel/time/root.zig` calls `arch.platform.tsc
/// .getTime()` unconditionally (wall-clock math needs a monotonic clock
/// on every arch, not just x86_64), so this needs to exist and type-check
/// even though it's never meaningfully reached -- `init()` below panics
/// before `kmain` gets anywhere near a real timekeeping call.
pub const tsc = struct {
    pub fn getTime() f64 {
        return 0;
    }
};

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
/// TODO: not implemented -- panics immediately. Takes the same `InitParams`
/// shape as every other arch (see above) purely so `kmain` can call this
/// uniformly; nothing inside actually uses `params` yet.
pub fn init(allocator: std.mem.Allocator, params: InitParams) void {
    _ = allocator;
    _ = params;
    log.err("platform init not yet implemented for aarch64", .{});
    @panic("TODO: platform init not yet implemented for aarch64");
}
