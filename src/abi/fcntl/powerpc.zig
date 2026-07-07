//! Linux `open()`/`fcntl()` flag and command constants for powerpc
//! (32-bit).
//!
//! Sourced from the Linux kernel source tree
//! (`include/uapi/asm-generic/fcntl.h` plus the powerpc override,
//! `arch/powerpc/include/uapi/asm/fcntl.h`), torvalds/linux @
//! 8cdeaa50eae8dad34885515f62559ee83e7e8dda (kernel version 7.2.0-rc2), by
//! fetching both files directly and mechanically extracting (name, value)
//! pairs -- not transcribed by hand. Re-derive from those same files if
//! this ever looks stale; do not hand-edit values here.
//!
//! `arch/powerpc/include/uapi/asm/fcntl.h` DOES exist and reorders four
//! flags relative to the generic/x86_64 positions: O_DIRECTORY = (1 << 14),
//! O_NOFOLLOW = (1 << 15), O_LARGEFILE = (1 << 16), O_DIRECT = (1 << 17).
//! Compare against x86_64.zig (plain generic positions: O_DIRECT=14,
//! O_LARGEFILE=15, O_DIRECTORY=16, O_NOFOLLOW=17) and aarch64.zig/arm.zig
//! (which agree with powerpc on O_DIRECTORY=14 and O_NOFOLLOW=15, but swap
//! O_LARGEFILE and O_DIRECT relative to powerpc's ordering: arm/aarch64 put
//! O_DIRECT at 16 and O_LARGEFILE at 17).
//!
//! F_GETLK64 / F_SETLK64 / F_SETLKW64 are guarded in the generic header by
//! `#if __BITS_PER_LONG == 32 || defined(__KERNEL__)`. This project targets
//! 32-bit (non-powerpc64) powerpc, where
//! arch/powerpc/include/uapi/asm/bitsperlong.h resolves __BITS_PER_LONG to
//! 32 (the `defined(__powerpc64__)` branch selecting 64 does not apply) --
//! so these three commands ARE part of the powerpc uapi and are included
//! below. Compare x86_64.zig and aarch64.zig, where the 64-bit
//! __BITS_PER_LONG excludes them.
//!
//! Scope: flat O_*/F_*/LOCK_* integer constants only -- `struct flock`,
//! `struct flock64`, and `struct f_owner_ex` belong in a separate,
//! structs-focused pass.
//!
//! Not wired to any dispatcher -- this is a reference-data-only file.

/// Bitmask for extracting the access mode (O_RDONLY/O_WRONLY/O_RDWR) from a
/// set of `open()` flags.
pub const O_ACCMODE: u32 = 3;
/// Open the file for reading only.
pub const O_RDONLY: u32 = 0;
/// Open the file for writing only.
pub const O_WRONLY: u32 = 1 << 0;
/// Open the file for both reading and writing.
pub const O_RDWR: u32 = 1 << 1;
/// Create the file if it doesn't already exist.
pub const O_CREAT: u32 = 1 << 6;
/// Combined with O_CREAT, fail with `EEXIST` if the file already exists,
/// so file creation can be done atomically.
pub const O_EXCL: u32 = 1 << 7;
/// Don't let this file become the process's controlling terminal, even if
/// it refers to a terminal device.
pub const O_NOCTTY: u32 = 1 << 8;
/// Truncate an existing regular file to zero length when opening it.
pub const O_TRUNC: u32 = 1 << 9;
/// Always write at the current end of the file, atomically repositioning
/// to EOF before each write.
pub const O_APPEND: u32 = 1 << 10;
/// Open (and perform subsequent I/O) in non-blocking mode instead of
/// blocking when the operation would otherwise have to wait.
pub const O_NONBLOCK: u32 = 1 << 11;
/// Writes complete once the data (though not necessarily all file
/// metadata) has been transferred to the underlying hardware.
pub const O_DSYNC: u32 = 1 << 12;
/// Enable signal-driven I/O: send SIGIO/SIGURG to the owning process or
/// process group when I/O becomes possible on this descriptor.
pub const FASYNC: u32 = 1 << 13;

