//! Transformations on decoded `draw.PixelBuffer`s (scaling, and anywhere
//! else this grows to). Operates purely on already-decoded pixel data, so
//! it doesn't care whether the source was a BMP, a future PNG decoder, or
//! anything else.

const std = @import("std");

const PixelBuffer = @import("draw.zig").PixelBuffer;
const Color = @import("color.zig").Color;

/// The largest `(width, height)` that fits within `max_width` x
/// `max_height` while preserving the aspect ratio of a `src_width` x
/// `src_height` source image.
pub fn fitDimensions(
    src_width: usize,
    src_height: usize,
    max_width: usize,
    max_height: usize,
) struct { width: usize, height: usize } {
    // Try scaling to the full available width first; if the resulting
    // height fits too, that's the answer. Otherwise the height is the
    // binding constraint instead.
    const height_at_max_width = @max(1, src_height * max_width / src_width);
    if (height_at_max_width <= max_height) {
        return .{ .width = max_width, .height = height_at_max_width };
    }
    const width_at_max_height = @max(1, src_width * max_height / src_height);
    return .{ .width = width_at_max_height, .height = max_height };
}

/// Resize `src` to exactly `dst_width` x `dst_height` using box-filter
/// averaging: each destination pixel is the average of every source pixel
/// that falls within its footprint. Intended for downscaling (e.g. a large
/// embedded logo down to the current display resolution); this is a
/// one-time boot-time operation, not something written for speed.
///
/// The returned buffer's `pixels` slice is allocated from `allocator`; the
/// caller owns it and is responsible for freeing it.
pub fn resize(
    allocator: std.mem.Allocator,
    src: PixelBuffer,
    dst_width: usize,
    dst_height: usize,
) std.mem.Allocator.Error!PixelBuffer {
    const pixels = try allocator.alloc(Color, dst_width * dst_height);

    for (0..dst_height) |dst_y| {
        const src_y0 = dst_y * src.height / dst_height;
        const src_y1 = @max(src_y0 + 1, (dst_y + 1) * src.height / dst_height);
        for (0..dst_width) |dst_x| {
            const src_x0 = dst_x * src.width / dst_width;
            const src_x1 = @max(src_x0 + 1, (dst_x + 1) * src.width / dst_width);

            var r_sum: usize = 0;
            var g_sum: usize = 0;
            var b_sum: usize = 0;
            var count: usize = 0;
            for (src_y0..src_y1) |sy| {
                const row = src.pixels[sy * src.width ..][0..src.width];
                for (row[src_x0..src_x1]) |p| {
                    r_sum += p.red;
                    g_sum += p.green;
                    b_sum += p.blue;
                    count += 1;
                }
            }
            pixels[dst_y * dst_width + dst_x] = .{
                .red = @intCast(r_sum / count),
                .green = @intCast(g_sum / count),
                .blue = @intCast(b_sum / count),
                .reserved = 0,
            };
        }
    }

    return .{ .width = dst_width, .height = dst_height, .pixels = pixels };
}
