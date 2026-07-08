//! Module root for the "abi" package (see build.zig) -- Linux syscall/ABI
//! compatibility reference data (see README.md); nothing here is wired to a
//! dispatcher yet. Add new ABI categories here rather than importing them by
//! relative path from elsewhere.

const std = @import("std");
const log = std.log.scoped(.abi);
const builtin = @import("builtin");

/// Per-architecture Linux syscall numbering -- see each file under
/// src/abi/syscall/ for provenance. Picked at comptime for whichever
/// architecture is actually being built, same pattern as
/// src/kernel/arch.zig's per-arch platform selection.
pub const syscall = switch (builtin.cpu.arch) {
    .x86_64 => @import("syscall/x86_64.zig"),
    .aarch64 => @import("syscall/aarch64.zig"),
    .arm => @import("syscall/arm.zig"),
    .powerpc => @import("syscall/powerpc.zig"),
    else => @compileError("No syscall ABI data for this architecture"),
};

/// Per-architecture Linux auxiliary vector (`AT_*`) type constants -- see
/// each file under src/abi/auxv/ for provenance. Picked at comptime for
/// whichever architecture is actually being built, same pattern as
/// `syscall` above.
pub const auxv = switch (builtin.cpu.arch) {
    .x86_64 => @import("auxv/x86_64.zig"),
    .aarch64 => @import("auxv/aarch64.zig"),
    .arm => @import("auxv/arm.zig"),
    .powerpc => @import("auxv/powerpc.zig"),
    else => @compileError("No auxv ABI data for this architecture"),
};

/// Per-architecture `open()`/`fcntl()` flag and command constants -- see
/// each file under src/abi/fcntl/ for provenance. Picked at comptime, same
/// pattern as `syscall` above.
pub const fcntl = switch (builtin.cpu.arch) {
    .x86_64 => @import("fcntl/x86_64.zig"),
    .aarch64 => @import("fcntl/aarch64.zig"),
    .arm => @import("fcntl/arm.zig"),
    .powerpc => @import("fcntl/powerpc.zig"),
    else => @compileError("No fcntl ABI data for this architecture"),
};

/// Per-architecture `mmap()`/`mprotect()`/`mlock()`/`madvise()` flag
/// constants -- see each file under src/abi/mman/ for provenance. Picked at
/// comptime, same pattern as `syscall` above.
pub const mman = switch (builtin.cpu.arch) {
    .x86_64 => @import("mman/x86_64.zig"),
    .aarch64 => @import("mman/aarch64.zig"),
    .arm => @import("mman/arm.zig"),
    .powerpc => @import("mman/powerpc.zig"),
    else => @compileError("No mman ABI data for this architecture"),
};

/// Linux errno values -- see src/abi/errno.zig for provenance. Generic
/// across all four target architectures (with one documented powerpc
/// exception), so unlike `syscall`/`auxv`/`fcntl`/`mman` above this is a
/// single shared import, not a per-arch switch.
pub const errno = @import("errno.zig");

/// Linux signal numbers -- see src/abi/signal.zig for provenance. Generic
/// across all four target architectures, so this is a single shared import,
/// not a per-arch switch.
pub const signal = @import("signal.zig");

/// Linux struct/type layouts (stat, timespec, rlimit, iovec, utsname,
/// dirent64) -- see src/abi/types/root.zig and the files alongside it for
/// provenance.
pub const types = @import("types/root.zig");
