const sysinfo = @import("builtin");
const std = @import("std");
const Io = std.Io;
const Threaded = Io.Threaded;

const native_os = sysinfo.os.tag;
const is_windows = native_os == .windows;
const have_networking = std.options.networking and native_os != .wasi;

pub fn operate(userdata: ?*anyopaque, operation: Io.Operation) Io.Cancelable!Io.Operation.Result {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    switch (operation) {
        .file_read_streaming => return .{
            // .file_read_streaming = Threaded.fileReadStreaming(t, o.file, o.data) catch |err| switch (err) {
            //     error.Canceled => |e| return e,
            //     else => |e| e,
            // },
        },
        .file_write_streaming => return .{
            // .file_write_streaming = Threaded.fileWriteStreaming(t, o.file, o.header, o.data, o.splat) catch |err| switch (err) {
            //     error.Canceled => |e| return e,
            //     else => |e| e,
            // },
        },
        .device_io_control => return .{
            // .device_io_control = try Threaded.deviceIoControl(o)
        },
        .net_receive => return .{ .net_receive = .{ error.NetworkDown, 0 } },
        .net_read => return .{
            // .net_read = Threaded.netRead(o.socket_handle, o.data) catch |err| switch (err) {
            //     error.Canceled => |e| return e,
            //     else => |e| e,
            // },
        },
    }
}
