//! Linux `struct stat`/`struct stat64` layouts, one per architecture.
//!
//! Sourced from the Linux kernel source tree, torvalds/linux @
//! 8cdeaa50eae8dad34885515f62559ee83e7e8dda (kernel version 7.2.0-rc2):
//!
//! | arch | source file |
//! | --- | --- |
//! | x86_64 | `arch/x86/include/uapi/asm/stat.h` |
//! | aarch64 | `include/uapi/asm-generic/stat.h` (aarch64 has no override) |
//! | arm | `arch/arm/include/uapi/asm/stat.h` |
//! | powerpc | `arch/powerpc/include/uapi/asm/stat.h` |
//!
//! `struct stat`'s field order and widths genuinely differ on
//! every architecture, so there is no shared field list to factor out.
//! Therefore, each arch gets its own private struct type below,
//! and `pub const Stat` picks the right one via a `builtin.cpu.arch` switch.

const sysinfo = @import("builtin");
const std = @import("std");
const log = std.log.scoped(.abi_stat);

/// Linux `struct stat` layout for x86_64.
///
/// From the `#else` branch of `arch/x86/include/uapi/asm/stat.h` that
/// applies when `__i386__` is not defined -- x86_64 userspace takes this
/// branch, not the `__i386__` one, and does not use the `struct stat64`/
/// `struct __old_kernel_stat` also declared in that file, both of which are
/// 32-bit/i386-compat-only and out of scope here.
///
/// Fields are declared with `__kernel_ulong_t`/`__kernel_long_t`, whose
/// underlying type was cross-checked via `arch/x86/include/uapi/asm/posix_types.h`
/// (which, for `__KERNEL__`-less/non-i386/non-x32 builds, i.e. plain x86_64,
/// includes `arch/x86/include/uapi/asm/posix_types_64.h`) and then
/// `include/uapi/asm-generic/posix_types.h` (included at the bottom of
/// `posix_types_64.h`, which does not `#define __kernel_long_t`/
/// `__kernel_ulong_t` itself before that include, so the asm-generic
/// defaults apply): `__kernel_long_t` is plain `long` and `__kernel_ulong_t`
/// is plain `unsigned long`, both 8 bytes wide on x86_64 (LP64).
///
/// `_align1` and the trailing `_align2` are explicit reserved/padding
/// fields present in the kernel header itself, kept here for byte-exact
/// layout; they are never populated with meaningful data.
///
/// Expected `@sizeOf(X86_64Stat) == 144` (computed from the field list below
/// on a target with natural 8-byte alignment for 8-byte integers and 4-byte
/// alignment for 4-byte integers, which x86_64's SysV ABI uses; no implicit
/// compiler-inserted padding beyond what's shown, since every field already
/// falls on its own natural-alignment boundary in this exact field order).
const X86_64Stat = extern struct {
    /// ID of the device containing this file.
    st_dev: u64,
    /// Inode number; uniquely identifies the file within its filesystem.
    st_ino: u64,
    /// Number of hard links to this file.
    st_nlink: u64,

    /// File type and permission bits.
    st_mode: u32,
    /// User ID of the file's owner.
    st_uid: u32,
    /// Group ID of the file's owner.
    st_gid: u32,
    /// padding/reserved, must be present for layout
    _align1: u32,

    /// Device ID, if this is a special/device file.
    st_rdev: u64,
    /// Total size of the file in bytes (regular files); meaning varies for
    /// other file types (e.g. length of the target for a symlink).
    st_size: i64,
    /// Preferred block size for efficient filesystem I/O on this file.
    st_blksize: i64,
    /// Number of 512-byte blocks actually allocated to the file on disk.
    st_blocks: i64,

    /// Time of last access (read) of the file's data, whole seconds.
    st_atime: u64,
    /// Nanoseconds component of `st_atime`.
    st_atime_nsec: u64,
    /// Time of last modification of the file's data (content), whole seconds.
    st_mtime: u64,
    /// Nanoseconds component of `st_mtime`.
    st_mtime_nsec: u64,
    /// Time of last change to the file's inode metadata (permissions,
    /// ownership, link count, or content), whole seconds.
    st_ctime: u64,
    /// Nanoseconds component of `st_ctime`.
    st_ctime_nsec: u64,
    /// padding/reserved, must be present for layout
    _align2: [3]i64,
};

