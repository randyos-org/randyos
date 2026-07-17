const log = @import("std").log.scoped(.gfx_dev);

const common = @import("common");
const KernelBootInfo = common.boot_info.KernelBootInfo;

const kpa = @import("../mem/root.zig").kernel_page_allocator;

const color_mod = @import("color.zig");
const Color = color_mod.Color;
const PixelFormat = color_mod.PixelFormat;
const draw_mod = @import("draw.zig");
pub const drawRect = draw_mod.drawRect;
pub const drawBitmap = draw_mod.drawBitmap;
const BackBuffer = @import("buffer.zig");

const Self = @This();

framebuffer_pointer: [*]volatile u32 = undefined,
pixels_per_scanline: u32 = undefined,
pixel_format: PixelFormat = undefined,
pixel_width: u32 = undefined,
pixel_height: u32 = undefined,
/// Shadow of `framebuffer_pointer`. Once `initBackBuffer` allocates it
/// (not done by `init` -- see its doc), all drawing targets this instead
/// (see `buffer.zig`). Call presentSpan/presentAll to push to screen.
/// Until then, `drawTarget()` is what drawing goes through.
back_buffer: BackBuffer = .{},

pub fn init(self: *Self, boot_data: *KernelBootInfo) void {
    log.debug("initializing graphics device", .{});
    self.framebuffer_pointer = boot_data.video_mode_info.framebuffer_pointer;
    self.pixels_per_scanline = boot_data.video_mode_info.pixels_per_scanline;
    self.pixel_format = switch (boot_data.video_mode_info.pixel_format) {
        .rgb => .rgb,
        .bgr => .bgr,
    };
    self.pixel_width = boot_data.video_mode_info.horizontal_resolution;
    self.pixel_height = boot_data.video_mode_info.vertical_resolution;
    // back buffer deliberately not allocated here -- unsafe this early,
    // see drawTarget's doc
    log.debug("graphics device initialized", .{});
}

/// Allocate back buffer, switch drawing to it. Only safe once real paging
/// is active (see `drawTarget`). Seeds it from the current framebuffer so
/// nothing already on screen is lost/flickers.
pub fn initBackBuffer(self: *Self) void {
    self.back_buffer.init(kpa.allocator, self.pixels_per_scanline * self.pixel_height);
    const fb: []const u32 = @volatileCast(self.framebuffer_pointer[0..self.back_buffer.pixels.len]);
    @memcpy(self.back_buffer.pixels, fb);
}

pub fn getColorInt(self: *Self, color: Color) u32 {
    return color.getInt(self.pixel_format);
}

/// Where drawing targets: back buffer once `initBackBuffer` runs, else
/// the real framebuffer.
///
/// `Device.init` runs before `arch.platform.init` sets up kernel page
/// tables, so a panic during platform init still has a screen (see
/// `main.zig`). Can't allocate the back buffer that early:
/// `kernel_page_allocator` uses the firmware memory map, which may not
/// match the still-firmware page tables active at that point -- caused a
/// real fault once. Drawing straight to the framebuffer during this
/// window avoids that whole class of fault.
pub fn drawTarget(self: *Self) []u32 {
    if (self.back_buffer.pixels.len != 0) return self.back_buffer.pixels;
    return @volatileCast(self.framebuffer_pointer[0 .. self.pixels_per_scanline * self.pixel_height]);
}

/// Fill draw target with `color` and present. Back buffer isn't
/// guaranteed zeroed, so without this, drawn content sits on garbage
/// instead of the theme background.
pub fn clear(self: *Self, color: Color) void {
    @memset(self.drawTarget(), self.getColorInt(color));
    self.presentAll();
}

/// Bulk-copy back_buffer.pixels[start..end] (pixel indices) to the real
/// framebuffer. One sequential copy -- see `buffer.zig`. No-op before
/// `initBackBuffer`: drawing already went straight to the framebuffer.
pub fn presentSpan(self: *Self, start: usize, end: usize) void {
    if (self.back_buffer.pixels.len == 0) return;
    // only writer, never read back -- safe to drop volatile, lets
    // compiler vectorize the copy
    const fb: []u32 = @volatileCast(self.framebuffer_pointer[start..end]);
    @memcpy(fb, self.back_buffer.pixels[start..end]);
}

/// Present the entire back buffer.
pub fn presentAll(self: *Self) void {
    self.presentSpan(0, self.back_buffer.pixels.len);
}
