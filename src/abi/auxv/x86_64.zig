//! Linux auxiliary vector (`AT_*`) type constants for x86_64.
//!
//! Sourced from the Linux kernel source tree (`include/uapi/linux/auxvec.h`
//! and `arch/x86/include/uapi/asm/auxvec.h`), torvalds/linux @
//! 8cdeaa50eae8dad34885515f62559ee83e7e8dda (kernel version 7.2.0-rc2), by
//! fetching those files directly and mechanically extracting (name, value)
//! pairs -- not transcribed by hand. Re-derive from those same files if this
//! ever looks stale; do not hand-edit numbers here.
//!
//! These are the keys of the auxv (auxiliary vector) entries the kernel
//! places on a new process's initial stack, alongside argv/envp, describing
//! things like the ELF program headers' address (`AT_PHDR`), page size
//! (`AT_PAGESZ`), and vDSO location (`AT_SYSINFO_EHDR`). Each entry is an
//! `(a_type, a_val)` pair; this enum is the `a_type` side only.
//!
//! Not wired to any ELF loader/process bring-up yet -- this is a numbering
//! reference only.

const std = @import("std");
const log = std.log.scoped(.abi_auxv_x86_64);

pub const Type = enum(u32) {
    /// Terminating entry marking the end of the auxiliary vector.
    AT_NULL = 0,
    /// Marks an entry that should be ignored by the program.
    AT_IGNORE = 1,
    /// Open file descriptor referring to the program image, used when the
    /// kernel could not load the executable itself.
    AT_EXECFD = 2,
    /// Address of the program headers table in the loaded ELF image.
    AT_PHDR = 3,
    /// Size in bytes of a single entry in the program headers table.
    AT_PHENT = 4,
    /// Number of entries in the program headers table.
    AT_PHNUM = 5,
    /// The system's memory page size in bytes.
    AT_PAGESZ = 6,
    /// Base address at which the ELF interpreter (dynamic linker) was loaded.
    AT_BASE = 7,
    /// Flags word associated with the auxiliary vector (currently unused).
    AT_FLAGS = 8,
    /// The program's entry point address.
    AT_ENTRY = 9,
    /// Nonzero if the program image is not in ELF format.
    AT_NOTELF = 10,
    /// Real user ID of the process.
    AT_UID = 11,
    /// Effective user ID of the process.
    AT_EUID = 12,
    /// Real group ID of the process.
    AT_GID = 13,
    /// Effective group ID of the process.
    AT_EGID = 14,
    /// Pointer to a string identifying the CPU for optimization purposes.
    AT_PLATFORM = 15,
    /// Bitmask of architecture-dependent hints about CPU capabilities.
    AT_HWCAP = 16,
    /// Frequency (in ticks per second) at which `times()` increments.
    AT_CLKTCK = 17,
    // 18-22 reserved in the generic header (powerpc uses that range for its
    // own AT_*CACHEBSIZE/AT_IGNOREPPC extras; not applicable to x86_64).
    /// Boolean indicating "secure mode" (e.g. a setuid/setgid execution),
    /// signaling that libc should harden itself (ignore certain env vars).
    AT_SECURE = 23,
    /// String identifying the real hardware platform, which may differ from
    /// `AT_PLATFORM` (e.g. when running in compatibility mode).
    AT_BASE_PLATFORM = 24,
    /// Address of 16 random bytes supplied by the kernel, used to seed
    /// stack-protector canaries and other userspace randomness.
    AT_RANDOM = 25,
    /// Bitmask of additional CPU capability bits extending `AT_HWCAP`.
    AT_HWCAP2 = 26,
    /// Size in bytes of the restartable sequences (rseq) feature area
    /// supported by the kernel.
    AT_RSEQ_FEATURE_SIZE = 27,
    /// Required alignment in bytes for the restartable sequences (rseq)
    /// memory area.
    AT_RSEQ_ALIGN = 28,
    /// Bitmask of additional CPU capability bits further extending
    /// `AT_HWCAP`.
    AT_HWCAP3 = 29,
    /// Bitmask of additional CPU capability bits further extending
    /// `AT_HWCAP`.
    AT_HWCAP4 = 30,
    /// Pointer to a string containing the pathname used to execute the
    /// program.
    AT_EXECFN = 31,

    // x86-specific extras (`arch/x86/include/uapi/asm/auxvec.h`).
    /// Address of the kernel's vsyscall/vDSO entry point used to make system
    /// calls efficiently. i386-only in the kernel header (guarded by
    /// `#ifdef __i386__`) and not meaningful in true 64-bit mode, but
    /// recorded here anyway since x86_64 systems may still service 32-bit/
    /// i386 compat processes and the value is cheap to keep for a complete
    /// picture.
    AT_SYSINFO = 32,
    /// Address of the vDSO ELF image mapped into the process.
    AT_SYSINFO_EHDR = 33,

    /// Minimum stack size in bytes required for signal delivery.
    AT_MINSIGSTKSZ = 51,
};
