//! Linux `mmap()`/`mprotect()`/`mlock()`/`madvise()` ABI constants, one file
//! covering all four architectures.
//!
//! Sourced from the Linux kernel source tree, torvalds/linux @
//! 8cdeaa50eae8dad34885515f62559ee83e7e8dda (kernel version 7.2.0-rc2):
//!
//! | scope | source file |
//! | --- | --- |
//! | generic base | `include/uapi/asm-generic/mman-common.h` (PROT_*, MAP_TYPE/FIXED/ANONYMOUS/POPULATE/NONBLOCK/STACK/HUGETLB/SYNC/FIXED_NOREPLACE/UNINITIALIZED, MLOCK_ONFAULT, MS_*, MADV_*, MAP_FILE, PKEY_*), `include/uapi/linux/mman.h` (MAP_SHARED/PRIVATE/SHARED_VALIDATE/DROPPABLE, MREMAP_*, OVERCOMMIT_*) |
//! | x86_64 | `arch/x86/include/uapi/asm/mman.h` -- includes `asm-generic/mman.h` (MAP_GROWSDOWN/DENYWRITE/EXECUTABLE/LOCKED/NORESERVE, MCL_*, SHADOW_STACK_SET_*) unmodified, adds `MAP_32BIT`/`MAP_ABOVE4G` |
//! | aarch64 | `arch/arm64/include/uapi/asm/mman.h` -- includes `asm-generic/mman.h` unmodified, adds `PROT_BTI`/`PROT_MTE`, overrides `PKEY_DISABLE_EXECUTE`/`PKEY_DISABLE_READ`/`PKEY_ACCESS_MASK` |
//! | arm | `arch/arm/include/uapi/asm/mman.h` -- confirmed pure passthrough (its only content beyond the `asm-generic/mman.h` include is an `arch_mmap_check()` macro, not a flag constant); defines no new PROT_*/MAP_*/MCL_*/PKEY_* values of its own |
//! | powerpc | `arch/powerpc/include/uapi/asm/mman.h` -- does **not** include `asm-generic/mman.h` at all (only `mman-common.h`), so it independently (re)defines `MAP_GROWSDOWN`/`DENYWRITE`/`EXECUTABLE` (values happen to match generic), its own `MAP_NORESERVE`/`MAP_LOCKED`/`MCL_*` values (genuinely diverge), `PROT_SAO`, a `MAP_RENAME` alias, and a powerpc-only `PKEY_DISABLE_EXECUTE` override; has no `SHADOW_STACK_SET_*` equivalent (no `map_shadow_stack()` support upstream at this commit) |
//!
//! Groups of independent, combinable bits (`PROT_*`, `MAP_*`, `MCL_*`,
//! `MREMAP_*`, `SHADOW_STACK_SET_*`, `PKEY_DISABLE_*`, `MS_*`) are modeled
//! as `packed struct(u32)` types with named `bool` fields instead of
//! discrete integer constants: `ProtFlags{ .read = true, .write = true }`
//! reads better than `PROT_READ | PROT_WRITE`, and `@bitCast(u32, flags)`
//! recovers the raw word the actual syscall ABI wants at zero runtime cost.
//! This includes `MS_*` even though `MS_ASYNC`/`MS_SYNC` are mutually
//! exclusive per the man page -- the struct doesn't enforce that any more
//! than raw integer flags did (nothing stops a caller from setting both
//! bits either way), so there's no correctness loss versus the discrete
//! constants, only the same ergonomic win the other groups get.
//! Where an architecture's bit layout genuinely differs (powerpc moves
//! `MAP_LOCKED`/`MAP_NORESERVE`/`MCL_*` to different bit positions; x86_64
//! adds two bits `MAP_32BIT`/`MAP_ABOVE4G` that don't exist elsewhere;
//! aarch64/powerpc each add different `PKEY_DISABLE_*` bits), there's a
//! private struct type per distinct layout below, with a public
//! `builtin.cpu.arch`-switched alias picking the right one for the target
//! -- the same per-arch-type-plus-switch pattern `stat.zig` uses for
//! `Stat`/`Stat64`, and the same `_align<N>` convention (restarting at 1 per
//! struct) `stat.zig` and `src/kernel/hw/acpi/madt.zig` use for padding:
//! a padding bit's name never appears in the ABI, only its position does.
//! Referencing a flag or type that doesn't exist for the target architecture
//! (e.g. `ProtFlags.bti` outside aarch64, or `ShadowStackSetFlags` at all on
//! powerpc) is a compile error, the same guarantee the discrete-constant
//! version had.
//!
//! `MAP_SHARED`/`MAP_PRIVATE`/`MAP_SHARED_VALIDATE` are the odd ones out
//! within `MAP_*`: they're not independent bits but a 2-bit sub-field
//! (`MapType`, bits 0-1 of the flags word) with four mutually exclusive
//! values -- `MAP_SHARED_VALIDATE` (`0x3`) is its own distinct mode, not
//! "shared and private at once". `MapType` itself doesn't vary per
//! architecture, only its neighboring bits do, so it's a single shared enum
//! embedded in each architecture's `MapFlags`.
//!
//! `MADV_*` (madvise() advice) and `OVERCOMMIT_*` (an overcommit *mode*, see
//! `/proc/sys/vm/overcommit_memory`) are mutually exclusive value sets, not
//! independent bits, so each is a plain `enum(u32)` (`Madvise`/
//! `OvercommitMode`) instead of a packed struct -- both are identical
//! across all four architectures, so neither needs a per-arch switch.
//!
//! `PROT_NONE`, `MAP_FILE`, and `PKEY_UNRESTRICTED` are each a single
//! sentinel *value* for their whole flags word (all-zero), not a bit of
//! their own, so they stay plain constants too -- `ProtFlags{}`/
//! `MapFlags{}`/`PkeyDisableFlags{}` (every field defaulted false) already
//! mean the same thing structurally.

