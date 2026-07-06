//! This module provides simple text output for UEFI

// Again, our standard library
const std = @import("std");
const uefi = std.os.uefi;
const log = std.log.scoped(.uefi_term);
const common = @import("common");
const Terminal = common.Terminal;

// We want to have a global console output protocol.
var con_out: *uefi.protocol.SimpleTextOutput = undefined;
// But because that protocol is undefined at the beginning, we need to fill it
// (at runtime).
// This is why we need this variable.
var already_called_puts: bool = false;

/// This function puts out any normal string. Assumes ASCII: each byte is
/// transcribed to one UTF-16 code unit with no UTF-8 decoding, so multi-byte
/// UTF-8 sequences would come out wrong.
pub fn puts(msg: []const u8) void {
    // iterate over the message we want to print out.
    for (msg) |c| {
        // For each character, we convert it to a null-terminated 16bit string.
        const c_ = [1:0]u16{c};
        // And then, we output that string.
        _ = con_out.outputString(&c_) catch {};
    }
}

fn uefiInitialize() void {
    // If this is the first time this function was called, we will do some
    // setup.
    if (already_called_puts == false) {
        // We save the console output protocol from the system table (so we
        // don't have to locate it).
        con_out = uefi.system_table.con_out.?;
        // We reset the screen…
        con_out.reset(false) catch {};
        // And we set our variable to true, so we enter this condition only
        // once.
        already_called_puts = true;
    }
}

pub fn uefiTermInit(term: *Terminal, args: ?*const anyopaque) void {
    _ = args;
    // Locate/reset the UEFI console once, shared across every Terminal that
    // uses this vtable.
    if (!already_called_puts) {
        uefiInitialize();
    }
    // Only wire up the generic Writer once the UEFI console is actually available.
    if (already_called_puts and !term.ready) {
        term.defaultInit(null);
    }
    term.ready = already_called_puts;
}

pub fn uefiTermPuts(term: *Terminal, s: []const u8) void {
    if (term.ready) {
        puts(s);
    }
}

pub const UefiTermVTable = Terminal.VTable{
    .puts = &uefiTermPuts,
    .init = &uefiTermInit,
};

pub var uefi_term = Terminal{
    .vtable = &UefiTermVTable,
    .supports_color = false,
};
