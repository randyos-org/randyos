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

/// A character-cell (column/row) position, used to track the cursor's
/// on-screen location across `render()` calls. A named type rather than
/// an inline anonymous struct so `prev_cursor`'s field and the locals
/// derived from it in `render` all unify to the same type.
const CursorPos = struct { x: usize, y: usize };

/// `page.Cell`'s zero-value (pristine/never-written state -- see
/// `drawn_cells`'s doc comment). `page.Cell` is a `packed struct(u64)`
/// containing a union, which `std.mem.zeroes` refuses to zero-initialize
/// (a union has no single well-defined zero representation in general);
/// bit-casting a zero `u64` sidesteps that since we specifically want the
/// all-zero-bits value, not a semantically-"default" union member.
const zero_cell: ghostty_vt.Cell = @bitCast(@as(u64, 0));

/// The underline is drawn this many glyph rows up from the bottom edge --
/// roughly a typical underline's thickness-from-baseline offset, scaled to
/// the font's height.
const underline_offset_divisor: u8 = 8;

/// The pointer to the graphics device
gd: *GraphicsDev = undefined,
/// Current Font
font: fonts.FontDesc = fonts.vga_8x16,
/// Maximal width, in character columns (not pixels)
max_width: u32 = 80,
/// Maximal height, in character rows (not pixels)
max_height: u32 = 25,
/// Terminal interface to the kernel
term: Terminal = undefined,
/// Kernel terminal vtable
term_vtable: Terminal.VTable = undefined,
/// GhosttyVt Terminal instance
gterm: ?GhosttyVtTerm = null,
/// The VT/ANSI parser driving `gterm`. Must be persistent (not
/// recreated per write) so escape sequences split across separate
/// `puts()` calls still parse correctly -- a fresh stream per call would
/// reset the parser mid-sequence. Allocation-free (`.init`, not
/// `.initAlloc`): OSC 52 clipboard and similar allocator-requiring
/// sequences aren't meaningful without a host clipboard, so we don't pay
/// for the allocator-backed variant.
vt_stream: ?VtStream = null,
/// Tracks what's currently been drawn to the framebuffer. Diffed against
/// `gterm`'s latest state on each `render()` call.
render_state: RenderState = .empty,
/// Shadow of the cell content last actually drawn to each screen
/// position (row-major, `max_width` x `max_height`). `ghostty-vt` only
/// tracks dirty state per *row* (see `render`'s doc comment), so a dirty
/// row makes every cell in it a redraw *candidate* -- this is what turns
/// that into an actual per-cell redraw: a candidate whose content is
/// bit-identical to what's already shadowed here is left alone. Allocated
/// (and zeroed) in `init`, matching `page.Cell`'s pristine/never-written
/// value, so a screen position nothing has written to yet -- e.g. the boot
/// logo, drawn directly into `gd.back_buffer` before this terminal existed
/// -- reads as "already matches, nothing to draw" from the very first
/// frame onward, not just a one-shot bootstrap exception. Reset to zero by
/// `clearScreen` alongside the physical wipe, since otherwise a cell whose
/// *content* didn't change would wrongly be skipped even though its pixels
/// were just blanked out from under it.
drawn_cells: []Cell = &.{},
/// The viewport position the cursor block was actually drawn at on the
/// last `render()` call, if any. When the cursor moves (or disappears),
/// the cell it used to occupy needs a forced real-content redraw to erase
/// the cursor block -- `drawn_cells` alone won't trigger that, since the
/// underlying cell content there usually hasn't changed at all.
prev_cursor: ?CursorPos = null,

pub fn deinit(self: *Self) void {
    self.render_state.deinit(kpa.allocator);
    kpa.allocator.free(self.drawn_cells);
    if (self.vt_stream) |*stream| stream.deinit();
    if (self.gterm) |*gterm| gterm.deinit(kpa.allocator);
}

/// wait until after setFont to ensure `max_width`/`max_height` are correct before calling this
fn resetCellCache(self: *Self) void {
    self.drawn_cells = kpa.allocator.alloc(Cell, @as(usize, self.max_width) * self.max_height) catch @panic("OOM allocating terminal cell shadow");
    @memset(self.drawn_cells, zero_cell);
}

/// Setup the Framebuffer Console
/// `clear`: whether to clear the screen immediately. Pass `false` to bring
/// up the terminal (and its logging plumbing) without disturbing whatever
/// is already on screen (e.g. a boot logo) -- call `clearScreen()`
/// explicitly later to switch over.
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

