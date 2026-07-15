const std = @import("std");
const uefi = std.os.uefi;
const Io = std.Io;
const log = std.log.scoped(.bootfs);

const state = @import("state.zig");
const unsupported = @import("__root__.zig").unsupported;

/// Locate the Simple File System protocol and open its root volume into
/// `state.root_dir`, returning the (handle-less, see state.zig) `Io.Dir`
/// token for it. Idempotent: subsequent calls reuse the already-open volume.
pub fn openRootDir() !Io.Dir {
    if (state.root_dir == null) {
        const bs = state.bootServices() orelse return error.BootServicesUnavailable;

        log.debug("locating simple file system protocol", .{});
        const res = bs.locateProtocol(uefi.protocol.SimpleFileSystem, null) catch |err| {
            log.err("locating simple file system protocol failed", .{});
            return err;
        };
        const file_system = res orelse {
            log.err("simple file system protocol not found!", .{});
            return error.NotFound;
        };

        log.debug("opening root volume", .{});
        state.root_dir = file_system.openVolume() catch |err| {
            log.err("opening root volume failed: {s}", .{@errorName(err)});
            return err;
        };
    }
    return .{ .handle = {} };
}

pub fn dirCreateDir(_: ?*anyopaque, _: Io.Dir, _: []const u8, _: Io.Dir.Permissions) Io.Dir.CreateDirError!void {
    unsupported(@src());
}

pub fn dirCreateDirPath(_: ?*anyopaque, _: Io.Dir, _: []const u8, _: Io.Dir.Permissions) Io.Dir.CreateDirPathError!Io.Dir.CreatePathStatus {
    unsupported(@src());
}

pub fn dirCreateDirPathOpen(_: ?*anyopaque, _: Io.Dir, _: []const u8, _: Io.Dir.Permissions, _: Io.Dir.OpenOptions) Io.Dir.CreateDirPathOpenError!Io.Dir {
    unsupported(@src());
}

pub fn dirOpenDir(_: ?*anyopaque, _: Io.Dir, _: []const u8, _: Io.Dir.OpenOptions) Io.Dir.OpenError!Io.Dir {
    unsupported(@src());
}

pub fn dirStat(_: ?*anyopaque, _: Io.Dir) Io.Dir.StatError!Io.Dir.Stat {
    unsupported(@src());
}

pub fn dirStatFile(_: ?*anyopaque, _: Io.Dir, _: []const u8, _: Io.Dir.StatFileOptions) Io.Dir.StatFileError!Io.File.Stat {
    unsupported(@src());
}

pub fn dirAccess(_: ?*anyopaque, _: Io.Dir, _: []const u8, _: Io.Dir.AccessOptions) Io.Dir.AccessError!void {
    unsupported(@src());
}

pub fn dirCreateFile(_: ?*anyopaque, _: Io.Dir, _: []const u8, _: Io.Dir.CreateFileOptions) Io.File.OpenError!Io.File {
    unsupported(@src());
}

pub fn dirCreateFileAtomic(_: ?*anyopaque, _: Io.Dir, _: []const u8, _: Io.Dir.CreateFileAtomicOptions) Io.Dir.CreateFileAtomicError!Io.File.Atomic {
    unsupported(@src());
}

pub fn dirOpenFile(_: ?*anyopaque, _: Io.Dir, sub_path: []const u8, options: Io.Dir.OpenFileOptions) Io.File.OpenError!Io.File {
    // The boot volume is the only directory in existence (see state.zig),
    // and this bootloader only ever reads from it.
    if (options.mode != .read_only) return error.ReadOnlyFileSystem;
    const root = state.root_dir orelse return error.Unexpected; // openRootDir was never called
    if (state.open_file != null) {
        // `Io.File` carries no handle bits on UEFI, so a second
        // simultaneously-open file would be indistinguishable from the
        // first. "Too many open files" is the honest POSIX spelling of
        // that limit (which here is 1).
        return error.ProcessFdQuotaExceeded;
    }

    // UEFI wants UCS-2 with backslash separators.
    var path_utf16: [128:0]u16 = undefined;
    if (sub_path.len >= path_utf16.len) return error.NameTooLong;
    const len = std.unicode.utf8ToUtf16Le(&path_utf16, sub_path) catch return error.BadPathName;
    for (path_utf16[0..len]) |*unit| {
        if (unit.* == '/') unit.* = '\\';
    }
    path_utf16[len] = 0;

    const opened = root.open(path_utf16[0..len :0], .read, .{}) catch |err| return switch (err) {
        error.NotFound => error.FileNotFound,
        error.AccessDenied => error.AccessDenied,
        error.OutOfResources => error.SystemResources,
        error.WriteProtected => error.ReadOnlyFileSystem,
        error.VolumeFull => error.NoSpaceLeft,
        error.InvalidParameter => error.BadPathName,
        error.NoMedia, error.MediaChanged, error.DeviceError, error.VolumeCorrupted => error.NoDevice,
        error.Unexpected => error.Unexpected,
    };
    state.open_file = opened;
    return .{ .handle = {}, .flags = .{ .nonblocking = false } };
}

