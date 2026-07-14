//! Arch PowerPC (32-bit) main platform
//!
//! STUB: this is a roadmap placeholder, not a working port. Nothing below
//! `setup()` should be assumed to work -- `init()` panics immediately.
//!
//! Targets 32-bit big-endian PowerPC (e.g. the 750FX/G3 in classic iBooks),
//! not little-endian variants. Classic PowerPC Macs boot via Open Firmware,
//! not UEFI -- see src/bootloader/ofw/ for that side of the story; there is
//! no `boot-powerpc` build step because of it.

const std = @import("std");
const log = std.log.scoped(.arch_ppc);

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
/// TODO: not implemented -- panics immediately. Takes the same `InitParams`
/// shape as every other arch (see above) purely so `kmain` can call this
/// uniformly; nothing inside actually uses `params` yet.
pub fn init(allocator: std.mem.Allocator, params: InitParams) void {
    _ = allocator;
    _ = params;
    log.err("platform init not yet implemented for powerpc", .{});
    @panic("TODO: platform init not yet implemented for powerpc");
}
