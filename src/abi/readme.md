# ABI roadmap

The kernel will eventually be tested against for compliance:

1. **Linux syscall ABI compatibility** is the design goal for that userspace,
   i.e. the kernel should eventually understand the same syscall numbers,
   calling convention, error numbers, and struct layouts Linux uses on each
   architecture, rather than inventing its own, so existing Linux binaries
   (built against musl) have a shot at running unmodified.
2. **musl** is the intended target libc for userspace, once RandyOS grows a
   userspace at all. Not vendored, not linked against, not built yet.

Everything below is sourced directly from the Linux kernel source tree.
Unless noted otherwise, everything is pinned to the same snapshot:
`torvalds/linux` @ `8cdeaa50eae8dad34885515f62559ee83e7e8dda` (kernel version 7.2.0-rc2).

Each category is exposed from `root.zig` (the `"abi"` module -- see
`build.zig`); per-architecture categories resolve at comptime via
`switch (builtin.cpu.arch)`, the same pattern `src/kernel/arch.zig` uses for
per-arch kernel code.

## `syscall.zig` -- syscall numbering, union of all four architectures

Linux's syscall numbering is **not** shared across architectures:
the same syscall has a different number on each arch
(e.g. `read` is 0 on x86_64 but 63 on aarch64),
and not every arch defines every syscall
(aarch64 dropped plain `open` in favor of `openat` only).
`syscall.zig`'s `Number` enum covers the union of all names any of the four
define (489 total); each name's value is picked per architecture by a
`builtin.cpu.arch` switch, and a name an architecture doesn't define resolves
to a distinct `_invalid<N>` sentinel (`std.math.maxInt(u32) - N`) on that
architecture rather than a compile error.
Real Linux syscall numbers never set a `u32`'s top bit, so a dispatcher can
treat a "negative-when-reinterpreted-as-`i32`" value as invalid and panic or no-op.

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
`EDEADLK` like the other three).

| file | source file(s) |
| --- | --- |
| `errno.zig` | `include/uapi/asm-generic/errno-base.h`, `errno.h`, `arch/powerpc/.../asm/errno.h` |
| `signal.zig` | `include/uapi/asm-generic/signal.h` (cross-checked against all four arch headers) |

## `auxv.zig` -- mostly-generic auxiliary vector (`AT_*`) types

The `(a_type, a_val)` pairs the kernel places on a new process's initial
stack alongside argv/envp (program headers address, page size, vDSO
location, etc.) -- needed once ELF loading/process bring-up exists.
`AT_SYSINFO_EHDR` (33) is shared by all four; powerpc additionally uses the
generic header's "reserved" 18-22 range plus a 40-47 cache-geometry block for
its own extras, and x86_64 alone adds `AT_SYSINFO` (32). Since the four arch
headers agree on all but a handful of tags, this is a single enum (`AT` in
`auxv.zig`). Each arch-specific tag's doc comment is prefixed with which
architecture(s) it's specific to (e.g. `[powerpc]`),
with no prefix meaning the tag is common to all four.

| arch | source file(s) |
| --- | --- |
| generic base | `include/uapi/linux/auxvec.h` |
| x86_64 | `arch/x86/include/uapi/asm/auxvec.h` |
| aarch64 | `arch/arm64/include/uapi/asm/auxvec.h` |
| arm | `arch/arm/include/uapi/asm/auxvec.h` |
| powerpc | `arch/powerpc/include/uapi/asm/auxvec.h` |

## `fcntl.zig` -- mostly-generic `open()`/`fcntl()` flags and commands

`open()`'s flags are independent, combinable bits, so `OpenFlags` is a
`packed struct(u32)`, same treatment as `mman.zig`'s `ProtFlags`/`MapFlags`.
`O_DIRECT`, `O_LARGEFILE`, `O_DIRECTORY`, and `O_NOFOLLOW` sit at
**different bit positions on every architecture** (x86_64 uses the plain
generic positions; arm/aarch64 agree with each other but differ from
powerpc, which swaps `O_LARGEFILE`/`O_DIRECT`) -- this is real ABI
divergence, not an artifact of extraction, so there's a private `OpenFlags`
type per distinct layout plus a public `builtin.cpu.arch`-switched alias.
`fcntl()`'s command argument (`FcntlCommand`) is a mutually exclusive
enum instead; arm and powerpc (32-bit `__BITS_PER_LONG`) additionally
define `getlk64`/`setlk64`/`setlkw64`, which x86_64/aarch64 (64-bit) do
not -- tagged `[arm][powerpc]` in their doc comments rather than gated out,
the same convention `auxv.zig` uses for its own small set of extras.

