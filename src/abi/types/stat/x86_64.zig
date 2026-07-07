//! Linux `struct stat` layout for x86_64.
//!
//! Sourced from the Linux kernel source tree (`arch/x86/include/uapi/asm/stat.h`,
//! the `#else` branch that applies when `__i386__` is not defined -- x86_64
//! userspace takes this branch, not the `__i386__` one, and does not use the
//! `struct stat64`/`struct __old_kernel_stat` also declared in that file, both
//! of which are 32-bit/i386-compat-only and out of scope here), torvalds/linux
//! @ 8cdeaa50eae8dad34885515f62559ee83e7e8dda (kernel version 7.2.0-rc2), by
//! fetching that file directly and mechanically extracting the struct layout
//! -- not transcribed by hand. Re-derive from that same file if this ever
//! looks stale; do not hand-edit fields here.
//!
//! Fields are declared with `__kernel_ulong_t`/`__kernel_long_t`, whose
//! underlying type was cross-checked via `arch/x86/include/uapi/asm/posix_types.h`
//! (which, for `__KERNEL__`-less/non-i386/non-x32 builds, i.e. plain x86_64,
//! includes `arch/x86/include/uapi/asm/posix_types_64.h`) and then
//! `include/uapi/asm-generic/posix_types.h` (included at the bottom of
//! `posix_types_64.h`, which does not `#define __kernel_long_t`/
//! `__kernel_ulong_t` itself before that include, so the asm-generic
//! defaults apply): `__kernel_long_t` is plain `long` and `__kernel_ulong_t`
//! is plain `unsigned long`, both 8 bytes wide on x86_64 (LP64).
//!
//! `__pad0` and the trailing `__unused[3]` are explicit reserved/padding
//! fields present in the kernel header itself, kept here for byte-exact
//! layout; they are never populated with meaningful data.
//!
//! Expected `@sizeOf(Stat) == 144` (computed from the field list below on a
//! target with natural 8-byte alignment for 8-byte integers and 4-byte
//! alignment for 4-byte integers, which x86_64's SysV ABI uses; no implicit
//! compiler-inserted padding beyond what's shown, since every field already
//! falls on its own natural-alignment boundary in this exact field order).
//!
//! Not wired to any dispatcher -- this is a layout reference only.

pub const Stat = extern struct {
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
    __pad0: u32, // padding/reserved, must be present for layout
    /// Device ID, if this is a special/device file.
    st_rdev: u64,
    /// Total size of the file in bytes (regular files); meaning varies for
    /// other file types (e.g. length of the target for a symlink).
    st_size: i64,
    /// Preferred block size for efficient filesystem I/O on this file.
    st_blksize: i64,
    st_blocks: i64, // Number 512-byte blocks allocated.

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
    __unused: [3]i64, // padding/reserved, must be present for layout
};
