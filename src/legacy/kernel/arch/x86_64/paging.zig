//! Paging (4-level)
//! 2024 by Samuel Fiedler

const std = @import("std");
const log = std.log.scoped(.arch_paging);

const common = @import("common");
const pages = common.pages;
const registers = @import("registers.zig");

/// alignment for a one-page page-table alloc (every table here is exactly
/// `pages.page_size`, so this is just `page_shift` as the enum form
/// `allocWithOptions` wants)
const page_table_alignment: std.mem.Alignment = @enumFromInt(pages.page_shift);

/// phys region one L2 large page covers: 512 * 4KiB = 2MiB
const l2_large_page_size: usize = pages.page_size * 512;

pub const Level = enum(u8) {
    L1,
    L2,
    L3,
    L4,
};

pub const PageSize = enum(u1) {
    small = 0,
    large = 1,
};

/// Page-map-level-N entry (Intel SDM Vol 3A, 4.5.4). One layout shared
/// across all 4 levels; leaf-only fields (`ps`, `d`, `g`, `pk`) apply only
/// at a leaf entry (always L1, or L2/L3 when `ps == .large`) -- otherwise
/// ignored/reserved.
pub fn PMLNE(level: Level) type {
    return packed struct(u64) {
        const PME = @This();
        /// must be 1 to reference this entry's table
        p: bool,
        /// if 0, writes disallowed in this entry's region
        r_w: bool,
        /// if 0, user-mode access disallowed in this entry's region
        u_s: bool,
        /// write-through; affects memory type of referenced table
        pwt: bool,
        /// cache disable; affects memory type of referenced table
        pcd: bool,
        /// set once used for translation
        a: bool,
        /// dirty (leaf) / ignored (table): set once written
        d: bool,
        /// 1 = leaf, 0 = table. At L1 this bit is actually PAT (a PTE
        /// always maps 4KB); left at default (PAT 0) throughout.
        ps: PageSize = .small,
        /// global (leaf, if CR4.PGE) / ignored (table)
        g: bool,
        /// Ignored
        ign1: u2,
        /// ordinary paging: ignored. HLAT: restart w/ ordinary paging if 1
        r: bool,
        /// 4KB-aligned phys addr of next table, or the mapped page itself
        /// at a leaf. See `getAddress`/`setAddress` for per-level shift.
        addr: u40,
        /// Ignored
        ign2: u7,
        /// protection key (leaf) / ignored (table)
        pk: u4,
        /// execute-disable if EFER.NXE=1, else reserved (must be 0)
        xd: bool,

        const impls: type = switch (level) {
            .L1 => struct {
                fn getAddr(self: *const PME) usize {
                    return self.addr << pages.page_shift;
                }
                fn setAddr(self: *PME, addr: usize) void {
                    self.addr = @truncate(addr >> pages.page_shift);
                }
            },
            .L2 => struct {
                fn getAddr(self: *const PME) usize {
                    return (self.addr >> 9) << 21;
                }
                fn setAddr(self: *PME, addr: usize) void {
                    self.addr = @truncate((addr >> 21) << 9);
                }
            },
            .L3 => struct {
                fn getAddr(self: *const PME) usize {
                    // addr stores PA bits [51:12]; 1GiB page base is bits
                    // [51:30], so drop low 18 bits before << 30
                    return (self.addr >> 18) << 30;
                }
                fn setAddr(self: *PME, addr: usize) void {
                    // inverse of getAddr
                    self.addr = @truncate((addr >> 30) << 18);
                }
            },
            .L4 => struct {
                fn getAddr(self: *const PME) usize {
                    return self.addr;
                }
                fn setAddr(self: *PME, addr: usize) void {
                    self.addr = addr;
                }
            },
        };

        pub const getAddress = impls.getAddr;
        pub const setAddress = impls.setAddr;

        /// table referenced by this entry
        fn get(self: *const PME) *PMLNT(@enumFromInt(@intFromEnum(level) - 1)) {
            return @ptrFromInt(self.addr << pages.page_shift);
        }
    };
}

pub fn PMLNT(level: Level) type {
    return [512]PMLNE(level);
}

