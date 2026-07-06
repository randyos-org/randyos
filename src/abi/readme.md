# ABI roadmap: musl + Linux syscall compatibility

STUB area -- nothing here is wired up or implemented. It exists to record two
decisions for the multi-arch roadmap (x86_64, aarch64, arm, powerpc):

1. **musl** is the intended target libc for userspace, once RandyOS grows a
   userspace at all. Not vendored, not linked against, not built yet.
2. **Linux syscall ABI compatibility** is the design goal for that userspace
   -- i.e. the kernel should eventually understand the same syscall numbers
   and calling convention Linux uses on each architecture, rather than
   inventing its own, so existing Linux binaries (built against musl) have a
   shot at running unmodified.

Linux's syscall numbering is **not** shared across architectures -- the same
syscall has a different number on each arch (e.g. `read` is 0 on x86_64 but
63 on aarch64, and aarch64 dropped plain `open` in favor of `openat` only).

`syscall/<arch>.zig` records the full per-arch numbering (350-450+ entries
each), fetched directly from the Linux kernel source tree rather than
transcribed from memory, and mechanically extracted into Zig enums (not
hand-typed) to avoid transcription error:

| arch    | source file                                       |
| ------- | ------------------------------------------------- |
| x86_64  | `arch/x86/entry/syscalls/syscall_64.tbl`          |
| aarch64 | `include/uapi/asm-generic/unistd.h`               |
| arm     | `arch/arm/tools/syscall.tbl`                      |
| powerpc | `arch/powerpc/kernel/syscalls/syscall.tbl`        |

Snapshot from `torvalds/linux` @ `8cdeaa50eae8dad34885515f62559ee83e7e8dda`
(kernel version 7.2.0-rc2). If this ever needs refreshing, re-fetch those
files and re-run the extraction rather than hand-editing numbers in place.

None of it is wired to a dispatcher; there is no `dispatch()` anywhere yet.
