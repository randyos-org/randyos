//! Paging (4-level)
//! 2024 by Samuel Fiedler

const std = @import("std");
const log = std.log.scoped(.arch_paging);

const common = @import("common");
const pages = common.pages;
const registers = @import("registers.zig");

/// `std.mem.Alignment` for a single page-table-sized (one page) allocation --
/// every page table in this file is exactly `pages.page_size` bytes, aligned
/// to the same, so this is just `pages.page_shift` in the enum form
/// `allocWithOptions` wants.
const page_table_alignment: std.mem.Alignment = @enumFromInt(pages.page_shift);

/// Size of the physical region one L2 (PDE) "large" page covers: 512 (entries
/// per table level) 4KiB pages, i.e. 2MiB.
const l2_large_page_size: usize = pages.page_size * 512;

/// Paging Level
pub const Level = enum(u8) {
    L1,
    L2,
    L3,
    L4,
};

/// Page Size
pub const PageSize = enum(u1) {
    small = 0,
    large = 1,
};

/// Page Map Level N Entry
/// From the Intel SDM Volume 3A (December 2023), Chapter 4.5.4
/// One layout is shared across all 4 levels (PML4E/PDPTE/PDE/PTE); fields
/// like `ps`, `d`, `g`, `pk` only take their "mapping a page" meaning at a
/// leaf entry (always true at L1, and at L2/L3 when `ps == .large`) --
/// elsewhere they're ignored/reserved, per the per-field docs below.
pub fn PMLNE(level: Level) type {
    return packed struct(u64) {
        const PME = @This();
        /// Present
        /// Must be 1 to reference a page-directory-pointer table.
        p: bool,
        /// Read/write
        /// If 0, writes may not be allowed to the 512GB region controlled by this entry.
        r_w: bool,
        /// User/supervisor
        /// If 0, user-mode accesses are not allowed to the 512GB region controlled by this entry.
        u_s: bool,
        /// Page-level write-through
        /// Indirectly determines the memory type used to access the page-directory-pointer table referenced by this entry.
        pwt: bool,
        /// Page-level cache disable
        /// Indirectly determines the memory type used to access the page-directory-pointer table referenced by this entry.
        pcd: bool,
        /// Accessed
        /// Indicates whether this entry has been used for linear-address translation.
        a: bool,
        /// Dirty when mapping a page, Ignored when referencing a table
        /// Indicates whether software has written to the page referenced by this entry.
        d: bool,
        /// Page Size
        /// Must be 1 when mapping a page, must be 0 when referencing a table.
        /// At L1 (PTE) this bit is actually PAT (page attribute table
        /// selector), not a size choice -- a PTE always maps a single 4KB
        /// page, so there's nothing to select here; left at the default
        /// (PAT index 0) throughout this codebase.
        ps: PageSize = .small,
        /// Global when mapping a page, Ignored when referencing a table
        /// If GR4.PGE = 1, determines whether the translation is global, ignored otherwise.
        g: bool,
        /// Ignored
        ign1: u2,
        /// For ordinary paging, ignored; for HLAT paging, restart
        /// (if 1, linear-address translation is restarted with ordinary paging)
        r: bool,
        /// Physical address (4KB aligned) of whatever this entry points at:
        /// the next-level table in the common case, or the mapped page
        /// itself at a leaf entry (always at L1; at L2/L3 when `ps ==
        /// .large`). See `getAddress`/`setAddress` for the per-level shift.
        addr: u40,
        /// Ignored
        ign2: u7,
        /// Protection key when mapping a page, Ignored when referencing a table
        pk: u4,
        /// If IA32_EFER.NXE = 1, execute-disable; otherwise reserved (must be 0)
        /// (if 1, instruction fetches are not allowed from the 512GB region controlled by this entry)
        xd: bool,

        const impls: type = switch (level) {
            .L1 => struct {
                /// Get the L1 address
                fn getAddr(self: *const PME) usize {
                    return self.addr << pages.page_shift;
                }
                /// Set the L1 address
                fn setAddr(self: *PME, addr: usize) void {
                    self.addr = @truncate(addr >> pages.page_shift);
                }
            },
            .L2 => struct {
                /// Get the L2 address
                fn getAddr(self: *const PME) usize {
                    return (self.addr >> 9) << 21;
                }
                /// Set the L2 address
                fn setAddr(self: *PME, addr: usize) void {
                    self.addr = @truncate((addr >> 21) << 9);
                }
            },
            .L3 => struct {
                /// Get the L3 address
                fn getAddr(self: *const PME) usize {
                    // `addr` always stores bits [51:12] of a 4KiB-aligned
                    // base. For a 1GiB (L3 large) page, the physical base is
                    // in bits [51:30], so we drop the low 18 bits of `addr`
                    // (which correspond to PA bits [29:12]) before restoring
                    // the final << 30 alignment.
                    return (self.addr >> 18) << 30;
                }
                /// Set the L3 address
                fn setAddr(self: *PME, addr: usize) void {
                    // Inverse of getAddr: keep PA bits [51:30], place them
                    // into descriptor bits [51:30], and leave low bits clear.
                    self.addr = @truncate((addr >> 30) << 18);
                }
            },
            .L4 => struct {
                /// Get the L4 address
                fn getAddr(self: *const PME) usize {
                    return self.addr;
                }
                /// Set the L4 address
                fn setAddr(self: *PME, addr: usize) void {
                    self.addr = addr;
                }
            },
        };

        pub const getAddress = impls.getAddr;
        pub const setAddress = impls.setAddr;

        /// Get the table referenced by this entry
        fn get(self: *const PME) *PMLNT(@enumFromInt(@intFromEnum(level) - 1)) {
            return @ptrFromInt(self.addr << pages.page_shift);
        }
    };
}

