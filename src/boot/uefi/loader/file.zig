//! Generic file-reading helpers shared by the rest of the loader, built on
//! `std.Io` positional reads (backed by the UEFI file protocol via the
//! bootloader's `Io` implementation in ../io/).

const std = @import("std");
const uefi = std.os.uefi;
const Io = std.Io;
const log = std.log.scoped(.bootfile);

/// Read exactly `buffer.len` bytes from absolute `position` in `file`.
/// Callers always know the exact size they want (from ELF headers), so a
/// short read here means a truncated/corrupt image, not a normal EOF.
pub fn readFile(
    io: Io,
    /// This is our file we want to read
    file: Io.File,
    /// This is the start position we want to read from
    position: u64,
    /// And the buffer we want to read into
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

/// Read a file range and allocate free memory for it
pub fn readAndAllocate(
    io: Io,
    /// This is our file we want to read
    file: Io.File,
    /// This is the start position we want to read from
    position: u64,
    /// How much we want to read
    size: usize,
    /// And the buffer we want to read into
    buffer: *[]u8,
) !void {
    // We need the boot services to do that.
    const boot_services = uefi.system_table.boot_services.?;
    // Then, we allocate some memory for the file. We use the `.loader_data`
    // memory type rather than the default boot-services pool; most callers
    // still `freePool` this buffer once they're done with it, but the
    // debug-info sections read through this function are kept around
    // un-freed for the kernel to use later.
    buffer.* = boot_services.allocatePool(.loader_data, size) catch |err| {
        log.err("allocating space for file failed: {s}", .{@errorName(err)});
        return err;
    };

    try readFile(io, file, position, buffer.*);
}
