//! Picks/reserves the physical memory the kernel's ELF `PT_LOAD` segments
//! load into.
//!
//! Kernel is non-relocatable: linked to run at `KERNEL_PHYS_START` (1M),
//! and always assumes link address == physical address. So the image
//! *must* end up physically at its link address ("the destination")
//! before the jump.
//!
//! Complication: the destination range may not be fully free yet (firmware
//! owns chunks of low memory until `exitBootServices`), and the kernel has
//! outgrown what QEMU/OVMF leaves free at 1M. So this module produces a
//! `KernelLoadPlan`: load directly at the destination if the firmware
//! allows it, else load into a `staging` area and let `main.zig` move the
//! image down after `exitBootServices`.

const std = @import("std");
const uefi = std.os.uefi;
const elf = std.elf;
const log = std.log.scoped(.bootaddr);

const rstd = @import("rstd");
const pages = rstd.memory;
const memory = @import("../memory.zig");

/// Errors from planning the kernel load
pub const PlanKernelLoadError = error{ NoSuitableMemory, Unaligned };

/// Never stage below this address -- legacy 1MiB low memory (BDA,
/// VGA/option ROM windows); same boundary the kernel's page allocator
/// uses later.
const min_kernel_load_address: u64 = 0x100000;

/// Where the kernel image lives at each stage of the boot.
pub const KernelLoadPlan = struct {
    /// Physical address the kernel runs at -- lowest `PT_LOAD` vaddr, i.e.
    /// the link address.
    dest: u64,
    /// Bytes from `dest` through the end of the highest segment (`memsz`,
    /// includes .bss).
    size: u64,
    /// Where segments are read while Boot Services still run. Equal to
    /// `dest` if the whole destination was free up front; otherwise a
    /// staging area `main.zig` copies down to `dest` after `exitBootServices`.
    staging: u64,
};

/// Compute the kernel's physical footprint from its `PT_LOAD` headers,
/// then secure memory for it:
///
/// 1. Try allocating the destination range itself. If granted, load
///    straight there (no post-exit move needed).
/// 2. Otherwise reserve whatever parts of the destination are still free
///    (so no later allocation lands where the post-exit move will
///    overwrite it), and allocate a staging range elsewhere.
///
/// Either way, every allocation is `.loader_data`, mapped to
/// `kernel_and_modules` so the kernel's page allocator leaves it alone.
pub fn planKernelLoad(
    mm: memory.MemoryMap,
    program_headers: []const elf.Elf64.Phdr,
) PlanKernelLoadError!KernelLoadPlan {
    const boot_services = uefi.system_table.boot_services.?;

    var min_vaddr: u64 = std.math.maxInt(u64);
    var max_vaddr_end: u64 = 0;
    var any_load = false;

    for (program_headers) |phdr| {
        if (phdr.type != .LOAD) continue;
        any_load = true;
        if (phdr.vaddr < min_vaddr) min_vaddr = phdr.vaddr;
        const segment_end = phdr.vaddr + phdr.memsz;
        if (segment_end > max_vaddr_end) max_vaddr_end = segment_end;
    }
    if (!any_load) {
        log.err("no LOAD segments to size the kernel image from", .{});
        return error.NoSuitableMemory;
    }
    if (min_vaddr & pages.page_mask != 0) {
        log.err("kernel link address 0x{x} is not page-aligned", .{min_vaddr});
        return error.Unaligned;
    }
    if (min_vaddr < min_kernel_load_address) {
        // jump runs under identity mapping; a link addr in legacy low
        // memory could never be honored safely
        log.err("kernel link address 0x{x} is below the 1M low-memory boundary", .{min_vaddr});
        return error.NoSuitableMemory;
    }

    const required_size = max_vaddr_end - min_vaddr;
    const required_pages = memory.efiSizeToPages(required_size);
    log.debug("kernel image needs {} bytes ({} pages) at 0x{x}-0x{x}", .{
        required_size,
        required_pages,
        min_vaddr,
        max_vaddr_end,
    });

    var plan: KernelLoadPlan = .{
        .dest = min_vaddr,
        .size = required_size,
        .staging = undefined,
    };

    // fast path: try allocating dest directly rather than scanning our
    // (possibly stale) memory map
    if (boot_services.allocatePages(
        .{ .address = @ptrFromInt(plan.dest) },
        .loader_data,
        required_pages,
    )) |_| {
        log.debug("destination range is free; loading kernel directly at 0x{x}", .{plan.dest});
        plan.staging = plan.dest;
        zeroImageSpan(plan.staging, required_pages);
        return plan;
    } else |_| {
        log.debug("destination range not fully free yet; staging elsewhere", .{});
    }

    // reserve free parts of dest so nothing else lands there; failure here
    // is survivable (dest gets carved out regardless, see toGenericMemoryMap)
    reserveDestination(boot_services, mm, plan.dest, max_vaddr_end);

    // find a staging range: walk map for conventional regions big enough,
    // not overlapping dest; AllocateAddress verifies each candidate
    var mem_index: usize = 0;
    while (mem_index < mm.info.len) : (mem_index += 1) {
        const mem_point: *uefi.tables.MemoryDescriptor = @ptrCast(@alignCast(mm.map.ptr + (mem_index * mm.info.descriptor_size)));
        if (mem_point.type != .conventional_memory) continue;
        const region_start = mem_point.physical_start;
        const region_end = region_start + mem_point.number_of_pages * @as(u64, pages.page_size);
        if (region_start < min_kernel_load_address) continue;
        if (region_end - region_start < required_size) continue;
        // no overlap with the destination
        if (region_start < max_vaddr_end and plan.dest < region_end) continue;

        if (boot_services.allocatePages(
            .{ .address = @ptrFromInt(region_start) },
            .loader_data,
            required_pages,
        )) |_| {
            log.debug("staging kernel at 0x{x} ({} pages)", .{ region_start, required_pages });
            plan.staging = region_start;
            zeroImageSpan(plan.staging, required_pages);
            return plan;
        } else |err| {
            // map snapshot predates our own allocations, so a candidate
            // can be stale -- move on to the next one
            log.debug("staging candidate 0x{x} not available ({s}); trying next", .{ region_start, @errorName(err) });
        }
    }

    log.err("no conventional memory region big enough to stage the kernel image ({} bytes)", .{required_size});
    return error.NoSuitableMemory;
}

