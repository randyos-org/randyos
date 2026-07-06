//! The Framebuffer Console
//! 2024 by Samuel Fiedler

const std = @import("std");
const log = std.log.scoped(.term_fbcon);

const common = @import("common");
const Terminal = common.Terminal;
const boot_info = common.boot_info;

const fonts = @import("fonts.zig");
const Color = @import("../graphics/color.zig").Color;
const GraphicsDev = @import("../graphics/Device.zig");
pub const selectGraphicRendition = @import("FBCon/SGR.zig").selectGraphicRendition;
pub const colorFromANSI = @import("FBCon/SGR.zig").colorFromANSI;
pub const eraseInDisplay = @import("FBCon/DECSED.zig").eraseInDisplay;
pub const theme = @import("FBCon/theme.zig");

const CursorPosition = struct {
    column: usize,
    row: usize,
};

pub const StateValue = struct {
    index: u8,
    values: [8]u8,
};

/// The State of the Special Character "parser"
pub const State = union(enum) {
    /// Currently no control sequence detected
    none,
    /// Escape char (could be a control sequence)
    escape_statement,
    /// Escape char AND "[" (CSI)
    control_sequence_start,
    /// Control Sequence Value
    control_sequence_value: StateValue,
    /// Control Sequence Value Delimiter
    control_sequence_delimiter,
    /// Control Sequence Final
    control_sequence_command,
};

/// The control sequence type
pub const ControlSequence = struct {
    /// The control sequence "command" (final byte)
    command: u8,
    /// The control sequence "command" args
    args: [8]?ControlSequenceArgument,
    /// The control sequence "command" arg index
    index: usize,
    /// Indicator whether the control sequence is ready to be executed or not
    ready_for_exec: bool,
};

/// The control sequence argument union
pub const ControlSequenceArgument = union(enum) {
    char: u8,
    number: u32,
};

/// The graphical features supported by the framebuffer console
/// No italic because VT510 does not do that (see https://vt100.net/docs/vt510-rm/chapter4.html#S4.6)
pub const GraphicalFeatures = struct {
    /// Bold
    bold: bool,
    /// Underline
    underline: bool,
    /// Reverse (bg and fg are exchanged)
    reversed: bool,
    /// Invisible (text will not be printed out)
    invisible: bool,
};

const Self = @This();
// according to wikipedia, control sequences can have a maximum number of 5 args
// we make maximum 8 args, just in case
var control_sequence_arg_buffer: [8]u32 = undefined;

/// The pointer to the graphics device
gd: *GraphicsDev = undefined,
/// ANSI Escape Code Parser State
state: State = .none,
/// ANSI Escape Command
control_sequence: ControlSequence = undefined,
/// Current output color (foreground)
color_int: u32 = 0xffffffff,
/// Current output color (background)
bgcolor_int: u32 = 0,
/// Current Font
font: fonts.FontDesc = fonts.vga_8x16,
/// Current Cursor Position
curpos: CursorPosition = CursorPosition{
    .column = 0,
    .row = 0,
},
/// Maximal width, in character columns (not pixels)
max_width: u32 = 80,
/// Maximal height, in character rows (not pixels)
max_height: u32 = 25,
/// Graphical Features
graphical_features: GraphicalFeatures = .{
    .bold = false,
    .underline = false,
    .reversed = false,
    .invisible = false,
},
term: Terminal = undefined,
term_vtable: Terminal.VTable = undefined,

/// Setup the Framebuffer Console
/// `clear`: whether to clear the screen immediately. Pass `false` to bring
/// up the terminal (and its logging plumbing) without disturbing whatever
/// is already on screen (e.g. a boot logo) -- call `clearScreen()`
/// explicitly later to switch over.
pub fn init(self: *Self, gd: *GraphicsDev, clear: bool) void {
    self.gd = gd;
    self.state = .none;
    self.control_sequence = .{
        .command = undefined,
        .args = .{ null, null, null, null, null, null, null, null },
        .index = 0,
        .ready_for_exec = false,
    };
    self.font = fonts.vga_8x16;
    self.curpos.column = 0;
    self.curpos.row = 0;
    self.updateDimensions();
    self.graphical_features = .{
        .bold = false,
        .underline = false,
        .reversed = false,
        .invisible = false,
    };
    if (clear) self.clearScreen();
    const primary = theme.get().primary;
    self.setColor(primary.foreground, primary.background);
    self.term_vtable = .{
        .puts = &fbconTermPuts,
        .cls = &fbconTermCls,
    };
    self.term = Terminal{
        .vtable = &self.term_vtable,
        .supports_color = true,
    };
    self.term.init(.{});
}

