const std = @import("std");
const uefi = std.os.uefi;
const epoch = std.time.epoch;
const log = std.log.scoped(.bootinfo);

const rstd = @import("rstd");
const KernelBootInfo = rstd.machine.KernelBootInfo;

pub const memory = @import("memory.zig");
pub const graphics = @import("graphics.zig");

/// Convert UEFI `Time` to Unix epoch seconds -- the firmware-neutral form
/// `KernelBootInfo` actually carries.
fn toEpochSeconds(t: uefi.Time) i64 {
    var days: i64 = 0;

    var year: epoch.Year = epoch.epoch_year;
    while (year < t.year) : (year += 1) {
        days += epoch.getDaysInYear(year);
    }

    var month: u4 = 1;
    while (month < t.month) : (month += 1) {
        days += epoch.getDaysInMonth(t.year, @enumFromInt(month));
    }
    days += t.day - 1;

    var secs: i64 = days * @as(i64, epoch.secs_per_day);
    secs += @as(i64, t.hour) * 3600 + @as(i64, t.minute) * 60 + t.second;
    if (t.timezone != uefi.Time.unspecified_timezone) {
        // timezone = minutes offset from UTC
        secs -= @as(i64, t.timezone) * 60;
    }
    return secs;
}

/// Store a pointer to `kbi` at `base_address` -- the kernel's
/// `__boot_info_ptr` slot -- so the kernel can find its boot info.
pub fn writeBootInfoPointer(base_address: u64, kbi: *const KernelBootInfo) void {
    const boot_info_ptr: *usize = @ptrFromInt(base_address);
    boot_info_ptr.* = @intFromPtr(kbi);
}

/// Fill in `kernel_boot_info` fields only known after the memory map
/// reaches its final post-`exitBootServices` shape: the firmware-neutral
/// memory map (kernel range carved out as `kernel_and_modules`, see
/// `memory.toGenericMemoryMap`) and wall-clock time.
///
/// `kernel_phys_start`/`kernel_size` are the kernel's final physical range
/// (known from the load plan).
pub fn finalizeKernelBootInfo(
    kbi: *KernelBootInfo,
    runtime_services: *uefi.tables.RuntimeServices,
    mm: memory.MemoryMap,
    kernel_phys_start: u64,
    kernel_size: u64,
) !void {
    kbi.kernel_phys_start = kernel_phys_start;
    try memory.installVirtualAddressMap(runtime_services, mm);
    kbi.memory_map = memory.toGenericMemoryMap(mm, kernel_phys_start, kernel_size);
    kbi.boot_wall_clock_unix_seconds = if (runtime_services.getTime()) |result|
        toEpochSeconds(result[0])
    else |err| blk: {
        log.warn("could not read wall-clock time from firmware: {s}", .{@errorName(err)});
        break :blk null;
    };

    // hand off raw Runtime Services ptr as opaque data; see
    // FirmwareRuntimeData in src/common/boot_info.zig. usage is up to a
    // future driver (src/drivers/uefi/__root__.zig), not this bootloader.
    kbi.fw_runtime_ptr = runtime_services;
}

/// Assemble `KernelBootInfo` minus the memory-map fields (filled in later,
/// post-`exitBootServices`).
pub fn buildKernelBootInfo(
    system_table: *uefi.tables.SystemTable,
    gfxinfo: graphics.GraphicsInfo,
    dwarf_info: *?std.debug.Dwarf,
) !KernelBootInfo {
    var kbi: KernelBootInfo = undefined;
    findAcpiTables(system_table, &kbi);
    kbi.video_mode_info.framebuffer_pointer = @as([*]volatile u32, @ptrFromInt(gfxinfo.output.mode.frame_buffer_base));
    kbi.video_mode_info.horizontal_resolution = gfxinfo.mode_info.horizontal_resolution;
    kbi.video_mode_info.vertical_resolution = gfxinfo.mode_info.vertical_resolution;
    kbi.video_mode_info.pixels_per_scanline = gfxinfo.mode_info.pixels_per_scan_line;
    kbi.video_mode_info.pixel_format = switch (gfxinfo.mode_info.pixel_format) {
        .red_green_blue_reserved_8_bit_per_color => .rgb,
        .blue_green_red_reserved_8_bit_per_color => .bgr,
        .bit_mask, .blt_only => |pf| {
            const err = error.UnsupportedPixelFormat;
            log.err("invalid pixel format: {t} ({t})", .{ pf, err });
            return err;
        },
    };
    kbi.dwarf_info = dwarf_info;
    return kbi;
}

/// Find the ACPI RSDP in the firmware's config table, record as
/// `kbi.hardware_description`. Checks both 1.0/2.0 GUIDs (2.0 wins if
/// both present); stays `null` if neither found.
fn findAcpiTables(system_table: *uefi.tables.SystemTable, kbi: *KernelBootInfo) void {
    var rsdp_10: ?*anyopaque = null;
    var rsdp_20: ?*anyopaque = null;
    for (0..system_table.number_of_table_entries) |index| {
        const entry = system_table.configuration_table[index];
        if (entry.vendor_guid.eql(uefi.tables.ConfigurationTable.acpi_10_table_guid)) {
            rsdp_10 = entry.vendor_table;
        }
        if (entry.vendor_guid.eql(uefi.tables.ConfigurationTable.acpi_20_table_guid)) {
            rsdp_20 = entry.vendor_table;
        }
    }
    const winner = rsdp_20 orelse rsdp_10;
    kbi.hardware_description = if (winner) |rsdp| rsdp else null;
}
