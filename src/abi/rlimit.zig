//! Linux `struct rlimit` and the `RLIMIT_*` resource IDs.
//!
//! Sourced from the Linux kernel source tree (`include/uapi/linux/resource.h`
//! for the struct, `include/uapi/asm-generic/resource.h` for the resource
//! IDs), torvalds/linux @ 8cdeaa50eae8dad34885515f62559ee83e7e8dda (kernel version 7.2.0-rc2)
//!
//! `arch/x86/include/uapi/asm/resource.h`, `arch/arm/include/uapi/asm/resource.h`,
//! `arch/arm64/include/uapi/asm/resource.h`, and
//! `arch/powerpc/include/uapi/asm/resource.h` do not exist at this commit --
//! all four of this project's target architectures use the generic resource
//! ID numbering verbatim.
//!
//! `struct rlimit`'s two fields are `__kernel_ulong_t` (`include/uapi/asm-generic/posix_types.h`:
//! `unsigned long`), which is word-size-dependent: 8 bytes on x86_64/aarch64,
//! 4 bytes on the 32-bit arm/powerpc targets this project builds for. `Word`
//! below is resolved at comptime so one struct definition is correct for all
//! four architectures.

const sysinfo = @import("builtin");
const std = @import("std");
const log = std.log.scoped(.abi_rlimit);

const Word = switch (sysinfo.cpu.arch) {
    .x86_64, .aarch64 => u64,
    .arm, .powerpc => u32,
    else => @compileError("unsupported architecture for rlimit ABI"),
};

pub const Rlimit = extern struct {
    /// Soft limit: the value the kernel enforces for this resource right now.
    rlim_cur: Word,
    /// Hard limit: the ceiling the soft limit may be raised to (without
    /// elevated privileges).
    rlim_max: Word,
};

/// Generic default: `(~0UL)` -- all bits set for the architecture's word
/// width (see `Word` above), per `include/uapi/asm-generic/resource.h`.
pub const RLIM_INFINITY: Word = ~@as(Word, 0);

/// `RLIMIT_*` resource IDs from `include/uapi/asm-generic/resource.h`.
pub const Resource = enum(u8) {
    /// Maximum amount of CPU time (in seconds) the process may consume.
    RLIMIT_CPU = 0,
    /// Maximum size (in bytes) of a file the process may create or extend.
    RLIMIT_FSIZE = 1,
    /// Maximum size (in bytes) of the process's data segment (heap).
    RLIMIT_DATA = 2,
    /// Maximum size (in bytes) of the process's stack.
    RLIMIT_STACK = 3,
    /// Maximum size (in bytes) of a core dump file produced for this process.
    RLIMIT_CORE = 4,
    /// Historical limit on resident set size (physical memory usage); no
    /// longer enforced by the Linux memory management code.
    RLIMIT_RSS = 5,
    /// Maximum number of processes/threads the real user ID may own.
    RLIMIT_NPROC = 6,
    /// Maximum number of open file descriptors, one more than the highest fd number allowed.
    RLIMIT_NOFILE = 7,
    /// Maximum amount of memory (in bytes) the process may lock into RAM (e.g. via mlock).
    RLIMIT_MEMLOCK = 8,
    /// Maximum size (in bytes) of the process's total virtual address space.
    RLIMIT_AS = 9,
    /// Maximum number of flock()/fcntl() advisory file locks the process may hold.
    RLIMIT_LOCKS = 10,
    /// Maximum number of signals queued for the real user ID across all processes.
    RLIMIT_SIGPENDING = 11,
    /// Maximum number of bytes usable across all POSIX message queues for the real user ID.
    RLIMIT_MSGQUEUE = 12,
    /// Ceiling on the nice value that may be raised for a non-privileged process (higher value = better priority).
    RLIMIT_NICE = 13,
    /// Ceiling on the real-time scheduling priority a non-privileged process may set.
    RLIMIT_RTPRIO = 14,
    /// Maximum contiguous CPU time (in microseconds) a real-time-scheduled process may run without a blocking syscall.
    RLIMIT_RTTIME = 15,
};

/// Count of defined resource IDs (`RLIM_NLIMITS` in the kernel header) --
/// not itself a resource ID, so it is not a member of `Resource` above.
pub const RLIM_NLIMITS: u8 = 16;
