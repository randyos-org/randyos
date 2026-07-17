//! UEFI memory map handling: fetch map, install virtual addr map before
//! `exitBootServices` hands control to the kernel.

const std = @import("std");
const uefi = std.os.uefi;
const log = std.log.scoped(.bootmem);

const rstd = @import("rstd");
const pages = rstd.memory;
const efi_page_shift = pages.page_shift;
const efi_page_mask = pages.page_mask;
const MemoryRegion = rstd.machine.MemoryRegion;
const MemoryRegionKind = rstd.machine.MemoryRegionKind;

/// Extra descriptor slots of headroom for `exitBootServices` retry fetches,
/// covering firmware growing the map between fetch and retry. Slack in
/// whole descriptors, not bytes -- the map reliably grows by a full
/// descriptor between the size query and the actual `getMemoryMap` call.
const exit_boot_services_retry_padding: usize = 8;

/// Convert byte size to page count (4096B pages)
pub inline fn efiSizeToPages(value: anytype) @TypeOf(value) {
    const addition: @TypeOf(value) = if (value & efi_page_mask != 0) 1 else 0;
    const ret = (value >> efi_page_shift) + addition;
    return ret;
}

/// A UEFI memory map plus the metadata (descriptor size/count/key) needed
/// to walk or re-submit it.
pub const MemoryMap = struct {
    info: uefi.tables.MemoryMapInfo,
    buffer: []u8,
    map: uefi.tables.MemoryMapSlice,
};

/// Fetch the current UEFI memory map: info, then a matching allocation,
/// then the map itself.
///
/// `extra_descriptors` pads the allocation by this many extra descriptor
/// slots, since firmware can grow the map between the info call and the
/// `getMemoryMap` call (any allocation can do it, including this
/// function's own). Pass 0 for a one-off read, nonzero when about to
/// retry `exitBootServices` (see below).
pub fn fetch(boot_services: *uefi.tables.BootServices, extra_descriptors: usize) !MemoryMap {
    var info = boot_services.getMemoryMapInfo() catch |err| {
        log.err("getting memory map info failed: {s}", .{@errorName(err)});
        return err;
    };
    const buffer = boot_services.allocatePool(
        .boot_services_data,
        info.descriptor_size * (info.len + extra_descriptors),
    ) catch |err| {
        log.err("allocating memory map buffer failed: {s}", .{@errorName(err)});
        return err;
    };
    // re-read info/key after allocating: the allocation itself changes the
    // map, so the pre-allocation info is already stale by getMemoryMap time
    info = boot_services.getMemoryMapInfo() catch |err| {
        log.err("getting memory map info failed: {s}", .{@errorName(err)});
        return err;
    };
    const map = boot_services.getMemoryMap(buffer) catch |err| {
        log.err("getting memory map failed: {s}", .{@errorName(err)});
        return err;
    };
    return .{ .info = info, .buffer = buffer, .map = map };
}

/// Re-fetch the memory map and retry `exitBootServices` until it succeeds.
/// A stale key is the expected first failure -- fetching the map is
/// itself an allocation that can invalidate the previous key.
pub fn exitBootServices(boot_services: *uefi.tables.BootServices, handle: uefi.Handle, current: *MemoryMap) !void {
    while (true) {
        boot_services.exitBootServices(handle, current.info.key) catch {
            log.info("getting memory map and trying to exit boot services", .{});
            // free the stale buffer before replacing it, else each retry
            // leaks an allocation (which itself perturbs the map further)
            boot_services.freePool(@alignCast(current.buffer.ptr)) catch |err| {
                log.warn("freeing stale memory map buffer failed: {s}", .{@errorName(err)});
            };
            current.* = try fetch(boot_services, exit_boot_services_retry_padding);
            continue;
        };
        return;
    }
}