/// Zero the freshly allocated image span (covers .bss and alignment gaps).
fn zeroImageSpan(base: u64, page_count: u64) void {
    const span: [*]u8 = @ptrFromInt(base);
    @memset(span[0 .. page_count * pages.page_size], 0);
}

/// Best-effort reserve of free portions of `[dest, dest_end)`. See
/// `planKernelLoad` for why failure here is logged, not fatal.
fn reserveDestination(
    boot_services: *uefi.tables.BootServices,
    mm: memory.MemoryMap,
    dest: u64,
    dest_end: u64,
) void {
    var mem_index: usize = 0;
    while (mem_index < mm.info.len) : (mem_index += 1) {
        const mem_point: *uefi.tables.MemoryDescriptor = @ptrCast(@alignCast(mm.map.ptr + (mem_index * mm.info.descriptor_size)));
        if (mem_point.type != .conventional_memory) continue;
        const region_start = mem_point.physical_start;
        const region_end = region_start + mem_point.number_of_pages * @as(u64, pages.page_size);
        const overlap_start = @max(region_start, dest);
        const overlap_end = @min(region_end, dest_end);
        if (overlap_start >= overlap_end) continue;

        const overlap_pages = memory.efiSizeToPages(overlap_end - overlap_start);
        if (boot_services.allocatePages(
            .{ .address = @ptrFromInt(overlap_start) },
            .loader_data,
            overlap_pages,
        )) |_| {
            log.debug("reserved destination sub-range 0x{x}-0x{x}", .{ overlap_start, overlap_end });
        } else |err| {
            log.warn("could not reserve destination sub-range 0x{x}-0x{x} ({s})", .{ overlap_start, overlap_end, @errorName(err) });
        }
    }
}

/// Copy the staged kernel image down to its link address. No-op if the
/// loader placed it there directly. Only callable after
/// `exitBootServices`: while Boot Services run, the destination may still
/// be firmware-owned (the whole reason staging exists).
pub fn moveKernelToDestination(plan: KernelLoadPlan) void {
    if (plan.staging == plan.dest) return;
    const src: [*]const u8 = @ptrFromInt(plan.staging);
    const dst: [*]u8 = @ptrFromInt(plan.dest);
    // shouldn't overlap (staging avoids the destination), but copy in the
    // safe direction anyway
    if (plan.dest < plan.staging) {
        std.mem.copyForwards(u8, dst[0..plan.size], src[0..plan.size]);
    } else {
        std.mem.copyBackwards(u8, dst[0..plan.size], src[0..plan.size]);
    }
}
