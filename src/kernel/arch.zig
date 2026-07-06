//! Architecture-specific kernel code
//! 2024 by Samuel Fiedler

const builtin = @import("builtin");

pub const platform = switch (builtin.cpu.arch) {
    .x86_64 => @import("./arch/x86_64/platform.zig"),
    .aarch64 => @import("./arch/aarch64/platform.zig"),
    .arm => @import("./arch/arm/platform.zig"),
    .powerpc => @import("./arch/powerpc/platform.zig"),
    else => @compileError("No architecture-specific code for this architecture!"),
};
