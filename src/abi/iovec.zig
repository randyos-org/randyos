//! Linux `struct iovec`, used by the `readv`/`writev`/`preadv`/`pwritev`
//! family of syscalls to describe scatter/gather I/O buffers.
//!
//! Sourced from the Linux kernel source tree (`include/uapi/linux/uio.h`),
//! torvalds/linux @ 8cdeaa50eae8dad34885515f62559ee83e7e8dda (kernel version 7.2.0-rc2)
//!
//! `iov_base` is `void __user *` (a pointer) and `iov_len` is
//! `__kernel_size_t` -- both are simply "however wide a pointer/size_t is on
//! the target", with no separate Linux-specific width rule the way
//! `rlimit`'s `__kernel_ulong_t` has. Zig's `usize` already has exactly that
//! meaning (native pointer width) on every architecture this project
//! targets, so unlike `rlimit.zig`'s explicit comptime-resolved `Word`, a
//! plain `usize` is used directly here -- no separate word-size switch is
//! needed.

const std = @import("std");
const log = std.log.scoped(.abi_iovec);

pub const Iovec = extern struct {
    /// Address of the start of this segment's buffer.
    iov_base: usize,
    /// Length in bytes of the buffer at `iov_base`.
    iov_len: usize,
};

/// `UIO_FASTIOV` -- number of `iovec`s the kernel keeps on-stack before
/// falling back to a heap allocation.
pub const UIO_FASTIOV: usize = 8;

/// `UIO_MAXIOV` -- the maximum number of `iovec`s a single call may pass, per
/// 1003.1g (5.4.1.1).
pub const UIO_MAXIOV: usize = 1024;