/// Identity-remap `mm` and install it via `setVirtualAddressMap`.
///
/// Everything is identity-mapped: the kernel is non-relocatable and always
/// ends up physically at its link address before the jump (see
/// loader/loadaddr.zig), so no special-casing is needed here.
pub fn installVirtualAddressMap(
    runtime_services: *uefi.tables.RuntimeServices,
    mm: MemoryMap,
) !void {
    var mem_index: usize = 0;
    while (mem_index < mm.info.len) : (mem_index += 1) {
        const mem_point: *uefi.tables.MemoryDescriptor = @ptrCast(@alignCast(mm.map.ptr + (mem_index * mm.info.descriptor_size)));
        mem_point.virtual_start = mem_point.physical_start;
    }
    try runtime_services.setVirtualAddressMap(mm.map);
}

/// Max regions `toGenericMemoryMap` can emit. Real/virtualized firmware
/// typically reports well under 100 descriptors; generous headroom.
const max_memory_regions = 256;

/// Backing storage for `toGenericMemoryMap`'s result. Static, not
/// allocated: runs after `exitBootServices`, so Boot Services' pool
/// allocator is gone.
var memory_region_storage: [max_memory_regions]MemoryRegion = undefined;

/// Translate a raw UEFI memory map into the firmware-neutral
/// `[]const MemoryRegion` shape the kernel consumes -- the kernel never
/// needs UEFI's descriptor stride or type enum.
///
/// `[kernel_start, kernel_start + kernel_size)` is force-marked
/// `kernel_and_modules` no matter what UEFI type covers it, splitting
/// regions as needed. Otherwise a firmware-owned-until-exit part of that
/// range would report `usable`, and the kernel's page allocator would
/// hand out pages the kernel itself lives in.
pub fn toGenericMemoryMap(mm: MemoryMap, kernel_start: u64, kernel_size: u64) []const MemoryRegion {
    const page_size: u64 = pages.page_size;
    const kernel_end = kernel_start + (efiSizeToPages(kernel_size) * page_size);
    var count: usize = 0;
    var index: usize = 0;
    while (index < mm.info.len and count < max_memory_regions) : (index += 1) {
        const d: *uefi.tables.MemoryDescriptor = @ptrCast(@alignCast(mm.map.ptr + index * mm.info.descriptor_size));
        const kind: MemoryRegionKind = switch (d.type) {
            .conventional_memory => .usable,
            .acpi_reclaim_memory => .acpi_reclaimable,
            .acpi_memory_nvs => .acpi_nvs,
            .boot_services_code, .boot_services_data => .bootloader_reclaimable,
            .loader_code, .loader_data => .kernel_and_modules,
            .memory_mapped_io, .memory_mapped_io_port_space => .mmio,
            .unusable_memory => .bad,
            else => .reserved,
        };

        const region_start = d.physical_start;
        const region_end = region_start + d.number_of_pages * page_size;
        const overlap_start = @max(region_start, kernel_start);
        const overlap_end = @min(region_end, kernel_end);

        if (overlap_start >= overlap_end or kind == .kernel_and_modules) {
            // no overlap, or already right kind: pass through
            count = appendRegion(count, region_start, (region_end - region_start) / page_size, kind);
            continue;
        }

        // split around kernel image: before, overlap (as kernel_and_modules), after
        if (overlap_start > region_start) {
            count = appendRegion(count, region_start, (overlap_start - region_start) / page_size, kind);
        }
        count = appendRegion(count, overlap_start, (overlap_end - overlap_start) / page_size, .kernel_and_modules);
        if (region_end > overlap_end) {
            count = appendRegion(count, overlap_end, (region_end - overlap_end) / page_size, kind);
        }
    }
    return memory_region_storage[0..count];
}

/// Append one region to `memory_region_storage` (bounds-checked). Drops
/// zero-page regions.
fn appendRegion(count: usize, phys_start: u64, page_count: u64, kind: MemoryRegionKind) usize {
    if (page_count == 0 or count >= max_memory_regions) return count;
    memory_region_storage[count] = .{
        .phys_start = phys_start,
        .page_count = page_count,
        .kind = kind,
    };
    return count + 1;
}