// The following four flags sit at different bit positions per architecture
// -- see file header. powerpc's arch/powerpc/include/uapi/asm/fcntl.h
// override reorders these relative to the generic (x86_64) positions, and
// differs from arm/aarch64's override too (O_LARGEFILE/O_DIRECT swapped).
/// Hint to perform I/O directly between user-space buffers and the
/// underlying device, minimizing page-cache effects.
pub const O_DIRECT: u32 = 1 << 17;
/// Historically required to open large files whose size doesn't fit in a
/// 32-bit `off_t`; a no-op on platforms where `off_t` is already 64-bit.
pub const O_LARGEFILE: u32 = 1 << 16;
/// Fail with `ENOTDIR` unless the given path resolves to a directory.
pub const O_DIRECTORY: u32 = 1 << 14;
/// Fail with `ELOOP` if the final path component is a symbolic link,
/// instead of following it.
pub const O_NOFOLLOW: u32 = 1 << 15;

/// Don't update the file's last-access ("atime") timestamp on read.
pub const O_NOATIME: u32 = 1 << 18;
/// Atomically set the close-on-exec flag on the new file descriptor, so
/// it is closed automatically across `execve()`.
pub const O_CLOEXEC: u32 = 1 << 19;

/// Internal building-block bit that combines with O_DSYNC to form O_SYNC.
/// `__O_SYNC` in the kernel header; must never be used directly -- test
/// against O_SYNC (below) instead.
pub const __O_SYNC: u32 = 1 << 20;
/// Writes complete only once all data and metadata have been transferred
/// to the underlying hardware (full Posix synchronized I/O semantics).
pub const O_SYNC: u32 = __O_SYNC | O_DSYNC;

/// Open a location in the filesystem purely for path-based operations
/// (e.g. `fstat`, `fchdir`) without opening the file for reading or
/// writing and without requiring read/write permission on it.
pub const O_PATH: u32 = 1 << 21;

/// Internal building-block bit that combines with O_DIRECTORY to form
/// O_TMPFILE. `__O_TMPFILE` in the kernel header; O_TMPFILE (below) folds
/// in O_DIRECTORY, which makes O_TMPFILE's numeric value arch-dependent
/// too, even though the __O_TMPFILE bit itself is not one of the four
/// arch-varying flags.
pub const __O_TMPFILE: u32 = 1 << 22;
/// Create an unnamed temporary file with no directory entry, in the
/// directory given by the path, that is discarded once the last
/// reference to it is closed (unless later linked into the tree).
pub const O_TMPFILE: u32 = __O_TMPFILE | O_DIRECTORY;

/// Allow an empty path together with a directory file descriptor (as used
/// by the `*at()` family) to refer to that descriptor's own file.
pub const O_EMPTYPATH: u32 = 1 << 26;
/// Historical BSD-compatible alias for O_NONBLOCK.
pub const O_NDELAY: u32 = O_NONBLOCK;

/// Duplicate this file descriptor, returning the lowest-numbered
/// available descriptor that is greater than or equal to the given
/// argument.
pub const F_DUPFD: u32 = 0;
/// Get the file descriptor flags (currently just the close-on-exec bit).
pub const F_GETFD: u32 = 1;
/// Set the file descriptor flags (currently just the close-on-exec bit).
pub const F_SETFD: u32 = 2;
/// Get the file access mode and file status flags.
pub const F_GETFL: u32 = 3;
/// Set the file status flags (only a subset of flags, such as
/// O_APPEND/O_NONBLOCK/O_DIRECT, can be changed after open).
pub const F_SETFL: u32 = 4;
/// Test whether a record lock could be placed, without actually placing
/// it, reporting any conflicting lock that would block it.
pub const F_GETLK: u32 = 5;
/// Acquire or release a record lock, failing immediately if it cannot be
/// acquired.
pub const F_SETLK: u32 = 6;
/// Acquire or release a record lock, blocking until it can be acquired.
pub const F_SETLKW: u32 = 7;
/// Set the process or process group ID that receives SIGIO/SIGURG signals
/// for this descriptor.
pub const F_SETOWN: u32 = 8;
/// Get the process or process group ID currently set to receive
/// SIGIO/SIGURG signals for this descriptor.
pub const F_GETOWN: u32 = 9;
/// Set the signal sent when I/O becomes possible on this descriptor (0
/// restores the default, SIGIO).
pub const F_SETSIG: u32 = 10;
/// Get the signal currently configured to be sent when I/O becomes
/// possible on this descriptor.
pub const F_GETSIG: u32 = 11;

