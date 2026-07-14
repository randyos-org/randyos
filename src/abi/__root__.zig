//! Module root for the "abi" package (see build.zig) -- Linux syscall/ABI
//! compatibility reference data (see README.md); nothing here is wired to a
//! dispatcher yet. Add new ABI categories here rather than importing them by
//! relative path from elsewhere.

const std = @import("std");
const log = std.log.scoped(.abi);

/// Linux syscall numbering
pub const syscall = @import("syscall.zig");

/// Linux auxiliary vector (`AT_*`) type constants
pub const auxv = @import("auxv.zig");

/// File control `open()`/`fcntl()` flag and command constants
pub const fcntl = @import("fcntl.zig");

/// Memory management `mmap()`/`mprotect()`/`mlock()`/`madvise()` flag constants
pub const mman = @import("mman.zig");

/// Linux errno values
pub const errno = @import("errno.zig");

/// Linux signal numbers
pub const signal = @import("signal.zig");

pub const timespec = @import("timespec.zig");
pub const rlimit = @import("rlimit.zig");
pub const iovec = @import("iovec.zig");
pub const utsname = @import("utsname.zig");
pub const dirent64 = @import("dirent64.zig");
pub const stat = @import("stat.zig");
