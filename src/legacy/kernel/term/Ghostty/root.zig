//! The libghostty-vt backed Framebuffer Console.

const std = @import("std");
const log = std.log.scoped(.ghostty_term);

const common = @import("common");
const Terminal = common.Terminal;
const boot_info = common.boot_info;

const ghostty_vt = @import("ghostty-vt");
const GhosttyVtTerm = ghostty_vt.Terminal;
const RenderState = ghostty_vt.RenderState;
const Style = ghostty_vt.Style;
const RGB = ghostty_vt.color.RGB;
const VtStream = ghostty_vt.TerminalStream;
const Cell = ghostty_vt.Cell;

const kpa = @import("../../mem/root.zig").kernel_page_allocator;
const fonts = @import("../fonts/root.zig");
const Color = @import("../../gfx/color.zig").Color;
const GraphicsDev = @import("../../gfx/Device.zig");
const theme_mod = @import("../theme/root.zig");
const Theme = theme_mod;
const themes = theme_mod.themes;

const Self = @This();

/// Cursor cell (column/row) position across `render()` calls. Named type
/// so `prev_cursor` and its derived locals in `render` unify.
const CursorPos = struct { x: usize, y: usize };

/// `page.Cell`'s zero value (pristine, never-written -- see
/// `drawn_cells`). `page.Cell` is a packed(u64) struct with a union,
/// which `std.mem.zeroes` refuses; bitcasting a zero u64 gets the
/// all-zero-bits value directly.
const zero_cell: ghostty_vt.Cell = @bitCast(@as(u64, 0));

/// underline offset from bottom edge, in glyph rows
const underline_offset_divisor: u8 = 8;

gd: *GraphicsDev = undefined,
font: fonts.FontDesc = fonts.vga_8x16,
/// width in columns, not px
max_width: u32 = 80,
/// height in rows, not px
max_height: u32 = 25,
term: Terminal = undefined,
term_vtable: Terminal.VTable = undefined,
gterm: ?GhosttyVtTerm = null,
/// VT/ANSI parser driving `gterm`. Must persist across `puts()` calls --
/// a fresh stream per call would reset mid-sequence. Allocation-free
/// (.init not .initAlloc): OSC 52 clipboard etc. aren't meaningful
/// without a host clipboard, so skip the allocator-backed variant.
vt_stream: ?VtStream = null,
/// What's currently drawn to the framebuffer. Diffed against `gterm`'s
/// state each `render()`.
render_state: RenderState = .empty,
/// Shadow of last-drawn cell content per screen position (row-major,
/// max_width x max_height). `ghostty-vt` only tracks dirty per *row*
/// (see `render`), so a dirty row makes every cell a redraw candidate --
/// this filters that down to cells whose content actually changed.
/// Zeroed in `init` to match pristine `page.Cell`, so untouched
/// positions (e.g. the boot logo) read as "already matches" from frame
/// one. Reset by `clearScreen` alongside the physical wipe, else an
/// unchanged cell would wrongly be skipped after its pixels were blanked.
drawn_cells: []Cell = &.{},
/// Viewport position the cursor block was drawn at last `render()`, if
/// any. When the cursor moves/disappears, that cell needs a forced
/// redraw to erase the block -- `drawn_cells` alone won't catch it since
/// the underlying content usually hasn't changed.
prev_cursor: ?CursorPos = null,

pub fn deinit(self: *Self) void {
    self.render_state.deinit(kpa.allocator);
    kpa.allocator.free(self.drawn_cells);
    if (self.vt_stream) |*stream| stream.deinit();
    if (self.gterm) |*gterm| gterm.deinit(kpa.allocator);
}

/// call after setFont so max_width/max_height are correct
fn resetCellCache(self: *Self) void {
    self.drawn_cells = kpa.allocator.alloc(Cell, @as(usize, self.max_width) * self.max_height) catch @panic("OOM allocating terminal cell shadow");
    @memset(self.drawn_cells, zero_cell);
}

