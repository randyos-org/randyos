//! Linux mmap()/mprotect()/mlock()/madvise() ABI constants for arm
//! (32-bit EABI).
//!
//! Sourced from the Linux kernel source tree:
//!   - `include/uapi/asm-generic/mman-common.h` (PROT_*, MAP_TYPE/FIXED/
//!     ANONYMOUS/POPULATE/NONBLOCK/STACK/HUGETLB/SYNC/FIXED_NOREPLACE/
//!     UNINITIALIZED, MLOCK_ONFAULT, MS_*, MADV_*, MAP_FILE, PKEY_*)
//!   - `include/uapi/linux/mman.h` (MAP_SHARED/PRIVATE/SHARED_VALIDATE/
//!     DROPPABLE, MREMAP_*, OVERCOMMIT_*)
//!   - `include/uapi/asm-generic/mman.h` (MAP_GROWSDOWN/DENYWRITE/EXECUTABLE/
//!     LOCKED/NORESERVE, MCL_*, SHADOW_STACK_SET_*) -- arm includes this file
//!     unmodified via `arch/arm/include/uapi/asm/mman.h`
//!   - `arch/arm/include/uapi/asm/mman.h` -- confirmed to be a pure
//!     passthrough: its only content beyond the asm-generic/mman.h include is
//!     an `arch_mmap_check(addr, len, flags)` macro (an mmap address-range
//!     sanity check used internally by the kernel's mmap implementation),
//!     which is not a flag constant and has no ABI-visible value, so it is
//!     out of scope here. arm defines **no** new PROT_*/MAP_*/MCL_*/PKEY_*
//!     values of its own.
//! torvalds/linux @ 8cdeaa50eae8dad34885515f62559ee83e7e8dda (kernel version
//! 7.2.0-rc2), by fetching each file directly and mechanically extracting
//! values -- not transcribed by hand. Re-derive from those same files if
//! this ever looks stale; do not hand-edit values here.
//!
//! Flattened: every value below is exactly the generic asm-generic value --
//! arm adds nothing. Contrast with x86_64 (adds MAP_32BIT/MAP_ABOVE4G),
//! aarch64 (adds PROT_BTI/PROT_MTE, overrides PKEY_*), and powerpc (skips
//! the generic asm-generic/mman.h include entirely and diverges heavily).
//!
//! MADV_* values are mutually-exclusive integer arguments, not bitflags, but
//! are kept as plain `u32` constants here (not an enum) for consistency with
//! the other flag groups in this file and across the four per-arch mman
//! files.
//!
//! Not wired to any dispatcher -- this is a reference-value listing only.

// PROT_* -- mmap()/mprotect() protection flags.
/// The page may not be accessed at all -- no read, write, or execute.
pub const PROT_NONE: u32 = 0x0;
/// The page may be read.
pub const PROT_READ: u32 = 0x1;
/// The page may be written.
pub const PROT_WRITE: u32 = 0x2;
/// The page may be executed as code.
pub const PROT_EXEC: u32 = 0x4;
/// The page may be used for atomic operations (rarely used outside a few
/// architectures' historical semaphore support).
pub const PROT_SEM: u32 = 0x8;
// Bits 0x10 and 0x20 are reserved for arch-specific use in the generic
// header; arm does not define anything there (contrast aarch64's
// PROT_BTI/PROT_MTE and powerpc's PROT_SAO, which use those same bits).
/// mprotect() flag: also extend the protection change to the rest of a
/// downward-growing (stack-like) mapping.
pub const PROT_GROWSDOWN: u32 = 0x01000000;
/// mprotect() flag: also extend the protection change to the rest of an
/// upward-growing mapping.
pub const PROT_GROWSUP: u32 = 0x02000000;

