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

/// Physical regions below this address are skipped during `bootstrap`, even
/// if reported usable -- the legacy 1MiB low-memory area (BIOS data area,
/// VGA/option ROM windows, etc.) that's unsafe to treat as general-purpose
/// free memory.
const low_memory_reserved_end: usize = 0x100000;

/// Number of free-region slots `bootstrap_memory` reserves for regions found
/// during `bootstrap` (see `bootstrap_slot_count` for the total, which also
/// reserves room for the map's own backing allocation).
const bootstrap_max_free_regions: usize = 16;
/// Total slots in `bootstrap_memory`: `bootstrap_max_free_regions` free
/// regions plus room for the entry describing the map's own backing storage.
const bootstrap_slot_count: usize = 32;

/// An entry in our map
pub const Entry = packed struct(u128) {
    /// The address
    addr: usize = 0,
    /// Whether this map slot holds a real entry (vs. still being a blank,
    /// never-assigned filler slot). Not the same as allocation status --
    /// see `free` for that.
    used: bool = false,
    /// Is the memory described by our entry free?
    free: bool = true,
    /// Reserved bits (padding)
    _align1: u30 = 0,
    /// Count of pages in this region. u32 caps a single region at 2^32
    /// pages (16 TiB) -- comfortably more than any real UEFI memory-map
    /// entry, unlike a 16-bit count, which silently truncated (via the
    /// `@truncate` in `bootstrap` below) on regions bigger than ~256MB, a
    /// real problem on hardware/VMs with multi-GB contiguous free regions.
    num_pages: u32 = 0,
};

/// Scratch space for the map before we have real memory to back it:
/// `bootstrap()` records up to 16 free regions here (see `mem_max_cnt`)
/// plus one entry for the map's own backing storage, then re-slices `map`
/// onto freshly allocated pages and copies these entries over.
var bootstrap_memory: [bootstrap_slot_count]Entry = @splat(.{});

/// Our map (where we will save everything in). We start with our bootstrap memory and after that,
/// we can allocate more space.
pub var map: []Entry = bootstrap_memory[0..];

/// Maximum amount of pages available
pub var max_pages: usize = 0;

/// Bootstrap the allocator
pub fn bootstrap(regions: []const MemoryRegion) void {
    // not bootstrap_slot_count, because we need some free space in the map to specify our map allocations
    const mem_max_cnt: usize = @min(bootstrap_max_free_regions, regions.len);
    var index: usize = 0;
    var cnt_free: usize = 0;
    // walk over memory map
    while (cnt_free < mem_max_cnt and index < regions.len) : (index += 1) {
        const region = regions[index];
        if (region.kind == .usable and region.phys_start > low_memory_reserved_end) {
            log.debug("{} free pages found at 0x{x}", .{ region.page_count, region.phys_start });
            map[cnt_free] = .{
                .addr = region.phys_start,
                .used = true,
                .free = true,
                .num_pages = @truncate(region.page_count),
            };
            max_pages += region.page_count;
            cnt_free += 1;
        }
    }
    // walk over own map to find free space
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
    // walk over own map to set free space as used
    for (map) |*entry| {
        if (!entry.used) {
            entry.used = true;
            entry.free = false;
            entry.addr = addr;
            entry.num_pages = @truncate(amount_of_pages_needed);
        }
    }
    log.debug("Reslicing the map to 0x{x:0>16}", .{addr});
    // reslice the map
    map = @as([*]Entry, @ptrFromInt(addr))[0..max_pages];
    // migrate the map
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

// FIXME:GPL begin
/// Count all pages that are free
pub fn cntFreePages() usize {
    var num_free_pages: usize = 0;
    for (map) |*entry| {
        if (entry.free) {
            num_free_pages += entry.num_pages;
        }
    }
    return num_free_pages;
}
// FIXME:GPL end

/// Allocate bytes (page-wise)
pub fn alloc(_: *anyopaque, len: usize, _: mem.Alignment, _: usize) ?[*]u8 {
    const page_len = math.divCeil(usize, len, pages.page_size) catch unreachable;
    var addr: ?usize = null;
    // find free space and reduce that free space
    for (map) |*entry| {
        if (entry.num_pages > page_len and entry.free == true) {
            entry.num_pages -= @truncate(page_len);
            addr = entry.addr + (@as(usize, entry.num_pages) * pages.page_size);
            break;
        }
    }
    // return null if addr hasn't been modified (so there is no space that is big enough)
    if (addr == null) return null;
    // mark the resulting address as used
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

/// Free bytes (page-wise)
pub fn free(_: *anyopaque, buf: []u8, _: mem.Alignment, _: usize) void {
    const addr: usize = @intFromPtr(buf.ptr);
    // round down to the containing page's base address to match how map entries are keyed
    const safe_addr: usize = addr - (addr % pages.page_size);
    for (map) |*entry| {
        if (entry.addr == safe_addr) {
            entry.free = true;
        }
    }
}

/// Allocator
pub const allocator = mem.Allocator{
    .ptr = undefined,
    .vtable = &.{
        .alloc = alloc,
        .free = free,
        .resize = std.mem.Allocator.noResize,
        .remap = std.mem.Allocator.noRemap,
    },
};

/// Initialize the kernel page allocator
pub fn init(kernel_boot_info: *KernelBootInfo) void {
    log.info("kernel page allocator initialization...", .{});
    log.debug("bootstrapping the allocator...", .{});
    bootstrap(kernel_boot_info.memory_map);
    log.info("kernel page allocator initialization successful!", .{});
}