/// Clear the Screen (effectively set the color of everything to the theme's
/// background color) and home the cursor to (0, 0)
pub fn clearScreen(self: *Self) void {
    const gd = self.gd;
    const total_size: usize = gd.pixels_per_scanline * gd.pixel_height;
    const bg_int = theme.get().primary.background.getInt(gd.pixel_format);
    // The framebuffer pointer is `volatile` so scattered single-pixel writes
    // elsewhere (drawChar, drawRect) aren't eliminated as dead stores, but
    // that same qualifier stops the compiler from vectorizing this bulk
    // fill. We're the only writer and no read-back matters here, so cast it
    // away just for this one bulk op.
    const fb: []u32 = @volatileCast(gd.framebuffer_pointer[0..total_size]);
    @memset(fb, bg_int);
    self.curpos.column = 0;
    self.curpos.row = 0;
}

/// Draw a single character (CP437). `x`/`y` are character-cell (column/row)
/// coordinates, not pixel coordinates -- they get multiplied by the font
/// size below to find the actual pixel origin.
pub fn drawChar(self: *Self, char_index: u8, x: usize, y: usize) void {
    const width = self.font.width;
    const height = self.font.height;
    const gd = self.gd;
    const px_per_scanline = gd.pixels_per_scanline;
    const fb = gd.framebuffer_pointer;
    const char_start: usize = char_index * @as(usize, height);
    const base_index: usize = x * @as(usize, width) + (y * @as(usize, height)) *% px_per_scanline;
    var col: u4 = 0;
    var row: u8 = 0;
    var bgcolor: u32 = self.bgcolor_int;
    var color: u32 = self.color_int;
    // main rendering logic
    if (self.graphical_features.reversed == true) {
        bgcolor = self.color_int;
        color = self.bgcolor_int;
    }
    if (self.graphical_features.invisible == true) {
        // Hidden text still occupies a cell -- paint it as a plain background
        // rect instead of skipping the draw entirely, so it doesn't leave
        // the previous glyph's pixels on screen.
        while (row < height) : ({
            row += 1;
            col = 0;
        }) {
            while (col < width) : (col += 1) {
                const index: usize = base_index + col + row *% px_per_scanline;
                fb[index] = bgcolor;
            }
        }
        return;
    }
    while (row < height) : ({
        row += 1;
        col = 0;
    }) {
        while (col < width) : (col += 1) {
            var index: usize = base_index + col;
            index += row *% px_per_scanline;
            // Glyph rows are MSB-first (bit 7 = leftmost pixel), so column
            // `col` (0 = leftmost) lives at bit `width - 1 - col`.
            const value = self.font.data[char_start + row] & @as(u16, 1) << (width - 1 - col);
            fb[index] = if (value == 0) bgcolor else color;
        }
    }
    // graphical features
    if (self.graphical_features.bold == true) {
        // bold: OR 1pxl to left
        row = 0;
        col = 0;
        while (row < height) : ({
            row += 1;
            col = 0;
        }) {
            while (col < width) : (col += 1) {
                const col_left: u4 = if (col == 0) 0 else col - 1;
                const index: usize = base_index + col + row *% px_per_scanline;
                const value_left = self.font.data[char_start + row] & @as(u16, 1) << (width - 1 - col_left);
                if (value_left != 0) fb[index] = color;
            }
        }
    }
    if (self.graphical_features.underline == true) {
        // underline: OR 1pxl with height/8 pxls offset from bottom
        row = height - @divFloor(height, 8);
        col = 0;
        while (col < width) : (col += 1) {
            const index: usize = base_index + col + row *% px_per_scanline;
            fb[index] = color;
        }
    }
}

/// Set font
pub fn setFont(self: *Self, new_font: fonts.FontDesc) void {
    self.font = new_font;
    self.updateDimensions();
}

