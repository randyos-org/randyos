# TODO — path to running systemd (and later, DRM)

## Current state of `src/abi/`

Pure reference data: errno numbers, signal numbers, per-arch syscall number
tables, mmap/fcntl/prot flag constants, and struct layouts (stat, timespec,
rlimit, iovec, utsname, dirent64). No executable logic, nothing in
`src/kernel/` calls into it yet. This is the vocabulary, not the
implementation — maybe 1-2% of the work needed to run real Linux userspace.

## Two separate ABI layers (don't conflate these)

1. **User ⇿ kernel**: the syscall ABI. Not a C-linkable API — it's a CPU
   trap (`syscall` on x86_64, `svc #0` on aarch64/arm, `sc` on powerpc).
   Args arrive in registers (RAX = number, RDI/RSI/RDX/R10/R8/R9 on x86_64),
   not a stack-based call. Kernel trap handler reads the number, indexes a
   dispatch table, calls an internal handler. `src/abi/syscall/*.zig`
   numbering tables are the index into that table — dispatcher +
   handlers still need to be written.

2. **Kernel-internal driver framework** (relevant for DRM/GPU drivers):
   a real, large, C-linkable API (`drm_dev_alloc`, GEM/TTM helpers,
   `pci_register_driver`, IOMMU helpers, `request_firmware`, etc.) but
   it's kernel-internal and not stable/binary-portable. To run
   amdgpu/nouveau you'd need to reimplement enough of this framework
   (matching signatures) that their existing driver *source* recompiles
   against our kernel — analogous to FreeBSD's `drm-kmod`. This is a
   separate, later project from the syscall work below.

   Kernel modules in general (not just DRM) never cross the syscall trap
   boundary at all — a `.ko` links directly into kernel address space and
   touches kernel-internal structs directly. Supporting arbitrary Linux
   `.ko` binaries means binary-compatibility with Linux's internals at an
   exact version, which is a categorically different (and effectively
   unbounded) problem. **Out of scope for now.**

   `nvidia.ko` specifically is a closed binary tied to one exact kernel
   build's internal struct layouts/symbol versions — no source to target,
   no stable surface, not achievable via syscall-ABI compatibility no
   matter how good that gets.

## Syscall implementation priority (x86_64, target: boot systemd as PID 1)

Ordered by hard dependency — each tier gates the next actually doing
anything testable.

### Tier 0 — get any static binary to exit cleanly

- `exit` / `exit_group`
- `write`, `read`
- `open` / `openat`, `close`
- `mmap` / `munmap` / `mprotect`, `brk`
- `arch_prctl` (TLS/FS-base setup — glibc dies immediately without this)
- `set_tid_address`, `set_robust_list`
- `rseq` (glibc >= 2.35 calls at thread init — can stub as no-op success)
- `getpid` / `gettid`
- `fstat` / `newfstatat`, `lseek`
- `ioctl` (stub returning ENOTTY or similar is fine early)

### Tier 1 — dynamic linking (systemd is 100% dynamically linked)

- ld.so's use of open/mmap/fstat from Tier 0
- `access` / `faccessat`
- `readlink` / `readlinkat`
- `getrandom` (glibc >= 2.36 needs this for stack-protector/ASLR — not optional)
- `uname`
- `prlimit64` / `getrlimit`
- `getuid` / `geteuid` / `getgid` / `getegid` / `getresuid` / `getresgid`
- `capget`
- `gettimeofday` / `clock_gettime` / `clock_getres`
- `prctl` (systemd calls this constantly — PR_SET_NAME etc.)

### Tier 2 — process/thread model (biggest implementation lift)

- `clone` / `clone3` (modern glibc pthread_create + systemd itself use clone3)
- `execve` / `execveat`
- `wait4` / `waitid` (PID 1 is the universal orphan reaper)
- `kill` / `tgkill`
- `rt_sigaction` / `rt_sigprocmask` / `rt_sigreturn`
- `futex` (mandatory the instant anything threaded touches a lock —
  glibc malloc included)
- `set_robust_list` / `get_robust_list`

Requires: real scheduler, real address-space copy/COW, real signal delivery.

### Tier 3 — real filesystem semantics

- `mount` / `umount2` (systemd's first acts as PID 1: mount proc/sysfs/
  devtmpfs/cgroup2/tmpfs)
- `getdents64` (constant directory scanning of unit files)
- `statx` / `stat` / `fstatat`
- `mkdir` / `rmdir` / `unlink` / `rename` / `symlink` / `link`
  (the `*at` variants — systemd uses these almost exclusively)
- `chmod` / `chown` / `utimensat`
- `statfs` / `fstatfs` (detect cgroup2 vs legacy)

### Tier 4 — event loop (systemd's core is built entirely on this)

- `epoll_create1` / `epoll_ctl` / `epoll_wait`
- `signalfd4`
- `timerfd_create` / `timerfd_settime`
- `eventfd2`
- `pipe2`

sd-event (systemd's internal event loop) cannot start without epoll — this
gates earlier than a naive syscall-count view would suggest.

### Tier 5 — sockets

- `socket` / `socketpair` / `bind` / `listen` / `accept4` / `connect` /
  `sendmsg` / `recvmsg` / `setsockopt` / `getsockopt` / `shutdown`
  for AF_UNIX, with real `SCM_CREDENTIALS` / `SO_PEERCRED` support
  (systemd authenticates every client via peer creds — sd_notify, the
  private control socket, journald all depend on this)
- AF_NETLINK (rtnetlink + uevent) — deferrable if systemd-udevd runs
  degraded/absent

### Tier 6 — cgroup v2

Not new syscalls — `mount` + `mkdir`/`write` on a filesystem type the VFS
recognizes as cgroup2. Controllers can be no-ops initially; systemd only
hard-requires the *hierarchy* to exist to start units, not working resource
limits.

### Tier 7 — namespaces

- `unshare` / `setns`

Deferrable to reach a shell, but most stock unit files set sandboxing
directives (`PrivateTmp=`, `ProtectSystem=`) that need this fast.

## Not a syscall, but equally load-bearing

**procfs/sysfs content correctness.** Systemd parses `/proc/self/mountinfo`,
`/proc/meminfo`, `/proc/[pid]/status`, `/sys/fs/cgroup/*` structurally, not
as opaque files. Faking the syscalls without faking believable structured
content here will get past `open()` and then fail deep in systemd's own
parsing logic.

## Next steps (not started)

- [ ] Scaffold Tier 0: per-arch trap/exception entry + syscall dispatch
      table + handlers for the Tier 0 list above.
- [ ] Once Tier 0-1 boot a static/dynamic "hello world," move to Tier 2
      (process/thread model) — largest single lift.
- [ ] Revisit DRM/GPU driver framework as its own project after systemd
      boots to a shell; scope separately (kernel-internal driver API,
      not syscalls).
