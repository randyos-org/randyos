//! BMP file parsing.
//! Only uncompressed 24bpp (BI_RGB); else error.
//!
//! Decodes into `draw.PixelBuffer` (format-agnostic).

const std = @import("std");
const log = std.log.scoped(.bmp);

const Color = @import("color.zig").Color;
const PixelBuffer = @import("draw.zig").PixelBuffer;

pub const BmpError = std.mem.Allocator.Error || error{
    NotABmp,
    Unsupported,
    Truncated,
};

/// BI_RGB (uncompressed) -- only mode supported.
const bi_rgb_compression: u32 = 0;
/// Only bpp supported.
const supported_bits_per_pixel: u16 = 24;
/// Bytes per pixel (24bpp).
const bytes_per_pixel: usize = supported_bits_per_pixel / 8;
/// Row padding boundary.
const row_alignment: usize = 4;

/// BMP file header ("BITMAPFILEHEADER").
/// align(1): overlays raw file bytes, no padding.
const FileHeader = extern struct {
    magic: [2]u8 align(1),
    file_size: u32 align(1),
    _reserved: u32 align(1),
    pixel_data_offset: u32 align(1),
};

/// BMP info header ("BITMAPINFOHEADER"). V4/V5 add fields, but
/// pixel_data_offset (file header) locates pixels, so only these
/// common leading fields matter.
const InfoHeader = extern struct {
    header_size: u32 align(1),
    width: i32 align(1),
    height: i32 align(1),
    planes: u16 align(1),
    bits_per_pixel: u16 align(1),
    compression: u32 align(1),
    image_size: u32 align(1),
    x_pixels_per_meter: i32 align(1),
    y_pixels_per_meter: i32 align(1),
    colors_used: u32 align(1),
    colors_important: u32 align(1),
};

/// Decode uncompressed 24bpp BMP into a `PixelBuffer`. Caller owns/frees
/// the returned `pixels` slice. `bmp_data`: raw `.bmp` bytes.
pub fn parse(allocator: std.mem.Allocator, bmp_data: []const u8) BmpError!PixelBuffer {
    if (bmp_data.len < @sizeOf(FileHeader) + @sizeOf(InfoHeader)) return error.Truncated;
    const file_header: *const FileHeader = @ptrCast(bmp_data.ptr);
    if (!std.mem.eql(u8, &file_header.magic, "BM")) return error.NotABmp;

    const info_header: *const InfoHeader = @ptrCast(bmp_data.ptr + @sizeOf(FileHeader));
    if (info_header.compression != bi_rgb_compression) {
        log.err("BMP uses compression {} -- only uncompressed (BI_RGB) is supported", .{info_header.compression});
        return error.Unsupported;
    }
    if (info_header.bits_per_pixel != supported_bits_per_pixel) {
        log.err("BMP has {} bits per pixel -- only 24bpp color is supported", .{info_header.bits_per_pixel});
        return error.Unsupported;
    }

    const width: usize = @intCast(@abs(info_header.width));
    const height: usize = @intCast(@abs(info_header.height));
    // negative height = top-down; default is bottom-up
    const top_down = info_header.height < 0;
    // row padded to 4 bytes
    const row_size = std.mem.alignForward(usize, width * bytes_per_pixel, row_alignment);

    if (bmp_data.len < file_header.pixel_data_offset) return error.Truncated;
    const pixel_data = bmp_data[file_header.pixel_data_offset..];
    if (pixel_data.len < row_size * height) return error.Truncated;

    const pixels = try allocator.alloc(Color, width * height);
    for (0..height) |dst_row| {
        // PixelBuffer is top-down; BMP default is bottom-up
        const src_row = if (top_down) dst_row else height - 1 - dst_row;
        const row_bytes = pixel_data[src_row * row_size ..][0 .. width * bytes_per_pixel];
        for (0..width) |col| {
            // stored as B,G,R
            const px = row_bytes[col * bytes_per_pixel ..][0..bytes_per_pixel];
            pixels[dst_row * width + col] = .{ .blue = px[0], .green = px[1], .red = px[2] };
        }
    }

    return .{ .width = width, .height = height, .pixels = pixels };
}
