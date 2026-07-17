//! Loup color theme
//! Original hardcoded VGA palette; named for
//! https://codeberg.org/loup-os/kernel, the fork origin

const std = @import("std");
const log = std.log.scoped(.loup);

const Theme = @import("root.zig");
const hex = Theme.hex;

pub const theme: Theme = .{
    .primary = .{
        .background = hex("#000000"),
        .foreground = hex("#aaaaaa"),
    },
    .cursor = .{
        .cursor = hex("#aaaaaa"),
        .text = hex("#000000"),
    },
    .selection = .{
        .background = hex("#aaaaaa"),
        .text = hex("#000000"),
    },
    .normal = .{
        .black = hex("#000000"),
        .red = hex("#aa0000"),
        .green = hex("#00aa00"),
        .yellow = hex("#aa5500"),
        .blue = hex("#0000aa"),
        .magenta = hex("#aa00aa"),
        .cyan = hex("#00aaaa"),
        .white = hex("#aaaaaa"),
    },
    .bright = .{
        .black = hex("#555555"),
        .red = hex("#ff5555"),
        .green = hex("#55ff55"),
        .yellow = hex("#ffff55"),
        .blue = hex("#5555ff"),
        .magenta = hex("#ff55ff"),
        .cyan = hex("#55ffff"),
        .white = hex("#ffffff"),
    },
};
