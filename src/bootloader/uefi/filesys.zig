const std = @import("std");
const uefi = std.os.uefi;
const log = std.log.scoped(.bootfs);

/// Locate the simple file system protocol and open its root volume.
pub fn openRootFileSystem(boot_services: *uefi.tables.BootServices) !*const uefi.protocol.File {
    log.debug("locating simple file system protocol", .{});

    const res = boot_services.locateProtocol(uefi.protocol.SimpleFileSystem, null) catch |err| {
        log.err("locating simple file system protocol failed", .{});
        return err;
    };
    const file_system = res orelse {
        log.err("simple file system protocol not found!", .{});
        return error.NotFound;
    };

    log.debug("opening root volume", .{});
    return file_system.openVolume() catch |err| {
        log.err("opening root volume failed: {s}", .{@errorName(err)});
        return err;
    };
}
