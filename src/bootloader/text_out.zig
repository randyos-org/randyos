//! This module provides simple text output for UEFI
//! 2023 by Samuel Fiedler

const std = @import("std");
const uefi = std.os.uefi;

var con_out: *uefi.protocol.SimpleTextOutput = undefined;
var already_called_puts: u8 = 0;

/// Put out any string
///   - msg: the string to put out
pub fn puts(msg: []const u8) void {
    if (already_called_puts == 0) {
        con_out = uefi.system_table.con_out.?;
        _ = con_out.reset(false);
        already_called_puts = 1;
    }
    for (msg) |c| {
        const c_ = [1:0]u16{c};
        _ = con_out.outputString(@as(*const [1:0]u16, &c_));
    }
}

/// Put out any formatted string
pub fn printf(comptime fmt: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    var msg: []u8 = undefined;
    msg = std.fmt.bufPrint(&buf, fmt, args) catch unreachable;
    puts(msg);
}
