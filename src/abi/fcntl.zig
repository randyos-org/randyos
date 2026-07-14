//! Linux `open()`/`fcntl()` flag and command constants, one file covering
//! all four architectures.
//!
//! Sourced from the Linux kernel source tree, torvalds/linux @
//! 8cdeaa50eae8dad34885515f62559ee83e7e8dda (kernel version 7.2.0-rc2):
//!
//! | scope | source file |
//! | --- | --- |
//! | generic base | `include/uapi/asm-generic/fcntl.h` |
//! | x86_64 | (no override at this commit -- `arch/x86/include/uapi/asm/fcntl.h` doesn't exist; uses the plain generic bit positions) |
//! | aarch64 | `arch/arm64/include/uapi/asm/fcntl.h` -- reorders `O_DIRECTORY`/`O_NOFOLLOW`/`O_DIRECT`/`O_LARGEFILE` ("Using our own definitions for AArch32 (compat) support", per that file's comment); bit-for-bit identical to arm's override |
//! | arm | `arch/arm/include/uapi/asm/fcntl.h` -- identical reordering to aarch64 |
//! | powerpc | `arch/powerpc/include/uapi/asm/fcntl.h` -- reorders the same four flags, but swaps `O_LARGEFILE`/`O_DIRECT` relative to arm/aarch64's ordering |
//!
//! `O_DIRECT`/`O_LARGEFILE`/`O_DIRECTORY`/`O_NOFOLLOW` sit at **different
//! bit positions on every architecture** (x86_64 uses the plain generic
//! positions; arm/aarch64 agree with each other but differ from powerpc,
//! which swaps `O_LARGEFILE`/`O_DIRECT`) -- this is real ABI divergence, not
//! an artifact of extraction. `F_GETLK64`/`F_SETLK64`/`F_SETLKW64` are
//! guarded in the generic header by `__BITS_PER_LONG == 32`, so they only
//! exist on the two 32-bit targets here (arm, powerpc); x86_64/aarch64 are
//! 64-bit and never see them.
//!
//! `open()`'s flags are genuinely independent, combinable bits, so
//! `OpenFlags` is a `packed struct(u32)` with named `bool` fields --
//! `OpenFlags{ .creat = true, .excl = true }` reads better than
//! `O_CREAT | O_EXCL`, and `@bitCast` recovers the raw word the syscall ABI
//! wants at zero cost. Because the four arch-varying bits sit at different
//! positions per architecture, there's a private struct type per distinct
//! layout (`X86_64OpenFlags`, `Aarch64ArmOpenFlags` shared between the two
//! identical layouts, `PowerpcOpenFlags`) plus a public
//! `builtin.cpu.arch`-switched `OpenFlags` alias, the same per-arch-type-
//! plus-switch pattern `stat.zig`/`mman.zig` use, with the same `_align<N>`
//! padding-naming convention (restarting at 1 per struct) they use too.
//! `O_RDONLY`/`O_WRONLY`/`O_RDWR` are, like `mman.zig`'s `MapType`, a 2-bit
//! mutually-exclusive sub-field (`AccessMode`, bits 0-1) rather than
//! independent bits, and don't vary per architecture. `O_SYNC` and
//! `O_TMPFILE` are each two bits combined (an internal `__O_*` building
//! block plus a "real" flag) rather than a bit of their own, so they're
//! exposed as pre-built `OpenFlags` values instead of a single field --
//! `OpenFlags.sync`/`OpenFlags.tmpfile` don't exist as single bits because
//! the kernel doesn't define them that way either.
//!
//! flock()'s flags (`LOCK_*`) are also modeled as a packed struct
//! (`LockFlags`) even though `sh`/`ex`/`un` are conventionally mutually
//! exclusive in practice (you pass exactly one, optionally OR'd with `nb`)
//! -- same tradeoff `mman.zig`'s `MsFlags` makes for `MS_ASYNC`/`MS_SYNC`:
//! the struct doesn't enforce exclusivity any more than the raw integer
//! flags did, so there's no correctness loss, only the same ergonomic win.
//! `LOCK_MAND`/`LOCK_READ`/`LOCK_WRITE` are legacy bits the kernel no
//! longer honors, kept only because the generic header still defines them;
//! `LOCK_RW` (`READ|WRITE` combined) is a pre-built `LockFlags` value like
//! `O_SYNC` above.
//!
//! `fcntl()`'s command argument (`F_DUPFD`, `F_GETFD`, ...) is a mutually
//! exclusive *selector*, not bits, so it's `FcntlCommand`, a flat
//! `enum(u32)` -- identical across all four architectures except
//! `F_GETLK64`/`F_SETLK64`/`F_SETLKW64`, which only arm/powerpc define
//! (32-bit `__BITS_PER_LONG`). Rather than gating those three out via a
//! `builtin.cpu.arch` switch (the way `syscall.zig` must, because presence
//! differs across most of that table), they're included unconditionally
//! with an `[arm][powerpc]` doc-comment prefix -- the same convention
//! `auxv.zig` uses for its own small set of arch-specific extras; no prefix
//! means common to all four. `F_RDLCK`/`F_WRLCK`/`F_UNLCK` (a record lock's
//! `l_type`) and `F_OWNER_TID`/`F_OWNER_PID`/`F_OWNER_PGRP` (an owner's
//! `type` in `struct f_owner_ex`) are each their own small mutually
//! exclusive value set, so they're `LockType`/`OwnerType` enums rather than
//! folded into `FcntlCommand`, which they're not part of. `F_EXLCK`/
//! `F_SHLCK` (legacy alternate `l_type` values, used when a libc
//! implementation emulates BSD `flock()` on top of `fcntl()` record
//! locking) are `BsdLockType`, a separate small enum alongside `LockType`
//! rather than folded into it -- same family, but a distinct legacy
//! numbering that was never meant to combine with `LockType`'s.
//! `F_LINUX_SPECIFIC_BASE` isn't a selectable command at all, just a
//! documented numbering-scheme offset, so it's a `pub const` nested inside
//! `FcntlCommand` itself: namespaced under the type it's conceptually
//! grouped with, without polluting `@typeInfo(FcntlCommand).@"enum".fields`
//! or being usable anywhere a `FcntlCommand` value is expected (its type is
//! plain `u32`).
//!
//! `FD_CLOEXEC` (the single `F_GETFD`/`F_SETFD` flag bit, with no siblings
//! to group it with) stays a plain constant.
//!
//! Scope: flat `O_*`/`F_*`/`LOCK_*` integer constants only -- `struct
//! flock`, `struct flock64`, and `struct f_owner_ex` belong in a separate,
//! structs-focused pass.