/// Recompute `max_width`/`max_height` (in character cells) to fill the
/// screen at the current font size, based on the graphics device's
/// resolution. Any leftover pixels that don't make up a full cell (the
/// screen dimensions need not be an exact multiple of the font size) are
/// left blank at the right/bottom edge, same as most terminal emulators.
fn updateDimensions(self: *Self) void {
    self.max_width = @divTrunc(self.gd.pixel_width, @as(u32, self.font.width));
    self.max_height = @divTrunc(self.gd.pixel_height, @as(u32, self.font.height));
}

/// Set colors
pub fn setColor(self: *Self, color: Color, bgcolor: Color) void {
    const pxfmt = self.gd.pixel_format;
    self.color_int = color.getInt(pxfmt);
    self.bgcolor_int = bgcolor.getInt(pxfmt);
}

/// Scroll
pub fn scroll(self: *Self) void {
    const gd = self.gd;
    const px_per_scanline = gd.pixels_per_scanline;
    const px_height = gd.pixel_height;
    const amount_to_discard: usize = px_per_scanline * self.font.height;
    const max_addr: usize = px_per_scanline * px_height;
    // Cast away volatility just for this bulk shift-up, same reasoning as
    // clearScreen(): we're the sole writer, so the compiler is free to
    // vectorize this instead of being forced into a per-element copy.
    const fb: []u32 = @volatileCast(gd.framebuffer_pointer[0..max_addr]);
    std.mem.copyForwards(u32, fb[0 .. max_addr - amount_to_discard], fb[amount_to_discard..max_addr]);
    // the copy above only shifts existing rows up -- the row it just
    // exposed at the bottom still holds whatever was there before (usually
    // a stale duplicate of the line that just triggered this scroll), so it
    // must be cleared explicitly.
    const bg_int = theme.get().primary.background.getInt(gd.pixel_format);
    @memset(fb[max_addr - amount_to_discard .. max_addr], bg_int);
}

/// Handle a control sequence argument value (basically just a number parser)
pub fn handleVal(self: *Self, val: StateValue) void {
    // find out last num index
    var number_end: u32 = 0;
    var number: u32 = 0;
    for (val.values) |value| {
        switch (value) {
            '0'...'9' => {
                number_end += 1;
            },
            else => {},
        }
    }
    // parse int
    for (0..number_end) |i| {
        const multiplicator = std.math.pow(u32, 10, @as(u32, @intCast(number_end - (i + 1))));
        if (val.values[i] != '0') {
            number += (val.values[i] - '0') * multiplicator;
        }
    }
    self.control_sequence.args[self.control_sequence.index] = ControlSequenceArgument{ .number = number };
    self.control_sequence.index += 1;
}

/// Check whether a character is special (newline, CR, ESC, or part of an
/// in-progress control sequence) rather than plain printable text.
///
/// Also drives the control-sequence parser's state machine as a side effect.
pub fn isSpecialChar(self: *Self, char: u8) bool {
    return switch (char) {
        '\n' => true,
        '\r' => true,
        '\x1b' => blk: {
            // perhaps a control sequence
            self.state = .escape_statement;
            self.control_sequence.args = .{ null, null, null, null, null, null, null, null };
            self.control_sequence.index = 0;
            self.control_sequence.command = 0;
            self.control_sequence.ready_for_exec = false;
            break :blk true;
        },
        '[' => blk: {
            // control sequence start
            switch (self.state) {
                .escape_statement => {
                    self.state = .control_sequence_start;
                    break :blk true;
                },
                else => break :blk false,
            }
        },
        '0'...':', '<'...'?' => blk: {
            // control sequence "argument"
            switch (self.state) {
                .control_sequence_start, .control_sequence_delimiter => {
                    if ('<' <= char and char <= '?') {
                        // DEC private-mode prefix byte (e.g. '?' in `CSI ?25h`) -- stored as-is, not parsed as a digit
                        self.control_sequence.args[self.control_sequence.index] = ControlSequenceArgument{ .char = char };
                        self.control_sequence.index += 1;
                    } else {
                        // first digit of a new numeric argument
                        self.state = State{
                            .control_sequence_value = .{
                                .values = [_]u8{ char, 0, 0, 0, 0, 0, 0, 0 },
                                .index = 1,
                            },
                        };
                    }
                    break :blk true;
                },
                .control_sequence_value => |*val| {
                    val.*.values[val.*.index] = char;
                    val.*.index += 1;
                    break :blk true;
                },
                else => break :blk false,
            }
        },
        ';' => blk: {
            // control sequence "argument" delimiter
            switch (self.state) {
                .control_sequence_value => |val| {
                    self.handleVal(val);
                    self.state = .control_sequence_delimiter;
                    break :blk true;
                },
                .control_sequence_delimiter => {
                    // empty arguments are treated as 0
                    self.control_sequence.args[self.control_sequence.index] = ControlSequenceArgument{ .number = 0 };
                    self.control_sequence.index += 1;
                    break :blk true;
                },
                else => break :blk false,
            }
        },
        '@'...'Z', '\\'...'~' => blk: {
            // control sequence "command" (final byte)
            switch (self.state) {
                .control_sequence_start => {
                    self.control_sequence.command = char;
                    self.control_sequence.ready_for_exec = true;
                    self.state = .control_sequence_command;
                    break :blk true;
                },
                .control_sequence_value => |val| {
                    self.handleVal(val);
                    self.control_sequence.ready_for_exec = true;
                    self.control_sequence.command = char;
                    self.state = .control_sequence_command;
                    break :blk true;
                },
                else => break :blk false,
            }
        },
        else => blk: {
            // any other byte aborts an in-progress sequence (back to `.none`)
            // rather than trying to recover -- malformed sequences are just
            // dropped, and the byte itself is treated as plain text
            if (self.state != .none) {
                self.state = .none;
            }
            break :blk false;
        },
    };
}

