const sysinfo = @import("builtin");
const std = @import("std");
const Io = std.Io;

const native_os = sysinfo.os.tag;
const is_windows = native_os == .windows;
const have_networking = std.options.networking and native_os != .wasi;

/// Stub: no real backing yet for streaming file I/O, raw device ioctl, or
/// networking on UEFI (unlike `dir.zig`/`file.zig`'s positional file ops,
/// which DO have real Simple File System-backed implementations). `userdata`
/// deliberately untyped/unused here -- see `__root__.zig` doc comment for why
/// this can't be `*std.Io.Threaded`. Each arm below just reports the
/// operation as unavailable for now; replace with a real implementation as
/// each is added.
pub fn operate(userdata: ?*anyopaque, operation: Io.Operation) Io.Cancelable!Io.Operation.Result {
    _ = userdata;
    return switch (operation) {
        .file_read_streaming => .{
            // TODO: back with root.open()/File.read() like file.zig's fileReadPositional
            .file_read_streaming = error.InputOutput,
        },
        .file_write_streaming => .{
            // TODO: back with File.write() like fileReadPositional's read counterpart
            .file_write_streaming = error.InputOutput,
        },
        .device_io_control => unreachable, // no UEFI ioctl-equivalent planned
        .net_receive => .{
            // TODO: back with EFI network protocols (see net.zig)
            .net_receive = .{ error.NetworkDown, 0 },
        },
        .net_read => .{
            // TODO: back with EFI network protocols (see net.zig)
            .net_read = error.NetworkDown,
        },
    };
}