const sysinfo = @import("builtin");
const std = @import("std");
const log = std.log.scoped(.abi_fcntl);

/// The `open()` access-mode sub-field occupying bits 0-1 of the flags word
/// -- a mutually-exclusive mode selector, not independent bits. Doesn't
/// vary per architecture. Non-exhaustive: bit pattern `0b11` has no
/// standard named meaning here (unlike `mman.zig`'s `MapType`, where all
/// four 2-bit combinations are named).
pub const AccessMode = enum(u2) {
    /// Open the file for reading only.
    rdonly = 0,
    /// Open the file for writing only.
    wronly = 1,
    /// Open the file for both reading and writing.
    rdwr = 2,
    _,
};

/// x86_64: no arch override exists, so the four arch-varying bits use the
/// plain generic positions (`direct`=14, `largefile`=15, `directory`=16,
/// `nofollow`=17).
const X86_64OpenFlags = packed struct(u32) {
    access_mode: AccessMode = .rdonly,
    /// padding/reserved, must be present for layout
    _align1: u4 = 0,
    /// Create the file if it doesn't already exist.
    creat: bool = false,
    /// Combined with `creat`, fail with `EEXIST` if the file already
    /// exists, so file creation can be done atomically.
    excl: bool = false,
    /// Don't let this file become the process's controlling terminal, even
    /// if it refers to a terminal device.
    noctty: bool = false,
    /// Truncate an existing regular file to zero length when opening it.
    trunc: bool = false,
    /// Always write at the current end of the file, atomically
    /// repositioning to EOF before each write.
    append: bool = false,
    /// Open (and perform subsequent I/O) in non-blocking mode instead of
    /// blocking when the operation would otherwise have to wait.
    nonblock: bool = false,
    /// Writes complete once the data (though not necessarily all file
    /// metadata) has been transferred to the underlying hardware.
    dsync: bool = false,
    /// Enable signal-driven I/O: send SIGIO/SIGURG to the owning process
    /// or process group when I/O becomes possible on this descriptor.
    fasync: bool = false,
    /// Hint to perform I/O directly between user-space buffers and the
    /// underlying device, minimizing page-cache effects.
    direct: bool = false,
    /// Historically required to open large files whose size doesn't fit
    /// in a 32-bit `off_t`; a no-op on platforms where `off_t` is already
    /// 64-bit.
    largefile: bool = false,
    /// Fail with `ENOTDIR` unless the given path resolves to a directory.
    directory: bool = false,
    /// Fail with `ELOOP` if the final path component is a symbolic link,
    /// instead of following it.
    nofollow: bool = false,
    /// Don't update the file's last-access ("atime") timestamp on read.
    noatime: bool = false,
    /// Atomically set the close-on-exec flag on the new file descriptor,
    /// so it is closed automatically across `execve()`.
    cloexec: bool = false,
    /// Internal building-block bit that combines with `dsync` to form
    /// `O_SYNC` (see the file-level doc comment). `__O_SYNC` in the kernel
    /// header; must never be used directly.
    __o_sync: bool = false,
    /// Open a location in the filesystem purely for path-based operations
    /// (e.g. `fstat`, `fchdir`) without opening the file for reading or
    /// writing and without requiring read/write permission on it.
    path: bool = false,
    /// Internal building-block bit that combines with `directory` to form
    /// `O_TMPFILE` (see the file-level doc comment). `__O_TMPFILE` in the
    /// kernel header; must never be used directly.
    __o_tmpfile: bool = false,
    /// padding/reserved, must be present for layout
    _align2: u3 = 0,
    /// Allow an empty path together with a directory file descriptor (as
    /// used by the `*at()` family) to refer to that descriptor's own file.
    emptypath: bool = false,
    /// padding/reserved, must be present for layout
    _align3: u5 = 0,

    /// Writes complete only once all data and metadata have been transferred to
    /// the underlying hardware (full Posix synchronized I/O semantics) -- the
    /// combination of `__o_sync` and `dsync`, not a bit of its own.
    pub const sync = OpenFlags{ .__o_sync = true, .dsync = true };

    /// Create an unnamed temporary file with no directory entry, in the
    /// directory given by the path, that is discarded once the last reference
    /// to it is closed (unless later linked into the tree) -- the combination
    /// of `__o_tmpfile` and `directory`, not a bit of its own.
    pub const tmpfile = OpenFlags{ .__o_tmpfile = true, .directory = true };

    /// Historical BSD-compatible alias for `OpenFlags{ .nonblock = true }`.
    pub const ndelay = OpenFlags{ .nonblock = true };
};