// F_GETLK64/F_SETLK64/F_SETLKW64 are part of the powerpc (32-bit) uapi --
// see file header (__BITS_PER_LONG == 32 keeps them visible).
/// 64-bit variant of F_GETLK using `struct flock64`, for 32-bit
/// architectures where `off_t` doesn't cover large files.
pub const F_GETLK64: u32 = 12;
/// 64-bit variant of F_SETLK using `struct flock64`, for 32-bit
/// architectures where `off_t` doesn't cover large files.
pub const F_SETLK64: u32 = 13;
/// 64-bit, blocking variant of F_SETLKW using `struct flock64`, for
/// 32-bit architectures where `off_t` doesn't cover large files.
pub const F_SETLKW64: u32 = 14;

/// Like F_SETOWN, but lets the owner be specified as a thread, process,
/// or process group via `struct f_owner_ex`.
pub const F_SETOWN_EX: u32 = 15;
/// Like F_GETOWN, but returns the owner as a thread, process, or process
/// group via `struct f_owner_ex`.
pub const F_GETOWN_EX: u32 = 16;
/// Get the real and effective user IDs of the socket owner set by
/// F_SETOWN, used for permission checks.
pub const F_GETOWNER_UIDS: u32 = 17;

/// Test whether an open-file-description (rather than process-associated)
/// record lock could be placed, without actually placing it.
pub const F_OFD_GETLK: u32 = 36;
/// Acquire or release an open-file-description record lock, failing
/// immediately if it cannot be acquired.
pub const F_OFD_SETLK: u32 = 37;
/// Acquire or release an open-file-description record lock, blocking
/// until it can be acquired.
pub const F_OFD_SETLKW: u32 = 38;

/// In `struct f_owner_ex`, the owner ID identifies an individual thread
/// (by its kernel thread ID).
pub const F_OWNER_TID: u32 = 0;
/// In `struct f_owner_ex`, the owner ID identifies a process (by its
/// process ID).
pub const F_OWNER_PID: u32 = 1;
/// In `struct f_owner_ex`, the owner ID identifies a process group (by
/// its process group ID).
pub const F_OWNER_PGRP: u32 = 2;

/// The close-on-exec flag bit used with F_GETFD/F_SETFD; distinct from
/// the open-time O_CLOEXEC flag.
/// For F_GETFL/F_SETFL: actually anything with the low bit set goes.
pub const FD_CLOEXEC: u32 = 1;

/// Record lock type: shared (read) lock.
pub const F_RDLCK: u32 = 0;
/// Record lock type: exclusive (write) lock.
pub const F_WRLCK: u32 = 1;
/// Record lock type: remove/release an existing lock.
pub const F_UNLCK: u32 = 2;

/// Legacy BSD `flock()`-style exclusive lock constant, used by `lockf()`.
pub const F_EXLCK: u32 = 4;
/// Legacy BSD `flock()`-style shared lock constant, used by `lockf()`.
pub const F_SHLCK: u32 = 8;

/// Acquire a shared `flock()` lock (multiple holders may share it
/// concurrently).
pub const LOCK_SH: u32 = 1;
/// Acquire an exclusive `flock()` lock (only one holder at a time).
pub const LOCK_EX: u32 = 2;
/// OR this in with LOCK_SH/LOCK_EX to make the `flock()` call
/// non-blocking instead of waiting for the lock to become available.
pub const LOCK_NB: u32 = 4;
/// Release an existing `flock()` lock.
pub const LOCK_UN: u32 = 8;

// LOCK_MAND support was removed from the kernel; these legacy symbols are
// retained here only because the generic header still defines them.
/// Legacy: requested a mandatory `flock()` lock (kernel support removed;
/// kept only so old code still compiles).
pub const LOCK_MAND: u32 = 32;
/// Legacy: allowed concurrent reads under a mandatory lock (kernel
/// support removed).
pub const LOCK_READ: u32 = 64;
/// Legacy: allowed concurrent writes under a mandatory lock (kernel
/// support removed).
pub const LOCK_WRITE: u32 = 128;
/// Legacy: allowed concurrent reads and writes under a mandatory lock
/// (kernel support removed).
pub const LOCK_RW: u32 = 192;

/// Base value historically used to number Linux-specific `fcntl()`
/// commands beyond the POSIX-standard ones.
pub const F_LINUX_SPECIFIC_BASE: u32 = 1024;
