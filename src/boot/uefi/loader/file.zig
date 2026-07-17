//! Generic file-reading helpers built on `std.Io` positional reads (backed
//! by the UEFI file protocol, see ../io/).

const std = @import("std");
const uefi = std.os.uefi;
const Io = std.Io;
const log = std.log.scoped(.bootfile);

/// Read exactly `buffer.len` bytes from absolute `position` in `file`. A
/// short read here means a truncated/corrupt image, not a normal EOF.
pub fn readFile(
    io: Io,
    /// file to read
    file: Io.File,
    /// start position
    position: u64,
    /// dest buffer
    buffer: []u8,
) !void {
    const n = file.readPositionalAll(io, buffer, position) catch |err| {
        log.err("reading file failed: {s}", .{@errorName(err)});
        return err;
    };
    if (n != buffer.len) {
        log.err("short read: wanted 0x{x} bytes at offset 0x{x}, got 0x{x}", .{ buffer.len, position, n });
        return error.EndOfStream;
    }
}

/// Read a file range into a freshly allocated buffer
pub fn readAndAllocate(
    io: Io,
    /// file to read
    file: Io.File,
    /// start position
    position: u64,
    /// bytes to read
    size: usize,
    /// out: dest buffer
    buffer: *[]u8,
) !void {
    const boot_services = uefi.system_table.boot_services.?;
    // .loader_data, not the default pool: most callers freePool this once
    // done, but debug-info sections read through here stay allocated for
    // the kernel to use later
    buffer.* = boot_services.allocatePool(.loader_data, size) catch |err| {
        log.err("allocating space for file failed: {s}", .{@errorName(err)});
        return err;
    };

    try readFile(io, file, position, buffer.*);
}