/// Page Map Level N Table
pub fn PMLNT(level: Level) type {
    return [512]PMLNE(level);
}

/// A virtual address split into indices
pub const Indices = struct {
    /// Offset
    offset: u12,
    /// L1 address
    l1: u9,
    /// L2 address
    l2: u9,
    /// L3 address
    l3: u9,
    /// L4 address
    l4: u9,

    /// Indices from virtual address
    pub fn fromVirt(virt: usize) Indices {
        return .{
            .offset = @truncate(virt),
            .l1 = @truncate(virt >> pages.page_shift),
            .l2 = @truncate(virt >> 21),
            .l3 = @truncate(virt >> 30),
            .l4 = @truncate(virt >> 39),
        };
    }

    /// Virtual address from indices
    pub fn toVirt(self: *const Indices) usize {
        var addr: usize = 0;
        addr += self.offset;
        addr += @as(usize, self.l1) << pages.page_shift;
        addr += @as(usize, self.l2) << 21;
        addr += @as(usize, self.l3) << 30;
        addr += @as(usize, self.l4) << 39;
        return addr;
    }
};

/// Print a set of addresses summarized
pub fn summarizeAddresses(comptime level: Level, addresses: [512]?usize) void {
    const log_local = std.log.scoped(.arch_paging_info);
    var first_known_existence: usize = 0;
    // repeat over all addresses (from page table)
    for (addresses, 0..) |value, i| {
        if (i > 0) {
            if (value == null and addresses[i - 1] != null and addresses[first_known_existence] != null) {
                // if current and prev value is null and first known existence since last print, print out
                log_local.debug("{s}{} {s} pages from 0x{x:0>16} to 0x{x:0>16}", .{
                    @as([2 * (4 - @intFromEnum(level))]u8, @splat("  ")),
                    i - first_known_existence,
                    @tagName(level),
                    addresses[first_known_existence].?,
                    addresses[i - 1].?,
                });
            } else if (value != null and addresses[i - 1] == null) {
                // if current value isn't null but prev value is null, set first known existence
                first_known_existence = i;
            }
        }
    }
    // print last address "chunk"
    if (addresses[511] != null and addresses[first_known_existence] != null) {
        log_local.debug("{s}{} {s} pages from 0x{x:0>16} to 0x{x:0>16}", .{
            @as([2 * (4 - @intFromEnum(level))]u8, @splat("  ")),
            512 - first_known_existence,
            @tagName(level),
            addresses[first_known_existence].?,
            addresses[511].?,
        });
    }
}