const sysinfo = @import("builtin");
const std = @import("std");
const log = std.log.scoped(.abi_mman);

// PROT_* -- mmap()/mprotect() protection flags.

/// x86_64/arm: no arch-specific PROT_* bits are defined, so bits 4-5 (which
/// aarch64 and powerpc use for their own extras) are pure padding here.
const GenericProtFlags = packed struct(u32) {
    /// The page may be read.
    read: bool = false,
    /// The page may be written.
    write: bool = false,
    /// The page may be executed as code.
    exec: bool = false,
    /// The page may be used for atomic operations (rarely used outside a
    /// few architectures' historical semaphore support).
    sem: bool = false,
    /// padding/reserved, must be present for layout
    _align1: u20 = 0,
    /// mprotect() flag: also extend the protection change to the rest of a
    /// downward-growing (stack-like) mapping.
    growsdown: bool = false,
    /// mprotect() flag: also extend the protection change to the rest of
    /// an upward-growing mapping.
    growsup: bool = false,
    /// padding/reserved, must be present for layout
    _align2: u6 = 0,

    /// No access at all -- no read, write, or execute. The all-zero `ProtFlags`.
    pub const NONE: GenericProtFlags = 0;
};

const Aarch64ProtFlags = packed struct(u32) {
    /// The page may be read.
    read: bool = false,
    /// The page may be written.
    write: bool = false,
    /// The page may be executed as code.
    exec: bool = false,
    /// The page may be used for atomic operations (rarely used outside a
    /// few architectures' historical semaphore support).
    sem: bool = false,
    /// aarch64-only: marks the page as a Branch Target Identification (BTI)
    /// guarded landing pad for indirect branches.
    bti: bool = false,
    /// aarch64-only: enables Memory Tagging Extension (MTE) tag checking
    /// for this normal (non-device) mapping.
    mte: bool = false,
    /// padding/reserved, must be present for layout
    _align1: u18 = 0,
    /// mprotect() flag: also extend the protection change to the rest of a
    /// downward-growing (stack-like) mapping.
    growsdown: bool = false,
    /// mprotect() flag: also extend the protection change to the rest of
    /// an upward-growing mapping.
    growsup: bool = false,
    /// padding/reserved, must be present for layout
    _align2: u6 = 0,

    /// No access at all -- no read, write, or execute. The all-zero `ProtFlags`.
    pub const NONE: GenericProtFlags = 0;
};

