//! Picking and reserving the physical memory the kernel's ELF `PT_LOAD`
//! segments get loaded into.
//!
//! The kernel is not relocatable: it's linked to run at `KERNEL_PHYS_START`
//! (1M, see the kernel linker script), the bootloader jumps to its ELF entry
//! point under the firmware's identity-mapped paging, and the kernel itself
//! keeps assuming link address == physical address afterwards. So the image
//! *must* end up physically at its link address ("the destination") before
//! the jump.
//!
//! The complication: the whole destination range isn't necessarily free
//! while Boot Services are still running (firmware owns chunks of low
//! memory for boot-services data until `exitBootServices`), and the kernel
//! has outgrown what QEMU/OVMF leaves free at 1M. So this module produces a
//! `KernelLoadPlan`: load directly into the destination when the firmware
//! lets us allocate all of it, otherwise load into a `staging` area and let
//! `main.zig` move the image down to the destination after
//! `exitBootServices`, once the firmware's claim on that memory is void.

const std = @import("std");
const uefi = std.os.uefi;
const elf = std.elf;
const log = std.log.scoped(.bootaddr);

const rstd = @import("rstd");
const pages = rstd.memory;
const memory = @import("../memory.zig");

/// Errors from planning the kernel load
pub const PlanKernelLoadError = error{ NoSuitableMemory, Unaligned };

/// Physical regions below this address are never considered for staging --
/// the legacy 1MiB low-memory area (BIOS data area, VGA/option ROM windows,
/// etc.), same boundary the kernel's own page allocator applies later.
const min_kernel_load_address: u64 = 0x100000;

/// Where the kernel image lives at each stage of the boot.
pub const KernelLoadPlan = struct {
    /// Physical address the image must occupy when the kernel starts
    /// running -- the lowest `PT_LOAD` vaddr, i.e. the link address.
    dest: u64,
    /// Total bytes from `dest` through the end of the highest segment
    /// (`memsz`, so this includes .bss).
    size: u64,
    /// Where the segments are actually read while Boot Services are still
    /// running. Equal to `dest` when the whole destination could be
    /// allocated up front; otherwise a separately allocated area that
    /// `main.zig` copies down to `dest` after `exitBootServices`.
    staging: u64,
};

/// Compute the kernel image's physical footprint from its `PT_LOAD`
/// headers, then secure memory for it:
///
/// 1. Try to allocate the destination range itself. If the firmware grants
///    it, load straight there (no post-exit move needed).
/// 2. Otherwise, reserve whatever parts of the destination *are* still
///    free -- not to use them yet, but so no later allocation (ours or the
///    firmware's, e.g. the DWARF pool) lands inside memory the post-exit
///    move is going to overwrite -- and allocate a staging range big enough
///    for the whole image elsewhere.
///
/// Either way, every allocation is `.loader_data`, which the boot-info
/// translation maps to `kernel_and_modules` so the kernel's page allocator
/// leaves it alone.
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
        // The jump runs under identity mapping, so a link address inside
        // legacy low memory could never be honored safely.
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

    // Fast path: the whole destination is free right now. Let the firmware
    // be the judge (a single AllocateAddress attempt) rather than scanning
    // the (possibly already stale) memory map ourselves.
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

    // Reserve the parts of the destination that are still free, so nothing
    // new gets allocated inside memory the post-exit move will overwrite.
    // Failure here is survivable (whatever occupies the range is
    // firmware-owned and dead after exitBootServices; the final memory map
    // handed to the kernel gets the whole destination carved out
    // regardless -- see toGenericMemoryMap), so log and continue.
    reserveDestination(boot_services, mm, plan.dest, max_vaddr_end);

    // Find and allocate a staging range. Walk the map for conventional
    // regions big enough for the whole image that don't overlap the
    // destination (regions we just reserved still look conventional in
    // this pre-reservation snapshot), and let AllocateAddress verify each
    // candidate is still actually free.
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
            // The map snapshot predates this function's own allocations
            // (and any pool churn since), so a candidate can be stale --
            // just move on to the next one.
            log.debug("staging candidate 0x{x} not available ({s}); trying next", .{ region_start, @errorName(err) });
        }
    }

    log.err("no conventional memory region big enough to stage the kernel image ({} bytes)", .{required_size});
    return error.NoSuitableMemory;
}

/// Zero the freshly allocated image span in one pass. Covers .bss and any
/// alignment gaps between segments, so segment loading only has to read
/// each segment's file bytes on top.
fn zeroImageSpan(base: u64, page_count: u64) void {
    const span: [*]u8 = @ptrFromInt(base);
    @memset(span[0 .. page_count * pages.page_size], 0);
}

/// Best-effort reservation of the still-free portions of the destination
/// range `[dest, dest_end)`: clip every conventional region against the
/// range and AllocateAddress the overlap. See `planKernelLoad` for why a
/// failure here is logged rather than fatal.
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

/// Copy the staged kernel image down to its link address. No-op when the
/// loader was able to place it there directly. Only callable after
/// `exitBootServices`: while Boot Services run, parts of the destination
/// range may still be firmware-owned (that's the entire reason staging
/// exists) -- afterwards, that claim is void and the memory map already
/// reports the destination as `kernel_and_modules` (see
/// `memory.toGenericMemoryMap`), so nothing else will ever use it.
pub fn moveKernelToDestination(plan: KernelLoadPlan) void {
    if (plan.staging == plan.dest) return;
    const src: [*]const u8 = @ptrFromInt(plan.staging);
    const dst: [*]u8 = @ptrFromInt(plan.dest);
    // The ranges shouldn't overlap (staging explicitly avoids the
    // destination), but copy in the safe direction anyway.
    if (plan.dest < plan.staging) {
        std.mem.copyForwards(u8, dst[0..plan.size], src[0..plan.size]);
    } else {
        std.mem.copyBackwards(u8, dst[0..plan.size], src[0..plan.size]);
    }
}
