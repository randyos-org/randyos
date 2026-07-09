//! Linux auxiliary vector (`AT_*`) type constants.
//!
//! Sourced from the Linux kernel source tree, torvalds/linux @
//! 8cdeaa50eae8dad34885515f62559ee83e7e8dda (kernel version 7.2.0-rc2):
//!
//! | scope | source file |
//! | --- | --- |
//! | generic base | `include/uapi/linux/auxvec.h` |
//! | x86_64 override | `arch/x86/include/uapi/asm/auxvec.h` |
//! | aarch64 override | `arch/arm64/include/uapi/asm/auxvec.h` |
//! | arm override | `arch/arm/include/uapi/asm/auxvec.h` |
//! | powerpc override | `arch/powerpc/include/uapi/asm/auxvec.h` |
//!
//! Each tag's doc comment is prefixed with the architectures
//! it's specific to, e.g. `[powerpc]` or `[powerpc][x86_64]`; no prefix means
//! the tag is common to x86_64/aarch64/arm/powerpc. This is a numbering
//! reference only -- the target architecture is not consulted to restrict
//! which tags are reachable, so nothing stops code from naming a tag that the
//! real kernel would never place in that architecture's auxv.
//!
//! These are the keys of the auxv (auxiliary vector) entries the kernel
//! places on a new process's initial stack, alongside argv/envp, describing
//! things like the ELF program headers' address (`AT_PHDR`), page size
//! (`AT_PAGESZ`), and vDSO location (`AT_SYSINFO_EHDR`). Each entry is an
//! `(a_type, a_val)` pair; this enum is the `a_type` side only.
//!
//! powerpc uses the generic header's reserved 18-22 range for its own
//! cache-block-size/glibc-compat extras (`AT_DCACHEBSIZE`, `AT_ICACHEBSIZE`,
//! `AT_UCACHEBSIZE`, `AT_IGNOREPPC`) and adds a further block of
//! cache-geometry entries (40-47): for each cache level, a `*_CACHESIZE`
//! entry (size in bytes) and a `*_CACHEGEOMETRY` entry that packs the cache
//! *line* size in bytes into the bottom 16 bits and the associativity into
//! the next 16 bits (N-way set associative for a 16-bit value of N; 0xffff
//! means fully associative; 1 means directly mapped). A value of 0 in any of
//! these entries means the information is not known. Note the
//! `*_CACHEBSIZE` entries (18-22 range) describe the cache *block* size --
//! the size affected by cache-management instructions like `dcbz` -- which
//! does not necessarily match the cache *line* size encoded in
//! `*_CACHEGEOMETRY`.

const std = @import("std");
const log = std.log.scoped(.abi_auxv);

pub const AT = enum(u32) {
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

    // Generic header's reserved 18-22 range; powerpc uses it for its own
    // cache-block-size/glibc-compat extras (`arch/powerpc/include/uapi/asm/
    // auxvec.h`).
    /// [powerpc] Data cache block size in bytes -- the size affected by
    /// cache-management instructions such as `dcbz`, so glibc can use them
    /// safely.
    AT_DCACHEBSIZE = 19,
    /// [powerpc] Instruction cache block size in bytes -- the size affected
    /// by cache-management instructions, so glibc can use them safely.
    AT_ICACHEBSIZE = 20,
    /// [powerpc] Unified cache block size in bytes -- the size affected by
    /// cache-management instructions, so glibc can use them safely.
    AT_UCACHEBSIZE = 21,
    /// [powerpc] A special entry type that is always ignored, kept for glibc
    /// compatibility on PowerPC.
    AT_IGNOREPPC = 22,

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

    /// [x86_64] Address of the kernel's vsyscall/vDSO entry point used to
    /// make system calls efficiently. i386-only in the kernel header (guarded
    /// by `#ifdef __i386__`) and not meaningful in true 64-bit mode, but
    /// recorded here anyway since x86_64 systems may still service 32-bit/
    /// i386 compat processes and the value is cheap to keep for a complete
    /// picture.
    AT_SYSINFO = 32,
    /// Address of the vDSO ELF image mapped into the process; the powerpc
    /// kernel header notes this "has to use the same value as x86 for
    /// glibc's sake." Also redundantly re-declared by
    /// `arch/arm64/include/uapi/asm/auxvec.h` (guarded by
    /// `#ifndef AT_SYSINFO_EHDR`) alongside its own `AT_MINSIGSTKSZ = 51` --
    /// confirmed both values match the generic numbering exactly.
    AT_SYSINFO_EHDR = 33,

    // powerpc-only cache-geometry extras -- see the file header for the
    // *_CACHEGEOMETRY bit-packing.
    /// [powerpc] Level 1 instruction cache size in bytes.
    AT_L1I_CACHESIZE = 40,
    /// [powerpc] Level 1 instruction cache line size (bits 0-15) and
    /// associativity (bits 16-31); see the file header for the exact
    /// bit-packing.
    AT_L1I_CACHEGEOMETRY = 41,
    /// [powerpc] Level 1 data cache size in bytes.
    AT_L1D_CACHESIZE = 42,
    /// [powerpc] Level 1 data cache line size (bits 0-15) and associativity
    /// (bits 16-31); see the file header for the exact bit-packing.
    AT_L1D_CACHEGEOMETRY = 43,
    /// [powerpc] Level 2 cache size in bytes.
    AT_L2_CACHESIZE = 44,
    /// [powerpc] Level 2 cache line size (bits 0-15) and associativity (bits
    /// 16-31); see the file header for the exact bit-packing.
    AT_L2_CACHEGEOMETRY = 45,
    /// [powerpc] Level 3 cache size in bytes.
    AT_L3_CACHESIZE = 46,
    /// [powerpc] Level 3 cache line size (bits 0-15) and associativity (bits
    /// 16-31); see the file header for the exact bit-packing.
    AT_L3_CACHEGEOMETRY = 47,

    /// Minimum stack size in bytes required for signal delivery.
    AT_MINSIGSTKSZ = 51,
};