/// Virtual address split into per-level indices
pub const Indices = struct {
    offset: u12,
    l1: u9,
    l2: u9,
    l3: u9,
    l4: u9,

    pub fn fromVirt(virt: usize) Indices {
        return .{
            .offset = @truncate(virt),
            .l1 = @truncate(virt >> pages.page_shift),
            .l2 = @truncate(virt >> 21),
            .l3 = @truncate(virt >> 30),
            .l4 = @truncate(virt >> 39),
        };
    }

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

/// Print a run-length-collapsed summary of addresses
pub fn summarizeAddresses(comptime level: Level, addresses: [512]?usize) void {
    const log_local = std.log.scoped(.arch_paging_info);
    var first_known_existence: usize = 0;
    for (addresses, 0..) |value, i| {
        if (i > 0) {
            if (value == null and addresses[i - 1] != null and addresses[first_known_existence] != null) {
                // end of a run: print it
                log_local.debug("{s}{} {s} pages from 0x{x:0>16} to 0x{x:0>16}", .{
                    @as([2 * (4 - @intFromEnum(level))]u8, @splat("  ")),
                    i - first_known_existence,
                    @tagName(level),
                    addresses[first_known_existence].?,
                    addresses[i - 1].?,
                });
            } else if (value != null and addresses[i - 1] == null) {
                // start of a new run
                first_known_existence = i;
            }
        }
    }
    // final run
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

pub const MapPageOptions = struct {
    w: bool,
    x: bool,
    u: bool,
    g: bool,
    /// write-back if true. Only set false (uncacheable) for MMIO etc,
    /// where a stale cached read/write is wrong, not just slow.
    cacheable: bool = true,
};

/// PML4 index where the canonical-address split falls: bit 47 set (indices
/// 256-511, >= 0xffff800000000000) is "upper half". See `AddressSpace.create`.
const kernel_half_start_index: usize = 256;

/// Higher-half alias addr `AddressSpace.mapKernel` also maps the kernel
/// image to (canonical x86_64 "negative 2GiB" base). Linker still
/// loads/links at low phys addr (KERNEL_PHYS_START, 1MiB); this is a
/// second alias of the same phys pages.
const kernel_higher_half_addr: usize = 0xffffffff80000000;

/// One address space (process or kernel), rooted at its own PML4.
pub const AddressSpace = struct {
    pml4: *align(pages.page_size) PMLNT(.L4),

    /// New address space for a userspace process. Lower half (user, 0-255)
    /// starts empty; upper half (kernel, 256-511) points at the *same*
    /// next-level tables as the kernel's own space -- not copies -- so
    /// every kernel mapping (incl. future ones) is visible with no sync
    /// needed. Without this, switching CR3 into a fresh process would
    /// immediately fault fetching the running handler.
    pub fn create(allocator: std.mem.Allocator) !AddressSpace {
        const kernel_pml4 = kernelAddressSpace().pml4;
        const new_pml4: *align(pages.page_size) PMLNT(.L4) = (try allocator.allocWithOptions(PMLNE(.L4), 512, page_table_alignment, null))[0..512];
        for (new_pml4[0..kernel_half_start_index]) |*entry| entry.p = false;
        @memcpy(new_pml4[kernel_half_start_index..512], kernel_pml4[kernel_half_start_index..512]);
        return .{ .pml4 = new_pml4 };
    }

    /// Load CR3 with this address space
    pub fn activate(self: *const AddressSpace) void {
        const cr3 = registers.CR3{
            .pwt = false,
            .pcd = false,
            .addr = @truncate(@intFromPtr(self.pml4) >> pages.page_shift),
        };
        cr3.set();
    }

    pub fn physFromVirt(self: *const AddressSpace, virt: usize) ?usize {
        const indices: Indices = Indices.fromVirt(virt);
        var level: Level = .L4;
        var current_page_table: *PMLNT(.L4) = self.pml4;
        inline for ([_]usize{ indices.l4, indices.l3, indices.l2 }) |i| {
            const entry = current_page_table[i];
            if (entry.p) {
                if (entry.ps == .large) {
                    // shifts inlined by hand, not via entry.getAddress():
                    // current_page_table stays statically *PMLNT(.L4)
                    // (reassigned via @ptrCast), so entry's static type is
                    // always PMLNE(.L4) regardless of level -- only the
                    // separately-tracked `level` picks the right shift
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
        if (current_page_table[indices.l1].p) {
            return (current_page_table[indices.l1].addr << pages.page_shift) + indices.offset;
        } else {
            return null;
        }
    }

    /// Split large `entry` (at `current_page_table[i]`) into a page table
    /// at `level`, replicating the original range/perms at finer
    /// granularity -- otherwise every address it used to cover besides the
    /// one being changed would silently become unmapped.
    ///
    /// Returns the new table, already installed into `current_page_table[i]`
    /// (that slot itself left maximally permissive, like other intermediate
    /// entries here, since the new table's entries carry the real perms).
    fn splitLargeEntry(
        self: *const AddressSpace,
        allocator: std.mem.Allocator,
        current_page_table: *PMLNT(.L4),
        i: usize,
        entry: PMLNE(.L4),
        comptime level: Level,
    ) std.mem.Allocator.Error!*align(pages.page_size) PMLNT(level) {
        // decoded by hand, same reason as physFromVirt: entry's static
        // type is always PMLNE(.L4) here
        const orig_phys_base: usize = switch (level) {
            .L2 => (@as(usize, entry.addr) >> 18) << 30, // splitting 1GiB PDPTE
            .L1 => (@as(usize, entry.addr) >> 9) << 21, // splitting 2MiB PDE
            else => unreachable, // only L2/L3 can have PS=1
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

    /// Force a large page down to 4K-table granularity ahead of time (see
    /// `splitLargeEntry`), e.g. before a batch of `mapPage` calls each
    /// changing a small part of what used to be one large page.
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
                    // split instead of erroring: mapping a 4K page inside
                    // an old huge page just works, no replacePageWithTable needed
                    const alloc = allocator orelse return error.AllocatorRequired;
                    current_page_table = @ptrCast(try self.splitLargeEntry(alloc, current_page_table, i, entry, level));
                } else {
                    current_page_table = @ptrCast(entry.get());
                }
            } else {
                const alloc = allocator orelse return error.AllocatorRequired;
                log.debug("Allocating {s} table at index {} of current page table", .{ @tagName(level), i });
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
                // descend into the newly allocated table (like the
                // present-entry branch does via entry.get())
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

    pub fn changePage(self: *AddressSpace, virt: usize, options: MapPageOptions) !void {
        const phys_opt = self.physFromVirt(virt);
        if (phys_opt) |phys_addr| {
            try self.mapPage(null, virt, phys_addr, false, options);
        }
    }

    /// Clears mapping + invalidates TLB, but does *not* free the phys page
    /// or reclaim an now-empty table -- no ownership model for that yet.
    /// Caller must know whether the unmapped page should also be freed.
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

    pub fn mapKernel(self: *AddressSpace, allocator: std.mem.Allocator, kernel_phys_addr: usize, kernel_page_size: usize) void {
        // TODO: maps whole image (code/rodata/data/bss) with one perm set,
        // so .w must stay true until sections are split .text/.rodata
        // read-only from .data/.bss
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

/// Kernel's own address space. `null` until `init` runs.
var kernel_address_space_storage: ?AddressSpace = null;

/// Kernel's address space; every `AddressSpace.create`d process shares its
/// upper half.
pub fn kernelAddressSpace() *AddressSpace {
    return if (kernel_address_space_storage) |*as| as else @panic("paging.init() must run before any page table operation");
}

/// Print firmware-neutral boot memory map, collapsing same-kind runs
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

/// Init paging
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
    // copy firmware's mappings so what we're running on (stack, GDT/IDT,
    // page allocator arena) stays mapped after CR3 switch; firmware's PML4
    // itself isn't writable
    pml4.* = old_pml4.*;
    kernel_address_space_storage = .{ .pml4 = pml4 };
    const kas = kernelAddressSpace();
    kas.mapKernel(allocator, kernel_physical_address, kernel_page_size);
    kas.activate();
    log.info("Paging initialization successful!", .{});
}