/// Print a page table tree
pub fn printPTT(comptime level: Level, page_table: PMLNT(level)) void {
    const log_local = std.log.scoped(.arch_paging_info);
    var page_table_addresses: [512]?usize = @splat(null);
    for (page_table, 0..) |page_entry, i| {
        if (page_entry.p) {
            if (page_entry.ps == .large) {
                switch (level) {
                    .L1, .L4 => log_local.err("{s}{}. {s} pages are not allowed to have PS flag set!", .{
                        @as([2 * (4 - @intFromEnum(level))]u8, @splat("  ")),
                        i,
                        @tagName(level),
                    }),
                    .L2, .L3 => page_table_addresses[i] = page_entry.getAddress(),
                }
            } else {
                if (level != .L1) {
                    log_local.debug("{s}{}. {s} table at 0x{x:0>16}", .{
                        @as([2 * (4 - @intFromEnum(level))]u8, @splat("  ")),
                        i,
                        @tagName(@as(Level, @enumFromInt(@intFromEnum(level) - 1))),
                        page_entry.getAddress(),
                    });
                    printPTT(@enumFromInt(@intFromEnum(level) - 1), page_entry.get());
                } else {
                    page_table_addresses[i] = page_entry.getAddress();
                }
            }
        }
    }
    summarizeAddresses(level, page_table_addresses);
}

/// Map Page Options
pub const MapPageOptions = struct {
    /// Writable
    w: bool,
    /// Executable
    x: bool,
    /// User
    u: bool,
    /// Global
    g: bool,
    /// Cacheable (write-back). Only regular RAM should ever set this to
    /// `false` (uncacheable) -- e.g. MMIO registers, where a cached stale
    /// read/write would be wrong, not just slow.
    cacheable: bool = true,
};

/// The PML4 index the canonical-address split falls on: virtual addresses
/// with bit 47 set (indices 256-511, i.e. >= 0xffff800000000000) are the
/// "upper half"; below that is the "lower half". See `AddressSpace.create`.
const kernel_half_start_index: usize = 256;

/// Virtual address `AddressSpace.mapKernel` additionally maps the kernel
/// image to: the canonical x86_64 "negative 2GiB" higher-half base. The
/// linker (`kernel.ld`) still links/loads the image at its low physical
/// address (`KERNEL_PHYS_START`, 1MiB) -- this is a second, higher-half alias
/// of those same physical pages, not where the linker itself placed them.
const kernel_higher_half_addr: usize = 0xffffffff80000000;

