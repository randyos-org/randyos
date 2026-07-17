//! FBCon color themes
//! Loosely modeled on Alacritty's theme layout

const std = @import("std");
const log = std.log.scoped(.theme);

const Color = @import("../../gfx/color.zig").Color;

const Self = @This();

primary: PrimaryColors,
cursor: CursorColors,
selection: SelectionColors,
normal: Palette,
bright: Palette,

/// 8 normal/bright ANSI colors
pub const Palette = struct {
    black: Color,
    red: Color,
    green: Color,
    yellow: Color,
    blue: Color,
    magenta: Color,
    cyan: Color,
    white: Color,
};

/// default fg/bg colors
pub const PrimaryColors = struct {
    background: Color,
    foreground: Color,
};

pub const CursorColors = struct {
    cursor: Color,
    text: Color,
};

/// selection colors
pub const SelectionColors = struct {
    background: Color,
    text: Color,
};

/// parse one hex digit, comptime
fn hexNibble(comptime c: u8) u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => @compileError("invalid hex digit: \"" ++ [_]u8{c} ++ "\""),
    };
}

/// parse "#RRGGBB" into a Color, comptime
pub fn hex(comptime s: []const u8) Color {
    if (s.len != 7 or s[0] != '#') @compileError("expected \"#RRGGBB\" color string, got \"" ++ s ++ "\"");
    return .{
        .red = hexNibble(s[1]) << 4 | hexNibble(s[2]),
        .green = hexNibble(s[3]) << 4 | hexNibble(s[4]),
        .blue = hexNibble(s[5]) << 4 | hexNibble(s[6]),
    };
}

/// Built-in themes
pub const themes = struct {
    pub const material_dark = @import("material_dark.zig").theme;
    pub const loup = @import("loup.zig").theme;

    var current: *const Self = &material_dark;

    pub fn get_current() *const Self {
        return current;
    }

    pub fn set_current(theme: *const Self) void {
        current = theme;
    }
};

/// map ANSI color code to this theme's Color
pub fn colorFromANSI(self: *const Self, color_code: u32) Color {
    return switch (color_code) {
        30, 40 => self.normal.black,
        31, 41 => self.normal.red,
        32, 42 => self.normal.green,
        33, 43 => self.normal.yellow,
        34, 44 => self.normal.blue,
        35, 45 => self.normal.magenta,
        36, 46 => self.normal.cyan,
        37, 47 => self.normal.white,
        90, 100 => self.bright.black,
        91, 101 => self.bright.red,
        92, 102 => self.bright.green,
        93, 103 => self.bright.yellow,
        94, 104 => self.bright.blue,
        95, 105 => self.bright.magenta,
        96, 106 => self.bright.cyan,
        97, 107 => self.bright.white,
        else => self.normal.black,
    };
}