/// Setup FBCon. `clear=false` inits without disturbing screen (e.g. boot
/// logo); call `clearScreen()` later to switch over.
pub fn init(self: *Self, gd: *GraphicsDev, clear: bool) void {
    self.gd = gd;
    self.setFont(fonts.vga_8x16);
    resetCellCache(self);

    const primary = themes.get_current().primary;
    self.gterm = GhosttyVtTerm.init(kpa.allocator, .{
        .cols = @intCast(self.max_width),
        .rows = @intCast(self.max_height),
        .colors = .{
            .background = .init(colorToRGB(primary.background)),
            .foreground = .init(colorToRGB(primary.foreground)),
            .cursor = .unset,
            .palette = .init(themePalette(themes.get_current())),
        },
    }) catch |err| {
        log.warn("ghostty-vt init failed: {s}", .{@errorName(err)});
        return;
    };
    if (self.gterm) |*gterm| self.vt_stream = .init(gterm.vtHandler());

    if (clear) self.clearScreen();
    self.term_vtable = .{
        .puts = &gTermPuts,
        .cls = &gTermCls,
        .render = &gTermRender,
        .inputs = &gTermInputs,
    };
    self.term = Terminal{
        .vtable = &self.term_vtable,
        .supports_color = true,
    };
    self.term.init(.{});
}

/// Clear screen to theme bg, home cursor to (0,0).
pub fn clearScreen(self: *Self) void {
    self.gd.clear(themes.get_current().primary.background);
    // physical wipe invalidates drawn_cells' record; without this reset
    // an unchanged cell would wrongly be skipped after being blanked
    @memset(self.drawn_cells, zero_cell);
    self.prev_cursor = null;
    // render state no longer reflects screen; force full redraw next
    // time via deinit+reset to .empty rather than trusting stale dirty state
    self.render_state.deinit(kpa.allocator);
    self.render_state = .empty;
    self.render();
}

/// Draw a CP437 glyph. x/y are cell coords, not pixels. fg/bg are
/// already pixel-format-encoded (see `GraphicsDev.getColorInt`); caller
/// resolves cell style first (pass fg == bg for invisible text).
pub fn drawGlyph(
    self: *Self,
    char_index: u8,
    x: usize,
    y: usize,
    fg: u32,
    bg: u32,
    bold: bool,
    underline: bool,
) void {
    // runs per-pixel per redrawn cell; debug bounds checking roughly
    // doubled measured cost. indices are bounded by font/grid dims, safe to drop
    @setRuntimeSafety(false);

    const width = self.font.width;
    const height = self.font.height;
    const gd = self.gd;
    const px_per_scanline = gd.pixels_per_scanline;
    // back buffer once it exists, else real framebuffer (see drawTarget);
    // Ghostty renders during platform init, before the back buffer exists
    const fb = gd.drawTarget();
    const char_start: usize = char_index * @as(usize, height);
    const base_index: usize = x * @as(usize, width) + (y * @as(usize, height)) *% px_per_scanline;
    var col: u4 = 0;
    var row: u8 = 0;
    while (row < height) : ({
        row += 1;
        col = 0;
    }) {
        while (col < width) : (col += 1) {
            var index: usize = base_index + col;
            index += row *% px_per_scanline;
            // MSB-first glyph rows: col 0 (leftmost) is bit width-1
            const value = self.font.data[char_start + row] & @as(u16, 1) << (width - 1 - col);
            fb[index] = if (value == 0) bg else fg;
        }
    }
    if (bold) {
        // no separate bold glyphs; fake it by smearing strokes 1px wider
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
                if (value_left != 0) fb[index] = fg;
            }
        }
    }
    if (underline) {
        row = height - @divFloor(height, underline_offset_divisor);
        col = 0;
        while (col < width) : (col += 1) {
            const index: usize = base_index + col + row *% px_per_scanline;
            fb[index] = fg;
        }
    }
}

pub fn setFont(self: *Self, new_font: fonts.FontDesc) void {
    self.font = new_font;
    self.updateDimensions();
}

/// Recompute max_width/max_height in cells for current font+resolution.
/// Leftover pixels (not a full cell) left blank at right/bottom edge.
fn updateDimensions(self: *Self) void {
    self.max_width = @divTrunc(self.gd.pixel_width, @as(u32, self.font.width));
    self.max_height = @divTrunc(self.gd.pixel_height, @as(u32, self.font.height));
}

/// kernel gfx.Color -> ghostty_vt.color.RGB
fn colorToRGB(c: Color) RGB {
    return .{ .r = c.red, .g = c.green, .b = c.blue };
}