const PowerpcProtFlags = packed struct(u32) {
    /// The page may be read.
    read: bool = false,
    /// The page may be written.
    write: bool = false,
    /// The page may be executed as code.
    exec: bool = false,
    /// The page may be used for atomic operations (rarely used outside a
    /// few architectures' historical semaphore support).
    sem: bool = false,
    /// powerpc-only: Strong Access Ordering hint disabling weak memory
    /// ordering/reordering optimizations for this page.
    sao: bool = false,
    /// padding/reserved, must be present for layout
    _align1: u19 = 0,
    /// mprotect() flag: also extend the protection change to the rest of a
    /// downward-growing (stack-like) mapping.
    growsdown: bool = false,
    /// mprotect() flag: also extend the protection change to the rest of
    /// an upward-growing mapping.
    growsup: bool = false,
    /// padding/reserved, must be present for layout
    _align2: u6 = 0,

    /// No access at all -- no read, write, or execute. The all-zero `ProtFlags`.
    pub const NONE: GenericProtFlags = 0;
};

/// mmap()/mprotect() protection flags for whichever architecture is
/// actually being built. Bits 4-5 (the generic header's reserved
/// arch-specific range) hold different flags per architecture: aarch64 uses
/// them for `bti`/`mte`, powerpc uses bit 4 alone for `sao`; x86_64/arm
/// leave both unused.
pub const ProtFlags = switch (sysinfo.cpu.arch) {
    .x86_64, .arm => GenericProtFlags,
    .aarch64 => Aarch64ProtFlags,
    .powerpc => PowerpcProtFlags,
    else => @compileError("No mman ABI data for this architecture"),
};

// MAP_* -- mmap() flags.

/// The mapping-type sub-field occupying bits 0-1 of the `MAP_*` flags word
/// -- a 2-bit mutually-exclusive mode selector, not independent bits.
/// `shared_validate` is its own distinct mode (the kernel rejects any
/// unrecognized flag bits), not "shared and private at once".
pub const MapType = enum(u2) {
    none = 0,
    /// Changes to the mapping are shared with other processes mapping the
    /// same file/region and are written back to the underlying file.
    shared = 1,
    /// Changes to the mapping are private, copy-on-write, and never
    /// written back to the underlying file.
    private = 2,
    /// Like `.shared`, but the kernel rejects any unrecognized flag bits
    /// instead of silently ignoring them.
    shared_validate = 3,
};

/// x86_64: adds `map32bit`/`above4g` at bits 6-7 (not present on any other
/// architecture); `locked`/`noreserve` sit at the generic bit positions
/// (13/14).
const X86_64MapFlags = packed struct(u32) {
    map_type: MapType = .none,
    /// padding/reserved, must be present for layout
    _align1: u1 = 0,
    /// Lets the kernel silently discard (zero) these pages under memory
    /// pressure instead of writing them to swap.
    droppable: bool = false,
    /// Interpret the given address exactly, unmapping any existing
    /// mapping that overlaps it.
    fixed: bool = false,
    /// The mapping isn't backed by a file -- contents are zero-initialized.
    anonymous: bool = false,
    /// x86_64-only: restrict the mapping to the low 2GB of address space
    /// so pointers into it fit in 32 bits.
    map32bit: bool = false,
    /// x86_64-only: force the mapping to be placed entirely above the 4GB
    /// address boundary.
    above4g: bool = false,
    /// Used for stack-like mappings that automatically grow downward as
    /// they're accessed.
    growsdown: bool = false,
    /// padding/reserved, must be present for layout
    _align2: u2 = 0,
    /// Historical flag, now ignored by the kernel; used to deny writes to
    /// the mapped file while it was mapped (ETXTBSY semantics).
    denywrite: bool = false,
    /// Historical flag, now ignored by the kernel; used to mark the
    /// mapping as backing an executable file.
    executable: bool = false,
    /// Lock the mapped pages into physical memory, as if by mlock().
    locked: bool = false,
    /// Don't reserve swap/commit space for this mapping up front; only
    /// fail later if memory actually runs out.
    noreserve: bool = false,
    /// Prefault and populate page tables for the whole mapping
    /// immediately, avoiding later minor page faults.
    populate: bool = false,
    /// With `populate`, only prefault pages already resident in memory;
    /// don't block on I/O to bring pages in.
    nonblock: bool = false,
    /// Hints the kernel to place the mapping at an address suitable for a
    /// process/thread stack.
    stack: bool = false,
    /// Back the mapping with huge pages instead of the normal page size.
    hugetlb: bool = false,
    /// Ensure page faults on this (DAX) mapping are synchronous, so writes
    /// are durable without a separate msync().
    sync: bool = false,
    /// Like `fixed`, but fail instead of clobbering any existing mapping
    /// that overlaps the requested address.
    fixed_noreplace: bool = false,
    /// padding/reserved, must be present for layout
    _align3: u5 = 0,
    /// On nommu systems, allow anonymous memory to be left uninitialized
    /// instead of zero-filled, for performance.
    uninitialized: bool = false,
    /// padding/reserved, must be present for layout
    _align4: u5 = 0,

    /// Historical compatibility flag with no effect; always zero.
    pub const FILE: X86_64MapFlags = 0;
};

