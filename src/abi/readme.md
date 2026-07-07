# ABI roadmap: musl + Linux syscall compatibility

STUB area -- nothing here is wired up or implemented (no dispatcher, no ELF
loader, no signal delivery). It exists to record two decisions for the
multi-arch roadmap (x86_64, aarch64, arm, powerpc), and to hold the reference
data the kernel will eventually be tested against for compliance:

1. **musl** is the intended target libc for userspace, once RandyOS grows a
   userspace at all. Not vendored, not linked against, not built yet.
2. **Linux syscall ABI compatibility** is the design goal for that userspace
   -- i.e. the kernel should eventually understand the same syscall numbers,
   calling convention, error numbers, and struct layouts Linux uses on each
   architecture, rather than inventing its own, so existing Linux binaries
   (built against musl) have a shot at running unmodified.

Everything below is sourced directly from the Linux kernel source tree rather
than transcribed from memory, and mechanically extracted into Zig code (not
hand-typed) to avoid transcription error. Unless noted otherwise, everything
is pinned to the same snapshot: `torvalds/linux` @
`8cdeaa50eae8dad34885515f62559ee83e7e8dda` (kernel version 7.2.0-rc2). If
this ever needs refreshing, re-fetch the relevant files and re-run the
extraction rather than hand-editing values in place.

Each category is exposed from `root.zig` (the `"abi"` module -- see
`build.zig`); per-architecture categories resolve at comptime via
`switch (builtin.cpu.arch)`, the same pattern `src/kernel/arch.zig` uses for
per-arch kernel code.

## `syscall/` -- per-architecture syscall numbering

Linux's syscall numbering is **not** shared across architectures -- the same
syscall has a different number on each arch (e.g. `read` is 0 on x86_64 but
63 on aarch64, and aarch64 dropped plain `open` in favor of `openat` only).
`syscall/<arch>.zig` records the full per-arch numbering (350-450+ entries
each).

| arch | source file |
| --- | --- |
| x86_64 | `arch/x86/entry/syscalls/syscall_64.tbl` |
| aarch64 | `include/uapi/asm-generic/unistd.h` |
| arm | `arch/arm/tools/syscall.tbl` |
| powerpc | `arch/powerpc/kernel/syscalls/syscall.tbl` |

## `errno.zig` / `signal.zig` -- generic, not per-arch

Unlike syscall numbers, errno values and signal numbers are identical across
all four target architectures (with one documented exception: powerpc
redefines `EDEADLOCK` to a distinct value, `58`, instead of aliasing
`EDEADLK` like the other three -- see `EDEADLOCK_powerpc` in `errno.zig`).
So these two are single shared files, not a `<name>/<arch>.zig` directory.

| file | source file(s) |
| --- | --- |
| `errno.zig` | `include/uapi/asm-generic/errno-base.h`, `errno.h`, `arch/powerpc/.../asm/errno.h` |
| `signal.zig` | `include/uapi/asm-generic/signal.h` (cross-checked against all four arch headers) |

## `auxv/` -- per-architecture auxiliary vector (`AT_*`) types

The `(a_type, a_val)` pairs the kernel places on a new process's initial
stack alongside argv/envp (program headers address, page size, vDSO
location, etc.) -- needed once ELF loading/process bring-up exists.
`AT_SYSINFO_EHDR` (33) is shared by all four; powerpc additionally uses the
generic header's "reserved" 18-22 range plus a 40-47 cache-geometry block for
its own extras.

| arch | source file(s) |
| --- | --- |
| generic base | `include/uapi/linux/auxvec.h` |
| x86_64 | `arch/x86/include/uapi/asm/auxvec.h` |
| aarch64 | `arch/arm64/include/uapi/asm/auxvec.h` |
| arm | `arch/arm/include/uapi/asm/auxvec.h` |
| powerpc | `arch/powerpc/include/uapi/asm/auxvec.h` |

