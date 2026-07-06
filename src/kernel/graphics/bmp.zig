//! BMP (Windows Bitmap) file parsing.
//! Only supports the common uncompressed (BI_RGB), 24-bit-per-pixel case --
//! that covers the vast majority of BMP files in the wild and keeps this
//! simple; anything else is reported as an error rather than guessed at.
//!
//! Decodes into a `draw.PixelBuffer`, which is format-agnostic -- `draw.zig`
//! doesn't know or care that the source was a BMP.

const std = @import("std");
const log = std.log.scoped(.graphics_bmp);

const Color = @import("color.zig").Color;
const PixelBuffer = @import("draw.zig").PixelBuffer;

pub const BmpError = std.mem.Allocator.Error || error{
    NotABmp,
    Unsupported,
    Truncated,
};

/// BMP file header ("BITMAPFILEHEADER").
/// Every field is `align(1)` because this overlays raw file bytes directly
/// -- there is no compiler-inserted padding to match.
const FileHeader = extern struct {
    magic: [2]u8 align(1),
    file_size: u32 align(1),
    _reserved: u32 align(1),
    pixel_data_offset: u32 align(1),
};

/// BMP bitmap info header ("BITMAPINFOHEADER"). Later BMP variants
/// (V4/V5) extend this with more fields, but `pixel_data_offset` from the
/// file header is what actually locates the pixel data, so only these
/// leading fields (common to every variant) need to be read.
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

/// Parse and fully decode an uncompressed (`BI_RGB`), 24-bit color BMP file
/// into a `PixelBuffer`. The returned buffer's `pixels` slice is allocated
/// from `allocator`; the caller owns it and is responsible for freeing it.
/// `bmp_data` is the raw contents of a `.bmp` file, e.g. from `@embedFile`.
pub fn parse(allocator: std.mem.Allocator, bmp_data: []const u8) BmpError!PixelBuffer {
    if (bmp_data.len < @sizeOf(FileHeader) + @sizeOf(InfoHeader)) return error.Truncated;
    const file_header: *const FileHeader = @ptrCast(bmp_data.ptr);
    if (!std.mem.eql(u8, &file_header.magic, "BM")) return error.NotABmp;

    const info_header: *const InfoHeader = @ptrCast(bmp_data.ptr + @sizeOf(FileHeader));
    if (info_header.compression != 0) {
        log.err("BMP uses compression {} -- only uncompressed (BI_RGB) is supported", .{info_header.compression});
        return error.Unsupported;
    }
    if (info_header.bits_per_pixel != 24) {
        log.err("BMP has {} bits per pixel -- only 24bpp color is supported", .{info_header.bits_per_pixel});
        return error.Unsupported;
    }

    const width: usize = @intCast(@abs(info_header.width));
    const height: usize = @intCast(@abs(info_header.height));
    // A negative height means the rows are stored top-down; BMP's default
    // (positive height) is bottom-up.
    const top_down = info_header.height < 0;
    // Each row is padded to a 4 byte boundary.
    const row_size = std.mem.alignForward(usize, width * 3, 4);

    if (bmp_data.len < file_header.pixel_data_offset) return error.Truncated;
    const pixel_data = bmp_data[file_header.pixel_data_offset..];
    if (pixel_data.len < row_size * height) return error.Truncated;

    const pixels = try allocator.alloc(Color, width * height);
    for (0..height) |dst_row| {
        // `PixelBuffer` is top-down; BMP's default row order is bottom-up.
        const src_row = if (top_down) dst_row else height - 1 - dst_row;
        const row_bytes = pixel_data[src_row * row_size ..][0 .. width * 3];
        for (0..width) |col| {
            // BMP pixel data is stored blue, green, red.
            const px = row_bytes[col * 3 ..][0..3];
            pixels[dst_row * width + col] = .{ .blue = px[0], .green = px[1], .red = px[2], .reserved = 0 };
        }
    }

    return .{ .width = width, .height = height, .pixels = pixels };
}
