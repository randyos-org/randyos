const std = @import("std");
const log = std.log.scoped(.gfx_draw);

const Device = @import("Device.zig");
const Color = @import("color.zig").Color;

/// Draw a rect into `dev.drawTarget()`. Call presentSpan/presentAll to
/// show it (no-op pre-back-buffer, already visible immediately then).
pub fn drawRect(dev: *Device, x: u16, y: u16, width: u16, height: u16, color: Color) void {
    const target = dev.drawTarget();
    var row: u16 = 0;
    var col: u16 = 0;
    while (row < height) : ({
        row += 1;
        col = 0;
    }) {
        while (col < width) : (col += 1) {
            var index: usize = x + col;
            // wrapping multiply: avoid overflow panic on out-of-bounds coords
            index += (y + row) *% dev.pixels_per_scanline;
            target[index] = color.getInt(dev.pixel_format);
        }
    }
}

/// Decoded, row-major (top-down, left-to-right) pixels, format-agnostic
/// (BMP, future PNG, solid fill, ...).
pub const PixelBuffer = struct {
    width: usize,
    height: usize,
    pixels: []const Color,
};

/// Blit pixel buffer to `dev.drawTarget()`, top-left at (x, y). Call
/// presentSpan/presentAll to show it.
pub fn drawBitmap(dev: *Device, x: u16, y: u16, image: PixelBuffer) void {
    const target = dev.drawTarget();
    for (0..image.height) |row| {
        for (0..image.width) |col| {
            // wrapping multiply: same as drawRect, avoid panic on bad coords
            const index = (x + col) + (y + row) *% dev.pixels_per_scanline;
            target[index] = dev.getColorInt(image.pixels[row * image.width + col]);
        }
    }
}
