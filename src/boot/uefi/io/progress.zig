const std = @import("std");
const uefi = std.os.uefi;
const Io = std.Io;

const unsupported = @import("__root__.zig").unsupported;

pub fn progressParentFile(_: ?*anyopaque) std.Progress.ParentFileError!Io.File {
    unsupported(@src());
}