/// Clear the Screen (effectively set the color of everything to the theme's
/// background color) and home the cursor to (0, 0)
pub fn clearScreen(self: *Self) void {
    self.gd.clear(themes.get_current().primary.background);
    // The physical wipe above invalidates `drawn_cells`' record of what's
    // on screen -- without this reset, a cell whose content didn't change
    // across the clear would be wrongly skipped on the next render even
    // though its pixels were just blanked out from under it.
    @memset(self.drawn_cells, zero_cell);
    self.prev_cursor = null;
    // The render state no longer reflects what's on screen (we just wiped
    // it), so force a full redraw next time instead of trusting stale dirty
    // tracking -- `deinit`+reset to `.empty` is the simplest way to get
    // `update()` to treat this as a from-scratch build.
    self.render_state.deinit(kpa.allocator);
    self.render_state = .empty;
    self.render();
}

/// Draw a single glyph (CP437). `x`/`y` are character-cell (column/row)
/// coordinates, not pixel coordinates -- they get multiplied by the font
/// size below to find the actual pixel origin. `fg`/`bg` are already
/// pixel-format-encoded colors (see `GraphicsDev.getColorInt`); the caller
/// is responsible for resolving cell style (including reverse video and
/// invisible text -- pass `fg == bg` for the latter) before calling this.
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
    // This runs per-pixel for every cell `render` actually redraws, and
    // Debug-build bounds/overflow checking roughly doubled its cost in
    // measurement. Every index here is derived from `x`/`y`/`col`/`row`
    // bounded by the font and grid dimensions, so it's safe to drop.
    @setRuntimeSafety(false);

    const width = self.font.width;
    const height = self.font.height;
    const gd = self.gd;
    const px_per_scanline = gd.pixels_per_scanline;
    // The back buffer once it exists, the real framebuffer directly before
    // then -- see `GraphicsDev.drawTarget`'s doc comment. Ghostty starts
    // logging (and therefore rendering) before that point, during platform
    // init, so this has to handle both.
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
            // Glyph rows are MSB-first (bit 7 = leftmost pixel), so column
            // `col` (0 = leftmost) lives at bit `width - 1 - col`.
            const value = self.font.data[char_start + row] & @as(u16, 1) << (width - 1 - col);
            fb[index] = if (value == 0) bg else fg;
        }
    }
    if (bold) {
        // bold: OR 1pxl to left -- we have no separate bold glyphs, so we
        // fake it by smearing each stroke one pixel wider.
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

/// Convert a kernel `gfx.Color` (0-255 per channel, `reserved` ignored) to
/// the `ghostty_vt.color.RGB` type `Style`/`Terminal.Colors` expect.
fn colorToRGB(c: Color) RGB {
    return .{ .r = c.red, .g = c.green, .b = c.blue };
}

/// Build a full 256-entry ANSI palette (indices 0-15 from `theme`'s
/// normal/bright colors, 16-255 from ghostty-vt's built-in 216-color cube
/// + grayscale ramp) so SGR 30-37/90-97 colors (what our `std.log` color
/// codes -- see `common/ansi.zig`'s `SgrCode` -- actually emit) resolve to
/// the same vivid colors FBCon's hand-rolled ANSI parser used via
/// `Theme.colorFromANSI`, instead of ghostty-vt's own (duller) built-in
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

/// Convert a `ghostty_vt.color.RGB` back to a pixel-format-encoded `u32`
/// via the graphics device.
fn rgbInt(self: *const Self, rgb: RGB) u32 {
    return self.gd.getColorInt(.{ .red = rgb.r, .green = rgb.g, .blue = rgb.b });
}

/// Diff `gterm`'s latest state against what we last drew and blit only
/// what changed. Safe (and cheap) to call even when nothing changed --
/// `RenderState.update` no-ops and we bail out immediately on `.false`.
///
/// Called synchronously after every `puts` (see `gTermPuts`) so that log
/// output is visible on screen immediately, even if the kernel panics
/// before ever returning to the idle loop. The idle loop also calls this
/// as a cheap safety net for state changes that don't flow through `puts`
/// (e.g. future keyboard-echo or cursor-blink support).
///
/// `ghostty-vt` only exposes per-*row* dirty tracking (`RenderState.Row.dirty`),
/// not per-cell, so a single changed cell still makes every other cell in
/// its row a redraw *candidate* -- `drawn_cells` (see its doc comment) is
/// what turns that into an actual per-cell redraw, comparing each
/// candidate's content against what's already on screen and skipping it
/// when nothing's changed. Row `pin` identity is stable across a scroll --
/// `ghostty-vt` shifts cell *content* between fixed row slots internally
/// before `RenderState` is ever built -- so it carries no reusable "this
/// content already exists on screen elsewhere" signal; row-granularity
/// dirty tracking is the finest this library offers, and per-cell content
/// comparison is the finest we can add on top of it.
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

    // Track the lowest/highest touched character row so we can present
    // (bulk-copy to the real framebuffer) just that pixel-row span instead
    // of the whole back buffer -- see `GraphicsDev.presentSpan`.
    var min_row: usize = self.render_state.rows;
    var max_row: usize = 0;

    // If the cursor moved (or disappeared) since the last render, the cell
    // it used to occupy needs a forced real-content redraw this pass to
    // erase the cursor block -- see `prev_cursor`'s doc comment. Otherwise
    // the shadow-diff below would see unchanged underlying cell content
    // there and skip it, leaving a stale cursor-shaped block on screen.
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
        // Consume this row's dirty flag now that we're handling it. Not
        // done automatically by `update()` -- confirmed both by the C
        // example (`GHOSTTY_RENDER_STATE_ROW_OPTION_DIRTY`) and the real
        // desktop renderer (generic.zig), which both explicitly clear it
        // per row after rendering. Leaving this unset means every row
        // that was ever dirty once looks dirty forever after, forcing a
        // full-grid-cost redraw on every single frame regardless of
        // whether anything actually changed.
        row_dirty[y] = false;
        if (y < min_row) min_row = y;
        if (y > max_row) max_row = y;

        var cells = row_cells[y].slice();
        for (0..self.render_state.cols) |x| {
            const cell = cells.get(x);
            const shadow_idx = y * stride + x;

            // Skip cells whose content is bit-identical to what's already
            // on screen -- see `drawn_cells`'s doc comment. The cell that
            // used to hold the cursor block is never skipped: its content
            // usually hasn't changed, but its *pixels* still need a real
            // redraw to erase the cursor.
            const force_cell = force_row and cursor_erase.?.x == x;
            if (!force_cell and std.meta.eql(cell.raw, self.drawn_cells[shadow_idx])) continue;
            self.drawn_cells[shadow_idx] = cell.raw;

            // `cell.style` is only meaningful when the raw cell actually
            // has a style/color attached; otherwise it's uninitialized
            // memory. Fall back to a blank (all-default) style so
            // `Style.fg`/`.bg` resolve to the terminal defaults.
            const style: Style = if (cell.raw.style_id != 0 or
                cell.raw.content_tag == .bg_color_rgb or
                cell.raw.content_tag == .bg_color_palette)
                cell.style
            else
                .{};

            var fg_rgb = style.fg(.{
                .default = default_fg,
                .palette = palette,
                // No separate bright/bold color mapping yet -- we fake
                // bold by smearing the glyph a pixel wider instead (see
                // drawGlyph), so bold text keeps the same color.
                .bold = null,
            });
            var bg_rgb = style.bg(&cell.raw, palette) orelse default_bg;
            if (style.flags.inverse) std.mem.swap(RGB, &fg_rgb, &bg_rgb);

            var fg_int = self.rgbInt(fg_rgb);
            const bg_int = self.rgbInt(bg_rgb);
            if (style.flags.invisible) fg_int = bg_int;

            // Codepoints outside the BMP (astral emoji, etc.) can never
            // match a CP437 entry anyway, so they fall back to blank
            // (0x00) the same as any other unmapped codepoint.
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

    // Draw the cursor as a solid block in the foreground color. No
    // blink timing yet -- it's just always on while visible. Drawn
    // unconditionally (not gated on row dirty/shadow state) since it's an
    // overlay, not real cell content -- `drawn_cells` above still holds
    // the real content underneath it, and `cursor_erase` (next call) is
    // what cleans this up once the cursor moves on.
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

    // bulk-copy just the touched pixel-row span from the back
    // buffer to the real framebuffer. `min_row > max_row` here means we
    // only ever drew the cursor onto an otherwise-clean frame
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
