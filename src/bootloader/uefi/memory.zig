//! UEFI memory map handling: fetching the current map and installing the
//! virtual address map firmware expects before `exitBootServices` hands
//! control to the kernel.

const std = @import("std");
const uefi = std.os.uefi;
const log = std.log.scoped(.bootmem);

const common = @import("common");
const pages = common.pages;
const efi_page_shift = pages.page_shift;
const efi_page_mask = pages.page_mask;
const MemoryRegion = common.boot_info.MemoryRegion;

/// Extra bytes of per-descriptor headroom `exitBootServices` requests on
/// each retry fetch, on top of whatever `getMemoryMapInfo` reports needing --
/// covers firmware growing the map again between this fetch and the retry.
const exit_boot_services_retry_padding: usize = 4;

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
/// `extra_descriptor_padding` pads the allocation beyond what
/// `getMemoryMapInfo` reports needing, in bytes per descriptor: firmware
/// can grow the map between the info call and the actual `getMemoryMap`
/// call (any allocation can do it, including the one this function just
/// made), so a snug buffer can undersize by the time it's used. Pass 0 for
/// a one-off read; pass a nonzero pad when about to retry
/// `exitBootServices` (see `exitBootServices` below).
pub fn fetch(boot_services: *uefi.tables.BootServices, extra_descriptor_padding: usize) !MemoryMap {
    var info = boot_services.getMemoryMapInfo() catch |err| {
        log.err("getting memory map info failed: {s}", .{@errorName(err)});
        return err;
    };
    const buffer = boot_services.allocatePool(
        .boot_services_data,
        (info.descriptor_size + extra_descriptor_padding) * info.len,
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
            current.* = try fetch(boot_services, exit_boot_services_retry_padding);
            continue;
        };
        return;
    }
}

/// Remap `mm` for `runtime_services.setVirtualAddressMap` and install it.
///
/// In the kernel linker script, the kernel is linked to start at 1M
/// (0x100000), but the physical memory the loader actually found for it
/// doesn't have to be there -- so every `.loader_data` descriptor (the
/// region `loadSegment` in uefi/loader/segments.zig allocated the kernel
/// into) gets
/// remapped to `kernel_start_address` instead of identity-mapped like
/// everything else. Returns that region's physical start, which the caller
/// still needs separately as `kernel_phys_start`.
pub fn installVirtualAddressMap(
    runtime_services: *uefi.tables.RuntimeServices,
    mm: MemoryMap,
    kernel_start_address: u64,
) !u64 {
    var kernel_phys_start: u64 = undefined;
    var mem_index: usize = 0;
    while (mem_index < mm.info.len) : (mem_index += 1) {
        const mem_point: *uefi.tables.MemoryDescriptor = @ptrCast(@alignCast(mm.map.ptr + (mem_index * mm.info.descriptor_size)));
        if (mem_point.type == .loader_data) {
            mem_point.virtual_start = kernel_start_address;
            kernel_phys_start = mem_point.physical_start;
        } else {
            mem_point.virtual_start = mem_point.physical_start;
        }
    }
    try runtime_services.setVirtualAddressMap(mm.map);
    return kernel_phys_start;
}

/// Upper bound on how many regions `toGenericMemoryMap` can emit. Real and
/// virtualized UEFI firmware typically report well under 100 descriptors;
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
pub fn toGenericMemoryMap(mm: MemoryMap) []const MemoryRegion {
    var count: usize = 0;
    var index: usize = 0;
    while (index < mm.info.len and count < max_memory_regions) : (index += 1) {
        const d: *uefi.tables.MemoryDescriptor = @ptrCast(@alignCast(mm.map.ptr + index * mm.info.descriptor_size));
        memory_region_storage[count] = .{
            .phys_start = d.physical_start,
            .page_count = d.number_of_pages,
            .kind = switch (d.type) {
                .conventional_memory => .usable,
                .acpi_reclaim_memory => .acpi_reclaimable,
                .acpi_memory_nvs => .acpi_nvs,
                .boot_services_code, .boot_services_data => .bootloader_reclaimable,
                .loader_code, .loader_data => .kernel_and_modules,
                .memory_mapped_io, .memory_mapped_io_port_space => .mmio,
                .unusable_memory => .bad,
                else => .reserved,
            },
        };
        count += 1;
    }
    return memory_region_storage[0..count];
}