/// aarch64/arm: no `map32bit`/`above4g` (x86_64-only); `locked`/`noreserve`
/// sit at the generic bit positions (13/14), same as x86_64.
const GenericMapFlags = packed struct(u32) {
    map_type: MapType = .none,
    /// padding/reserved, must be present for layout
    _align1: u1 = 0,
    /// Lets the kernel silently discard (zero) these pages under memory
    /// pressure instead of writing them to swap.
    droppable: bool = false,
    /// Interpret the given address exactly, unmapping any existing
    /// mapping that overlaps it.
    fixed: bool = false,
    /// The mapping isn't backed by a file -- contents are zero-initialized.
    anonymous: bool = false,
    /// padding/reserved, must be present for layout
    _align2: u2 = 0,
    /// Used for stack-like mappings that automatically grow downward as
    /// they're accessed.
    growsdown: bool = false,
    /// padding/reserved, must be present for layout
    _align3: u2 = 0,
    /// Historical flag, now ignored by the kernel; used to deny writes to
    /// the mapped file while it was mapped (ETXTBSY semantics).
    denywrite: bool = false,
    /// Historical flag, now ignored by the kernel; used to mark the
    /// mapping as backing an executable file.
    executable: bool = false,
    /// Lock the mapped pages into physical memory, as if by mlock().
    locked: bool = false,
    /// Don't reserve swap/commit space for this mapping up front; only
    /// fail later if memory actually runs out.
    noreserve: bool = false,
    /// Prefault and populate page tables for the whole mapping
    /// immediately, avoiding later minor page faults.
    populate: bool = false,
    /// With `populate`, only prefault pages already resident in memory;
    /// don't block on I/O to bring pages in.
    nonblock: bool = false,
    /// Hints the kernel to place the mapping at an address suitable for a
    /// process/thread stack.
    stack: bool = false,
    /// Back the mapping with huge pages instead of the normal page size.
    hugetlb: bool = false,
    /// Ensure page faults on this (DAX) mapping are synchronous, so writes
    /// are durable without a separate msync().
    sync: bool = false,
    /// Like `fixed`, but fail instead of clobbering any existing mapping
    /// that overlaps the requested address.
    fixed_noreplace: bool = false,
    /// padding/reserved, must be present for layout
    _align4: u5 = 0,
    /// On nommu systems, allow anonymous memory to be left uninitialized
    /// instead of zero-filled, for performance.
    uninitialized: bool = false,
    /// padding/reserved, must be present for layout
    _align5: u5 = 0,

    /// Historical compatibility flag with no effect; always zero.
    pub const FILE: GenericMapFlags = 0;
};

