const std = @import("std");
const Writer = std.Io.Writer;
const log = std.log.scoped(.common_term);

const Terminal = @This();
const ansi = @import("ansi.zig");

/// Terminal writer
pub var default_term: ?*Terminal = null;

writer: Writer = .{
    .buffer = &.{},
    .vtable = &.{
        .drain = &defaultDrain,
    },
},
vtable: *const VTable,
ready: bool = false,
supports_color: bool = false,
/// Storage for the writer's vtable, so that defaultInit can rebuild
/// `writer` at runtime without the vtable pointer dangling into a
/// stack frame that's already returned.
writer_vtable: Writer.VTable = .{ .drain = &defaultDrain },

pub const VTable = struct {
    puts: *const fn (term: *Terminal, s: []const u8) void,
    init: *const fn (term: *Terminal, args: ?*const anyopaque) void = defaultInit,
    cls: *const fn (term: *Terminal) void = defaultCls,
    printf: *const fn (term: *Terminal, comptime fmt: []const u8, args: anytype) void = defaultPrintf,
    drain: *const fn (w: *Writer, data: []const []const u8, splat: usize) Writer.Error!usize = defaultDrain,
};

pub fn init(term: *Terminal, args: anytype) void {
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);
    if (args_type_info != .@"struct") {
        @compileError("expected tuple or struct argument, found " ++ @typeName(ArgsType));
    }

    if (comptime @sizeOf(ArgsType) == 0) {
        term.vtable.init(term, null);
    } else {
        term.vtable.init(term, &args);
    }
}

pub fn puts(term: *Terminal, s: []const u8) void {
    term.vtable.puts(term, s);
}

pub fn cls(term: *Terminal) void {
    term.vtable.cls(term);
}

pub fn defaultInit(term: *Terminal, args: ?*const anyopaque) void {
    _ = args;

    if (!term.ready) {
        term.writer_vtable = .{ .drain = term.vtable.drain };
        term.writer = .{
            .buffer = &.{},
            .vtable = &term.writer_vtable,
        };
        term.ready = true;
    }
}

pub fn defaultCls(term: *Terminal) void {
    // clear screen and move cursor to home position
    term.vtable.puts(term, ansi.CSI ++ ansi.CLS ++ ansi.CSI ++ ansi.HOME);
}

pub fn defaultPrintf(term: *Terminal, comptime fmt: []const u8, args: anytype) void {
    term.writer.print(fmt, args) catch @panic("printf failed");
}

pub fn defaultDrain(w: *Writer, data: []const []const u8, splat: usize) Writer.Error!usize {
    var total: usize = 0;
    var term: *Terminal = @fieldParentPtr("writer", w);
    // flush buffer first
    if (w.buffer.len > 0 and w.end > 0) {
        term.vtable.puts(term, w.buffer[0..w.end]);
        w.end = 0;
    }
    if (data.len == 0) return 0;
    const last_index = data.len - 1;
    for (data[0..last_index]) |item| {
        term.vtable.puts(term, item);
        total += item.len;
    }
    // repeat the last element `splat` number of times
    for (0..splat) |i| {
        _ = i;
        term.vtable.puts(term, data[last_index]);
        total += data[last_index].len;
    }
    return total;
}
