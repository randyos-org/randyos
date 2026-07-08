//! Linux signal numbers, generic across x86_64, arm, arm64, and powerpc.
//!
//! Sourced from the Linux kernel source tree (`include/uapi/asm-generic/signal.h`),
//! torvalds/linux @ 8cdeaa50eae8dad34885515f62559ee83e7e8dda (kernel version 7.2.0-rc2), by fetching
//! that file directly and mechanically extracting (name, value) pairs -- not
//! transcribed by hand. Re-derive from that same file if this ever looks
//! stale; do not hand-edit numbers here.
//!
//! Cross-checked against `arch/x86/include/uapi/asm/signal.h`,
//! `arch/arm/include/uapi/asm/signal.h`, `arch/arm64/include/uapi/asm/signal.h`
//! (which simply `#include <asm-generic/signal.h>` directly, defining no
//! numbers of its own), and `arch/powerpc/include/uapi/asm/signal.h`: all
//! four architectures define identical signal NUMBER values 1-31 and
//! SIGRTMIN=32. (Their `sigaction`/`sigset_t`/`stack_t` struct layouts and
//! `MINSIGSTKSZ`/`SIGSTKSZ` differ, but that is out of scope here -- this
//! file is numbers only.)
//!
//! `SIGIOT`, `SIGPOLL`, and `SIGUNUSED` are C aliases (`#define`d to another
//! name's value, not distinct numbers). Since a Zig enum cannot have two
//! members share one value without `EnumField` duplication headaches, they
//! are instead exposed as `pub const` bindings to the canonical `Number`
//! member, immediately below the enum.
//!
//! Not wired to any dispatcher -- this is a numbering reference only.

const std = @import("std");
const log = std.log.scoped(.abi_signal);

pub const Number = enum(u8) {
    /// Terminal hangup, or death of the controlling process; also
    /// conventionally used to tell a daemon to reload its configuration.
    SIGHUP = 1,
    /// Interrupt from the keyboard (typically Ctrl+C).
    SIGINT = 2,
    /// Quit from the keyboard (typically Ctrl+\), terminating the
    /// process and producing a core dump.
    SIGQUIT = 3,
    /// Illegal instruction was executed.
    SIGILL = 4,
    /// Trace/breakpoint trap, used by debuggers and `ptrace`.
    SIGTRAP = 5,
    /// Abort signal, typically raised by `abort()`; terminates with a
    /// core dump.
    SIGABRT = 6,
    /// Bus error: a memory access fault such as misaligned or
    /// nonexistent physical addressing.
    SIGBUS = 7,
    /// Floating-point exception, e.g. integer division by zero or
    /// arithmetic overflow.
    SIGFPE = 8,
    /// Kill signal: terminates the process unconditionally; cannot be
    /// caught, blocked, or ignored.
    SIGKILL = 9,
    /// User-defined signal 1, free for application-specific use.
    SIGUSR1 = 10,
    /// Invalid memory reference (segmentation fault).
    SIGSEGV = 11,
    /// User-defined signal 2, free for application-specific use.
    SIGUSR2 = 12,
    /// Broken pipe: wrote to a pipe or socket with no process left to
    /// read it.
    SIGPIPE = 13,
    /// Timer signal delivered when a real-time timer set by `alarm()`
    /// expires.
    SIGALRM = 14,
    /// Termination request; the default "please exit" signal, which can
    /// be caught or ignored.
    SIGTERM = 15,
    /// Stack fault on the coprocessor (historical; effectively unused on
    /// modern Linux).
    SIGSTKFLT = 16,
    /// Child process stopped, terminated, or continued.
    SIGCHLD = 17,
    /// Continue execution, if the process is currently stopped.
    SIGCONT = 18,
    /// Stop the process; cannot be caught, blocked, or ignored.
    SIGSTOP = 19,
    /// Stop signal typed at the terminal (typically Ctrl+Z); unlike
    /// `SIGSTOP`, this one can be caught or ignored.
    SIGTSTP = 20,
    /// Background process attempted to read from the controlling
    /// terminal.
    SIGTTIN = 21,
    /// Background process attempted to write to the controlling
    /// terminal.
    SIGTTOU = 22,
    /// Urgent condition on a socket (out-of-band data available).
    SIGURG = 23,
    /// CPU time limit exceeded (as set by `setrlimit(RLIMIT_CPU)`).
    SIGXCPU = 24,
    /// File size limit exceeded (as set by `setrlimit(RLIMIT_FSIZE)`).
    SIGXFSZ = 25,
    /// Virtual alarm clock: timer counting down the process's virtual
    /// (user-mode CPU) time expired.
    SIGVTALRM = 26,
    /// Profiling timer expired: timer counting down user and kernel CPU
    /// time expired.
    SIGPROF = 27,
    /// Terminal window size changed.
    SIGWINCH = 28,
    /// I/O is now possible on a descriptor marked for asynchronous I/O
    /// notification (also known as `SIGPOLL`).
    SIGIO = 29,
    /// Power failure or restart notification (used by some UPS/power
    /// management daemons).
    SIGPWR = 30,
    /// Bad system call: an invalid or filtered (e.g. seccomp-denied)
    /// system call was attempted.
    SIGSYS = 31,
};

/// `#define SIGIOT 6` (same value as `SIGABRT`) in `include/uapi/asm-generic/signal.h`.
///
/// Historical alias for the abort signal, named after the PDP-11 "IOT
/// trap" instruction; behaves identically to `SIGABRT`.
pub const SIGIOT = Number.SIGABRT;

/// `#define SIGPOLL SIGIO` in `include/uapi/asm-generic/signal.h`.
///
/// System V-style name for "a pollable event occurred"; behaves
/// identically to `SIGIO`.
pub const SIGPOLL = Number.SIGIO;

/// `#define SIGUNUSED 31` (same value as `SIGSYS`) in `include/uapi/asm-generic/signal.h`.
///
/// Legacy name for the bad-system-call signal; behaves identically to
/// `SIGSYS`.
pub const SIGUNUSED = Number.SIGSYS;

/// First realtime signal number. Not part of `Number` because realtime
/// signals (`SIGRTMIN` through `SIGRTMAX`) are a computed range, not fixed
/// identities -- `SIGRTMAX` itself is `_NSIG` (64), which varies by context.
///
/// Lowest-numbered real-time signal: unlike the standard signals above,
/// real-time signals (`SIGRTMIN`..`SIGRTMAX`) queue multiple pending
/// instances and are delivered in a defined priority order.
pub const SIGRTMIN: u8 = 32;
