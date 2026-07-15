const std = @import("std");
const uefi = std.os.uefi;
const Io = std.Io;

const state = @import("state.zig");
const unsupported = @import("__root__.zig").unsupported;

pub fn fileStat(_: ?*anyopaque, _: Io.File) Io.File.StatError!Io.File.Stat {
    unsupported(@src());
}

pub fn fileLength(_: ?*anyopaque, _: Io.File) Io.File.LengthError!u64 {
    const file = state.open_file orelse return error.Unexpected;
    // Setting the position to all-ones is the UEFI-blessed "seek to end of
    // file"; the resulting position *is* the length. Restore afterwards so
    // this stays observation-only.
    const saved = file.getPosition() catch return error.Unexpected;
    file.setPosition(std.math.maxInt(u64)) catch return error.Unexpected;
    const end_pos = file.getPosition() catch return error.Unexpected;
    file.setPosition(saved) catch return error.Unexpected;
    return end_pos;
}

pub fn fileClose(_: ?*anyopaque, _: []const Io.File) void {
    // Every Io.File is the single open-file slot (see state.zig).
    if (state.open_file) |file| {
        file.close() catch {};
        state.open_file = null;
    }
}

pub fn fileWritePositional(_: ?*anyopaque, _: Io.File, _: []const u8, _: []const []const u8, _: usize, _: u64) Io.File.WritePositionalError!usize {
    unsupported(@src());
}

pub fn fileWriteFileStreaming(_: ?*anyopaque, _: Io.File, _: []const u8, _: *Io.File.Reader, _: Io.Limit) Io.File.Writer.WriteFileError!usize {
    unsupported(@src());
}

pub fn fileWriteFilePositional(_: ?*anyopaque, _: Io.File, _: []const u8, _: *Io.File.Reader, _: Io.Limit, _: u64) Io.File.WriteFilePositionalError!usize {
    unsupported(@src());
}

pub fn fileReadPositional(_: ?*anyopaque, _: Io.File, data: []const []u8, offset: u64) Io.File.ReadPositionalError!usize {
    const file = state.open_file orelse return error.Unexpected;
    file.setPosition(offset) catch return error.Unexpected;
    var total: usize = 0;
    for (data) |buffer| {
        if (buffer.len == 0) continue;
        const n = file.read(buffer) catch return error.InputOutput;
        total += n;
        // A short read means end of file: the contract is to return however
        // many bytes were available (0 when at/past the end).
        if (n < buffer.len) break;
    }
    return total;
}

pub fn fileSeekBy(_: ?*anyopaque, _: Io.File, _: i64) Io.File.SeekError!void {
    unsupported(@src());
}

pub fn fileSeekTo(_: ?*anyopaque, _: Io.File, _: u64) Io.File.SeekError!void {
    unsupported(@src());
}

pub fn fileSync(_: ?*anyopaque, _: Io.File) Io.File.SyncError!void {
    unsupported(@src());
}

pub fn fileIsTty(_: ?*anyopaque, _: Io.File) Io.Cancelable!bool {
    unsupported(@src());
}

pub fn fileEnableAnsiEscapeCodes(_: ?*anyopaque, _: Io.File) Io.File.EnableAnsiEscapeCodesError!void {
    unsupported(@src());
}

pub fn fileSupportsAnsiEscapeCodes(_: ?*anyopaque, _: Io.File) Io.Cancelable!bool {
    unsupported(@src());
}

pub fn fileSetLength(_: ?*anyopaque, _: Io.File, _: u64) Io.File.SetLengthError!void {
    unsupported(@src());
}

pub fn fileSetOwner(_: ?*anyopaque, _: Io.File, _: ?Io.File.Uid, _: ?Io.File.Gid) Io.File.SetOwnerError!void {
    unsupported(@src());
}

pub fn fileSetPermissions(_: ?*anyopaque, _: Io.File, _: Io.File.Permissions) Io.File.SetPermissionsError!void {
    unsupported(@src());
}

pub fn fileSetTimestamps(_: ?*anyopaque, _: Io.File, _: Io.File.SetTimestampsOptions) Io.File.SetTimestampsError!void {
    unsupported(@src());
}

pub fn fileLock(_: ?*anyopaque, _: Io.File, _: Io.File.Lock) Io.File.LockError!void {
    unsupported(@src());
}

pub fn fileTryLock(_: ?*anyopaque, _: Io.File, _: Io.File.Lock) Io.File.LockError!bool {
    unsupported(@src());
}

pub fn fileUnlock(_: ?*anyopaque, _: Io.File) void {
    unsupported(@src());
}

pub fn fileDowngradeLock(_: ?*anyopaque, _: Io.File) Io.File.DowngradeLockError!void {
    unsupported(@src());
}

pub fn fileRealPath(_: ?*anyopaque, _: Io.File, _: []u8) Io.File.RealPathError!usize {
    unsupported(@src());
}

pub fn fileHardLink(_: ?*anyopaque, _: Io.File, _: Io.Dir, _: []const u8, _: Io.File.HardLinkOptions) Io.File.HardLinkError!void {
    unsupported(@src());
}

pub fn fileMemoryMapCreate(_: ?*anyopaque, _: Io.File, _: Io.File.MemoryMap.CreateOptions) Io.File.MemoryMap.CreateError!Io.File.MemoryMap {
    unsupported(@src());
}

pub fn fileMemoryMapDestroy(_: ?*anyopaque, _: *Io.File.MemoryMap) void {
    unsupported(@src());
}

pub fn fileMemoryMapSetLength(_: ?*anyopaque, _: *Io.File.MemoryMap, _: usize) Io.File.MemoryMap.SetLengthError!void {
    unsupported(@src());
}

pub fn fileMemoryMapRead(_: ?*anyopaque, _: *Io.File.MemoryMap) Io.File.ReadPositionalError!void {
    unsupported(@src());
}

pub fn fileMemoryMapWrite(_: ?*anyopaque, _: *Io.File.MemoryMap) Io.File.WritePositionalError!void {
    unsupported(@src());
}
