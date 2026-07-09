//! Linux `struct __kernel_timespec`, the modern Y2038-safe time_t/timespec
//! ABI used by current syscalls (e.g. `clock_gettime`/`clock_gettime64`) on
//! every architecture, including 32-bit ones.
//!
//! Sourced from the Linux kernel source tree (`include/uapi/linux/time_types.h`),
//! torvalds/linux @ 8cdeaa50eae8dad34885515f62559ee83e7e8dda (kernel version 7.2.0-rc2)
//!
//! `tv_sec` is `__kernel_time64_t` (`long long`, i.e. always a fixed 64-bit
//! signed value regardless of word size) and `tv_nsec` is also explicitly
//! `long long` in this struct -- both fields are 64 bits wide on every
//! architecture, unlike `rlimit`/`iovec`'s word-size-dependent fields.
//!
//! The same header also defines a legacy `struct __kernel_old_timespec`
//! (32-bit, non-Y2038-safe `tv_sec`); that one is not implemented here since
//! it is not used by current syscalls.

const std = @import("std");
const log = std.log.scoped(.abi_timespec);

pub const Timespec = extern struct {
    /// Whole seconds component of the time value.
    tv_sec: i64,
    /// Nanoseconds component of the time value (0-999,999,999), added to `tv_sec`.
    tv_nsec: i64,
};
