//! Linux `struct stat`/`struct stat64` layouts for powerpc (32-bit, NOT
//! powerpc64 -- confirmed via `build.zig`'s `arch_stubs`, which targets
//! `.cpu_arch = .powerpc`).
//!
//! Sourced from the Linux kernel source tree (`arch/powerpc/include/uapi/asm/stat.h`
//! -- powerpc defines its own full `struct stat`/`struct stat64`, it does not
//! use the asm-generic version; the `#ifdef __powerpc64__` branch of
//! `struct stat` is skipped since we target 32-bit powerpc, so `Stat` below
//! follows the `#else` field order and widths), torvalds/linux
//! @ 8cdeaa50eae8dad34885515f62559ee83e7e8dda (kernel version 7.2.0-rc2), by
//! fetching that file directly and mechanically extracting the struct
//! layouts -- not transcribed by hand. Re-derive from that same file if this
//! ever looks stale; do not hand-edit fields here.
//!
//! IMPORTANT field-order note: on the 32-bit (non-`__powerpc64__`) branch,
//! the field order is `st_mode` THEN `st_nlink` -- the OPPOSITE of the
//! `__powerpc64__` branch's `st_nlink` THEN `st_mode` order. Verified
//! directly from the fetched header; do not swap these back to the 64-bit
//! order.
//!
//! `st_ino`/`st_mode`/`st_uid`/`st_gid` are declared with
//! `__kernel_ino_t`/`__kernel_mode_t`/`__kernel_uid32_t`/`__kernel_gid32_t`.
//! Their underlying types were cross-checked by fetching
//! `arch/powerpc/include/uapi/asm/posix_types.h` first: for 32-bit powerpc
//! (i.e. `__powerpc64__` not defined) it only defines `__kernel_ipc_pid_t`
//! itself and otherwise falls through to
//! `include/uapi/asm-generic/posix_types.h`, which does NOT override
//! `__kernel_ino_t`/`__kernel_mode_t`/`__kernel_uid32_t`/`__kernel_gid32_t`
//! either -- so all four resolve to the asm-generic defaults:
//!   - `__kernel_ino_t` -> `__kernel_ulong_t` -> `unsigned long` (4 bytes on
//!     32-bit powerpc)
//!   - `__kernel_mode_t` -> `unsigned int` (4 bytes) -- NOTE: this is
//!     `unsigned int`, not `unsigned short`; verified directly from
//!     asm-generic/posix_types.h rather than assumed.
//!   - `__kernel_uid32_t` -> `unsigned int` (4 bytes)
//!   - `__kernel_gid32_t` -> `unsigned int` (4 bytes)
//!
//! `struct stat64` is included here too, as `Stat64`, alongside `Stat`, for
//! the same reason as arm's `Stat64`: it's what the `*64` syscall variants
//! fill in on 32-bit powerpc for file sizes/inode numbers that don't fit the
//! narrower `Stat` fields -- both structs are genuinely part of the powerpc
//! ABI surface, not a redundant duplicate. Unlike arm's version, powerpc's
//! `struct stat64` in this header is not gated behind an `__ARMEB__`-style
//! endianness branch and has no `__st_ino`/legacy-inode field.
//!
//! `__unused4`/`__unused5` in `Stat`, and `__pad2` in `Stat64`, are explicit
//! reserved/padding fields present in the kernel header itself, kept here
//! for byte-exact layout; they are never populated with meaningful data.
//! (The `__powerpc64__`-only trailing `__unused6` field on the 64-bit branch
//! of `struct stat` does not apply to 32-bit powerpc and is correctly
//! omitted from `Stat` here.)
//!
//! Expected `@sizeOf(Stat) == 72` (computed from the field list below; every
//! field is 4 bytes or less. Note there is one implicit compiler-inserted
//! alignment gap of 2 bytes between `st_nlink` (`u16`, ending at offset 14)
//! and `st_uid` (`u32`, needing 4-byte alignment, so it starts at offset 16)
//! -- this gap is NOT a named field in the kernel header; it arises purely
//! from natural alignment and is reproduced automatically by Zig's `extern
//! struct` layout for this target, the same way a C compiler would insert
//! it).
//!
//! `@sizeOf(Stat64)` is deliberately NOT asserted here, for the same reason
//! as arm's `Stat64`: it mixes 8-byte (`unsigned long long`) fields with
//! narrower fields, and the resulting implicit alignment padding depends on
//! the target ABI's alignment rule for 8-byte integers on 32-bit powerpc,
//! which is a judgment call outside what this file can verify from the
//! header text alone.
//!
//! Not wired to any dispatcher -- this is a layout reference only.