/// powerpc: no `map32bit`/`above4g`; `locked`/`noreserve` DIVERGE to bits
/// 7/6 (independently defined -- powerpc never includes the generic
/// `asm-generic/mman.h` these normally come from), leaving the generic
/// bits 13-14 as padding instead.
const PowerpcMapFlags = packed struct(u32) {
    map_type: MapType = .none,
    /// padding/reserved, must be present for layout
    _align1: u1 = 0,
    /// Lets the kernel silently discard (zero) these pages under memory
    /// pressure instead of writing them to swap.
    droppable: bool = false,
    /// Interpret the given address exactly, unmapping any existing
    /// mapping that overlaps it.
    fixed: bool = false,
    /// The mapping isn't backed by a file -- contents are zero-initialized.
    /// Also known as `MAP_RENAME` on powerpc (legacy SunOS-terminology
    /// alias for the same bit, no separate meaning).
    anonymous: bool = false,
    /// powerpc-only bit position (0x40; the generic 0x4000 position is
    /// unused padding here instead -- see the type doc comment).
    noreserve: bool = false,
    /// powerpc-only bit position (0x80; the generic 0x2000 position is
    /// unused padding here instead -- see the type doc comment).
    locked: bool = false,
    /// Used for stack-like mappings that automatically grow downward as
    /// they're accessed.
    growsdown: bool = false,
    /// padding/reserved, must be present for layout
    _align2: u2 = 0,
    /// Historical flag, now ignored by the kernel; used to deny writes to
    /// the mapped file while it was mapped (ETXTBSY semantics).
    denywrite: bool = false,
    /// Historical flag, now ignored by the kernel; used to mark the
    /// mapping as backing an executable file.
    executable: bool = false,
    /// padding/reserved, must be present for layout (generic `locked`/
    /// `noreserve` bit positions; powerpc uses bits 6-7 instead)
    _align3: u2 = 0,
    /// Prefault and populate page tables for the whole mapping
    /// immediately, avoiding later minor page faults.
    populate: bool = false,
    /// With `populate`, only prefault pages already resident in memory;
    /// don't block on I/O to bring pages in.
    nonblock: bool = false,
    /// Hints the kernel to place the mapping at an address suitable for a
    /// process/thread stack.
    stack: bool = false,
    /// Back the mapping with huge pages instead of the normal page size.
    hugetlb: bool = false,
    /// Ensure page faults on this (DAX) mapping are synchronous, so writes
    /// are durable without a separate msync().
    sync: bool = false,
    /// Like `fixed`, but fail instead of clobbering any existing mapping
    /// that overlaps the requested address.
    fixed_noreplace: bool = false,
    /// padding/reserved, must be present for layout
    _align4: u5 = 0,
    /// On nommu systems, allow anonymous memory to be left uninitialized
    /// instead of zero-filled, for performance.
    uninitialized: bool = false,
    /// padding/reserved, must be present for layout
    _align5: u5 = 0,

    /// Historical compatibility flag with no effect; always zero.
    pub const FILE: PowerpcMapFlags = 0;

    /// legacy SunOS-terminology alias for MAP_ANONYMOUS; identical meaning.
    pub const RENAME: PowerpcMapFlags = @bitCast(PowerpcMapFlags{ .anonymous = true });
};

/// mmap() flags for whichever architecture is actually being built. See
/// each private per-arch type above for exactly which bits diverge.
pub const MapFlags = switch (sysinfo.cpu.arch) {
    .x86_64 => X86_64MapFlags,
    .aarch64, .arm => GenericMapFlags,
    .powerpc => PowerpcMapFlags,
    else => @compileError("No mman ABI data for this architecture"),
};

// mremap() flags -- identical across all four architectures.
pub const MremapFlags = packed struct(u32) {
    /// Allow the kernel to relocate the mapping to a new address if it
    /// can't be resized in place.
    maymove: bool = false,
    /// Place the resized mapping at the exact address given (requires
    /// `maymove`), like `MapFlags.fixed`.
    fixed: bool = false,
    /// When moving a mapping, leave the old address range mapped as a
    /// fresh anonymous region instead of unmapping it.
    dontunmap: bool = false,
    /// padding/reserved, must be present for layout
    _align1: u29 = 0,
};

/// Overcommit modes (see /proc/sys/vm/overcommit_memory) -- a mutually
/// exclusive mode *selector*, not combinable bits, so this is an enum
/// rather than a packed struct. Identical across all four architectures.
pub const OvercommitMode = enum(u32) {
    /// Kernel heuristically decides whether to grant memory requests based
    /// on estimated available resources.
    guess = 0,
    /// Kernel always grants memory allocation requests, regardless of
    /// whether enough memory is actually available.
    always = 1,
    /// Kernel refuses allocations that would exceed the configured commit
    /// limit; overcommit is disabled.
    never = 2,
};

/// mlockall() flags -- x86_64/aarch64/arm share the generic 1/2/4 bit
/// positions; powerpc DIVERGES to 0x2000/0x4000/0x8000 (independently
/// defined, alongside its own `MapFlags.locked` neighborhood of bits).
const GenericMclFlags = packed struct(u32) {
    /// Lock all pages currently mapped into the process's address space.
    current: bool = false,
    /// Lock all pages mapped into the process's address space in the
    /// future as well.
    future: bool = false,
    /// With `current`/`future`, only lock pages once they're actually
    /// faulted in, rather than immediately.
    onfault: bool = false,
    /// padding/reserved, must be present for layout
    _align1: u29 = 0,
};

