const std = @import("std");
const uefi = std.os.uefi;
const Io = std.Io;

const state = @import("state.zig");

pub const fileStat = Io.failingFileStat;

pub fn fileLength(userdata: ?*anyopaque, _: Io.File) Io.File.LengthError!u64 {
    const t: *Io.Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const file = state.open_file orelse return error.Unexpected;
    // seek to all-ones = UEFI's "seek to EOF"; resulting pos is the length; restore after
    const saved = file.getPosition() catch return error.Unexpected;
    file.setPosition(std.math.maxInt(u64)) catch return error.Unexpected;
    const end_pos = file.getPosition() catch return error.Unexpected;
    file.setPosition(saved) catch return error.Unexpected;
    return end_pos;
}

pub fn fileClose(userdata: ?*anyopaque, _: []const Io.File) void {
    const t: *Io.Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    // Io.File is the single open-file slot (see state.zig)
    if (state.open_file) |file| {
        file.close() catch {};
        state.open_file = null;
    }
}

pub const fileWritePositional = Io.failingFileWritePositional;
pub const fileWriteFileStreaming = Io.noFileWriteFileStreaming;
pub const fileWriteFilePositional = Io.noFileWriteFilePositional;

pub fn fileReadPositional(userdata: ?*anyopaque, _: Io.File, data: []const []u8, offset: u64) Io.File.ReadPositionalError!usize {
    const t: *Io.Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const file = state.open_file orelse return error.Unexpected;
    file.setPosition(offset) catch return error.Unexpected;
    var total: usize = 0;
    for (data) |buffer| {
        if (buffer.len == 0) continue;
        const n = file.read(buffer) catch return error.InputOutput;
        total += n;
        // short read = EOF; return bytes available (0 at/past end)
        if (n < buffer.len) break;
    }
    return total;
}

pub const fileSeekBy = Io.failingFileSeekBy;
pub const fileSeekTo = Io.failingFileSeekTo;
pub const fileSync = Io.failingFileSync;
pub const fileIsTty = Io.unreachableFileIsTty;
pub const fileEnableAnsiEscapeCodes = Io.unreachableFileEnableAnsiEscapeCodes;
pub const fileSupportsAnsiEscapeCodes = Io.unreachableFileSupportsAnsiEscapeCodes;
pub const fileSetLength = Io.failingFileSetLength;
pub const fileSetOwner = Io.failingFileSetOwner;
pub const fileSetPermissions = Io.failingFileSetPermissions;
pub const fileSetTimestamps = Io.noFileSetTimestamps;
pub const fileLock = Io.failingFileLock;
pub const fileTryLock = Io.failingFileTryLock;
pub const fileUnlock = Io.unreachableFileUnlock;
pub const fileDowngradeLock = Io.failingFileDowngradeLock;
pub const fileRealPath = Io.failingFileRealPath;
pub const fileHardLink = Io.failingFileHardLink;

pub const fileMemoryMapCreate = Io.failingFileMemoryMapCreate;
pub const fileMemoryMapDestroy = Io.unreachableFileMemoryMapDestroy;
pub const fileMemoryMapSetLength = Io.unreachableFileMemoryMapSetLength;
pub const fileMemoryMapRead = Io.unreachableFileMemoryMapRead;
pub const fileMemoryMapWrite = Io.unreachableFileMemoryMapWrite;