/// A single address space: one process's (or the kernel's own) view of
/// memory, rooted at its own PML4.
pub const AddressSpace = struct {
    pml4: *align(pages.page_size) PMLNT(.L4),

    /// Create a new address space for a userspace process. Its lower half
    /// (user space, indices 0-255) starts completely empty; its upper half
    /// (kernel space, indices 256-511) points at the *exact same*
    /// next-level tables as the kernel's own address space -- not copies --
    /// so this process sees every kernel mapping, including ones made after
    /// this call, without ever needing to keep its own copy in sync.
    /// Without this, switching CR3 into a fresh process on a syscall/
    /// interrupt would immediately fault trying to fetch the handler that's
    /// supposed to be running.
    pub fn create(allocator: std.mem.Allocator) !AddressSpace {
        const kernel_pml4 = kernelAddressSpace().pml4;
        const new_pml4: *align(pages.page_size) PMLNT(.L4) = (try allocator.allocWithOptions(PMLNE(.L4), 512, page_table_alignment, null))[0..512];
        for (new_pml4[0..kernel_half_start_index]) |*entry| entry.p = false;
        @memcpy(new_pml4[kernel_half_start_index..512], kernel_pml4[kernel_half_start_index..512]);
        return .{ .pml4 = new_pml4 };
    }

    /// Make this the active address space (loads CR3).
    pub fn activate(self: *const AddressSpace) void {
        const cr3 = registers.CR3{
            .pwt = false,
            .pcd = false,
            .addr = @truncate(@intFromPtr(self.pml4) >> pages.page_shift),
        };
        cr3.set();
    }

    /// Translate a virtual address to a physical address
    pub fn physFromVirt(self: *const AddressSpace, virt: usize) ?usize {
        // indices, level (mutable in loop) and current page table (will be set in loop)
        const indices: Indices = Indices.fromVirt(virt);
        var level: Level = .L4;
        var current_page_table: *PMLNT(.L4) = self.pml4;
        // repeat the following for L4, L3 and L2 indices
        inline for ([_]usize{ indices.l4, indices.l3, indices.l2 }) |i| {
            // get entry
            const entry = current_page_table[i];
            if (entry.p) {
                if (entry.ps == .large) {
                    // error or return for PS flag
                    //
                    // The shifts below are inlined copies of PMLNE(.L2/.L3)'s
                    // getAddress(), not calls to it: `current_page_table` keeps
                    // the single static type `*PMLNT(.L4)` for its whole
                    // lifetime here (each reassignment below goes through
                    // `@ptrCast`), so `entry`'s static type is always
                    // `PMLNE(.L4)` regardless of `level` -- calling
                    // `entry.getAddress()` would always resolve to L4's (shift-less)
                    // implementation. `level` (tracked separately, correctly) is
                    // what lets this switch pick the right shift by hand instead.
                    switch (level) {
                        .L1 => @panic("PS flag set on L1 page"),
                        .L2 => {
                            return ((entry.addr >> 9) << 21) + (@as(usize, indices.l1) << pages.page_shift) + indices.offset;
                        },
                        .L3 => {
                            return ((entry.addr >> 18) << 30) + (@as(usize, indices.l2) << 21) + (@as(usize, indices.l1) << pages.page_shift) + indices.offset;
                        },
                        .L4 => @panic("PS flag set on L4 page"),
                    }
                } else {
                    current_page_table = @ptrCast(entry.get());
                    level = @enumFromInt(@intFromEnum(level) - 1);
                }
            } else {
                return null;
            }
        }
        // return L1 page
        if (current_page_table[indices.l1].p) {
            return (current_page_table[indices.l1].addr << pages.page_shift) + indices.offset;
        } else {
            return null;
        }
    }

    /// Split a large `entry` (found at `current_page_table[i]`) into a page
    /// table at `level` (one level below the entry itself), replicating the
    /// original mapping's physical range and permissions at that finer
    /// granularity. Without this, every address the large entry used to
    /// cover -- other than whichever one the caller actually wants to
    /// change -- would silently become unmapped instead of keeping its
    /// prior mapping.
    ///
    /// Returns the newly allocated table, already installed into
    /// `current_page_table[i]`; that slot itself is left maximally
    /// permissive (matching how every other intermediate table entry in
    /// this file is built) since the returned table's own entries are what
    /// now actually carry the original entry's permissions.
    fn splitLargeEntry(
        self: *const AddressSpace,
        allocator: std.mem.Allocator,
        current_page_table: *PMLNT(.L4),
        i: usize,
        entry: PMLNE(.L4),
        comptime level: Level,
    ) std.mem.Allocator.Error!*align(pages.page_size) PMLNT(level) {
        // Decoded/re-encoded by hand for the same reason physFromVirt does
        // its own shifts above: `entry`'s static type is always PMLNE(.L4)
        // here.
        const orig_phys_base: usize = switch (level) {
            .L2 => (@as(usize, entry.addr) >> 18) << 30, // splitting a 1GiB PDPTE
            .L1 => (@as(usize, entry.addr) >> 9) << 21, // splitting a 2MiB PDE
            else => unreachable, // only L2/L3 entries can ever have PS=1
        };
        const sub_page_size: usize = switch (level) {
            .L2 => l2_large_page_size,
            .L1 => pages.page_size,
            else => unreachable,
        };

        log.debug("Splitting large page into {s} table at index {} of current page table", .{ @tagName(level), i });
        const tbl_ptr: *align(pages.page_size) PMLNT(level) = (try allocator.allocWithOptions(PMLNE(level), 512, page_table_alignment, null))[0..512];
        for (tbl_ptr, 0..) |*ent, j| {
            const sub_phys = orig_phys_base + j * sub_page_size;
            ent.* = .{
                .p = true,
                .r_w = entry.r_w,
                .u_s = entry.u_s,
                .pwt = entry.pwt,
                .pcd = entry.pcd,
                .ps = if (level == .L2) .large else .small,
                .xd = entry.xd,
                .a = false,
                .g = entry.g,
                .r = false,
                .d = false,
                .pk = entry.pk,
                .ign1 = 0,
                .ign2 = 0,
                .addr = switch (level) {
                    .L2 => @truncate((sub_phys >> 21) << 9),
                    .L1 => @truncate(sub_phys >> pages.page_shift),
                    else => unreachable,
                },
            };
        }
        current_page_table[i] = .{
            .p = true,
            .r_w = true,
            .u_s = true,
            .pwt = false,
            .pcd = false,
            .ps = .small,
            .xd = false,
            .a = false,
            .g = false,
            .r = false,
            .d = false,
            .pk = 0,
            .ign1 = 0,
            .ign2 = 0,
            .addr = @truncate(self.physFromVirt(@intFromPtr(tbl_ptr)).? >> pages.page_shift),
        };
        return tbl_ptr;
    }

    /// Replace a (large) page with a page table, preserving its existing
    /// mapping (see `splitLargeEntry`) -- a way to force a virtual address
    /// down to 4K-table granularity ahead of time, e.g. before a batch of
    /// `mapPage` calls that will each want to individually change small
    /// parts of a region that used to be one large page.
    pub fn replacePageWithTable(self: *AddressSpace, allocator: std.mem.Allocator, virt: usize) error{ WrongData, OutOfMemory }!void {
        var current_page_table: *PMLNT(.L4) = self.pml4;
        const indices: Indices = Indices.fromVirt(virt);
        comptime var level: Level = .L4;

        inline for ([_]usize{ indices.l4, indices.l3, indices.l2 }) |i| {
            level = @enumFromInt(@intFromEnum(level) - 1);
            const entry = current_page_table[i];
            if (entry.p) {
                if (entry.ps == .large) {
                    current_page_table = @ptrCast(try self.splitLargeEntry(allocator, current_page_table, i, entry, level));
                } else {
                    current_page_table = @ptrCast(entry.get());
                }
            } else {
                log.err("Calling this function wouldn't have been necessary!", .{});
                return error.WrongData;
            }
        }
    }

    /// Map a page
    pub fn mapPage(
        self: *AddressSpace,
        allocator: ?std.mem.Allocator,
        virt: usize,
        phys: usize,
        user: bool,
        options: MapPageOptions,
    ) error{ OutOfMemory, AllocatorRequired }!void {
        log.debug("Mapping virtual address 0x{x:0>16} to physical address 0x{x:0>16}", .{ virt, phys });
        var current_page_table: *PMLNT(.L4) = self.pml4;
        const indices: Indices = Indices.fromVirt(virt);
        comptime var level: Level = .L4;

        inline for ([_]usize{ indices.l4, indices.l3, indices.l2 }) |i| {
            level = @enumFromInt(@intFromEnum(level) - 1);
            const entry = current_page_table[i];
            if (entry.p) {
                if (entry.ps == .large) {
                    // Splitting (rather than erroring) means mapping a
                    // specific 4K page inside a region a huge page used to
                    // cover just works, instead of requiring the caller to
                    // already know to call replacePageWithTable first.
                    const alloc = allocator orelse return error.AllocatorRequired;
                    current_page_table = @ptrCast(try self.splitLargeEntry(alloc, current_page_table, i, entry, level));
                } else {
                    current_page_table = @ptrCast(entry.get());
                }
            } else {
                const alloc = allocator orelse return error.AllocatorRequired;
                log.debug("Allocating {s} table at index {} of current page table", .{ @tagName(level), i });
                // alignment of 12 is page-aligned
                const tbl_ptr: *PMLNT(level) = &((try alloc.allocWithOptions(PMLNT(level), 1, page_table_alignment, null))[0]);
                for (tbl_ptr) |*ent| {
                    ent.p = false;
                }
                current_page_table[i] = .{
                    .p = true,
                    .r_w = true,
                    .u_s = !user,
                    .pwt = false,
                    .pcd = false,
                    .ps = .small,
                    .xd = false,
                    .a = false,
                    .g = false,
                    .r = false,
                    .d = false,
                    .pk = 0,
                    .ign1 = 0,
                    .ign2 = 0,
                    .addr = @truncate(self.physFromVirt(@intFromPtr(tbl_ptr)).? >> pages.page_shift),
                };
                // descend into the table we just allocated, same as the
                // "entry already present" branch does via entry.get() --
                // otherwise the next iteration re-indexes the parent table
                // instead of walking down the hierarchy.
                current_page_table = @ptrCast(tbl_ptr);
            }
        }

        const was_present = current_page_table[indices.l1].p;

        current_page_table[indices.l1] = .{
            .p = true,
            .r_w = options.w,
            .u_s = !user,
            .pwt = false,
            .pcd = !options.cacheable,
            .ps = .small,
            .g = options.g,
            .xd = !options.x,
            .addr = @truncate(phys >> pages.page_shift),
            .a = false,
            .d = false,
            .ign1 = 0,
            .ign2 = 0,
            .r = false,
            .pk = 0,
        };

        if (was_present) {
            log.debug("Mapping was present, invalidating the TLB...", .{});
            registers.invlpg(virt);
        } else {
            log.debug("Mapping was not present, no need to invalidate the TLB", .{});
        }
    }

    /// Change a page
    pub fn changePage(self: *AddressSpace, virt: usize, options: MapPageOptions) !void {
        const phys_opt = self.physFromVirt(virt);
        if (phys_opt) |phys_addr| {
            try self.mapPage(null, virt, phys_addr, false, options);
        }
    }

    /// Unmap a page.
    ///
    /// This clears the mapping and invalidates the TLB, but does *not* free
    /// the underlying physical page (via some allocator) or reclaim a
    /// page-table page that becomes fully empty as a result -- both need an
    /// ownership model (who's allowed to free this physical page? is this
    /// table shared with another mapping?) that doesn't exist yet. Until
    /// then, callers are responsible for knowing whether the unmapped page
    /// should also be freed.
    pub fn unmapPage(self: *AddressSpace, allocator: ?std.mem.Allocator, virt: usize) !void {
        log.debug("Unmapping virtual address 0x{x:0>16}", .{virt});
        var current_page_table: *PMLNT(.L4) = self.pml4;
        const indices: Indices = Indices.fromVirt(virt);
        comptime var level: Level = .L4;

        inline for ([_]usize{ indices.l4, indices.l3, indices.l2 }) |i| {
            level = @enumFromInt(@intFromEnum(level) - 1);
            const entry = current_page_table[i];
            if (entry.p) {
                if (entry.ps == .large) {
                    const alloc = allocator orelse return error.AllocatorRequired;
                    current_page_table = @ptrCast(try self.splitLargeEntry(alloc, current_page_table, i, entry, level));
                } else {
                    current_page_table = @ptrCast(entry.get());
                }
            } else {
                log.err("Address 0x{x:0>16} isn't mapped", .{virt});
                return error.NotMapped;
            }
        }
        current_page_table[indices.l1].p = false;
        registers.invlpg(virt);
    }

    /// Map the kernel
    pub fn mapKernel(self: *AddressSpace, allocator: std.mem.Allocator, kernel_phys_addr: usize, kernel_page_size: usize) void {
        // TODO: actually implement mapping the kernel -- this maps the
        // entire image (code/rodata/data/bss alike) with one permission
        // set, so `.w` has to stay `true` (the kernel does need to write
        // its own globals) until this distinguishes sections and can map
        // .text/.rodata read-only separately from .data/.bss.
        log.debug("Kernel Physical Start: 0x{x:0>16}", .{kernel_phys_addr});
        log.debug("Kernel page size: {} pages", .{kernel_page_size});
        for (0..kernel_page_size) |i| {
            self.mapPage(allocator, kernel_higher_half_addr + i * pages.page_size, kernel_phys_addr + i * pages.page_size, false, .{
                .w = true,
                .x = true,
                .u = false,
                .g = false,
            }) catch {
                @panic("Mapping the kernel failed!");
            };
        }
        log.debug("Finished mapping the kernel!", .{});
    }
};

