const std = @import("std");
const uefi = std.os.uefi;

// kernel booting video mode information type
pub const KernelVideoModeInfo = extern struct {
    framebuffer_pointer: *?*anyopaque,
    horizontal_resolution: u32,
    vertical_resolution: u32,
    pixels_per_scan_line: u32,
};

// kernel booting information type
pub const KernelInfo = extern struct {
    memory_map: *uefi.tables.MemoryDescriptor,
    memory_map_size: usize,
    memory_map_descriptor_size: usize,
    video_mode_info: KernelVideoModeInfo,
};
