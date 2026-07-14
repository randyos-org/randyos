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
/// Off-screen shadow of `framebuffer_pointer`. Once allocated (see
/// `initBackBuffer` -- NOT done by `init`, see its doc comment), all
/// drawing (`drawRect`, `drawBitmap`, and terminal backends like Ghostty)
/// targets this instead of the real framebuffer directly -- see
/// `buffer.zig` for why. Call `presentSpan`/`presentAll` to push what's
/// been drawn to the screen. Until then, `drawTarget()` is what every
/// drawing call actually goes through.
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
    // The back buffer is deliberately *not* allocated here -- see
    // `drawTarget`'s doc comment for why doing so this early is unsafe.
    log.debug("graphics device initialized", .{});
}

/// Allocate the back buffer and switch subsequent drawing over to it. Only
/// safe to call once real paging is active -- see `drawTarget`'s doc
/// comment. Copies whatever's currently on the real framebuffer (the boot
/// logo, any panic output from during platform init) in as the back
/// buffer's starting contents, so switching over doesn't lose or flicker
/// past what's already on screen.
pub fn initBackBuffer(self: *Self) void {
    self.back_buffer.init(kpa.allocator, self.pixels_per_scanline * self.pixel_height);
    const fb: []const u32 = @volatileCast(self.framebuffer_pointer[0..self.back_buffer.pixels.len]);
    @memcpy(self.back_buffer.pixels, fb);
}

pub fn getColorInt(self: *Self, color: Color) u32 {
    return color.getInt(self.pixel_format);
}

/// The buffer live drawing should target: the back buffer once
/// `initBackBuffer` has allocated it, or the real framebuffer directly
/// before then.
///
/// `Device.init` runs very early in `kmain` -- deliberately before
/// `arch.platform.init` sets up the kernel's own page tables, so that a
/// panic during platform init still has a working screen to report onto
/// (see `main.zig`). That ordering means the back buffer can't simply be
/// allocated up front: `kernel_page_allocator` hands out memory based on
/// the firmware-reported memory map, not on what's actually mapped in
/// whatever page tables are active at the time -- still the
/// bootloader/firmware's, this early -- and the two don't necessarily
/// agree. Confirmed by a real fault from exactly this (allocating the back
/// buffer during `init`, before paging was safely up, hands back memory
/// the active page tables don't cover). Drawing straight to the real
/// framebuffer for this narrow bootstrap window avoids allocating -- and
/// therefore that whole class of fault -- entirely.
pub fn drawTarget(self: *Self) []u32 {
    if (self.back_buffer.pixels.len != 0) return self.back_buffer.pixels;
    return @volatileCast(self.framebuffer_pointer[0 .. self.pixels_per_scanline * self.pixel_height]);
}

/// Fill the entire draw target (see `drawTarget`) with `color` and present
/// it. The back buffer's backing allocation (see `back_buffer.init`) isn't
/// guaranteed to start zeroed -- it's ordinary heap memory that may hold
/// whatever the allocator's backing pages last contained -- so without an
/// explicit clear like this, anything drawn on top (e.g. the boot logo)
/// sits on top of leftover garbage instead of the theme's background
/// color.
pub fn clear(self: *Self, color: Color) void {
    @memset(self.drawTarget(), self.getColorInt(color));
    self.presentAll();
}

/// Bulk-copy `back_buffer.pixels[start..end]` (pixel indices, not byte
/// offsets) to the real framebuffer at the same offsets. One sequential
/// copy regardless of how many individual pixels changed within the span
/// -- see `buffer.zig` for why that matters. A no-op before
/// `initBackBuffer` has run: drawing already went straight to the real
/// framebuffer (see `drawTarget`), so there's nothing buffered to present.
pub fn presentSpan(self: *Self, start: usize, end: usize) void {
    if (self.back_buffer.pixels.len == 0) return;
    // We're the only writer to the real framebuffer and never read it
    // back, so casting away `volatile` for this one bulk op is safe and
    // lets the compiler vectorize/widen the copy.
    const fb: []u32 = @volatileCast(self.framebuffer_pointer[start..end]);
    @memcpy(fb, self.back_buffer.pixels[start..end]);
}

/// Present the entire back buffer.
pub fn presentAll(self: *Self) void {
    self.presentSpan(0, self.back_buffer.pixels.len);
}