/// Build 256-entry ANSI palette: 0-15 from theme normal/bright, 16-255
/// from ghostty-vt's built-in cube+grayscale. Makes SGR 30-37/90-97
/// (what std.log color codes emit, see common/ansi.zig SgrCode) resolve
/// to FBCon's vivid Theme.colorFromANSI colors, not ghostty-vt's duller
/// defaults.
fn themePalette(theme: *const Theme) ghostty_vt.color.Palette {
    var palette = ghostty_vt.color.default;
    const n = theme.normal;
    const b = theme.bright;
    palette[0] = colorToRGB(n.black);
    palette[1] = colorToRGB(n.red);
    palette[2] = colorToRGB(n.green);
    palette[3] = colorToRGB(n.yellow);
    palette[4] = colorToRGB(n.blue);
    palette[5] = colorToRGB(n.magenta);
    palette[6] = colorToRGB(n.cyan);
    palette[7] = colorToRGB(n.white);
    palette[8] = colorToRGB(b.black);
    palette[9] = colorToRGB(b.red);
    palette[10] = colorToRGB(b.green);
    palette[11] = colorToRGB(b.yellow);
    palette[12] = colorToRGB(b.blue);
    palette[13] = colorToRGB(b.magenta);
    palette[14] = colorToRGB(b.cyan);
    palette[15] = colorToRGB(b.white);
    return palette;
}

/// ghostty_vt.color.RGB -> pixel-format-encoded u32
fn rgbInt(self: *const Self, rgb: RGB) u32 {
    return self.gd.getColorInt(.{ .red = rgb.r, .green = rgb.g, .blue = rgb.b });
}

