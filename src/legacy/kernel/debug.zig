const std = @import("std");
const builtin = @import("builtin");
const log = std.log.scoped(.debug);

var already_panicking: bool = false;
var debug_info: ?std.debug.Dwarf = null;
var alloc: ?std.mem.Allocator = null;

/// max stack trace depth; deeper traces truncated, not grown dynamically
/// (allocation itself might be broken during a panic)
const max_stack_trace_depth: usize = 64;

/// Assert `ok`, panic with caller location (+ optional message) if not.
/// Call as `kassert(@src(), ok, null)`.
pub inline fn kassert(src: std.builtin.SourceLocation, ok: bool, message: ?[]const u8) void {
    if (ok) return;
    if (message) |msg| {
        std.debug.panic("assertion failed [{s} @ {s}:{d}:{d}] -- {s}", .{ src.fn_name, src.file, src.line, src.column, msg });
    } else {
        std.debug.panic("assertion failed [{s} @ {s}:{d}:{d}]", .{ src.fn_name, src.file, src.line, src.column });
    }
}

/// Panic with caller location + message. Call as `kpanic(@src(), "...")`.
pub inline fn kpanic(src: std.builtin.SourceLocation, msg: []const u8) noreturn {
    std.debug.panic("panic in {s} @ {s}:{d}:{d} -- {s}", .{ src.fn_name, src.file, src.line, src.column, msg });
}

pub fn panic(msg: []const u8, first_trace_addr: ?usize) noreturn {
    // panic while already panicking means the reporting below caused it;
    // don't recurse, just stop
    if (already_panicking) while (true) {};
    already_panicking = true;

    log.err("\r\n\r\n !!! Kernel Panic !!!\r\n", .{});
    log.err(" !!! Message: {s}", .{msg});

    // raw stack trace always available regardless of error return trace
    var addr_buffer: [max_stack_trace_depth]usize = undefined;
    const trace = std.debug.captureCurrentStackTrace(.{
        .first_address = first_trace_addr orelse @returnAddress(),
        .allow_unsafe_unwind = true,
    }, &addr_buffer);

    if (@errorReturnTrace()) |ret_trace| {
        if (ret_trace.index > 0) {
            log.err(" !!! Error Return Trace: ", .{});
            for (ret_trace.instruction_addresses) |addr| printAddress(addr);
        }
    }

    log.err(" !!! Stack Trace: ", .{});
    for (trace.return_addresses) |addr| printAddress(addr);
    while (true) {}
}

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
    // only reached if the block above failed (returns or breaks otherwise)
    log.err(" !!!   0x{x:0>16}: {s} at ???:?:? ", .{ addr, symbol });
}

/// Init panic system (DWARF debug info)
pub fn init(allocator: std.mem.Allocator, dwarf_info: *?std.debug.Dwarf) void {
    if (builtin.strip_debug_info) {
        log.err("debug info stripped");
        return;
    }
    log.debug("debug info initialization...", .{});
    alloc = allocator;
    debug_info = dwarf_info.*;
    if (debug_info == null) {
        log.debug("Initialization of panic system successful! (debug info not available)", .{});
    } else {
        log.debug("debug info initialization successful!", .{});
    }
}
