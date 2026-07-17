//! Transforms on decoded `draw.PixelBuffer`s (scaling, etc). Format-agnostic.

const std = @import("std");
const log = std.log.scoped(.gfx_xform);

const PixelBuffer = @import("draw.zig").PixelBuffer;
const Color = @import("color.zig").Color;

/// Largest (width, height) fitting max_width x max_height, aspect
/// preserved.
pub fn fitDimensions(
    src_width: usize,
    src_height: usize,
    max_width: usize,
    max_height: usize,
) struct { width: usize, height: usize } {
    // try full width first; if height fits too, done. else height binds.
    const height_at_max_width = @max(1, src_height * max_width / src_width);
    if (height_at_max_width <= max_height) {
        return .{ .width = max_width, .height = height_at_max_width };
    }
    const width_at_max_height = @max(1, src_width * max_height / src_height);
    return .{ .width = width_at_max_height, .height = max_height };
}

/// Resize src to dst_width x dst_height via box-filter averaging.
/// For downscaling; one-time boot op, not optimized for speed.
///
/// Caller owns/frees the returned `pixels` slice.
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
            };
        }
    }

    return .{ .width = dst_width, .height = dst_height, .pixels = pixels };
}
