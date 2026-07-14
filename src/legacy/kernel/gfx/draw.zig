const std = @import("std");
const log = std.log.scoped(.gfx_draw);

const Device = @import("Device.zig");
const Color = @import("color.zig").Color;

/// Draw a rect. Drawn into `dev.drawTarget()` -- the back buffer once
/// allocated, the real framebuffer directly before then (see that
/// function's doc comment) -- call `dev.presentSpan`/`presentAll` to make
/// it visible on screen (a no-op, pre-back-buffer, since a direct-target
/// draw is already visible immediately).
pub fn drawRect(dev: *Device, x: u16, y: u16, width: u16, height: u16, color: Color) void {
    const target = dev.drawTarget();
    // setup variables
    var row: u16 = 0;
    var col: u16 = 0;
    // iterate over each pixel to be drawn
    while (row < height) : ({
        row += 1;
        col = 0;
    }) {
        while (col < width) : (col += 1) {
            // main drawing logic
            var index: usize = x + col;
            // wrapping multiply: avoids an overflow panic in safety-checked
            // builds if a caller passes coordinates outside the framebuffer
            index += (y + row) *% dev.pixels_per_scanline;
            target[index] = color.getInt(dev.pixel_format);
        }
    }
}

/// A decoded, row-major (top-down, left-to-right) buffer of pixels --
/// generic over whatever format produced it (BMP, a future PNG decoder, a
/// solid fill, ...). `drawBitmap` only knows how to push this to the
/// framebuffer; it has no idea what file format, if any, it came from.
pub const PixelBuffer = struct {
    width: usize,
    height: usize,
    pixels: []const Color,
};

/// Blit a decoded pixel buffer to `dev.drawTarget()` (see `drawRect`'s doc
/// comment) with its top-left corner at `(x, y)`. Call
/// `dev.presentSpan`/`presentAll` to make it visible on screen.
pub fn drawBitmap(dev: *Device, x: u16, y: u16, image: PixelBuffer) void {
    const target = dev.drawTarget();
    for (0..image.height) |row| {
        for (0..image.width) |col| {
            // wrapping multiply: same defensive reasoning as drawRect, so
            // out-of-framebuffer coordinates wrap instead of panicking here
            const index = (x + col) + (y + row) *% dev.pixels_per_scanline;
            target[index] = dev.getColorInt(image.pixels[row * image.width + col]);
        }
    }
}
