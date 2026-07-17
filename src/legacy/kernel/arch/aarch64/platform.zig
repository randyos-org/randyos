//! AArch64 platform
//!
//! STUB: roadmap placeholder, not working. Everything below `setup()` is
//! unimplemented -- `init()` panics immediately.
//!
//! Covers two very different targets sharing one ISA/file: Raspberry Pi
//! (aarch64 UEFI via pftf, see `boot-aarch64` in build.zig) and Apple
//! Silicon Mac (no native UEFI, see src/bootloader/asahi/). Which one
//! applies is a `KernelBootInfo` concern (TODO in src/common/boot_info.zig),
//! not this file's.

const std = @import("std");
const log = std.log.scoped(.arch_aarch64);

const common = @import("common");
const KernelBootInfo = common.boot_info.KernelBootInfo;

/// Mirrors x86_64's `InitParams` so `kmain` can call `arch.platform.init`
/// uniformly across archs -- this stub just panics regardless of input.
pub const InitParams = struct {
    kernel_boot_info: *KernelBootInfo,
    kernel_page_size: usize,
};

/// Stub so `arch.platform.tsc.getTime()` type-checks everywhere; `init()`
/// panics before this is ever really reached.
pub const tsc = struct {
    pub fn getTime() f64 {
        return 0;
    }
};

/// Essential early setup, before which the CPU can't proceed.
///
/// Points SP at linker-provided `__stack_top`, branches to `_main`. Must be
/// real working asm -- it's the literal code `ENTRY(_start)` lands on.
pub inline fn setup() void {
    asm volatile (
        \\adrp x0, __stack_top
        \\add x0, x0, :lo12:__stack_top
        \\mov sp, x0
        \\mov x30, xzr
        \\b _main
    );
}

/// TODO: not implemented -- panics immediately. Same `InitParams` shape as
/// every arch so `kmain` can call uniformly; `params` unused.
pub fn init(allocator: std.mem.Allocator, params: InitParams) void {
    _ = allocator;
    _ = params;
    log.err("platform init not yet implemented for aarch64", .{});
    @panic("TODO: platform init not yet implemented for aarch64");
}
