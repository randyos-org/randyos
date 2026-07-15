const std = @import("std");
const uefi = std.os.uefi;
const Io = std.Io;

const unsupported = @import("__root__.zig").unsupported;

pub fn processExecutableOpen(_: ?*anyopaque, _: Io.Dir.OpenFileOptions) std.process.OpenExecutableError!Io.File {
    unsupported(@src());
}

pub fn processExecutablePath(_: ?*anyopaque, _: []u8) std.process.ExecutablePathError!usize {
    unsupported(@src());
}

pub fn processCurrentPath(_: ?*anyopaque, _: []u8) std.process.CurrentPathError!usize {
    unsupported(@src());
}

pub fn processSetCurrentDir(_: ?*anyopaque, _: Io.Dir) std.process.SetCurrentDirError!void {
    unsupported(@src());
}

pub fn processSetCurrentPath(_: ?*anyopaque, _: []const u8) std.process.SetCurrentPathError!void {
    unsupported(@src());
}

pub fn processReplace(_: ?*anyopaque, _: std.process.ReplaceOptions) std.process.ReplaceError {
    unsupported(@src());
}

pub fn processReplacePath(_: ?*anyopaque, _: Io.Dir, _: std.process.ReplaceOptions) std.process.ReplaceError {
    unsupported(@src());
}

pub fn processSpawn(_: ?*anyopaque, _: std.process.SpawnOptions) std.process.SpawnError!std.process.Child {
    unsupported(@src());
}

pub fn processSpawnPath(_: ?*anyopaque, _: Io.Dir, _: std.process.SpawnOptions) std.process.SpawnError!std.process.Child {
    unsupported(@src());
}

pub fn childWait(_: ?*anyopaque, _: *std.process.Child) std.process.Child.WaitError!std.process.Child.Term {
    unsupported(@src());
}

pub fn childKill(_: ?*anyopaque, _: *std.process.Child) void {
    unsupported(@src());
}