const PowerpcMclFlags = packed struct(u32) {
    /// padding/reserved, must be present for layout
    _align1: u13 = 0,
    /// Lock all pages currently mapped into the process's address space.
    current: bool = false,
    /// Lock all pages mapped into the process's address space in the
    /// future as well.
    future: bool = false,
    /// With `current`/`future`, only lock pages once they're actually
    /// faulted in, rather than immediately.
    onfault: bool = false,
    /// padding/reserved, must be present for layout
    _align2: u16 = 0,
};

/// mlockall() flags for whichever architecture is actually being built.
pub const MclFlags = switch (sysinfo.cpu.arch) {
    .x86_64, .aarch64, .arm => GenericMclFlags,
    .powerpc => PowerpcMclFlags,
    else => @compileError("No mman ABI data for this architecture"),
};

/// mlock2() flag -- a single bit with no siblings, so it stays a plain
/// constant rather than a one-field struct.
pub const MLOCK_ONFAULT: u32 = 0x01;

/// map_shadow_stack() flags. powerpc has no equivalent at all (no
/// `map_shadow_stack()` support upstream at this commit, since it never
/// includes the generic `asm-generic/mman.h` these come from) --
/// referencing `ShadowStackSetFlags` there is a compile error.
const GenericShadowStackSetFlags = packed struct(u32) {
    /// Write a restore token at the top of the newly allocated shadow
    /// stack.
    token: bool = false,
    /// Write a top-of-stack marker at the top of the newly allocated
    /// shadow stack.
    marker: bool = false,
    /// padding/reserved, must be present for layout
    _align1: u30 = 0,
};

pub const ShadowStackSetFlags = switch (sysinfo.cpu.arch) {
    .x86_64, .aarch64, .arm => GenericShadowStackSetFlags,
    else => @compileError("ShadowStackSetFlags does not exist on powerpc"),
};

/// msync() flags -- identical across all four architectures. `@"async"` and
/// `sync` are mutually exclusive per the man page (exactly one of the two
/// should be given); the struct doesn't enforce that any more than the raw
/// integer flags did, so a caller can still set both.
pub const MsFlags = packed struct(u32) {
    /// Schedule the mapping's dirty pages to be written back to the file,
    /// but return without waiting for the write to complete.
    async: bool = false,
    /// Invalidate other mappings of the same file so they observe the
    /// just-synced changes.
    invalidate: bool = false,
    /// Write the mapping's dirty pages back to the file and block until
    /// the write completes.
    sync: bool = false,
    /// padding/reserved, must be present for layout
    _align1: u29 = 0,
};

/// madvise() advice values -- mutually exclusive, not bitflags, so this is
/// an enum rather than a packed struct. Identical across all four
/// architectures.
pub const Madvise = enum(u32) {
    /// No special treatment; use the kernel's default readahead behavior.
    normal = 0,
    /// Expect page references in random order, so disable aggressive
    /// readahead.
    random = 1,
    /// Expect page references in sequential order, so allow aggressive
    /// readahead.
    sequential = 2,
    /// Expect these pages to be accessed soon; the kernel should prefetch
    /// them.
    willneed = 3,
    /// The application doesn't need these pages soon -- the kernel may
    /// free them and re-zero them on next access.
    dontneed = 4,
    /// The pages may be freed by the kernel under memory pressure, but
    /// keep their contents valid until then.
    free = 8,
    /// Free the underlying pages and resources for this range, as if
    /// punching a hole in the file.
    remove = 9,
    /// Exclude this range from the child process's address space after
    /// fork().
    dontfork = 10,
    /// Undo `.dontfork`, restoring normal inheritance of this range across
    /// fork().
    dofork = 11,
    /// Allow the kernel's KSM feature to merge identical pages in this
    /// range to save memory.
    mergeable = 12,
    /// Opt this range back out of KSM page merging.
    unmergeable = 13,
    /// Hint that this range is a good candidate for transparent huge
    /// pages.
    hugepage = 14,
    /// Hint that this range should not be backed by transparent huge
    /// pages.
    nohugepage = 15,
    /// Exclude this range from core dumps, overriding the coredump filter
    /// bits.
    dontdump = 16,
    /// Undo `.dontdump`, including this range in core dumps again.
    dodump = 17,
    /// Zero this range in the child after fork(), rather than inheriting
    /// its contents.
    wipeonfork = 18,
    /// Undo `.wipeonfork`, restoring normal content inheritance across
    /// fork().
    keeponfork = 19,
    /// Deactivate these pages, making them more likely to be reclaimed
    /// soon without discarding them outright.
    cold = 20,
    /// Proactively reclaim (page out) these pages now.
    pageout = 21,
    /// Prefault the page tables for this range for reading, without
    /// triggering copy-on-write.
    populate_read = 22,
    /// Prefault the page tables for this range for writing, triggering
    /// copy-on-write where needed.
    populate_write = 23,
    /// Like `.dontneed`, but also drop pages that are currently
    /// mlock()ed.
    dontneed_locked = 24,
    /// Synchronously attempt to collapse this range into transparent huge
    /// pages.
    collapse = 25,
    /// Simulate a hardware memory error on this page, for testing error
    /// handling.
    hwpoison = 100,
    /// Simulate soft-offlining this page (as if it were failing), for
    /// testing.
    soft_offline = 101,
    /// Install guard pages over this range that raise a fatal signal on
    /// any access.
    guard_install = 102,
    /// Remove previously installed guard pages from this range.
    guard_remove = 103,
};

