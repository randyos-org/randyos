const std = @import("std");
const builtin = @import("builtin");
const log = std.log.scoped(.debug);

var already_panicking: bool = false;
var debug_info: ?std.debug.Dwarf = null;
var alloc: ?std.mem.Allocator = null;

/// Maximum number of return addresses `panic` will capture into a stack
/// trace. Plenty for any call depth this kernel actually reaches today;
/// deeper traces are simply truncated rather than growing this buffer
/// dynamically (allocation itself might be what's broken during a panic).
const max_stack_trace_depth: usize = 64;

/// Assert `ok`, panicking with the caller's location (and an optional extra
/// message) if it isn't. Meant to be called as `kassert(@src(), ok, null)`.
pub inline fn kassert(src: std.builtin.SourceLocation, ok: bool, message: ?[]const u8) void {
    if (ok) return;
    if (message) |msg| {
        std.debug.panic("assertion failed [{s} @ {s}:{d}:{d}] -- {s}", .{ src.fn_name, src.file, src.line, src.column, msg });
    } else {
        std.debug.panic("assertion failed [{s} @ {s}:{d}:{d}]", .{ src.fn_name, src.file, src.line, src.column });
    }
}

/// Panic with the caller's location plus a message. Meant to be called as
/// `kpanic(@src(), "...")`.
pub inline fn kpanic(src: std.builtin.SourceLocation, msg: []const u8) noreturn {
    std.debug.panic("panic in {s} @ {s}:{d}:{d} -- {s}", .{ src.fn_name, src.file, src.line, src.column, msg });
}

/// Handle kernel panics
pub fn panic(msg: []const u8, first_trace_addr: ?usize) noreturn {
    // A panic while already handling one means the reporting below is what
    // caused it -- don't recurse into it again, just stop here.
    if (already_panicking) while (true) {};
    already_panicking = true;

    log.err("\r\n\r\n !!! Kernel Panic !!!\r\n", .{});
    log.err(" !!! Message: {s}", .{msg});

    // Capture the raw stack trace first; whether or not there's also an
    // error return trace to report, this one is always available.
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
