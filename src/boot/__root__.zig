//! Boot entry dispatcher.

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
pub const std_options = impl.zigconfig.std_options;
pub const std_options_debug_io = impl.zigconfig.std_options_debug_io;
pub const std_options_cwd: ?fn () std.Io.Dir = if (@hasDecl(impl.zigconfig, "std_options_cwd")) impl.zigconfig.std_options_cwd else null;
pub const os = impl.zigconfig.os;

// As of Zig 0.17.0-dev.203, the implementation of std.Io.Threaded has os-specific
// switches in a number of places that do not protect for UEFI or other uncommon
// OSes with safe fallbacks.  Specifically, there is a default value for
// std.Io.Threaded.RandomFile, which depends on posix.system.getrandom and is
// undefined for UEFI.  However, the only practical uses of this variable are in
// fallback contexts where std_options_debug_io are not explicitly defined and
// falls back to using the std.Io.Threaded backend.  This is likely going to be
// an issue for all our bootloaders, so we explicitly set this to null here to
// prevent other unexpected hidden callsites and to force our other bootloaders
// to provide an explicit concrete implementation of std_options_debug_io.
pub const std_options_debug_threaded_io = null;
