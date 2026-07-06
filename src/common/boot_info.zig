const std = @import("std");
const uefi = std.os.uefi;
const log = std.log.scoped(.boot_info);

/// Video Mode Info
pub const KernelBootVideoModeInfo = struct {
    framebuffer_pointer: [*]volatile u32,
    framebuffer_size: usize,
    horizontal_resolution: u32,
    vertical_resolution: u32,
    pixels_per_scanline: u32,
    pixel_format: u32,
};

// TODO(kernel portability): this struct is the contract *the kernel itself*
// (not just the bootloader) depends on -- main.zig takes a
// `*boot_info.KernelBootInfo` directly -- and it's hard-wired to UEFI types
// (`uefi.tables.MemoryMapSlice`/`MemoryMapInfo`/`RuntimeServices`). That's
// fine for x86_64 Mac/PC and Raspberry Pi 3/4 (all genuinely UEFI-booted),
// but Raspberry Pi 5 (see src/bootloader-rpi/), Apple Silicon Mac (see
// src/bootloader-asahi/), and powerpc (Open Firmware -- see
// src/bootloader-ofw/) won't be UEFI-booted at all, so whatever loads
// RandyOS on those either has to synthesize UEFI-shaped data it doesn't
// actually have, or (better) this struct needs to stop assuming UEFI is the
// only way a kernel ever gets handed its boot info. Not addressed here --
// revisit when a non-UEFI boot path is actually being built.
/// Kernel Boot Info
pub const KernelBootInfo = struct {
    map: uefi.tables.MemoryMapSlice,
    map_info: uefi.tables.MemoryMapInfo,
    video_mode_info: KernelBootVideoModeInfo,
    rsdp_10: ?*anyopaque,
    rsdp_20: ?*anyopaque,
    kernel_phys_start: usize,
    kernel_phys_end: usize,
    kernel_virt_start: usize,
    kernel_virt_end: usize,
    dwarf_info: *?std.debug.Dwarf,
    runtime_services: *uefi.tables.RuntimeServices,
};
