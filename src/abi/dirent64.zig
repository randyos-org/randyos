//! Linux `struct linux_dirent64`, the record layout `getdents64()` fills a
//! caller's buffer with.
//!
//! Sourced from the Linux kernel source tree (`include/linux/dirent.h` --
//! note this is a kernel-internal header, not under `include/uapi/`, but it
//! is the canonical definition actually used by the `getdents64` syscall),
//! torvalds/linux @ 8cdeaa50eae8dad34885515f62559ee83e7e8dda (kernel version 7.2.0-rc2)
//!
//! The real C struct ends with `char d_name[]` -- a flexible array member
//! holding the NUL-terminated filename, with no fixed size of its own. Zig's
//! `extern struct` has no equivalent of a C flexible array member, so only
//! the fixed header (`d_ino`, `d_off`, `d_reclen`, `d_type`) is represented
//! here. In an actual `getdents64()` buffer, `d_name` begins immediately
//! after this header in memory; its length is implied by `d_reclen`, which
//! covers the whole record -- header, name, and any trailing padding --
//! rather than by any fixed field. Consequently, a real reader MUST advance
//! to the next entry using `d_reclen` (current record's offset + d_reclen),
//! NOT `@sizeOf(LinuxDirent64)` -- assuming a fixed-size record here would
//! silently corrupt directory iteration by misreading `d_name` and every
//! entry after it.

const std = @import("std");
const log = std.log.scoped(.abi_dirent64);

pub const LinuxDirent64 = extern struct {
    /// Inode number of this directory entry.
    d_ino: u64,
    /// Opaque offset/cookie of the next entry, for use with seekdir/telldir.
    d_off: i64,
    /// Total length of this record in bytes (header, name, and padding).
    d_reclen: u16,
    /// File type of the entry (e.g. regular file, directory, symlink).
    d_type: u8,
};