| arch | source file(s) |
| --- | --- |
| generic base | `include/uapi/asm-generic/fcntl.h` |
| x86_64 | (no override at this commit -- uses generic positions verbatim) |
| aarch64 | `arch/arm64/include/uapi/asm/fcntl.h` |
| arm | `arch/arm/include/uapi/asm/fcntl.h` |
| powerpc | `arch/powerpc/include/uapi/asm/fcntl.h` |

## `mman.zig` -- mostly-generic `mmap()`/`mprotect()`/`mlock()`/`madvise()` flags

Groups of genuinely independent, combinable bits (`ProtFlags`, `MapFlags`,
`MclFlags`, `MremapFlags`, `ShadowStackSetFlags`, `PkeyDisableFlags`) are
`packed struct(u32)` types with named `bool` fields instead of discrete
`PROT_READ`-style integer constants -- `@bitCast` recovers the raw `u32` the
syscall ABI wants at zero cost. Where an architecture's bit layout genuinely
differs, there's a private struct type per distinct layout plus a public
`builtin.cpu.arch`-switched alias, the same per-arch-type-plus-switch
pattern `stat.zig` uses for `Stat`/`Stat64` (referencing a flag or type that
doesn't exist for the target, e.g. `ProtFlags.bti` outside aarch64, is a
compile error there too -- for free, via Zig's own "no field named" check).
Mutually exclusive *value* sets that aren't combinable flag bits at all
(`Madvise`, `OvercommitMode`) are plain enums instead. **powerpc diverges
significantly**: it doesn't include the generic `asm-generic/mman.h` at
all, and independently defines `MAP_NORESERVE` (`0x40`, not generic's
`0x4000`), `MAP_LOCKED` (`0x80`, not `0x2000`), and `MCL_CURRENT`/
`MCL_FUTURE`/`MCL_ONFAULT` (`0x2000`/`0x4000`/`0x8000`, not `1`/`2`/`4`), and
has no `ShadowStackSetFlags` equivalent at all. x86_64 adds `map32bit`/
`above4g` fields; aarch64 adds `bti`/`mte`/`execute`/`read` fields; powerpc
adds a `sao` field and a `MAP_RENAME` alias (same bit as `.anonymous`).

| arch | source file(s) |
| --- | --- |
| generic base | `include/uapi/asm-generic/mman-common.h`, `include/uapi/linux/mman.h`, `include/uapi/asm-generic/mman.h` |
| x86_64 | `arch/x86/include/uapi/asm/mman.h` |
| aarch64 | `arch/arm64/include/uapi/asm/mman.h` |
| arm | `arch/arm/include/uapi/asm/mman.h` (pure passthrough, no new values) |
| powerpc | `arch/powerpc/include/uapi/asm/mman.h` |

## `stat.zig` and the rest -- struct layouts

`stat.zig` holds a private struct type per architecture (`struct stat`
genuinely differs in field order and width across all four)
plus `pub const Stat`/`pub const Stat64` switches on `builtin.cpu.arch` to pick
the right one; arm and powerpc additionally get
a `Stat64` (the `*64` syscall variants' layout, for file sizes/inode numbers
too large for the plain 32-bit fields).

| file | source file(s) |
| --- | --- |
| `stat.zig` (x86_64) | `arch/x86/include/uapi/asm/stat.h` |
| `stat.zig` (aarch64) | `include/uapi/asm-generic/stat.h` (aarch64 has no override) |
| `stat.zig` (arm) | `arch/arm/include/uapi/asm/stat.h` |
| `stat.zig` (powerpc) | `arch/powerpc/include/uapi/asm/stat.h` |
| `timespec.zig` | `include/uapi/linux/time_types.h` (`__kernel_timespec` only) |
| `rlimit.zig` | `include/uapi/linux/resource.h`, `include/uapi/asm-generic/resource.h` |
| `iovec.zig` | `include/uapi/linux/uio.h` |
| `utsname.zig` | `include/uapi/linux/utsname.h` (`struct new_utsname` only) |
| `dirent64.zig` | `include/linux/dirent.h` (kernel-internal, not `uapi/`, but canonical) |
