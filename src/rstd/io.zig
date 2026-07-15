const sysinfo = @import("builtin");
const std = @import("std");

pub const io = switch (sysinfo.os.tag) {
    .linux, .macos, .freebsd, .openbsd, .netbsd, .dragonfly => std.Io,
    .uefi => @import("_os/uefi/io/__root__.zig"),
    else => null,
};

pub const Threaded = io.Threaded;