/// aarch64/arm: identical override ("Using our own definitions for AArch32
/// (compat) support" per the aarch64 header's own comment) -- the four
/// arch-varying bits reorder to `directory`=14, `nofollow`=15, `direct`=16,
/// `largefile`=17.
const Aarch64ArmOpenFlags = packed struct(u32) {
    access_mode: AccessMode = .rdonly,
    /// padding/reserved, must be present for layout
    _align1: u4 = 0,
    /// Create the file if it doesn't already exist.
    creat: bool = false,
    /// Combined with `creat`, fail with `EEXIST` if the file already
    /// exists, so file creation can be done atomically.
    excl: bool = false,
    /// Don't let this file become the process's controlling terminal, even
    /// if it refers to a terminal device.
    noctty: bool = false,
    /// Truncate an existing regular file to zero length when opening it.
    trunc: bool = false,
    /// Always write at the current end of the file, atomically
    /// repositioning to EOF before each write.
    append: bool = false,
    /// Open (and perform subsequent I/O) in non-blocking mode instead of
    /// blocking when the operation would otherwise have to wait.
    nonblock: bool = false,
    /// Writes complete once the data (though not necessarily all file
    /// metadata) has been transferred to the underlying hardware.
    dsync: bool = false,
    /// Enable signal-driven I/O: send SIGIO/SIGURG to the owning process
    /// or process group when I/O becomes possible on this descriptor.
    fasync: bool = false,
    /// Fail with `ENOTDIR` unless the given path resolves to a directory.
    directory: bool = false,
    /// Fail with `ELOOP` if the final path component is a symbolic link,
    /// instead of following it.
    nofollow: bool = false,
    /// Hint to perform I/O directly between user-space buffers and the
    /// underlying device, minimizing page-cache effects.
    direct: bool = false,
    /// Historically required to open large files whose size doesn't fit
    /// in a 32-bit `off_t`; a no-op on platforms where `off_t` is already
    /// 64-bit.
    largefile: bool = false,
    /// Don't update the file's last-access ("atime") timestamp on read.
    noatime: bool = false,
    /// Atomically set the close-on-exec flag on the new file descriptor,
    /// so it is closed automatically across `execve()`.
    cloexec: bool = false,
    /// Internal building-block bit that combines with `dsync` to form
    /// `O_SYNC` (see the file-level doc comment). `__O_SYNC` in the kernel
    /// header; must never be used directly.
    __o_sync: bool = false,
    /// Open a location in the filesystem purely for path-based operations
    /// (e.g. `fstat`, `fchdir`) without opening the file for reading or
    /// writing and without requiring read/write permission on it.
    path: bool = false,
    /// Internal building-block bit that combines with `directory` to form
    /// `O_TMPFILE` (see the file-level doc comment). `__O_TMPFILE` in the
    /// kernel header; must never be used directly.
    __o_tmpfile: bool = false,
    /// padding/reserved, must be present for layout
    _align2: u3 = 0,
    /// Allow an empty path together with a directory file descriptor (as
    /// used by the `*at()` family) to refer to that descriptor's own file.
    emptypath: bool = false,
    /// padding/reserved, must be present for layout
    _align3: u5 = 0,

    /// Writes complete only once all data and metadata have been transferred to
    /// the underlying hardware (full Posix synchronized I/O semantics) -- the
    /// combination of `__o_sync` and `dsync`, not a bit of its own.
    pub const sync = OpenFlags{ .__o_sync = true, .dsync = true };

    /// Create an unnamed temporary file with no directory entry, in the
    /// directory given by the path, that is discarded once the last reference
    /// to it is closed (unless later linked into the tree) -- the combination
    /// of `__o_tmpfile` and `directory`, not a bit of its own.
    pub const tmpfile = OpenFlags{ .__o_tmpfile = true, .directory = true };

    /// Historical BSD-compatible alias for `OpenFlags{ .nonblock = true }`.
    pub const ndelay = OpenFlags{ .nonblock = true };
};

