const std = @import("std");
const log = std.log.scoped(.common_boot_info);

/// Firmware-neutral classification of a physical memory region, as reported
/// by whatever firmware/bootloader actually handed the kernel its boot
/// info -- the kernel only ever sees this shape, never a raw
/// firmware-native memory map format.
pub const MemoryRegionKind = enum {
    usable,
    reserved,
    acpi_reclaimable,
    acpi_nvs,
    bootloader_reclaimable,
    kernel_and_modules,
    mmio,
    bad,
};

/// A single physical memory region, in firmware-neutral form.
pub const MemoryRegion = struct {
    phys_start: u64,
    page_count: u64,
    kind: MemoryRegionKind,
};

/// Framebuffer pixel channel order, in firmware-neutral form.
pub const FramebufferPixelFormat = enum {
    /// Red, Green, Blue, Reserved
    rgb,
    /// Blue, Green, Red, Reserved
    bgr,
};

/// Video Mode Info
pub const KernelBootVideoModeInfo = struct {
    framebuffer_pointer: [*]volatile u32,
    framebuffer_size: usize,
    horizontal_resolution: u32,
    vertical_resolution: u32,
    pixels_per_scanline: u32,
    pixel_format: FramebufferPixelFormat,
};

/// Kernel Boot Info
pub const KernelBootInfo = struct {
    memory_map: []const MemoryRegion,
    video_mode_info: KernelBootVideoModeInfo,
    rsdp_10: ?*anyopaque,
    rsdp_20: ?*anyopaque,
    kernel_phys_start: usize,
    kernel_phys_end: usize,
    kernel_virt_start: usize,
    kernel_virt_end: usize,
    dwarf_info: *?std.debug.Dwarf,
    /// Unix epoch seconds at boot, as reported by firmware. `null` if the
    /// bootloader couldn't determine a wall-clock time.
    boot_wall_clock_unix_seconds: ?i64,
};
