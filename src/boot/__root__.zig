//! Bootloader entry point dispatcher.

const sysinfo = @import("builtin");
const std = @import("std");
const log = std.log.scoped(.boot);

const rstd = @import("rstd");
pub const build_options = rstd.build_options;

const impl = switch (sysinfo.target.os.tag) {
    .uefi => @import("uefi/__root__.zig"),
    else => @compileError("no bootloader implementation for this target"),
};

pub const main = impl.main;
pub const std_options = impl.std_options;
pub const std_options_debug_io = impl.std_options_debug_io;