// MAP_* -- mmap() flags.
/// Changes to the mapping are shared with other processes mapping the same
/// file/region and are written back to the underlying file.
pub const MAP_SHARED: u32 = 0x01;
/// Changes to the mapping are private, copy-on-write, and never written
/// back to the underlying file.
pub const MAP_PRIVATE: u32 = 0x02;
/// Like MAP_SHARED, but the kernel rejects any unrecognized flag bits
/// instead of silently ignoring them.
pub const MAP_SHARED_VALIDATE: u32 = 0x03;
/// Bitmask isolating the mapping-type bits (MAP_SHARED/MAP_PRIVATE/
/// MAP_SHARED_VALIDATE) from the rest of the flags word.
pub const MAP_TYPE: u32 = 0x0f;
/// Interpret the given address exactly, unmapping any existing mapping that
/// overlaps it.
pub const MAP_FIXED: u32 = 0x10;
/// The mapping isn't backed by a file -- contents are zero-initialized.
pub const MAP_ANONYMOUS: u32 = 0x20;
/// Lets the kernel silently discard (zero) these pages under memory
/// pressure instead of writing them to swap.
pub const MAP_DROPPABLE: u32 = 0x08;
/// Used for stack-like mappings that automatically grow downward as
/// they're accessed.
pub const MAP_GROWSDOWN: u32 = 0x0100;
/// Historical flag, now ignored by the kernel; used to deny writes to the
/// mapped file while it was mapped (ETXTBSY semantics).
pub const MAP_DENYWRITE: u32 = 0x0800;
/// Historical flag, now ignored by the kernel; used to mark the mapping as
/// backing an executable file.
pub const MAP_EXECUTABLE: u32 = 0x1000;
/// Lock the mapped pages into physical memory, as if by mlock().
pub const MAP_LOCKED: u32 = 0x2000;
/// Don't reserve swap/commit space for this mapping up front; only fail
/// later if memory actually runs out.
pub const MAP_NORESERVE: u32 = 0x4000;
/// Prefault and populate page tables for the whole mapping immediately,
/// avoiding later minor page faults.
pub const MAP_POPULATE: u32 = 0x008000;
/// With MAP_POPULATE, only prefault pages already resident in memory;
/// don't block on I/O to bring pages in.
pub const MAP_NONBLOCK: u32 = 0x010000;
/// Hints the kernel to place the mapping at an address suitable for a
/// process/thread stack.
pub const MAP_STACK: u32 = 0x020000;
/// Back the mapping with huge pages instead of the normal page size.
pub const MAP_HUGETLB: u32 = 0x040000;
/// Ensure page faults on this (DAX) mapping are synchronous, so writes are
/// durable without a separate msync().
pub const MAP_SYNC: u32 = 0x080000;
/// Like MAP_FIXED, but fail instead of clobbering any existing mapping
/// that overlaps the requested address.
pub const MAP_FIXED_NOREPLACE: u32 = 0x100000;
/// On nommu systems, allow anonymous memory to be left uninitialized
/// instead of zero-filled, for performance.
pub const MAP_UNINITIALIZED: u32 = 0x4000000;
// Compatibility flag; always 0.
/// Historical compatibility flag with no effect; always zero.
pub const MAP_FILE: u32 = 0;

// mremap() flags.
/// Allow the kernel to relocate the mapping to a new address if it can't
/// be resized in place.
pub const MREMAP_MAYMOVE: u32 = 1;
/// Place the resized mapping at the exact address given (requires
/// MREMAP_MAYMOVE), like MAP_FIXED.
pub const MREMAP_FIXED: u32 = 2;
/// When moving a mapping, leave the old address range mapped as a fresh
/// anonymous region instead of unmapping it.
pub const MREMAP_DONTUNMAP: u32 = 4;

// Overcommit modes (see /proc/sys/vm/overcommit_memory).
/// Kernel heuristically decides whether to grant memory requests based on
/// estimated available resources.
pub const OVERCOMMIT_GUESS: u32 = 0;
/// Kernel always grants memory allocation requests, regardless of whether
/// enough memory is actually available.
pub const OVERCOMMIT_ALWAYS: u32 = 1;
/// Kernel refuses allocations that would exceed the configured commit
/// limit; overcommit is disabled.
pub const OVERCOMMIT_NEVER: u32 = 2;

// MCL_* -- mlockall() flags.
/// Lock all pages currently mapped into the process's address space.
pub const MCL_CURRENT: u32 = 1;
/// Lock all pages mapped into the process's address space in the future
/// as well.
pub const MCL_FUTURE: u32 = 2;
/// With MCL_CURRENT/MCL_FUTURE, only lock pages once they're actually
/// faulted in, rather than immediately.
pub const MCL_ONFAULT: u32 = 4;

// mlock2() flags.
/// Lock the pages only as they are faulted in, instead of prefaulting and
/// locking them immediately.
pub const MLOCK_ONFAULT: u32 = 0x01;

// SHADOW_STACK_* -- map_shadow_stack() flags.
/// Write a restore token at the top of the newly allocated shadow stack.
pub const SHADOW_STACK_SET_TOKEN: u32 = 1 << 0;
/// Write a top-of-stack marker at the top of the newly allocated shadow
/// stack.
pub const SHADOW_STACK_SET_MARKER: u32 = 1 << 1;

// MS_* -- msync() flags.
/// Schedule the mapping's dirty pages to be written back to the file, but
/// return without waiting for the write to complete.
pub const MS_ASYNC: u32 = 1;
/// Invalidate other mappings of the same file so they observe the
/// just-synced changes.
pub const MS_INVALIDATE: u32 = 2;
/// Write the mapping's dirty pages back to the file and block until the
/// write completes.
pub const MS_SYNC: u32 = 4;