const std = @import("std");
const log = std.log.scoped(.abi_types_stat_powerpc);

pub const Stat = extern struct {
    /// ID of the device containing this file.
    st_dev: u32,
    /// Inode number; uniquely identifies the file within its filesystem. (__kernel_ino_t -> unsigned long)
    st_ino: u32,
    /// File type and permission bits. (__kernel_mode_t -> unsigned int; 32-bit branch order: mode before nlink)
    st_mode: u32,
    /// Number of hard links to this file.
    st_nlink: u16,
    /// User ID of the file's owner. (__kernel_uid32_t -> unsigned int)
    st_uid: u32,
    /// Group ID of the file's owner. (__kernel_gid32_t -> unsigned int)
    st_gid: u32,
    /// Device ID, if this is a special/device file.
    st_rdev: u32,
    /// Total size of the file in bytes (regular files); meaning varies for
    /// other file types (e.g. length of the target for a symlink).
    st_size: i32,
    /// Preferred block size for efficient filesystem I/O on this file.
    st_blksize: u32,
    /// Number of 512-byte blocks actually allocated to the file on disk.
    st_blocks: u32,
    /// Time of last access (read) of the file's data, whole seconds.
    st_atime: u32,
    /// Nanoseconds component of `st_atime`.
    st_atime_nsec: u32,
    /// Time of last modification of the file's data (content), whole seconds.
    st_mtime: u32,
    /// Nanoseconds component of `st_mtime`.
    st_mtime_nsec: u32,
    /// Time of last change to the file's inode metadata (permissions,
    /// ownership, link count, or content), whole seconds.
    st_ctime: u32,
    /// Nanoseconds component of `st_ctime`.
    st_ctime_nsec: u32,
    __unused4: u32, // padding/reserved, must be present for layout
    __unused5: u32, // padding/reserved, must be present for layout
};

/// This matches `struct stat64` in glibc2.1, used only for 32-bit powerpc.
pub const Stat64 = extern struct {
    st_dev: u64, // Device. ID of the device containing this file.
    st_ino: u64, // File serial number; uniquely identifies the file within its filesystem.
    st_mode: u32, // File mode: file type and permission bits.
    st_nlink: u32, // Link count: number of hard links to this file.
    st_uid: u32, // User ID of the file's owner.
    st_gid: u32, // Group ID of the file's owner.
    st_rdev: u64, // Device number, if device: device ID, if this is a special/device file.
    __pad2: u16, // padding/reserved, must be present for layout
    st_size: i64, // Size of file, in bytes (regular files); meaning varies for other file types.
    st_blksize: i32, // Optimal block size for I/O: preferred block size for efficient filesystem I/O.
    st_blocks: i64, // Number 512-byte blocks allocated (actually allocated on disk).
    st_atime: i32, // Time of last access (read) of the file's data, whole seconds.
    st_atime_nsec: u32, // Nanoseconds component of st_atime.
    st_mtime: i32, // Time of last modification of the file's data (content), whole seconds.
    st_mtime_nsec: u32, // Nanoseconds component of st_mtime.
    st_ctime: i32, // Time of last change to the file's inode metadata (permissions, ownership, link count, or content), whole seconds.
    st_ctime_nsec: u32, // Nanoseconds component of st_ctime.
    __unused4: u32, // padding/reserved, must be present for layout
    __unused5: u32, // padding/reserved, must be present for layout
};