/// Handle a control sequence
/// See https://vt100.net/docs/vt510-rm/chapter4.html#S4.6 for all control sequences to be handled
pub fn handleControlSequence(self: *Self, control_sequence: ControlSequence) void {
    // check for the control sequence command to be executed
    switch (control_sequence.command) {
        // change color
        'm' => self.selectGraphicRendition(control_sequence),
        'J' => self.eraseInDisplay(control_sequence),
        else => log.warn("Unknown control sequence, skipping", .{}),
    }
}

/// Handle a special character: `\n`/`\r` move the cursor directly. Any other
/// special character (ESC or part of an in-progress control sequence) is a
/// no-op here unless it's the final byte that just completed the sequence,
/// in which case it's dispatched via `handleControlSequence`.
pub fn handleSpecialChar(self: *Self, char: u8) void {
    switch (char) {
        '\n' => {
            self.curpos.row += 1;
            self.curpos.column = 0;
        },
        '\r' => {
            self.curpos.column = 0;
        },
        else => {
            if (self.control_sequence.ready_for_exec) {
                log.debug("Found control sequence!", .{});
                log.debug("  Arguments: ", .{});
                for (0..self.control_sequence.index) |i| {
                    if (self.control_sequence.args[i]) |arg| {
                        switch (arg) {
                            .char => |val| log.debug("    Char: {s}", .{[_]u8{val}}),
                            .number => |val| log.debug("    Number: {}", .{val}),
                        }
                    }
                }
                log.debug("  Command: {s}", .{[_]u8{self.control_sequence.command}});
                log.debug("  Trying to handle it now", .{});
                self.handleControlSequence(self.control_sequence);
            }
        },
    }
}

/// Put out text
pub fn puts(self: *Self, msg: []const u8) void {
    for (msg) |char| {
        if (!self.isSpecialChar(char)) {
            const cp437 = fonts.unicodeToCP437(char);
            self.drawChar(cp437, self.curpos.column, self.curpos.row);
            self.curpos.column += 1;
        } else {
            self.handleSpecialChar(char);
        }
        if (self.curpos.column == self.max_width) {
            self.curpos.column = 0;
            self.curpos.row += 1;
        }
        if (self.curpos.row == self.max_height) {
            // ran off the bottom edge -- pull back onto the last row and
            // scroll its contents up, rather than growing past max_height
            self.curpos.row -= 1;
            self.scroll();
        }
    }
}

pub fn fbconTermPuts(term: *Terminal, s: []const u8) void {
    const self: *Self = @fieldParentPtr("term", term);
    if (term.ready) {
        self.puts(s);
    }
}

pub fn fbconTermCls(term: *Terminal) void {
    const self: *Self = @fieldParentPtr("term", term);
    self.clearScreen();
}
