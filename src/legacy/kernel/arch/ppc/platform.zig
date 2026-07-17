//! PowerPC (32-bit) platform
//!
//! STUB: roadmap placeholder, not working. Everything below `setup()` is
//! unimplemented -- `init()` panics immediately.
//!
//! Targets 32-bit big-endian PowerPC (e.g. 750FX/G3 in classic iBooks), not
//! little-endian. Classic PowerPC Macs boot via Open Firmware, not UEFI --
//! see src/bootloader/ofw/; hence no `boot-powerpc` build step.

const std = @import("std");
const log = std.log.scoped(.arch_ppc);

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
/// Points r1 (PowerPC SP) at linker-provided `__stack_top`, branches to
/// `_main`. Must be real working asm -- it's the literal code
/// `ENTRY(_start)` lands on.
pub inline fn setup() void {
    asm volatile (
        \\lis 1, __stack_top@ha
        \\addi 1, 1, __stack_top@l
        \\li 0, 0
        \\mtlr 0
        \\b _main
    );
}

/// TODO: not implemented -- panics immediately. Same `InitParams` shape as
/// every arch so `kmain` can call uniformly; `params` unused.
pub fn init(allocator: std.mem.Allocator, params: InitParams) void {
    _ = allocator;
    _ = params;
    log.err("platform init not yet implemented for powerpc", .{});
    @panic("TODO: platform init not yet implemented for powerpc");
}
