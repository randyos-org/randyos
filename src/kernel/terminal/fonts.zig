//! Kernel Compiled-In Fonts
//! 2024 by Samuel Fiedler

pub const vga_8x16 = @import("fonts/vga_8x16.zig").font_vga_8x16;
pub const unicodeToCP437 = @import("fonts/charmap.zig").unicodeToCP437;

/// The Font Descriptor
pub const FontDesc = struct {
    name: []const u8,
    /// Glyph width in pixels (a u4, so at most 15)
    width: u4,
    /// Glyph height in pixels
    height: u8,
    /// Number of glyphs in `data`
    charcount: usize,
    /// Raw glyph bitmaps: `charcount * height` bytes, one byte per scanline
    /// row, MSB-first (bit 7 = leftmost pixel). See fonts/vga_8x16.zig for
    /// the reference layout.
    data: []const u8,
};
