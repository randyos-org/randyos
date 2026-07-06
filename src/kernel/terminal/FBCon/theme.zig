//! Kernel Framebuffer Console: Color Themes
//! 2026 by Randy Eckman

const Color = @import("../../graphics/color.zig").Color;

/// The 8 "normal"/"bright" ANSI colors of a palette
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

/// The default foreground/background colors of the terminal
pub const PrimaryColors = struct {
    background: Color,
    foreground: Color,
};

/// The cursor colors
pub const CursorColors = struct {
    cursor: Color,
    text: Color,
};

/// The colors used when text is selected
pub const SelectionColors = struct {
    background: Color,
    text: Color,
};

/// A full terminal color theme (loosely modeled after the Alacritty color scheme layout)
pub const Theme = struct {
    primary: PrimaryColors,
    cursor: CursorColors,
    selection: SelectionColors,
    normal: Palette,
    bright: Palette,
};

/// Parse a single hex digit at comptime
fn hexNibble(comptime c: u8) u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => @compileError("invalid hex digit: \"" ++ [_]u8{c} ++ "\""),
    };
}

/// Parse a "#RRGGBB" hex color string into a `Color` at comptime
pub fn hex(comptime s: []const u8) Color {
    if (s.len != 7 or s[0] != '#') @compileError("expected \"#RRGGBB\" color string, got \"" ++ s ++ "\"");
    return .{
        .red = hexNibble(s[1]) << 4 | hexNibble(s[2]),
        .green = hexNibble(s[3]) << 4 | hexNibble(s[4]),
        .blue = hexNibble(s[5]) << 4 | hexNibble(s[6]),
        .reserved = 0x00,
    };
}

/// Built-in themes
pub const themes = struct {
    pub const material_dark = @import("themes/material_dark.zig").theme;
    pub const loup = @import("themes/loup.zig").theme;
};

/// The currently selected theme
var current: *const Theme = &themes.material_dark;

/// Get the currently selected theme
pub fn get() *const Theme {
    return current;
}

/// Select the active theme
pub fn set(theme: *const Theme) void {
    current = theme;
}