pub fn dirClose(_: ?*anyopaque, _: []const Io.Dir) void {
    // Every Io.Dir is the boot volume root (see state.zig).
    if (state.root_dir) |root| {
        root.close() catch {};
        state.root_dir = null;
    }
}

pub fn dirRead(_: ?*anyopaque, _: *Io.Dir.Reader, _: []Io.Dir.Entry) Io.Dir.Reader.Error!usize {
    unsupported(@src());
}

pub fn dirRealPath(_: ?*anyopaque, _: Io.Dir, _: []u8) Io.Dir.RealPathError!usize {
    unsupported(@src());
}

pub fn dirRealPathFile(_: ?*anyopaque, _: Io.Dir, _: []const u8, _: []u8) Io.Dir.RealPathFileError!usize {
    unsupported(@src());
}

pub fn dirDeleteFile(_: ?*anyopaque, _: Io.Dir, _: []const u8) Io.Dir.DeleteFileError!void {
    unsupported(@src());
}

pub fn dirDeleteDir(_: ?*anyopaque, _: Io.Dir, _: []const u8) Io.Dir.DeleteDirError!void {
    unsupported(@src());
}

pub fn dirRename(_: ?*anyopaque, _: Io.Dir, _: []const u8, _: Io.Dir, _: []const u8) Io.Dir.RenameError!void {
    unsupported(@src());
}

pub fn dirRenamePreserve(_: ?*anyopaque, _: Io.Dir, _: []const u8, _: Io.Dir, _: []const u8) Io.Dir.RenamePreserveError!void {
    unsupported(@src());
}

pub fn dirSymLink(_: ?*anyopaque, _: Io.Dir, _: []const u8, _: []const u8, _: Io.Dir.SymLinkFlags) Io.Dir.SymLinkError!void {
    unsupported(@src());
}

pub fn dirReadLink(_: ?*anyopaque, _: Io.Dir, _: []const u8, _: []u8) Io.Dir.ReadLinkError!usize {
    unsupported(@src());
}

pub fn dirSetOwner(_: ?*anyopaque, _: Io.Dir, _: ?Io.File.Uid, _: ?Io.File.Gid) Io.Dir.SetOwnerError!void {
    unsupported(@src());
}

pub fn dirSetFileOwner(_: ?*anyopaque, _: Io.Dir, _: []const u8, _: ?Io.File.Uid, _: ?Io.File.Gid, _: Io.Dir.SetFileOwnerOptions) Io.Dir.SetFileOwnerError!void {
    unsupported(@src());
}

pub fn dirSetPermissions(_: ?*anyopaque, _: Io.Dir, _: Io.Dir.Permissions) Io.Dir.SetPermissionsError!void {
    unsupported(@src());
}

pub fn dirSetFilePermissions(_: ?*anyopaque, _: Io.Dir, _: []const u8, _: Io.File.Permissions, _: Io.Dir.SetFilePermissionsOptions) Io.Dir.SetFilePermissionsError!void {
    unsupported(@src());
}

pub fn dirSetTimestamps(_: ?*anyopaque, _: Io.Dir, _: []const u8, _: Io.Dir.SetTimestampsOptions) Io.Dir.SetTimestampsError!void {
    unsupported(@src());
}

pub fn dirHardLink(_: ?*anyopaque, _: Io.Dir, _: []const u8, _: Io.Dir, _: []const u8, _: Io.Dir.HardLinkOptions) Io.Dir.HardLinkError!void {
    unsupported(@src());
}