/// The kernel's own address space. `null` until `init` runs.
var kernel_address_space_storage: ?AddressSpace = null;

/// The kernel's own address space, once `init` has run. Every new
/// `AddressSpace.create`d process shares this one's upper half.
pub fn kernelAddressSpace() *AddressSpace {
    return if (kernel_address_space_storage) |*as| as else @panic("paging.init() must run before any page table operation");
}

/// Print the (already firmware-neutral) boot memory map, collapsing
/// adjacent regions of the same kind into a single log line.
pub fn printMemMap(regions: []const common.boot_info.MemoryRegion) void {
    log.debug("Boot Memory Map Contents:", .{});
    if (regions.len == 0) return;
    var run_start = regions[0].phys_start;
    var run_kind = regions[0].kind;
    var pg_count: usize = 0;
    for (regions, 0..) |region, i| {
        pg_count += region.page_count;
        const next_kind = if (i + 1 < regions.len) regions[i + 1].kind else null;
        if (next_kind != run_kind) {
            log.debug("  P: 0x{x}-0x{x} PG: {} T: {s}", .{
                run_start,
                region.phys_start + region.page_count * pages.page_size,
                pg_count,
                @tagName(run_kind),
            });
            if (i + 1 < regions.len) {
                run_start = regions[i + 1].phys_start;
                run_kind = regions[i + 1].kind;
            }
            pg_count = 0;
        }
    }
}