/// Diff `gterm`'s state against what we last drew, blit only changes.
/// Cheap no-op when nothing changed (`RenderState.update` + `.false` bail).
///
/// Called synchronously after every `puts` so log output shows up even
/// if the kernel panics before returning to the idle loop. Idle loop
/// also calls it as a safety net for state changes outside `puts`.
///
/// `ghostty-vt` only tracks dirty per *row*, not per cell, so a changed
/// cell makes its whole row a redraw candidate -- `drawn_cells` filters
/// that to cells whose content actually differs. Row `pin` identity is
/// stable across scroll (ghostty-vt shifts content between fixed slots
/// internally), so there's no reuse signal beyond row granularity; this
/// per-cell comparison is the finest we can add on top.
pub fn render(self: *Self) void {
    const gterm = if (self.gterm) |*g| g else return;

    self.render_state.update(kpa.allocator, gterm) catch |err| {
        log.warn("ghostty-vt render state update failed: {s}", .{@errorName(err)});
        return;
    };
    if (self.render_state.dirty == .false) return;
    const full_redraw = self.render_state.dirty == .full;

    const palette = &self.render_state.colors.palette;
    const default_fg = self.render_state.colors.foreground;
    const default_bg = self.render_state.colors.background;

    const row_slice = self.render_state.row_data.slice();
    const row_dirty = row_slice.items(.dirty);
    const row_cells = row_slice.items(.cells);
    const stride: usize = self.max_width;

    // track lowest/highest touched row to present just that pixel-row
    // span (GraphicsDev.presentSpan) instead of the whole back buffer
    var min_row: usize = self.render_state.rows;
    var max_row: usize = 0;

    // if cursor moved/disappeared, its old cell needs a forced redraw
    // this pass to erase the block -- else the shadow-diff below sees
    // unchanged content and leaves a stale cursor-shaped block on screen
    const cursor_erase: ?CursorPos = blk: {
        const prev = self.prev_cursor orelse break :blk null;
        if (self.render_state.cursor.visible) {
            if (self.render_state.cursor.viewport) |vp| {
                if (vp.x == prev.x and vp.y == prev.y) break :blk null;
            }
        }
        break :blk prev;
    };

    for (0..self.render_state.rows) |y| {
        const force_row = cursor_erase != null and cursor_erase.?.y == y;
        if (!full_redraw and !row_dirty[y] and !force_row) continue;
        // consume dirty flag now; update() doesn't clear it automatically
        // (confirmed by the C example and desktop renderer, both clear
        // per row after render) -- else every row stays dirty forever,
        // forcing a full redraw every frame
        row_dirty[y] = false;
        if (y < min_row) min_row = y;
        if (y > max_row) max_row = y;

        var cells = row_cells[y].slice();
        for (0..self.render_state.cols) |x| {
            const cell = cells.get(x);
            const shadow_idx = y * stride + x;

            // skip cells bit-identical to what's on screen; never skip
            // the old cursor cell though, its pixels still need erasing
            const force_cell = force_row and cursor_erase.?.x == x;
            if (!force_cell and std.meta.eql(cell.raw, self.drawn_cells[shadow_idx])) continue;
            self.drawn_cells[shadow_idx] = cell.raw;

            // cell.style is only meaningful if the raw cell has a
            // style/color attached, else uninitialized memory; fall back
            // to a blank style so fg/bg resolve to terminal defaults
            const style: Style = if (cell.raw.style_id != 0 or
                cell.raw.content_tag == .bg_color_rgb or
                cell.raw.content_tag == .bg_color_palette)
                cell.style
            else
                .{};

            var fg_rgb = style.fg(.{
                .default = default_fg,
                .palette = palette,
                // no bold color mapping yet; drawGlyph fakes bold by
                // smearing the glyph, so bold text keeps the same color
                .bold = null,
            });
            var bg_rgb = style.bg(&cell.raw, palette) orelse default_bg;
            if (style.flags.inverse) std.mem.swap(RGB, &fg_rgb, &bg_rgb);

            var fg_int = self.rgbInt(fg_rgb);
            const bg_int = self.rgbInt(bg_rgb);
            if (style.flags.invisible) fg_int = bg_int;

            // codepoints outside the BMP never match CP437, fall back blank
            const cp437 = fonts.unicodeToCP437(std.math.cast(u16, cell.raw.codepoint()) orelse 0);
            self.drawGlyph(
                cp437,
                x,
                y,
                fg_int,
                bg_int,
                style.flags.bold,
                style.flags.underline != .none,
            );
        }
    }

    // solid-block cursor, no blink timing yet. Drawn unconditionally
    // since it's an overlay, not real content -- drawn_cells still holds
    // the real content underneath; cursor_erase cleans up once it moves
    var new_cursor: ?CursorPos = null;
    if (self.render_state.cursor.visible) {
        if (self.render_state.cursor.viewport) |vp| {
            const fg_int = self.rgbInt(default_fg);
            self.drawGlyph(fonts.unicodeToCP437(0x2588), vp.x, vp.y, fg_int, fg_int, false, false);
            if (vp.y < min_row) min_row = vp.y;
            if (vp.y > max_row) max_row = vp.y;
            new_cursor = .{ .x = vp.x, .y = vp.y };
        }
    }
    self.prev_cursor = new_cursor;

    self.render_state.dirty = .false;

    // bulk-copy just the touched pixel-row span. min_row > max_row means
    // we only drew the cursor onto an otherwise-clean frame
    if (min_row <= max_row) {
        const gd = self.gd;
        const px_per_scanline = gd.pixels_per_scanline;
        const start = min_row * self.font.height * px_per_scanline;
        const end = @min(
            (max_row + 1) * self.font.height * px_per_scanline,
            gd.back_buffer.pixels.len,
        );
        gd.presentSpan(start, end);
    }
}

pub fn gTermPuts(term: *Terminal, s: []const u8) void {
    const self: *Self = @fieldParentPtr("term", term);
    if (!term.ready) return;
    const stream = if (self.vt_stream) |*st| st else return;
    stream.nextSlice(s);
    self.render();
}

pub fn gTermCls(term: *Terminal) void {
    const self: *Self = @fieldParentPtr("term", term);
    self.clearScreen();
}

pub fn gTermRender(term: *Terminal) void {
    const self: *Self = @fieldParentPtr("term", term);
    self.render();
}

pub fn gTermInputs(term: *Terminal) void {
    const self: *Self = @fieldParentPtr("term", term);
    const gterm = if (self.gterm) |*g| g else return;
    _ = gterm;
    // gterm.processInput() catch |err| {
    //     log.warn("ghostty-vt processInput failed: {s}", .{@errorName(err)});
    //     return;
    // };
}
