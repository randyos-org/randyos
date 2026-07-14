//! UEFI memory map handling: fetching the current map and installing the
//! virtual address map firmware expects before `exitBootServices` hands
//! control to the kernel.

const std = @import("std");
const uefi = std.os.uefi;
const log = std.log.scoped(.bootmem);

const rstd = @import("rstd");
const pages = rstd.memory;
const efi_page_shift = pages.page_shift;
const efi_page_mask = pages.page_mask;
const MemoryRegion = rstd.machine.MemoryRegion;
const MemoryRegionKind = rstd.machine.MemoryRegionKind;

/// Extra whole descriptor slots of headroom `exitBootServices` requests on
/// each retry fetch, on top of whatever `getMemoryMapInfo` reports needing --
/// covers firmware growing the map again between this fetch and the retry.
/// The map can (and, empirically, reliably does) grow by a full new
/// descriptor between the size query inside `fetch` and its actual
/// `getMemoryMap` call a few lines later -- a few slack *bytes* per existing
/// descriptor (the previous scheme) doesn't cover that; a few slack
/// *descriptors* does.
const exit_boot_services_retry_padding: usize = 8;

/// Convert a memory size to memory pages (4096 bytes each)
pub inline fn efiSizeToPages(value: anytype) @TypeOf(value) {
    const addition: @TypeOf(value) = if (value & efi_page_mask != 0) 1 else 0;
    const ret = (value >> efi_page_shift) + addition;
    return ret;
}

/// A UEFI memory map together with the metadata (descriptor size/count/key)
/// needed to walk or re-submit it.
pub const MemoryMap = struct {
    info: uefi.tables.MemoryMapInfo,
    buffer: []u8,
    map: uefi.tables.MemoryMapSlice,
};

/// Fetch the current UEFI memory map (info, then a matching allocation,
/// then the map itself).
///
/// `extra_descriptors` pads the allocation, beyond what `getMemoryMapInfo`
/// reports needing, by this many whole extra descriptor slots: firmware can
/// grow the map between the info call and the actual `getMemoryMap` call
/// (any allocation can do it, including the one this function just made),
/// so a snug buffer can undersize by the time it's used. Pass 0 for a
/// one-off read; pass a nonzero pad when about to retry `exitBootServices`
/// (see `exitBootServices` below).
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
    // Re-read the info (in particular, the key) after allocating: the
    // allocation above is itself a change to the map, so the pre-allocation
    // info/key is already stale by the time getMemoryMap below runs. Using
    // it anyway would hand `exitBootServices` a key that can never match,
    // since it's stale before this function even returns.
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

/// Repeatedly re-fetch the memory map and retry `exitBootServices` until it
/// succeeds. A stale map key is the expected first failure -- fetching the
/// map itself is an allocation, and any allocation between the last fetch
/// and this call can invalidate the key -- so UEFI expects a retry loop
/// here rather than a single attempt.
pub fn exitBootServices(boot_services: *uefi.tables.BootServices, handle: uefi.Handle, current: *MemoryMap) !void {
    while (true) {
        boot_services.exitBootServices(handle, current.info.key) catch {
            log.info("getting memory map and trying to exit boot services", .{});
            // The failed attempt's buffer is about to be replaced below and
            // was never freed -- every retry through here otherwise leaks
            // one boot_services_data allocation, which itself perturbs the
            // memory map (new allocations are exactly what invalidates map
            // keys in the first place), compounding with each retry.
            boot_services.freePool(@alignCast(current.buffer.ptr)) catch |err| {
                log.warn("freeing stale memory map buffer failed: {s}", .{@errorName(err)});
            };
            current.* = try fetch(boot_services, exit_boot_services_retry_padding);
            continue;
        };
        return;
    }
}

/// Identity-remap `mm` for `runtime_services.setVirtualAddressMap` and
/// install it.
///
/// Everything is identity-mapped: the kernel is non-relocatable and always
/// ends up physically at its link address before the jump (staged and moved
/// there after exitBootServices if necessary -- see
/// uefi/loader/load_address.zig), so even the kernel's own memory needs no
/// special-casing here.
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

/// Upper bound on how many regions `toGenericMemoryMap` can emit. Real and
/// virtualized UEFI firmware typically report well under 100 descriptors
/// (plus at most two extra from splitting regions around the kernel image);
/// this is generous headroom, not a tight fit.
const max_memory_regions = 256;

/// Backing storage for `toGenericMemoryMap`'s result. Static rather than
/// allocated: this runs from `finalizeKernelBootInfo`, i.e. after
/// `exitBootServices` has already succeeded, so Boot Services' pool
/// allocator is no longer callable -- only Runtime Services and the raw
/// memory the firmware already handed us remain usable.
var memory_region_storage: [max_memory_regions]MemoryRegion = undefined;

/// Translate a raw UEFI memory map into the firmware-neutral
/// `[]const MemoryRegion` shape the kernel actually consumes -- the kernel
/// never needs to know about UEFI's per-descriptor stride or its firmware-
/// specific type enum.
///
/// `[kernel_start, kernel_start + kernel_size)` -- the physical range the
/// kernel image occupies once `main.zig`'s post-exitBootServices move has
/// run -- is force-marked `kernel_and_modules` no matter what UEFI type
/// covers it, splitting regions as needed. Without this, any part of that
/// range the loader couldn't pre-reserve (it may have been firmware-owned
/// until exitBootServices) would be reported `usable` and the kernel's page
/// allocator would hand out pages the kernel itself lives in.
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
            // No kernel overlap (or already the right kind): pass through.
            count = appendRegion(count, region_start, (region_end - region_start) / page_size, kind);
            continue;
        }

        // Split around the kernel image: the part before, the overlap
        // itself (as kernel_and_modules), and the part after.
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

/// Append one region to `memory_region_storage` (bounds-checked), returning
/// the new count. Zero-page regions are dropped.
fn appendRegion(count: usize, phys_start: u64, page_count: u64, kind: MemoryRegionKind) usize {
    if (page_count == 0 or count >= max_memory_regions) return count;
    memory_region_storage[count] = .{
        .phys_start = phys_start,
        .page_count = page_count,
        .kind = kind,
    };
    return count + 1;
}