/// Initialize Paging
pub fn init(
    allocator: std.mem.Allocator,
    memory_map: []const common.boot_info.MemoryRegion,
    kernel_physical_address: usize,
    kernel_page_size: usize,
) void {
    const old_pml4: *PMLNT(.L4) = @ptrFromInt(registers.CR3.get().addr << pages.page_shift);
    log.info("Paging initialization...", .{});
    printMemMap(memory_map);
    log.debug("Allocating a Page Map Level 4 Table", .{});
    const pml4: *align(pages.page_size) PMLNT(.L4) = (allocator.allocWithOptions(PMLNE(.L4), 512, page_table_alignment, null) catch @panic("OOM for page map L4!"))[0..512];
    // Start from a copy of the firmware's existing mappings so everything
    // we're currently running from (stack, GDT/IDT, page allocator arena,
    // etc.) stays mapped once we switch CR3 to this table -- the firmware's
    // own PML4 isn't writable, which is why we can't just keep mutating it
    // in place.
    pml4.* = old_pml4.*;
    kernel_address_space_storage = .{ .pml4 = pml4 };
    const kas = kernelAddressSpace();
    kas.mapKernel(allocator, kernel_physical_address, kernel_page_size);
    kas.activate();
    log.info("Paging initialization successful!", .{});
}
