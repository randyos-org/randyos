//! Paging (4-level)
//! 2024 by Samuel Fiedler

const std = @import("std");
const log = std.log.scoped(.arch_paging);

const registers = @import("registers.zig");

pub const AddMappingError = std.mem.Allocator.Error || error{NoPageTable};

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

/// Permissions
pub const Perm = packed struct(u3) {
    r: bool,
    w: bool,
    x: bool,
};

/// Page Map Level N Entry
/// From the Intel SDM Volume 3A (December 2023), Chapter 4.5.4
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
        /// Must be 1 when mapping a page, must be 0 when referencing a table
        ps: PageSize = .small,
        /// Global when mapping a page, Ignored when referencing a table
        /// If GR4.PGE = 1, determines whether the translation is global, ignored otherwise.
        g: bool,
        /// Ignored
        ign1: u2,
        /// For ordinary paging, ignored; for HLAT paging, restart
        /// (if 1, linear-address translation is restarted with ordinary paging)
        r: bool,
        /// Physical address of 4KB aligned page-directory-pointer table referenced by this entry
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
                    return self.addr << 12;
                }
                /// Set the L1 address
                fn setAddr(self: *PME, addr: usize) void {
                    self.addr = @truncate(addr >> 12);
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
                    return (self.addr >> 9) << 30;
                }
                /// Set the L3 address
                fn setAddr(self: *PME, addr: usize) void {
                    self.addr = @truncate((addr >> 30) << 9);
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
            return @ptrFromInt(self.addr << 12);
        }
    };
}

/// Page Map Level N Table
pub fn PMLNT(level: Level) type {
    return [512]PMLNE(level);
}

/// Page Map Level 4 (pointer)
/// `null` until `init` runs; callers must fall back to a caller-provided
/// `pml4` or panic rather than dereference this before it's set.
pub var pml4ptr: ?*PMLNT(.L4) align(4096) = null;

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
            .l1 = @truncate(virt >> 12),
            .l2 = @truncate(virt >> 21),
            .l3 = @truncate(virt >> 30),
            .l4 = @truncate(virt >> 39),
        };
    }

    /// Virtual address from indices
    pub fn toVirt(self: *const Indices) usize {
        var addr: usize = 0;
        addr += self.offset;
        addr += @as(usize, self.l1) << 12;
        addr += @as(usize, self.l2) << 21;
        addr += @as(usize, self.l3) << 30;
        addr += @as(usize, self.l4) << 39;
        return addr;
    }
};

