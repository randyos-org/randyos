//! Material Dark color theme
//! https://github.com/mbadolato/iTerm2-Color-Schemes/blob/master/alacritty/Material%20Dark.toml

const std = @import("std");
const log = std.log.scoped(.material_dark);

const Theme = @import("root.zig");
const hex = Theme.hex;

pub const theme: Theme = .{
    .primary = .{
        .background = hex("#232322"),
        .foreground = hex("#e5e5e5"),
    },
    .cursor = .{
        .cursor = hex("#16afca"),
        .text = hex("#dfdfdf"),
    },
    .selection = .{
        .background = hex("#dfdfdf"),
        .text = hex("#3d3d3d"),
    },
    .normal = .{
        .black = hex("#212121"),
        .red = hex("#b7141f"),
        .green = hex("#457b24"),
        .yellow = hex("#f6981e"),
        .blue = hex("#134eb2"),
        .magenta = hex("#701aa2"),
        .cyan = hex("#0e717c"),
        .white = hex("#efefef"),
    },
    .bright = .{
        .black = hex("#4f4f4f"),
        .red = hex("#e83b3f"),
        .green = hex("#7aba3a"),
        .yellow = hex("#ffea2e"),
        .blue = hex("#54a4f3"),
        .magenta = hex("#aa4dbc"),
        .cyan = hex("#26bbd1"),
        .white = hex("#d9d9d9"),
    },
};