/// powerpc: reorders the same four bits as arm/aarch64, but swaps
/// `largefile`/`direct` relative to their ordering: `directory`=14,
/// `nofollow`=15, `largefile`=16, `direct`=17.
const PowerpcOpenFlags = packed struct(u32) {
    access_mode: AccessMode = .rdonly,
    /// padding/reserved, must be present for layout
    _align1: u4 = 0,
    /// Create the file if it doesn't already exist.
    creat: bool = false,
    /// Combined with `creat`, fail with `EEXIST` if the file already
    /// exists, so file creation can be done atomically.
    excl: bool = false,
    /// Don't let this file become the process's controlling terminal, even
    /// if it refers to a terminal device.
    noctty: bool = false,
    /// Truncate an existing regular file to zero length when opening it.
    trunc: bool = false,
    /// Always write at the current end of the file, atomically
    /// repositioning to EOF before each write.
    append: bool = false,
    /// Open (and perform subsequent I/O) in non-blocking mode instead of
    /// blocking when the operation would otherwise have to wait.
    nonblock: bool = false,
    /// Writes complete once the data (though not necessarily all file
    /// metadata) has been transferred to the underlying hardware.
    dsync: bool = false,
    /// Enable signal-driven I/O: send SIGIO/SIGURG to the owning process
    /// or process group when I/O becomes possible on this descriptor.
    fasync: bool = false,
    /// Fail with `ENOTDIR` unless the given path resolves to a directory.
    directory: bool = false,
    /// Fail with `ELOOP` if the final path component is a symbolic link,
    /// instead of following it.
    nofollow: bool = false,
    /// Historically required to open large files whose size doesn't fit
    /// in a 32-bit `off_t`; a no-op on platforms where `off_t` is already
    /// 64-bit.
    largefile: bool = false,
    /// Hint to perform I/O directly between user-space buffers and the
    /// underlying device, minimizing page-cache effects.
    direct: bool = false,
    /// Don't update the file's last-access ("atime") timestamp on read.
    noatime: bool = false,
    /// Atomically set the close-on-exec flag on the new file descriptor,
    /// so it is closed automatically across `execve()`.
    cloexec: bool = false,
    /// Internal building-block bit that combines with `dsync` to form
    /// `O_SYNC` (see the file-level doc comment). `__O_SYNC` in the kernel
    /// header; must never be used directly.
    __o_sync: bool = false,
    /// Open a location in the filesystem purely for path-based operations
    /// (e.g. `fstat`, `fchdir`) without opening the file for reading or
    /// writing and without requiring read/write permission on it.
    path: bool = false,
    /// Internal building-block bit that combines with `directory` to form
    /// `O_TMPFILE` (see the file-level doc comment). `__O_TMPFILE` in the
    /// kernel header; must never be used directly.
    __o_tmpfile: bool = false,
    /// padding/reserved, must be present for layout
    _align2: u3 = 0,
    /// Allow an empty path together with a directory file descriptor (as
    /// used by the `*at()` family) to refer to that descriptor's own file.
    emptypath: bool = false,
    /// padding/reserved, must be present for layout
    _align3: u5 = 0,

    /// Writes complete only once all data and metadata have been transferred to
    /// the underlying hardware (full Posix synchronized I/O semantics) -- the
    /// combination of `__o_sync` and `dsync`, not a bit of its own.
    pub const sync = OpenFlags{ .__o_sync = true, .dsync = true };

    /// Create an unnamed temporary file with no directory entry, in the
    /// directory given by the path, that is discarded once the last reference
    /// to it is closed (unless later linked into the tree) -- the combination
    /// of `__o_tmpfile` and `directory`, not a bit of its own.
    pub const tmpfile = OpenFlags{ .__o_tmpfile = true, .directory = true };

    /// Historical BSD-compatible alias for `OpenFlags{ .nonblock = true }`.
    pub const ndelay = OpenFlags{ .nonblock = true };
};