/// Linux `struct stat` layout for aarch64.
///
/// aarch64 has no `arch/arm64/include/uapi/asm/stat.h` override (confirmed:
/// fetching that path 404s at the pinned commit above), so aarch64 userspace
/// gets `struct stat` from the generic header instead:
/// `include/uapi/asm-generic/stat.h`.
///
/// This header also defines a 32-bit-only `struct stat64` (gated on
/// `__BITS_PER_LONG != 64 || defined(__ARCH_WANT_STAT64)`), which does not
/// apply to aarch64 (a 64-bit architecture that does not opt into
/// `__ARCH_WANT_STAT64`) and is intentionally not implemented here.
///
/// `_align1`, `_align2`, `_align3`, and `_align4` are explicit
/// reserved/padding fields present in the kernel header itself, kept here
/// for byte-exact layout; they are never populated with meaningful data.
///
/// Expected `@sizeOf(Aarch64Stat) == 128` (computed from the field list below
/// on a target with natural 8-byte alignment for 8-byte integers and 4-byte
/// alignment for 4-byte integers, which aarch64's AAPCS64 ABI uses; no
/// implicit compiler-inserted padding beyond what's shown, since every field
/// already falls on its own natural-alignment boundary in this exact field
/// order).
const Aarch64Stat = extern struct {
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
    /// padding/reserved, must be present for layout
    _align1: u64,
    /// Total size of the file in bytes (regular files); meaning varies for
    /// other file types (e.g. length of the target for a symlink).
    st_size: i64,
    /// Preferred block size for efficient filesystem I/O on this file.
    st_blksize: i32,
    /// padding/reserved, must be present for layout
    _align2: i32,
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
    /// padding/reserved, must be present for layout
    _align3: u32,
    /// padding/reserved, must be present for layout
    _align4: u32,
};

/// Linux `struct stat` layout for arm (32-bit EABI, little-endian).
///
/// From `arch/arm/include/uapi/asm/stat.h` -- arm defines its own full
/// `struct stat`/`struct stat64`, it does not use the asm-generic version.
///
/// `struct stat` has a `#if defined(__ARMEB__)` (big-endian) branch and an
/// `#else` (little-endian) branch that differ in `st_dev`/`st_rdev`'s
/// representation (big-endian splits each into a 16-bit field plus an
/// explicit `__pad`; little-endian uses one plain `unsigned long`). This
/// project's arm target is little-endian, so `ArmStat` below follows the
/// `#else` branch.
///
/// `_align1`/`_align2` are explicit reserved/padding fields present in
/// the kernel header itself, kept here for byte-exact layout; they are never
/// populated with meaningful data.
///
/// Expected `@sizeOf(ArmStat) == 64` (computed from the field list below;
/// every field is 4 bytes or less and already falls on its own
/// natural-alignment boundary in this exact field order, so there is no
/// implicit compiler-inserted padding to account for).
const ArmStat = extern struct {
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
    /// padding/reserved, must be present for layout
    _align1: u32,
    /// padding/reserved, must be present for layout
    _align2: u32,
};

