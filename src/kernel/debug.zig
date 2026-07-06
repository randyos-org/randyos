const std = @import("std");
const builtin = @import("builtin");
const log = std.log.scoped(.debug);

var already_panicking: bool = false;
var debug_info: ?std.debug.Dwarf = null;
var alloc: ?std.mem.Allocator = null;

/// inline assert with panic, source location and message
pub inline fn kassert(src: std.builtin.SourceLocation, ok: bool, message: ?[]const u8) void {
    if (!ok) {
        if (message) |msg| {
            std.debug.panic("assert failed at {s}:{}:{} in {s} with message: '{s}'", .{ src.file, src.line, src.column, src.fn_name, msg });
        } else {
            std.debug.panic("assert failed at {s}:{}:{} in {s}", .{ src.file, src.line, src.column, src.fn_name });
        }
    }
}

/// inline panic with source location
pub inline fn kpanic(src: std.builtin.SourceLocation, msg: []const u8) noreturn {
    std.debug.panic("({s}:{}:{} in {s}): {s}", .{ src.file, src.line, src.column, src.fn_name, msg });
}

/// inline panic with source location and formatting
pub inline fn kpanicFmt(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.panic("({s}:{}:{} in {s}): " ++ fmt, .{ src.file, src.line, src.column, src.fn_name } ++ args);
}

/// Handle kernel panics
pub fn panic(msg: []const u8, first_trace_addr: ?usize) noreturn {
    // only print things if not panicking while panic
    if (!already_panicking) {
        already_panicking = true;
        log.err("\r\n\r\n !!! Kernel Panic !!!\r\n", .{});
        log.err(" !!! Message: {s}", .{msg});
        // error return trace
        if (@errorReturnTrace()) |t| if (t.index > 0) {
            log.err(" !!! Error Return Trace: ", .{});
            for (t.instruction_addresses) |addr| {
                printAddress(addr);
            }
        };
        // stack trace
        log.err(" !!! Stack Trace: ", .{});
        var addr_buffer: [64]usize = undefined;
        const st = std.debug.captureCurrentStackTrace(.{
            .first_address = first_trace_addr orelse @returnAddress(),
            .allow_unsafe_unwind = true,
        }, &addr_buffer);
        for (st.return_addresses) |addr| {
            printAddress(addr);
        }
        log.err(" !!! Will hang now ", .{});
    }
    // hang
    while (true) {}
}

/// Print address
pub fn printAddress(addr: usize) void {
    var symbol: []const u8 = "[no symbol]";
    if (debug_info) |*info| blk: {
        if (info.getSymbolName(addr)) |name| {
            symbol = name;
        }
        const compile_unit = info.findCompileUnit(builtin.cpu.arch.endian(), addr) catch break :blk;
        const line_info = info.getLineNumberInfo(alloc.?, alloc.?, builtin.cpu.arch.endian(), compile_unit, addr) catch break :blk;
        log.err(" !!!   0x{x:0>16}: {s} at {s}:{d}:{d} ", .{ addr, symbol, line_info.file_name, line_info.line, line_info.column });
        return;
    }
    // it will only get here if last step failed because last step will return or break
    log.err(" !!!   0x{x:0>16}: {s} at ???:?:? ", .{ addr, symbol });
}

/// Initialize Panicking (DWARF)
pub fn init(allocator: std.mem.Allocator, dwarf_info: *?std.debug.Dwarf) void {
    if (builtin.strip_debug_info) {
        log.err("debug info stripped, returning!");
        return;
    }
    log.debug("panic and debug info initialization...", .{});
    alloc = allocator;
    debug_info = dwarf_info.*;
    if (debug_info == null) {
        log.debug("Panic initialization successful! (debug info not available)", .{});
    } else {
        log.debug("panic and debug info initialization successful!", .{});
    }
}
