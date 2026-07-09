//! Generic UEFI file-reading helpers shared by the rest of the loader.

const std = @import("std");
const uefi = std.os.uefi;
const log = std.log.scoped(.bootfile);

/// Open `filename` off `root_file_system`, read-only.
pub fn openFile(
    root_file_system: *const uefi.protocol.File,
    filename: [*:0]const u16,
) !*uefi.protocol.File {
    return root_file_system.open(
        filename,
        .read,
        .{ .read_only = true },
    ) catch |err| {
        log.err("opening file failed: {s}", .{@errorName(err)});
        return err;
    };
}

/// Read a UEFI file
pub fn readFile(
    /// This is our file we want to read
    file: *uefi.protocol.File,
    /// This is the start position we want to read from
    position: u64,
    /// And the buffer we want to read into
    buffer: []u8,
) !void {
    // We set the position in the file we want to read from
    file.setPosition(position) catch |err| {
        log.err("setting file position failed: {s}", .{@errorName(err)});
        return err;
    };

    // Now, we can read the file. `read` returns the number of bytes actually
    // read, which we don't need here (the caller already knows the size it
    // asked for), so we discard it.
    // You may have recognized I return the error immediately (not handling it
    // as above). But this is the last thing we do, so we may as well just
    // "try" it.
    _ = try file.read(buffer);
}

/// Read a UEFI file and allocate free memory for it
pub fn readAndAllocate(
    /// This is our file we want to read
    file: *uefi.protocol.File,
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

    // As described above (in readFile), we just return the status of another
    // function.
    try readFile(file, position, buffer.*);
}
