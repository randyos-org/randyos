//! ARM (32-bit) platform
//!
//! STUB: roadmap placeholder, not working. Everything below `setup()` is
//! unimplemented -- `init()` panics immediately.
//!
//! Target: Raspberry Pi 3, 32-bit (armv7/armhf). Pi 3's UEFI (pftf) only
//! boots 64-bit mode -- no ARM UEFI 32-bit compat path (unlike x86 CSM).
//! So not the same target as aarch64/, despite same board; see
//! src/bootloader/rpi/ for the (unimplemented) non-UEFI boot story here.
//!
//! Targets plain `arm` ISA, not `thumb`. If handoff arrives in Thumb state,
//! entry needs an interworking `bx`; not handled here.

const std = @import("std");
const log = std.log.scoped(.arch_arm);

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
        \\ldr sp, =__stack_top
        \\mov lr, #0
        \\b _main
    );
}

/// TODO: not implemented -- panics immediately. Same `InitParams` shape as
/// every arch so `kmain` can call uniformly; `params` unused.
pub fn init(allocator: std.mem.Allocator, params: InitParams) void {
    _ = allocator;
    _ = params;
    log.err("platform init not yet implemented for arm", .{});
    @panic("TODO: platform init not yet implemented for arm");
}