/// `open()` flags for whichever architecture is actually being built. See
/// each private per-arch type above for exactly which bit positions the
/// four arch-varying flags (`direct`/`largefile`/`directory`/`nofollow`)
/// take.
pub const OpenFlags = switch (sysinfo.cpu.arch) {
    .x86_64 => X86_64OpenFlags,
    .aarch64, .arm => Aarch64ArmOpenFlags,
    .powerpc => PowerpcOpenFlags,
    else => @compileError("No fcntl ABI data for this architecture"),
};

/// flock() flags -- identical across all four architectures. `sh`/`ex`/`un`
/// are conventionally mutually exclusive (exactly one is passed per call,
/// optionally OR'd with `nb`), but the struct doesn't enforce that any more
/// than the raw integer flags did -- see the file-level doc comment.
pub const LockFlags = packed struct(u32) {
    /// Acquire a shared lock (multiple holders may share it concurrently).
    sh: bool = false,
    /// Acquire an exclusive lock (only one holder at a time).
    ex: bool = false,
    /// OR this in with `sh`/`ex` to make the call non-blocking instead of
    /// waiting for the lock to become available.
    nb: bool = false,
    /// Release an existing lock.
    un: bool = false,
    /// padding/reserved, must be present for layout
    _align1: u1 = 0,
    /// Legacy: requested a mandatory lock (kernel support removed; kept
    /// only because the generic header still defines it).
    mand: bool = false,
    /// Legacy: allowed concurrent reads under a mandatory lock (kernel
    /// support removed).
    read: bool = false,
    /// Legacy: allowed concurrent writes under a mandatory lock (kernel
    /// support removed).
    write: bool = false,
    /// padding/reserved, must be present for layout
    _align2: u24 = 0,

    /// Legacy: allowed concurrent reads and writes under a mandatory lock
    /// (kernel support removed) -- `read`+`write` combined, not a bit of its
    /// own.
    pub const LOCK_RW = LockFlags{ .read = true, .write = true };
};

