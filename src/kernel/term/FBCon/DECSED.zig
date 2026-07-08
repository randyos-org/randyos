//! Kernel Framebuffer Console: Control Sequence "Erase in Display"
//! 2024 by Samuel Fiedler

const log = @import("std").log.scoped(.fbcon_decsed);
const FBCon = @import("../FBCon.zig");
const theme = @import("theme.zig");

/// Erase in Display
pub fn eraseInDisplay(self: *FBCon, control_sequence: FBCon.ControlSequence) void {
    const gd = self.gd;
    // Cast away volatility just for these bulk fills, same reasoning as
    // FBCon.clearScreen()/scroll(): we're the sole writer, so the compiler
    // is free to vectorize instead of being forced into a per-element loop.
    const fb: [*]u32 = @volatileCast(gd.framebuffer_pointer);
    const px_per_scanline = gd.pixels_per_scanline;
    const px_height = gd.pixel_height;
    const bg_int = theme.get().primary.background.getInt(gd.pixel_format);
    // ANSI/DEC default a bare `ESC[J` (no explicit parameter) to 0 (erase
    // from cursor to end of screen), same as `ESC[0J`.
    const arg = control_sequence.args[0] orelse FBCon.ControlSequenceArgument{ .number = 0 };
    switch (arg) {
        .number => |num| {
            switch (num) {
                0 => {
                    // erase from the cursor to the end of the screen
                    const total_size: usize = px_per_scanline * px_height;
                    const start: usize = self.font.width * self.curpos.column + (px_per_scanline * self.font.height * self.curpos.row);
                    @memset(fb[start..total_size], bg_int);
                },
                1 => {
                    // erase from the start of the screen through the cursor (inclusive)
                    const start: usize = self.font.width * self.curpos.column + (px_per_scanline * self.font.height * self.curpos.row);
                    @memset(fb[0..start], bg_int);
                },
                2 => {
                    // erase the whole screen and home the cursor
                    const total_size: usize = px_per_scanline * px_height;
                    @memset(fb[0..total_size], bg_int);
                    self.curpos.column = 0;
                    self.curpos.row = 0;
                },
                else => log.warn("Wrong argument value, skipping", .{}),
            }
        },
        .char => log.warn("Wrong argument type, skipping", .{}),
    }
}
