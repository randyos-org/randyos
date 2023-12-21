//! The Kernel Boot Info structures
//! 2023 by Samuel Fiedler

const std = @import("std");
const uefi = std.os.uefi;

/// Video Mode Info
pub const KernelBootVideoModeInfo = extern struct {
    framebuffer_pointer: *anyopaque,
    horizontal_resolution: u32,
    vertical_resolution: u32,
    pixels_per_scanline: u32,
};

/// Kernel Boot Info
pub const KernelBootInfo = extern struct {
    memory_map: *uefi.tables.MemoryDescriptor,
    memory_map_size: usize,
    memory_map_descriptor_size: usize,
    video_mode_info: KernelBootVideoModeInfo,
};
