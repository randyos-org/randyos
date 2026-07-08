//! Linux `struct stat` layout for aarch64.
//!
//! aarch64 has no `arch/arm64/include/uapi/asm/stat.h` override (confirmed:
//! fetching that path 404s at the pinned commit below), so aarch64 userspace
//! gets `struct stat` from the generic header instead: sourced from
//! `include/uapi/asm-generic/stat.h`, torvalds/linux
//! @ 8cdeaa50eae8dad34885515f62559ee83e7e8dda (kernel version 7.2.0-rc2), by
//! fetching that file directly and mechanically extracting the struct layout
//! -- not transcribed by hand. Re-derive from that same file if this ever
//! looks stale; do not hand-edit fields here.
//!
//! This header also defines a 32-bit-only `struct stat64` (gated on
//! `__BITS_PER_LONG != 64 || defined(__ARCH_WANT_STAT64)`), which does not
//! apply to aarch64 (a 64-bit architecture that does not opt into
//! `__ARCH_WANT_STAT64`) and is intentionally not implemented here.
//!
//! `__pad1`, `__pad2`, `__unused4`, and `__unused5` are explicit
//! reserved/padding fields present in the kernel header itself, kept here
//! for byte-exact layout; they are never populated with meaningful data.
//!
//! Expected `@sizeOf(Stat) == 128` (computed from the field list below on a
//! target with natural 8-byte alignment for 8-byte integers and 4-byte
//! alignment for 4-byte integers, which aarch64's AAPCS64 ABI uses; no
//! implicit compiler-inserted padding beyond what's shown, since every field
//! already falls on its own natural-alignment boundary in this exact field
//! order).
//!
//! Not wired to any dispatcher -- this is a layout reference only.

const std = @import("std");
const log = std.log.scoped(.abi_types_stat_aarch64);

pub const Stat = extern struct {
    /// ID of the device containing this file.
    st_dev: u64,
    /// Inode number; uniquely identifies the file within its filesystem.
    st_ino: u64,
    /// File type and permission bits.
    st_mode: u32,
    /// Number of hard links to this file.
    st_nlink: u32,
    /// User ID of the file's owner.
    st_uid: u32,
    /// Group ID of the file's owner.
    st_gid: u32,
    /// Device ID, if this is a special/device file.
    st_rdev: u64,
    __pad1: u64, // padding/reserved, must be present for layout
    /// Total size of the file in bytes (regular files); meaning varies for
    /// other file types (e.g. length of the target for a symlink).
    st_size: i64,
    /// Preferred block size for efficient filesystem I/O on this file.
    st_blksize: i32,
    __pad2: i32, // padding/reserved, must be present for layout
    /// Number of 512-byte blocks actually allocated to the file on disk.
    st_blocks: i64,
    /// Time of last access (read) of the file's data, whole seconds.
    st_atime: i64,
    /// Nanoseconds component of `st_atime`.
    st_atime_nsec: u64,
    /// Time of last modification of the file's data (content), whole seconds.
    st_mtime: i64,
    /// Nanoseconds component of `st_mtime`.
    st_mtime_nsec: u64,
    /// Time of last change to the file's inode metadata (permissions,
    /// ownership, link count, or content), whole seconds.
    st_ctime: i64,
    /// Nanoseconds component of `st_ctime`.
    st_ctime_nsec: u64,
    __unused4: u32, // padding/reserved, must be present for layout
    __unused5: u32, // padding/reserved, must be present for layout
};