// MADV_* -- madvise() advice values (mutually exclusive, not bitflags).
/// No special treatment; use the kernel's default readahead behavior.
pub const MADV_NORMAL: u32 = 0;
/// Expect page references in random order, so disable aggressive
/// readahead.
pub const MADV_RANDOM: u32 = 1;
/// Expect page references in sequential order, so allow aggressive
/// readahead.
pub const MADV_SEQUENTIAL: u32 = 2;
/// Expect these pages to be accessed soon; the kernel should prefetch
/// them.
pub const MADV_WILLNEED: u32 = 3;
/// The application doesn't need these pages soon -- the kernel may free
/// them and re-zero them on next access.
pub const MADV_DONTNEED: u32 = 4;
/// The pages may be freed by the kernel under memory pressure, but keep
/// their contents valid until then.
pub const MADV_FREE: u32 = 8;
/// Free the underlying pages and resources for this range, as if punching
/// a hole in the file.
pub const MADV_REMOVE: u32 = 9;
/// Exclude this range from the child process's address space after
/// fork().
pub const MADV_DONTFORK: u32 = 10;
/// Undo MADV_DONTFORK, restoring normal inheritance of this range across
/// fork().
pub const MADV_DOFORK: u32 = 11;
/// Allow the kernel's KSM feature to merge identical pages in this range
/// to save memory.
pub const MADV_MERGEABLE: u32 = 12;
/// Opt this range back out of KSM page merging.
pub const MADV_UNMERGEABLE: u32 = 13;
/// Hint that this range is a good candidate for transparent huge pages.
pub const MADV_HUGEPAGE: u32 = 14;
/// Hint that this range should not be backed by transparent huge pages.
pub const MADV_NOHUGEPAGE: u32 = 15;
/// Exclude this range from core dumps, overriding the coredump filter
/// bits.
pub const MADV_DONTDUMP: u32 = 16;
/// Undo MADV_DONTDUMP, including this range in core dumps again.
pub const MADV_DODUMP: u32 = 17;
/// Zero this range in the child after fork(), rather than inheriting its
/// contents.
pub const MADV_WIPEONFORK: u32 = 18;
/// Undo MADV_WIPEONFORK, restoring normal content inheritance across
/// fork().
pub const MADV_KEEPONFORK: u32 = 19;
/// Deactivate these pages, making them more likely to be reclaimed soon
/// without discarding them outright.
pub const MADV_COLD: u32 = 20;
/// Proactively reclaim (page out) these pages now.
pub const MADV_PAGEOUT: u32 = 21;
/// Prefault the page tables for this range for reading, without
/// triggering copy-on-write.
pub const MADV_POPULATE_READ: u32 = 22;
/// Prefault the page tables for this range for writing, triggering
/// copy-on-write where needed.
pub const MADV_POPULATE_WRITE: u32 = 23;
/// Like MADV_DONTNEED, but also drop pages that are currently mlock()ed.
pub const MADV_DONTNEED_LOCKED: u32 = 24;
/// Synchronously attempt to collapse this range into transparent huge
/// pages.
pub const MADV_COLLAPSE: u32 = 25;
/// Simulate a hardware memory error on this page, for testing error
/// handling.
pub const MADV_HWPOISON: u32 = 100;
/// Simulate soft-offlining this page (as if it were failing), for
/// testing.
pub const MADV_SOFT_OFFLINE: u32 = 101;
/// Install guard pages over this range that raise a fatal signal on any
/// access.
pub const MADV_GUARD_INSTALL: u32 = 102;
/// Remove previously installed guard pages from this range.
pub const MADV_GUARD_REMOVE: u32 = 103;

// PKEY_* -- pkey_mprotect()/pkey_alloc() flags. Generic (unmodified) values;
// contrast aarch64 and powerpc, which override PKEY_ACCESS_MASK and add
// their own PKEY_DISABLE_* bits.
/// No access restrictions are applied by this protection key.
pub const PKEY_UNRESTRICTED: u32 = 0x0;
/// Disable all access (read and write) for memory tagged with this
/// protection key.
pub const PKEY_DISABLE_ACCESS: u32 = 0x1;
/// Disable write access for memory tagged with this protection key.
pub const PKEY_DISABLE_WRITE: u32 = 0x2;
/// Bitmask of all valid PKEY_DISABLE_* bits on this architecture.
pub const PKEY_ACCESS_MASK: u32 = PKEY_DISABLE_ACCESS | PKEY_DISABLE_WRITE;