// PKEY_* -- pkey_mprotect()/pkey_alloc() flags.

/// x86_64/arm: only the two generic bits, no `execute`/`read` overrides.
const GenericPkeyDisableFlags = packed struct(u32) {
    /// Disable all access (read and write) for memory tagged with this
    /// protection key.
    access: bool = false,
    /// Disable write access for memory tagged with this protection key.
    write: bool = false,
    /// padding/reserved, must be present for layout
    _align1: u30 = 0,

    /// No access restrictions are applied by this protection key.
    pub const PKEY_UNRESTRICTED: GenericPkeyDisableFlags = 0;
};

const Aarch64PkeyDisableFlags = packed struct(u32) {
    /// Disable all access (read and write) for memory tagged with this
    /// protection key.
    access: bool = false,
    /// Disable write access for memory tagged with this protection key.
    write: bool = false,
    /// aarch64-only: disable execute access for memory tagged with this
    /// protection key (arm64-specific override; no generic equivalent).
    execute: bool = false,
    /// aarch64-only: disable read access for memory tagged with this
    /// protection key (arm64-specific override; powerpc has no
    /// equivalent).
    read: bool = false,
    /// padding/reserved, must be present for layout
    _align1: u28 = 0,

    /// No access restrictions are applied by this protection key.
    pub const PKEY_UNRESTRICTED: GenericPkeyDisableFlags = 0;
};

const PowerpcPkeyDisableFlags = packed struct(u32) {
    /// Disable all access (read and write) for memory tagged with this
    /// protection key.
    access: bool = false,
    /// Disable write access for memory tagged with this protection key.
    write: bool = false,
    /// powerpc-only: disable execute access for memory tagged with this
    /// protection key (powerpc-specific override; no generic equivalent,
    /// and unlike aarch64, powerpc has no `read` override at all).
    execute: bool = false,
    /// padding/reserved, must be present for layout
    _align1: u29 = 0,

    /// No access restrictions are applied by this protection key.
    pub const PKEY_UNRESTRICTED: GenericPkeyDisableFlags = 0;
};

/// pkey_mprotect()/pkey_alloc() disable flags for whichever architecture is
/// actually being built. aarch64 and powerpc each override part of the
/// generic set with their own extra bits (see the private per-arch types
/// above); x86_64/arm use the plain generic two bits only.
pub const PkeyDisableFlags = switch (sysinfo.cpu.arch) {
    .x86_64, .arm => GenericPkeyDisableFlags,
    .aarch64 => Aarch64PkeyDisableFlags,
    .powerpc => PowerpcPkeyDisableFlags,
    else => @compileError("No mman ABI data for this architecture"),
};

/// Bitmask of all valid `PkeyDisableFlags` bits on this architecture --
/// computed from the type itself (every real field set to `true`) rather
/// than a hand-maintained magic number, so it can't drift out of sync with
/// the struct above.
pub const PKEY_ACCESS_MASK: u32 = switch (sysinfo.cpu.arch) {
    .x86_64, .arm => @bitCast(PkeyDisableFlags{ .access = true, .write = true }),
    .aarch64 => @bitCast(PkeyDisableFlags{
        .access = true,
        .write = true,
        .execute = true,
        .read = true,
    }),
    .powerpc => @bitCast(PkeyDisableFlags{ .access = true, .write = true, .execute = true }),
    else => @compileError("No mman ABI data for this architecture"),
};
