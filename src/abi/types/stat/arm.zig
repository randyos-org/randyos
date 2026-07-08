//! Linux `struct stat`/`struct stat64` layouts for arm (32-bit EABI).
//!
//! Sourced from the Linux kernel source tree (`arch/arm/include/uapi/asm/stat.h`
//! -- arm defines its own full `struct stat`/`struct stat64`, it does not use
//! the asm-generic version), torvalds/linux
//! @ 8cdeaa50eae8dad34885515f62559ee83e7e8dda (kernel version 7.2.0-rc2), by
//! fetching that file directly and mechanically extracting the struct
//! layouts -- not transcribed by hand. Re-derive from that same file if this
//! ever looks stale; do not hand-edit fields here.
//!
//! `struct stat` has a `#if defined(__ARMEB__)` (big-endian) branch and an
//! `#else` (little-endian) branch that differ in `st_dev`/`st_rdev`'s
//! representation (big-endian splits each into a 16-bit field plus an
//! explicit `__pad`; little-endian uses one plain `unsigned long`). This
//! project's arm target is little-endian, so `Stat` below follows the
//! `#else` branch.
//!
//! `struct stat64` is included here too, as `Stat64`, alongside `Stat`: this
//! is the layout the `*64` syscall variants (`stat64`/`fstat64`/`lstat64`,
//! plus the `*at64` family) fill in on 32-bit arm, used because the plain
//! 32-bit `Stat` fields for file size/inode/block-count are too narrow for
//! large files/filesystems -- both structs are genuinely part of the arm
//! ABI surface, not a redundant duplicate.
//!
//! `__unused4`/`__unused5` in `Stat`, and `__pad0`/`__pad3` in `Stat64`, are
//! explicit reserved/padding fields present in the kernel header itself,
//! kept here for byte-exact layout; they are never populated with
//! meaningful data. `Stat64` also has an `__st_ino` field (32-bit, legacy)
//! distinct from the trailing 64-bit `st_ino` -- both are genuinely present
//! in the kernel's struct (see `STAT64_HAS_BROKEN_ST_INO`/the "insane
//! amounts of padding" comment in the source: `__st_ino` exists for
//! binary-compatibility with old software that only reads the narrow field).
//!
//! Expected `@sizeOf(Stat) == 64` (computed from the field list below; every
//! field is 4 bytes or less and already falls on its own natural-alignment
//! boundary in this exact field order, so there is no implicit
//! compiler-inserted padding to account for).
//!
//! `@sizeOf(Stat64)` is deliberately NOT asserted here: `Stat64` mixes
//! `unsigned long long` fields (8 bytes) with narrower fields in a layout
//! that depends on the target ABI's alignment rule for 8-byte integers
//! (whether the toolchain treats `long long` as 8-byte-aligned, per AAPCS,
//! or 4-byte-aligned, as some older 32-bit ARM ABI conventions did) --
//! that's a judgment call outside what this file can verify from the header
//! text alone, so a reader/test should compute or measure it directly for
//! whatever target triple is in use rather than trusting a stated number
//! here.
//!
//! Not wired to any dispatcher -- this is a layout reference only.

const std = @import("std");
const log = std.log.scoped(.abi_types_stat_arm);

pub const Stat = extern struct {
    /// ID of the device containing this file.
    st_dev: u32,
    /// Inode number; uniquely identifies the file within its filesystem.
    st_ino: u32,
    /// File type and permission bits.
    st_mode: u16,
    /// Number of hard links to this file.
    st_nlink: u16,
    /// User ID of the file's owner.
    st_uid: u16,
    /// Group ID of the file's owner.
    st_gid: u16,
    /// Device ID, if this is a special/device file.
    st_rdev: u32,
    /// Total size of the file in bytes (regular files); meaning varies for
    /// other file types (e.g. length of the target for a symlink).
    st_size: u32,
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

/// This matches `struct stat64` in glibc2.1, hence the deliberately-inserted
/// `__pad0`/`__pad3` padding around the 64-bit `st_dev`/`st_rdev` fields (see
/// the file-level doc comment above).
pub const Stat64 = extern struct {
    /// ID of the device containing this file.
    st_dev: u64,
    __pad0: [4]u8, // padding/reserved, must be present for layout

    /// Legacy narrow inode number; see STAT64_HAS_BROKEN_ST_INO. Superseded
    /// by the wider `st_ino` field below -- kept only for compatibility with
    /// old software that reads this narrow field.
    __st_ino: u32,
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
    __pad3: [4]u8, // padding/reserved, must be present for layout

    /// Total size of the file in bytes (regular files); meaning varies for
    /// other file types (e.g. length of the target for a symlink).
    st_size: i64,
    /// Preferred block size for efficient filesystem I/O on this file.
    st_blksize: u32,
    st_blocks: u64, // Number 512-byte blocks allocated.

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

    /// Inode number (64-bit); the wide replacement for the legacy `__st_ino`
    /// field above.
    st_ino: u64,
};
