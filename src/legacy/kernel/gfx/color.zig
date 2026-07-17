//! Graphics Functionality
//! 2024 by Samuel Fiedler

const log = @import("std").log.scoped(.color);
const common = @import("common");

/// Pixel formats
pub const PixelFormat = enum {
    /// R,G,B,Reserved
    rgb,
    /// B,G,R,Reserved
    bgr,
};

pub const Color = struct {
    red: u8 = 0,
    green: u8 = 0,
    blue: u8 = 0,
    _align: u8 = 0,

    /// pack as u32 per format
    pub fn getInt(self: Color, pxl_fmt: PixelFormat) u32 {
        const red: u32 = self.red;
        const green: u32 = self.green;
        const blue: u32 = self.blue;
        const _align: u32 = self._align;
        switch (pxl_fmt) {
            .rgb => {
                // RGB order
                return red + (green << 8) + (blue << 16) + (_align << 24);
            },
            .bgr => {
                // BGR order
                return blue + (green << 8) + (red << 16) + (_align << 24);
            },
            // else => {
            //     // nothing
            //     log.err("pxl_fmt has an incorrect value; cannot access the screen safely!", .{});
            //     return 0;
            // },
        }
    }
};