## `fcntl/` -- per-architecture `open()`/`fcntl()` flags

`O_DIRECT`, `O_LARGEFILE`, `O_DIRECTORY`, and `O_NOFOLLOW` sit at **different
bit positions on every architecture** (x86_64 uses the plain generic
positions; arm/aarch64 agree with each other but differ from powerpc, which
uses yet another ordering) -- this is real ABI divergence, not an artifact of
extraction. arm and powerpc (32-bit `__BITS_PER_LONG`) also expose
`F_GETLK64`/`F_SETLK64`/`F_SETLKW64`, which x86_64/aarch64 (64-bit) do not.

| arch | source file(s) |
| --- | --- |
| generic base | `include/uapi/asm-generic/fcntl.h` |
| x86_64 | (no override at this commit -- uses generic positions verbatim) |
| aarch64 | `arch/arm64/include/uapi/asm/fcntl.h` |
| arm | `arch/arm/include/uapi/asm/fcntl.h` |
| powerpc | `arch/powerpc/include/uapi/asm/fcntl.h` |

## `mman/` -- per-architecture `mmap()`/`mprotect()`/`mlock()`/`madvise()` flags

Mostly shared, but **powerpc diverges significantly**: it doesn't include the
generic `asm-generic/mman.h` at all, and independently defines `MAP_NORESERVE`
(`0x40`, not generic's `0x4000`), `MAP_LOCKED` (`0x80`, not `0x2000`), and
`MCL_CURRENT`/`MCL_FUTURE`/`MCL_ONFAULT` (`0x2000`/`0x4000`/`0x8000`, not
`1`/`2`/`4`). x86_64 adds `MAP_32BIT`/`MAP_ABOVE4G`; aarch64 adds
`PROT_BTI`/`PROT_MTE` and a wider `PKEY_ACCESS_MASK`.

| arch | source file(s) |
| --- | --- |
| generic base | `include/uapi/asm-generic/mman-common.h`, `include/uapi/linux/mman.h`, `include/uapi/asm-generic/mman.h` |
| x86_64 | `arch/x86/include/uapi/asm/mman.h` |
| aarch64 | `arch/arm64/include/uapi/asm/mman.h` |
| arm | `arch/arm/include/uapi/asm/mman.h` (pure passthrough, no new values) |
| powerpc | `arch/powerpc/include/uapi/asm/mman.h` |

## `types/` -- struct layouts

`types/stat/<arch>.zig` is per-architecture (`struct stat` genuinely differs
in field order and width across all four -- e.g. x86_64 orders
`st_dev/st_ino/st_nlink` before `st_mode`, while 32-bit powerpc orders
`st_mode` before `st_nlink`); arm and powerpc additionally get a `Stat64`
(the `*64` syscall variants' layout, for file sizes/inode numbers too large
for the plain 32-bit fields). The rest of `types/` is uniform across all four
architectures, so those are single shared files.

| file | source file(s) |
| --- | --- |
| `stat/x86_64.zig` | `arch/x86/include/uapi/asm/stat.h` |
| `stat/aarch64.zig` | `include/uapi/asm-generic/stat.h` (aarch64 has no override) |
| `stat/arm.zig` | `arch/arm/include/uapi/asm/stat.h` |
| `stat/powerpc.zig` | `arch/powerpc/include/uapi/asm/stat.h` |
| `timespec.zig` | `include/uapi/linux/time_types.h` (`__kernel_timespec` only) |
| `rlimit.zig` | `include/uapi/linux/resource.h`, `include/uapi/asm-generic/resource.h` |
| `iovec.zig` | `include/uapi/linux/uio.h` |
| `utsname.zig` | `include/uapi/linux/utsname.h` (`struct new_utsname` only) |
| `dirent64.zig` | `include/linux/dirent.h` (kernel-internal, not `uapi/`, but canonical) |

None of it is wired to a dispatcher, ELF loader, or process bring-up; there
is no `dispatch()` anywhere yet.