/// `fcntl()`'s command argument -- a mutually exclusive selector, not bits,
/// so this is an enum rather than a packed struct. Identical across all
/// four architectures except the three tagged `[arm][powerpc]` below (see
/// the file-level doc comment for why they aren't gated the way
/// `syscall.zig`'s per-arch tables are).
pub const FcntlCommand = enum(u32) {
    /// Duplicate this file descriptor, returning the lowest-numbered
    /// available descriptor that is greater than or equal to the given
    /// argument.
    dupfd = 0,
    /// Get the file descriptor flags (currently just the close-on-exec
    /// bit).
    getfd = 1,
    /// Set the file descriptor flags (currently just the close-on-exec
    /// bit).
    setfd = 2,
    /// Get the file access mode and file status flags.
    getfl = 3,
    /// Set the file status flags (only a subset of flags, such as
    /// `append`/`nonblock`/`direct`, can be changed after open).
    setfl = 4,
    /// Test whether a record lock could be placed, without actually
    /// placing it, reporting any conflicting lock that would block it.
    getlk = 5,
    /// Acquire or release a record lock, failing immediately if it cannot
    /// be acquired.
    setlk = 6,
    /// Acquire or release a record lock, blocking until it can be
    /// acquired.
    setlkw = 7,
    /// Set the process or process group ID that receives SIGIO/SIGURG
    /// signals for this descriptor.
    setown = 8,
    /// Get the process or process group ID currently set to receive
    /// SIGIO/SIGURG signals for this descriptor.
    getown = 9,
    /// Set the signal sent when I/O becomes possible on this descriptor (0
    /// restores the default, SIGIO).
    setsig = 10,
    /// Get the signal currently configured to be sent when I/O becomes
    /// possible on this descriptor.
    getsig = 11,
    /// [arm][powerpc] 64-bit variant of `getlk` using `struct flock64`,
    /// for 32-bit architectures where `off_t` doesn't cover large files.
    getlk64 = 12,
    /// [arm][powerpc] 64-bit variant of `setlk` using `struct flock64`,
    /// for 32-bit architectures where `off_t` doesn't cover large files.
    setlk64 = 13,
    /// [arm][powerpc] 64-bit, blocking variant of `setlkw` using
    /// `struct flock64`, for 32-bit architectures where `off_t` doesn't
    /// cover large files.
    setlkw64 = 14,
    /// Like `setown`, but lets the owner be specified as a thread,
    /// process, or process group via `struct f_owner_ex`.
    setown_ex = 15,
    /// Like `getown`, but returns the owner as a thread, process, or
    /// process group via `struct f_owner_ex`.
    getown_ex = 16,
    /// Get the real and effective user IDs of the socket owner set by
    /// `setown`, used for permission checks.
    getowner_uids = 17,
    /// Test whether an open-file-description (rather than
    /// process-associated) record lock could be placed, without actually
    /// placing it.
    ofd_getlk = 36,
    /// Acquire or release an open-file-description record lock, failing
    /// immediately if it cannot be acquired.
    ofd_setlk = 37,
    /// Acquire or release an open-file-description record lock, blocking
    /// until it can be acquired.
    ofd_setlkw = 38,

    /// Base value historically used to number Linux-specific `fcntl()`
    /// commands beyond the POSIX-standard ones.
    pub const F_LINUX_SPECIFIC_BASE: u32 = 1024;
};

/// A record lock's `l_type` (in `struct flock`/`struct flock64`) -- a
/// mutually exclusive selector, not bits. Identical across all four
/// architectures.
pub const LockType = enum(u32) {
    /// Shared (read) lock.
    rdlck = 0,
    /// Exclusive (write) lock.
    wrlck = 1,
    /// Remove/release an existing lock.
    unlck = 2,
};

/// An owner's `type` (in `struct f_owner_ex`) -- a mutually exclusive
/// selector, not bits. Identical across all four architectures.
pub const OwnerType = enum(u32) {
    /// The owner ID identifies an individual thread (by its kernel thread
    /// ID).
    tid = 0,
    /// The owner ID identifies a process (by its process ID).
    pid = 1,
    /// The owner ID identifies a process group (by its process group ID).
    pgrp = 2,
};

/// Legacy alternate `l_type` values (in `struct flock`/`struct flock64`),
/// used when a libc emulates BSD `flock()` on top of `fcntl()` record
/// locking -- a mutually exclusive selector alongside `LockType`, not
/// independent bits, despite the "or 3"/"or 4" alternate numberings some
/// libc implementations use historically. Values `4`/`8` deliberately don't collide with
/// `LockType`'s `0`/`1`/`2`, but aren't meant to be combined with them
/// either -- a separate legacy namespace, not an extension of it.
pub const BsdLockType = enum(u32) {
    /// Legacy BSD-compat alternate for an exclusive (write) lock; see
    /// `LockType.wrlck`.
    exlck = 4,
    /// Legacy BSD-compat alternate for a shared (read) lock; see
    /// `LockType.rdlck`.
    shlck = 8,
};

/// The close-on-exec flag bit used with `FcntlCommand.getfd`/`.setfd`;
/// distinct from the open-time `OpenFlags.cloexec` flag. A single bit with
/// no siblings, so it stays a plain constant. For `FcntlCommand.getfl`/
/// `.setfl`, anything with the low bit set goes.
pub const FD_CLOEXEC: u32 = 1;
