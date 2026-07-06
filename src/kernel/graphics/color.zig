//! Graphics Functionality
//! 2024 by Samuel Fiedler

const log = @import("std").log.scoped(.graphics_color);
const common = @import("common");

/// Pixel formats
pub const PixelFormat = enum {
    /// Red, Green, Blue, Reserved
    rgb,
    /// Blue, Green, Red, Reserved
    bgr,
};

/// Color struct
pub const Color = struct {
    red: u8,
    green: u8,
    blue: u8,
    reserved: u8,

    /// Get the values of the color as u32
    pub fn getInt(self: Color, pxl_fmt: PixelFormat) u32 {
        const red: u32 = self.red;
        const green: u32 = self.green;
        const blue: u32 = self.blue;
        const reserved: u32 = self.reserved;
        switch (pxl_fmt) {
            .rgb => {
                // RedGreenBlueReserved8BitPerColor
                return red + (green << 8) + (blue << 16) + (reserved << 24);
            },
            .bgr => {
                // BlueGreenRedReserved8BitPerColor
                return blue + (green << 8) + (red << 16) + (reserved << 24);
            },
            // else => {
            //     // nothing
            //     log.err("pxl_fmt has an incorrect value; cannot access the screen safely!", .{});
            //     return 0;
            // },
        }
    }
};
