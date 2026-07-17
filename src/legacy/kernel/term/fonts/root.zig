//! Kernel Compiled-In Fonts
//! 2024 by Samuel Fiedler

const std = @import("std");
const log = std.log.scoped(.term_fonts);

pub const vga_8x16 = @import("vga_8x16.zig").font_vga_8x16;
pub const unicodeToCP437 = @import("charmap.zig").unicodeToCP437;

pub const FontDesc = struct {
    name: []const u8,
    /// glyph width in px (u4, max 15)
    width: u4,
    /// glyph height in px
    height: u8,
    /// glyph count in `data`
    charcount: usize,
    /// glyph bitmaps: charcount*height bytes, 1 byte/row, MSB-first.
    /// see vga_8x16.zig for reference layout
    data: []const u8,
};
