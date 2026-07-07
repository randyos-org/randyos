const std = @import("std");
const uefi = std.os.uefi;
const log = std.log.scoped(.bootinfo);

const common = @import("common");
const KernelBootInfo = common.boot_info.KernelBootInfo;

pub const memory = @import("memory.zig");
pub const graphics = @import("graphics.zig");

/// Store a pointer to `kbi` at `base_address` -- the kernel's
/// `__boot_info_ptr` slot, at the very start of the loaded image -- so
/// the kernel can find its boot info as soon as it starts running.
pub fn writeBootInfoPointer(base_address: u64, kbi: *const KernelBootInfo) void {
    const boot_info_ptr: *usize = @ptrFromInt(base_address);
    boot_info_ptr.* = @intFromPtr(kbi);
}

/// Fill in the `kernel_boot_info` fields that aren't known until after the
/// memory map has reached its final post-`exitBootServices` shape:
/// `kernel_phys_start` (returned by `installVirtualAddressMap` once it's
/// remapped the kernel's region) and the map/runtime-services handles
/// themselves.
pub fn finalizeKernelBootInfo(
    kbi: *KernelBootInfo,
    runtime_services: *uefi.tables.RuntimeServices,
    mm: memory.MemoryMap,
    kernel_start_address: u64,
) !void {
    kbi.kernel_phys_start = try memory.installVirtualAddressMap(runtime_services, mm, kernel_start_address);
    kbi.map = mm.map;
    kbi.map_info = mm.info;
    kbi.runtime_services = runtime_services;
}

/// Assemble the `KernelBootInfo` the kernel expects at its
/// `__boot_info_ptr` slot, minus the memory-map fields (filled in later,
/// once the map is in its final post-`exitBootServices` shape).
pub fn buildKernelBootInfo(
    system_table: *uefi.tables.SystemTable,
    gfxinfo: graphics.GraphicsInfo,
    dwarf_info: *?std.debug.Dwarf,
) KernelBootInfo {
    var kbi: KernelBootInfo = undefined;
    findAcpiTables(system_table, &kbi);
    kbi.video_mode_info.framebuffer_pointer = @as([*]volatile u32, @ptrFromInt(gfxinfo.output.mode.frame_buffer_base));
    kbi.video_mode_info.horizontal_resolution = gfxinfo.mode_info.horizontal_resolution;
    kbi.video_mode_info.vertical_resolution = gfxinfo.mode_info.vertical_resolution;
    kbi.video_mode_info.pixels_per_scanline = gfxinfo.mode_info.pixels_per_scan_line;
    kbi.video_mode_info.pixel_format = @intFromEnum(gfxinfo.mode_info.pixel_format);
    kbi.dwarf_info = dwarf_info;
    return kbi;
}

/// Record both ACPI RSDP GUIDs present in the firmware's configuration
/// table. Both are checked (rather than just the newer one) since
/// ACPI-1.0-only firmware won't publish the 2.0 GUID at all, and it's the
/// kernel that decides which version to trust.
fn findAcpiTables(system_table: *uefi.tables.SystemTable, kbi: *KernelBootInfo) void {
    for (0..system_table.number_of_table_entries) |index| {
        const entry = system_table.configuration_table[index];
        if (entry.vendor_guid.eql(uefi.tables.ConfigurationTable.acpi_10_table_guid)) {
            kbi.rsdp_10 = entry.vendor_table;
        }
        if (entry.vendor_guid.eql(uefi.tables.ConfigurationTable.acpi_20_table_guid)) {
            kbi.rsdp_20 = entry.vendor_table;
        }
    }
}