/// Linux `struct stat64` layout for arm (32-bit EABI) -- the layout the `*64`
/// syscall variants (`stat64`/`fstat64`/`lstat64`, plus the `*at64` family)
/// fill in on 32-bit arm, used because `ArmStat`'s fields for file size/
/// inode/block-count are too narrow for large files/filesystems. This
/// matches `struct stat64` in glibc2.1, hence the deliberately-inserted
/// `_align1`/`_align2` padding around the 64-bit `st_dev`/`st_rdev` fields.
///
/// `_align1`/`_align2` are explicit reserved/padding fields present in the
/// kernel header itself, kept here for byte-exact layout; they are never
/// populated with meaningful data. `__st_ino` is a 32-bit legacy field
/// distinct from the trailing 64-bit `st_ino` -- both are genuinely present
/// in the kernel's struct (see `STAT64_HAS_BROKEN_ST_INO`/the "insane
/// amounts of padding" comment in the source: `__st_ino` exists for
/// binary-compatibility with old software that only reads the narrow field).
///
/// `@sizeOf(ArmStat64)` is deliberately NOT asserted here: it mixes
/// `unsigned long long` fields (8 bytes) with narrower fields in a layout
/// that depends on the target ABI's alignment rule for 8-byte integers
/// (whether the toolchain treats `long long` as 8-byte-aligned, per AAPCS,
/// or 4-byte-aligned, as some older 32-bit ARM ABI conventions did) -- that's
/// a judgment call outside what this file can verify from the header text
/// alone, so a reader/test should compute or measure it directly for
/// whatever target triple is in use rather than trusting a stated number
/// here.
const ArmStat64 = extern struct {
    /// ID of the device containing this file.
    st_dev: u64,
    /// padding/reserved, must be present for layout
    _align1: [4]u8,

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
    /// padding/reserved, must be present for layout
    _align2: [4]u8,

    /// Total size of the file in bytes (regular files); meaning varies for
    /// other file types (e.g. length of the target for a symlink).
    st_size: i64,
    /// Preferred block size for efficient filesystem I/O on this file.
    st_blksize: u32,
    /// Number of 512-byte blocks actually allocated to the file on disk.
    st_blocks: u64,

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

/// Linux `struct stat` layout for powerpc (32-bit, NOT powerpc64 --
/// confirmed via `build.zig`'s `arch_stubs`, which targets
/// `.cpu_arch = .powerpc`).
///
/// From `arch/powerpc/include/uapi/asm/stat.h` -- powerpc defines its own
/// full `struct stat`/`struct stat64`, it does not use the asm-generic
/// version; the `#ifdef __powerpc64__` branch of `struct stat` is skipped
/// since we target 32-bit powerpc, so `PowerpcStat` below follows the
/// `#else` field order and widths.
///
/// IMPORTANT field-order note: on the 32-bit (non-`__powerpc64__`) branch,
/// the field order is `st_mode` THEN `st_nlink` -- the OPPOSITE of the
/// `__powerpc64__` branch's `st_nlink` THEN `st_mode` order. Verified
/// directly from the fetched header; do not swap these back to the 64-bit
/// order.
///
/// `st_ino`/`st_mode`/`st_uid`/`st_gid` are declared with
/// `__kernel_ino_t`/`__kernel_mode_t`/`__kernel_uid32_t`/`__kernel_gid32_t`.
/// Their underlying types were cross-checked by fetching
/// `arch/powerpc/include/uapi/asm/posix_types.h` first: for 32-bit powerpc
/// (i.e. `__powerpc64__` not defined) it only defines `__kernel_ipc_pid_t`
/// itself and otherwise falls through to
/// `include/uapi/asm-generic/posix_types.h`, which does NOT override
/// `__kernel_ino_t`/`__kernel_mode_t`/`__kernel_uid32_t`/`__kernel_gid32_t`
/// either -- so all four resolve to the asm-generic defaults:
///   - `__kernel_ino_t` -> `__kernel_ulong_t` -> `unsigned long` (4 bytes on
///     32-bit powerpc)
///   - `__kernel_mode_t` -> `unsigned int` (4 bytes) -- NOTE: this is
///     `unsigned int`, not `unsigned short`; verified directly from
///     asm-generic/posix_types.h rather than assumed.
///   - `__kernel_uid32_t` -> `unsigned int` (4 bytes)
///   - `__kernel_gid32_t` -> `unsigned int` (4 bytes)
///
/// `_align1`/`_align2` are explicit reserved/padding fields present in
/// the kernel header itself, kept here for byte-exact layout; they are never
/// populated with meaningful data. (The `__powerpc64__`-only trailing
/// `__unused6` field on the 64-bit branch of `struct stat` does not apply to
/// 32-bit powerpc and is correctly omitted here.)
///
/// Expected `@sizeOf(PowerpcStat) == 72` (computed from the field list
/// below; every field is 4 bytes or less. Note there is one implicit
/// compiler-inserted alignment gap of 2 bytes between `st_nlink` (`u16`,
/// ending at offset 14) and `st_uid` (`u32`, needing 4-byte alignment, so it
/// starts at offset 16) -- this gap is NOT a named field in the kernel
/// header; it arises purely from natural alignment and is reproduced
/// automatically by Zig's `extern struct` layout for this target, the same
/// way a C compiler would insert it).
const PowerpcStat = extern struct {
    /// ID of the device containing this file.
    st_dev: u32,
    /// Inode number; uniquely identifies the file within its filesystem.
    st_ino: u32,
    /// File type and permission bits. NOTE: this is `u32` on 32-bit powerpc, not `u16` as on arm
    st_mode: u32,
    /// Number of hard links to this file.
    st_nlink: u16,

    /// User ID of the file's owner.
    st_uid: u32,
    /// Group ID of the file's owner.
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
    /// padding/reserved, must be present for layout
    _align1: u32,
    /// padding/reserved, must be present for layout
    _align2: u32,
};

/// Linux `struct stat64` layout for powerpc (32-bit) -- the layout the `*64`
/// syscall variants fill in on 32-bit powerpc for file sizes/inode numbers
/// that don't fit `PowerpcStat`'s narrower fields. This matches
/// `struct stat64` in glibc2.1. Unlike arm's version, powerpc's
/// `struct stat64` in this header is not gated behind an `__ARMEB__`-style
/// endianness branch and has no `__st_ino`/legacy-inode field.
///
/// `_align1` is an explicit reserved/padding field present in the kernel
/// header itself, kept here for byte-exact layout; it is never populated
/// with meaningful data.
///
/// `@sizeOf(PowerpcStat64)` is deliberately NOT asserted here, for the same
/// reason as `ArmStat64`: it mixes 8-byte (`unsigned long long`) fields with
/// narrower fields, and the resulting implicit alignment padding depends on
/// the target ABI's alignment rule for 8-byte integers on 32-bit powerpc,
/// which is a judgment call outside what this file can verify from the
/// header text alone.
const PowerpcStat64 = extern struct {
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
    /// padding/reserved, must be present for layout
    _align1: u16,
    /// Total size of the file in bytes (regular files); meaning varies for
    /// other file types (e.g. length of the target for a symlink).
    st_size: i64,
    /// Preferred block size for efficient filesystem I/O on this file.
    st_blksize: i32,
    /// Number of 512-byte blocks actually allocated to the file on disk.
    st_blocks: i64,

    /// Time of last access (read) of the file's data, whole seconds.
    st_atime: i32,
    /// Nanoseconds component of `st_atime`.
    st_atime_nsec: u32,
    /// Time of last modification of the file's data (content), whole seconds.
    st_mtime: i32,
    /// Nanoseconds component of `st_mtime`.
    st_mtime_nsec: u32,
    /// Time of last change to the file's inode metadata (permissions,
    /// ownership, link count, or content), whole seconds.
    st_ctime: i32,
    /// Nanoseconds component of `st_ctime`.
    st_ctime_nsec: u32,
    /// padding/reserved, must be present for layout
    _align2: u32,
    /// padding/reserved, must be present for layout
    _align3: u32,
};

/// `struct stat` for whichever architecture is actually being built.
pub const Stat = switch (sysinfo.cpu.arch) {
    .x86_64 => X86_64Stat,
    .aarch64 => Aarch64Stat,
    .arm => ArmStat,
    .powerpc => PowerpcStat,
    else => @compileError("No stat layout for this architecture"),
};

/// `struct stat64` for whichever architecture is actually being built.
/// Only arm and powerpc define a different one; we use this as an alias for the
/// default struct on other platforms.
pub const Stat64 = switch (sysinfo.cpu.arch) {
    .x86_64 => X86_64Stat,
    .aarch64 => Aarch64Stat,
    .arm => ArmStat64,
    .powerpc => PowerpcStat64,
    else => @compileError("No stat64 layout for this architecture"),
};
