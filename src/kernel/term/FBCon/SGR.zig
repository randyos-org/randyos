//! Kernel Framebuffer Console: Control Sequence "Select Graphic Rendition"
//! 2024 by Samuel Fiedler

const log = @import("std").log.scoped(.fbcon_sgr);

const FBCon = @import("../FBCon.zig");
const Color = @import("../../gfx/color.zig").Color;
const theme = @import("theme.zig");

/// Create a Color from the ANSI color code, using the currently selected theme
pub fn colorFromANSI(color_code: u32) Color {
    const t = theme.get();
    return switch (color_code) {
        30, 40 => t.normal.black,
        31, 41 => t.normal.red,
        32, 42 => t.normal.green,
        33, 43 => t.normal.yellow,
        34, 44 => t.normal.blue,
        35, 45 => t.normal.magenta,
        36, 46 => t.normal.cyan,
        37, 47 => t.normal.white,
        90, 100 => t.bright.black,
        91, 101 => t.bright.red,
        92, 102 => t.bright.green,
        93, 103 => t.bright.yellow,
        94, 104 => t.bright.blue,
        95, 105 => t.bright.magenta,
        96, 106 => t.bright.cyan,
        97, 107 => t.bright.white,
        else => t.normal.black,
    };
}

/// Select Graphic Rendition
pub fn selectGraphicRendition(self: *FBCon, control_sequence: FBCon.ControlSequence) void {
    var len: usize = 0;
    const pxfmt = self.gd.pixel_format;
    // args are packed contiguously from index 0 -- the first null marks the
    // end, so this just counts how many were actually supplied.
    for (control_sequence.args) |arg| {
        if (arg) |_| {
            len += 1;
        } else {
            break;
        }
    }
    // ANSI defaults a bare `ESC[m` (no explicit parameters) to SGR 0
    // (reset), same as `ESC[0m`.
    const default_args = [1]?FBCon.ControlSequenceArgument{.{ .number = 0 }};
    const args = if (len == 0) default_args[0..] else control_sequence.args[0..len];
    for (args) |arg| {
        switch (arg orelse unreachable) {
            .number => |num| {
                switch (num) {
                    0 => {
                        const primary = theme.get().primary;
                        self.setColor(primary.foreground, primary.background);
                        self.graphical_features.bold = false;
                        self.graphical_features.underline = false;
                        self.graphical_features.reversed = false;
                        self.graphical_features.invisible = false;
                    },
                    1 => {
                        self.graphical_features.bold = true;
                    },
                    4 => {
                        self.graphical_features.underline = true;
                    },
                    5 => {
                        // no blinking support
                    },
                    7 => {
                        self.graphical_features.reversed = true;
                    },
                    8 => {
                        self.graphical_features.invisible = true;
                    },
                    22 => {
                        self.graphical_features.bold = false;
                    },
                    24 => {
                        self.graphical_features.underline = false;
                    },
                    25 => {
                        // no blinking support
                    },
                    27 => {
                        self.graphical_features.reversed = false;
                    },
                    28 => {
                        self.graphical_features.invisible = false;
                    },
                    30...37, 90...97 => {
                        self.color_int = colorFromANSI(num).getInt(pxfmt);
                    },
                    40...47, 100...107 => {
                        self.bgcolor_int = colorFromANSI(num).getInt(pxfmt);
                    },
                    else => {
                        // TODO support 256color
                        // TODO support truecolor
                        log.warn("Unknown control sequence argument, skipping", .{});
                        break;
                    },
                }
            },
            else => log.warn("Unknown control sequence argument type, skipping", .{}),
        }
    }
}
