//! Arch-specific kernel code
//! 2024 by Samuel Fiedler

const std = @import("std");
const builtin = @import("builtin");
const log = std.log.scoped(.arch);

pub const platform = switch (builtin.cpu.arch) {
    .x86_64 => @import("x86_64/platform.zig"),
    .aarch64 => @import("aarch64/platform.zig"),
    .arm => @import("arm/platform.zig"),
    .powerpc => @import("ppc/platform.zig"),
    else => @compileError("No architecture-specific code for this architecture!"),
};
