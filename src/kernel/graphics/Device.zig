const log = @import("std").log.scoped(.graphics_device);
const common = @import("common");
const boot_info = common.boot_info;

const color_mod = @import("color.zig");
const Color = color_mod.Color;
const PixelFormat = color_mod.PixelFormat;
const draw_mod = @import("draw.zig");
pub const drawRect = draw_mod.drawRect;
pub const drawBitmap = draw_mod.drawBitmap;

const Self = @This();

/// The pointer to the framebuffer
framebuffer_pointer: [*]volatile u32 = undefined,
/// Pixels per scan line
pixels_per_scanline: u32 = undefined,
/// Pixel format
pixel_format: PixelFormat = undefined,
/// Pixel width
pixel_width: u32 = undefined,
/// Pixel height
pixel_height: u32 = undefined,

pub fn init(self: *Self, boot_data: *boot_info.KernelBootInfo) void {
    log.debug("initializing graphics device", .{});
    self.framebuffer_pointer = boot_data.video_mode_info.framebuffer_pointer;
    self.pixels_per_scanline = boot_data.video_mode_info.pixels_per_scanline;
    self.pixel_format = switch (boot_data.video_mode_info.pixel_format) {
        0 => .rgb,
        1 => .bgr,
        else => @panic("wrong pixel format in video mode info!"),
    };
    self.pixel_width = boot_data.video_mode_info.horizontal_resolution;
    self.pixel_height = boot_data.video_mode_info.vertical_resolution;
}

pub fn getColorInt(self: *Self, color: Color) u32 {
    return color.getInt(self.pixel_format);
}
