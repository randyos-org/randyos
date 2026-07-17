//! Kernel Framebuffer Console: Control Sequence "Erase in Display"
//! 2024 by Samuel Fiedler

const log = @import("std").log.scoped(.fbcon_decsed);
const FBCon = @import("root.zig");
const theme_mod = @import("../theme/root.zig");
const themes = theme_mod.themes;

pub fn eraseInDisplay(self: *FBCon, control_sequence: FBCon.ControlSequence) void {
    const gd = self.gd;
    // sole writer, so drop volatile to let compiler vectorize the fill
    const fb: [*]u32 = @volatileCast(gd.framebuffer_pointer);
    const px_per_scanline = gd.pixels_per_scanline;
    const px_height = gd.pixel_height;
    const bg_int = themes.get_current().primary.background.getInt(gd.pixel_format);
    // bare ESC[J defaults to 0, same as ESC[0J
    const arg = control_sequence.args[0] orelse FBCon.ControlSequenceArgument{ .number = 0 };
    switch (arg) {
        .number => |num| {
            switch (num) {
                0 => {
                    // cursor to end of screen
                    const total_size: usize = px_per_scanline * px_height;
                    const start: usize = self.font.width * self.curpos.column + (px_per_scanline * self.font.height * self.curpos.row);
                    @memset(fb[start..total_size], bg_int);
                },
                1 => {
                    // start of screen through cursor, inclusive
                    const start: usize = self.font.width * self.curpos.column + (px_per_scanline * self.font.height * self.curpos.row);
                    @memset(fb[0..start], bg_int);
                },
                2 => {
                    // whole screen, home cursor
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
