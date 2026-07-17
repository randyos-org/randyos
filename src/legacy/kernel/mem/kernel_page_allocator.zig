//! Kernel Page Allocator
//! 2024 by Samuel Fiedler

const std = @import("std");
const log = std.log.scoped(.kp_alloc);
const mem = std.mem;
const math = std.math;

const common = @import("common");
const pages = common.pages;
const KernelBootInfo = common.boot_info.KernelBootInfo;
const MemoryRegion = common.boot_info.MemoryRegion;

/// Below this addr, skip during `bootstrap` even if usable -- legacy 1MiB
/// low-memory area (BDA, VGA/option ROM), unsafe as general free memory.
const low_memory_reserved_end: usize = 0x100000;

/// Free-region slots `bootstrap_memory` reserves during `bootstrap`.
const bootstrap_max_free_regions: usize = 16;
/// Total bootstrap_memory slots: free regions + map's own backing entry.
const bootstrap_slot_count: usize = 32;

/// Map entry. Int width left inferred, not pinned: `addr` (usize) is
/// 64-bit on x86_64/aarch64, 32-bit on arm/powerpc stubs, so total width
/// varies per target -- inferring keeps this portable.
pub const Entry = packed struct {
    addr: usize = 0,
    /// slot holds a real entry vs blank filler; not same as `free`
    used: bool = false,
    /// is this region free?
    free: bool = true,
    /// padding
    _align1: u30 = 0,
    /// pages in region; u32 caps at 2^32 pages (16TiB) so it doesn't
    /// silently truncate on multi-GB regions like a u16 count would
    num_pages: u32 = 0,
};

/// Scratch map before real memory backs it: `bootstrap()` records up to
/// 16 free regions plus one for its own backing storage, then re-slices
/// `map` onto allocated pages and copies these over.
var bootstrap_memory: [bootstrap_slot_count]Entry = @splat(.{});

/// The map. Starts on bootstrap memory, grows from there.
pub var map: []Entry = bootstrap_memory[0..];

pub var max_pages: usize = 0;

pub fn bootstrap(regions: []const MemoryRegion) void {
    // less than slot_count: map needs room for its own allocation entry
    const mem_max_cnt: usize = @min(bootstrap_max_free_regions, regions.len);
    var index: usize = 0;
    var cnt_free: usize = 0;
    while (cnt_free < mem_max_cnt and index < regions.len) : (index += 1) {
        const region = regions[index];
        if (region.kind == .usable and region.phys_start > low_memory_reserved_end) {
            log.debug("{} free pages found at 0x{x}", .{ region.page_count, region.phys_start });
            map[cnt_free] = .{
                // phys_start is u64 (firmware-neutral); truncates on
                // 32-bit archs, compile-only-stub concern only
                .addr = @intCast(region.phys_start),
                .used = true,
                .free = true,
                .num_pages = @truncate(region.page_count),
            };
            max_pages += @intCast(region.page_count);
            cnt_free += 1;
        }
    }
    // find free space in own map
    const amount_of_pages_needed: usize = math.divCeil(usize, max_pages * @sizeOf(Entry), pages.page_size) catch unreachable;
    log.debug("{} pages needed to store map", .{amount_of_pages_needed});
    var addr: usize = 0;
    for (map) |*entry| {
        if (entry.num_pages > amount_of_pages_needed and entry.free == true) {
            entry.num_pages -= @truncate(amount_of_pages_needed);
            addr = entry.addr + (@as(usize, entry.num_pages) * pages.page_size);
            break;
        }
    }
    // mark that space used
    for (map) |*entry| {
        if (!entry.used) {
            entry.used = true;
            entry.free = false;
            entry.addr = addr;
            entry.num_pages = @truncate(amount_of_pages_needed);
        }
    }
    log.debug("Reslicing the map to 0x{x:0>16}", .{addr});
    map = @as([*]Entry, @ptrFromInt(addr))[0..max_pages];
    log.debug("Migrating map contents from bootstrap to new slice", .{});
    for (map, 0..) |*entry, i| {
        if (i < bootstrap_memory.len) {
            entry.* = bootstrap_memory[i];
        } else {
            entry.* = .{
                .addr = 0,
                .num_pages = 0,
                .free = true,
                .used = false,
            };
        }
    }
}

pub fn countFreePages() usize {
    var num_free: usize = 0;
    for (map) |*entry| {
        if (entry.free) {
            num_free += entry.num_pages;
        }
    }
    return num_free;
}

/// Allocate bytes, page-wise.
pub fn alloc(_: *anyopaque, len: usize, _: mem.Alignment, _: usize) ?[*]u8 {
    const page_len = math.divCeil(usize, len, pages.page_size) catch unreachable;
    var addr: ?usize = null;
    // find and shrink free space
    for (map) |*entry| {
        if (entry.num_pages > page_len and entry.free == true) {
            entry.num_pages -= @truncate(page_len);
            addr = entry.addr + (@as(usize, entry.num_pages) * pages.page_size);
            break;
        }
    }
    // null addr = no space big enough
    if (addr == null) return null;
    // mark result used
    for (map) |*entry| {
        if (!entry.used) {
            entry.used = true;
            entry.free = false;
            entry.addr = addr.?;
            entry.num_pages = @truncate(page_len);
            break;
        }
    }
    return @as([*]u8, @ptrFromInt(addr.?));
}

/// Free bytes, page-wise.
pub fn free(_: *anyopaque, buf: []u8, _: mem.Alignment, _: usize) void {
    const addr: usize = @intFromPtr(buf.ptr);
    // round down to page base to match map entry keys
    const safe_addr: usize = addr - (addr % pages.page_size);
    for (map) |*entry| {
        if (entry.addr == safe_addr) {
            entry.free = true;
        }
    }
}

pub const allocator = mem.Allocator{
    .ptr = undefined,
    .vtable = &.{
        .alloc = alloc,
        .free = free,
        .resize = std.mem.Allocator.noResize,
        .remap = std.mem.Allocator.noRemap,
    },
};

pub fn init(kernel_boot_info: *KernelBootInfo) void {
    log.info("kernel page allocator initialization...", .{});
    log.debug("bootstrapping the allocator...", .{});
    bootstrap(kernel_boot_info.memory_map);
    log.info("kernel page allocator initialization successful!", .{});
}