/// Translate a virtual address to a physical address
pub fn physFromVirt(pml4: ?*PMLNT(.L4), virt: usize) ?usize {
    // indices, level (mutable in loop) and current page table (will be set in loop)
    const indices: Indices = Indices.fromVirt(virt);
    var level: Level = .L4;
    var current_page_table = pml4 orelse pml4ptr orelse @panic("page table must be provided");
    // repeat the following for L4, L3 and L2 indices
    inline for ([_]usize{ indices.l4, indices.l3, indices.l2 }) |i| {
        // get entry
        const entry = current_page_table[i];
        if (entry.p) {
            if (entry.ps == .large) {
                // error or return for PS flag
                switch (level) {
                    .L1 => @panic("PS flag set on L1 page"),
                    .L2 => {
                        return (entry.addr << 21) + (@as(usize, indices.l1) << 12) + indices.offset;
                    },
                    .L3 => {
                        return (entry.addr << 30) + (@as(usize, indices.l2) << 21) + (@as(usize, indices.l1) << 12) + indices.offset;
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
        return (current_page_table[indices.l1].addr << 12) + indices.offset;
    } else {
        return null;
    }
}

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
};

/// Replace a (large) page with a page table
pub fn replacePageWithTable(allocator: std.mem.Allocator, pml4: ?*PMLNT(.L4), virt: usize) error{ WrongData, OutOfMemory }!void {
    var current_page_table = pml4 orelse pml4ptr orelse @panic("page table must be provided");
    const indices: Indices = Indices.fromVirt(virt);
    comptime var level: Level = .L4;

    inline for ([_]usize{ indices.l4, indices.l3, indices.l2 }) |i| {
        level = @enumFromInt(@intFromEnum(level) - 1);
        var entry = current_page_table[i];
        if (entry.p) {
            if (entry.ps == .large) {
                entry.ps = .small;
                log.debug("Allocating {s} table at index {} of current page table", .{ @tagName(level), i });
                const tbl_ptr: *align(4096) PMLNT(level) = (try allocator.allocWithOptions(PMLNE(level), 512, @enumFromInt(12), null))[0..512];
                for (tbl_ptr) |*ent| {
                    ent.p = false;
                }
                current_page_table[i] = .{
                    .p = true,
                    .r_w = true,
                    .u_s = true,
                    .pwt = true,
                    .pcd = true,
                    .ps = .small,
                    .xd = false,
                    .a = false,
                    .g = false,
                    .r = false,
                    .d = false,
                    .pk = 0,
                    .ign1 = 0,
                    .ign2 = 0,
                    .addr = @truncate(physFromVirt(null, @intFromPtr(tbl_ptr)).? >> 12),
                };
                // descend into the table we just allocated -- otherwise the
                // next iteration re-indexes the parent table instead of
                // walking down the hierarchy.
                current_page_table = @ptrCast(tbl_ptr);
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
    allocator: ?std.mem.Allocator,
    pml4: ?*PMLNT(.L4),
    virt: usize,
    phys: usize,
    user: bool,
    options: MapPageOptions,
) error{ Unimplemented, OutOfMemory }!void {
    log.debug("Mapping virtual address 0x{x:0>16} to physical address 0x{x:0>16}", .{ virt, phys });
    var current_page_table = pml4 orelse pml4ptr orelse @panic("page table must be provided");
    const indices: Indices = Indices.fromVirt(virt);
    comptime var level: Level = .L4;

    inline for ([_]usize{ indices.l4, indices.l3, indices.l2 }) |i| {
        level = @enumFromInt(@intFromEnum(level) - 1);
        const entry = current_page_table[i];
        if (entry.p) {
            if (entry.ps == .large) {
                log.err("Huge pages unimplemented!", .{});
                return error.Unimplemented;
            }
            current_page_table = @ptrCast(entry.get());
        } else {
            if (allocator) |alloc| {
                log.debug("Allocating {s} table at index {} of current page table", .{ @tagName(level), i });
                // alignment of 12 is page-aligned
                const tbl_ptr: *PMLNT(level) = &((try alloc.allocWithOptions(PMLNT(level), 1, @enumFromInt(12), null))[0]);
                for (tbl_ptr) |*ent| {
                    ent.p = false;
                }
                current_page_table[i] = .{
                    .p = true,
                    .r_w = true,
                    .u_s = !user,
                    .pwt = true,
                    .pcd = true,
                    .ps = .small,
                    .xd = false,
                    .a = false,
                    .g = false,
                    .r = false,
                    .d = false,
                    .pk = 0,
                    .ign1 = 0,
                    .ign2 = 0,
                    .addr = @truncate(physFromVirt(null, @intFromPtr(tbl_ptr)).? >> 12),
                };
                // descend into the table we just allocated, same as the
                // "entry already present" branch does via entry.get() --
                // otherwise the next iteration re-indexes the parent table
                // instead of walking down the hierarchy.
                current_page_table = @ptrCast(tbl_ptr);
            }
        }
    }

    const was_present = current_page_table[indices.l1].p;

    current_page_table[indices.l1] = .{
        .p = true,
        .r_w = true,
        .u_s = !user,
        .pwt = true,
        .pcd = true,
        .ps = .small,
        .g = options.g,
        .xd = !options.x,
        .addr = @truncate(phys >> 12),
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
pub fn changePage(pml4: ?*PMLNT(.L4), virt: usize, options: MapPageOptions) !void {
    const phys_opt = physFromVirt(null, virt);
    if (phys_opt) |phys_addr| {
        try mapPage(null, pml4, virt, phys_addr, false, options);
    }
}

/// Unmap a page
pub fn unmapPage(pml4: ?*PMLNT(.L4), virt: usize) !void {
    log.debug("Unmapping virtual address 0x{x:0>16}", .{virt});
    var current_page_table = pml4 orelse pml4ptr orelse @panic("page table must be provided");
    const indices: Indices = Indices.fromVirt(virt);

    inline for ([_]usize{ indices.l4, indices.l3, indices.l2 }) |i| {
        const entry = current_page_table[i];
        if (entry.p) {
            if (entry.ps == .large) {
                log.err("Huge pages unimplemented!", .{});
                return error.Unimplemented;
            }
            current_page_table = @ptrCast(entry.get());
        } else {
            log.err("Allocating page maps unimplemented!", .{});
            return error.Unimplemented;
        }
    }
    current_page_table[indices.l1].p = false;
}

/// UEFI Tags (simplified)
pub const UEFITags = enum {
    loader,
    boot_services,
    conventional,
    acpi,
    runtime_services,
    reserved,
    unknown,
};

/// Print UEFI Memory Map
pub fn printMemMap(map: std.os.uefi.tables.MemoryMapSlice, map_info: std.os.uefi.tables.MemoryMapInfo) void {
    var mem_index: usize = 0;
    const mem_max = map_info.len;
    var last_addr: usize = 0;
    var pg_count: usize = 0;
    log.debug("UEFI Memory Map Contents:", .{});
    while (mem_index < mem_max) : (mem_index += 1) {
        const map_entry: *std.os.uefi.tables.MemoryDescriptor = @ptrCast(@alignCast(map.ptr + mem_index * map_info.descriptor_size));
        const map_entry_next: *std.os.uefi.tables.MemoryDescriptor = @ptrCast(@alignCast(map.ptr + (mem_index + 1) * map_info.descriptor_size));
        const tag: UEFITags = switch (map_entry.type) {
            .loader_code, .loader_data => .loader,
            .boot_services_code, .boot_services_data => .boot_services,
            .conventional_memory => .conventional,
            .acpi_memory_nvs, .acpi_reclaim_memory => .acpi,
            .runtime_services_code, .runtime_services_data => .runtime_services,
            .reserved_memory_type => .reserved,
            else => .unknown,
        };
        const tag_next: UEFITags = switch (map_entry_next.type) {
            .loader_code, .loader_data => .loader,
            .boot_services_code, .boot_services_data => .boot_services,
            .conventional_memory => .conventional,
            .acpi_memory_nvs, .acpi_reclaim_memory => .acpi,
            .runtime_services_code, .runtime_services_data => .runtime_services,
            .reserved_memory_type => .reserved,
            else => .unknown,
        };
        pg_count += map_entry.number_of_pages;
        if (tag != tag_next) {
            log.debug("  V: 0x{x}-0x{x} PG: {} T: {s}", .{
                last_addr,
                (map_entry.virtual_start + map_entry.number_of_pages * 0x1000),
                pg_count,
                @tagName(tag),
            });
            last_addr = map_entry_next.virtual_start;
            pg_count = 0;
        }
    }
}

/// Map the kernel
pub fn mapKernel(allocator: std.mem.Allocator, pml4: *PMLNT(.L4), kernel_phys_addr: usize, kernel_page_size: usize) void {
    // TODO: actually implement mapping the kernel
    log.debug("Kernel Physical Start: 0x{x:0>16}", .{kernel_phys_addr});
    const kernel_start_addr: usize = 0xffffffff80000000;
    log.debug("Kernel page size: {} pages", .{kernel_page_size});
    // _ = allocator;
    // _ = pml4;
    // _ = kernel_start_addr;
    for (0..kernel_page_size) |i| {
        mapPage(allocator, pml4, kernel_start_addr + i * 0x1000, kernel_phys_addr + i * 0x1000, false, .{
            .w = false,
            .x = true,
            .u = false,
            .g = false,
        }) catch {
            @panic("Mapping the kernel failed!");
        };
    }
    log.debug("Finished mapping the kernel!", .{});
}

/// Initialize Paging
pub fn init(
    allocator: std.mem.Allocator,
    memory_map: std.os.uefi.tables.MemoryMapSlice,
    memory_map_info: std.os.uefi.tables.MemoryMapInfo,
    kernel_physical_address: usize,
    kernel_page_size: usize,
) void {
    const old_pml4: *PMLNT(.L4) = @ptrFromInt(registers.CR3.get().addr << 12);
    log.info("Paging initialization...", .{});
    printMemMap(memory_map, memory_map_info);
    log.debug("Allocating a Page Map Level 4 Table", .{});
    const pml4: *align(4096) PMLNT(.L4) = (allocator.allocWithOptions(PMLNE(.L4), 512, @enumFromInt(12), null) catch @panic("OOM for page map L4!"))[0..512];
    // Start from a copy of the firmware's existing mappings so everything
    // we're currently running from (stack, GDT/IDT, page allocator arena,
    // etc.) stays mapped once we switch CR3 to this table -- the firmware's
    // own PML4 isn't writable, which is why we can't just keep mutating it
    // in place.
    pml4.* = old_pml4.*;
    pml4ptr = pml4;
    mapKernel(allocator, pml4, kernel_physical_address, kernel_page_size);
    const cr3 = registers.CR3{
        .pwt = true,
        .pcd = true,
        .addr = @truncate(@intFromPtr(pml4) >> 12),
    };
    cr3.set();
    log.info("Paging initialization successful!", .{});
}
