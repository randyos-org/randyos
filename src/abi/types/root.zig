//! Module root for `src/abi/types/` -- Linux struct/type layouts referenced
//! by the syscall ABI (see ../README.md). Add new shared or per-arch types
//! here rather than importing them by relative path from elsewhere.

const std = @import("std");
const log = std.log.scoped(.abi_types);
const builtin = @import("builtin");

/// Per-architecture `struct stat`/`struct stat64` layouts -- see each file
/// under src/abi/types/stat/ for provenance. Picked at comptime for
/// whichever architecture is actually being built, same pattern as
/// src/abi/root.zig's `syscall`/`auxv`/`fcntl`/`mman` selection.
pub const stat = switch (builtin.cpu.arch) {
    .x86_64 => @import("stat/x86_64.zig"),
    .aarch64 => @import("stat/aarch64.zig"),
    .arm => @import("stat/arm.zig"),
    .powerpc => @import("stat/powerpc.zig"),
    else => @compileError("No stat ABI data for this architecture"),
};

/// Uniform across all four target architectures -- see each file for
/// provenance.
pub const timespec = @import("timespec.zig");
pub const rlimit = @import("rlimit.zig");
pub const iovec = @import("iovec.zig");
pub const utsname = @import("utsname.zig");
pub const dirent64 = @import("dirent64.zig");
