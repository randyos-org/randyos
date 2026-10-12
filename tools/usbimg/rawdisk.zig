//! Whole-disk discovery and raw writes for the host OS (Windows, Linux).

const std = @import("std");
const builtin = @import("builtin");
const rstd = @import("rstd");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const Bus = enum {
    usb,
    sd,
    other,

    /// Buses a removable boot stick plausibly sits on.
    pub fn eligible(b: Bus) bool {
        return b != .other;
    }
};

pub const Disk = struct {
    /// What the user passes to `burn`: disk number (Windows) or /dev path.
    id: []const u8,
    path: []const u8,
    size: u64,
    sector_size: u32,
    bus: Bus,
    model: []const u8,
    /// Holds the running OS; never written to.
    system: bool,
    /// Mountpoints of its partitions (Linux); burning refuses while set.
    mounts: []const u8 = "",
};

pub const Error = error{ UnsupportedHost, NoSuchDisk, AccessDenied, Win32 } || Allocator.Error || Io.Cancelable;

pub fn list(arena: Allocator, io: Io) ![]Disk {
    return switch (builtin.os.tag) {
        .windows => windows.list(arena),
        .linux => linux.list(arena, io),
        else => error.UnsupportedHost,
    };
}

pub fn find(arena: Allocator, io: Io, id: []const u8) !Disk {
    return switch (builtin.os.tag) {
        .windows => (try windows.describe(arena, try windows.parseId(id))) orelse error.NoSuchDisk,
        .linux => linux.describe(arena, io, std.fs.path.basename(id)) catch error.NoSuchDisk,
        else => error.UnsupportedHost,
    };
}

/// Exclusive raw write access to a disk; its volumes stay unmounted until `close`.
pub const Target = switch (builtin.os.tag) {
    .windows => windows.Writer,
    .linux => linux.Writer,
    else => struct {
        pub fn open(_: Allocator, _: Io, _: Disk) !@This() {
            return error.UnsupportedHost;
        }
        pub fn write(_: *@This(), _: u64, _: []const u8) !void {}
        pub fn close(_: *@This()) !void {}
    },
};

const windows = struct {
    const w = rstd.win32.everything;
    const HANDLE = w.HANDLE;

    /// GENERIC_READ | GENERIC_WRITE; zigwin32's access flags lack the generic bits.
    const generic_rw: w.FILE_ACCESS_FLAGS = @bitCast(@as(u32, 0xC000_0000));
    const share_rw: w.FILE_SHARE_MODE = .{ .READ = 1, .WRITE = 1 };

    fn fail(what: []const u8) Error {
        const code = w.GetLastError();
        if (code == w.ERROR_ACCESS_DENIED) return error.AccessDenied;
        std.debug.print("{s} failed: Win32 error {d}\n", .{ what, @backingInt(code) });
        return error.Win32;
    }

    fn openDevice(path: [*:0]const u16, access: w.FILE_ACCESS_FLAGS, flags: w.FILE_FLAGS_AND_ATTRIBUTES) ?HANDLE {
        const h = w.CreateFileW(path, access, share_rw, null, .OPEN_EXISTING, flags, null);
        return if (h == w.INVALID_HANDLE_VALUE) null else h;
    }

    /// Bytes returned, or null on failure.
    fn ioctl(h: HANDLE, code: u32, in: ?*anyopaque, in_len: usize, out: ?*anyopaque, out_len: usize) ?u32 {
        var got: u32 = 0;
        if (w.DeviceIoControl(h, code, in, @intCast(in_len), out, @intCast(out_len), &got, null) == 0) return null;
        return got;
    }

    fn parseId(id: []const u8) !u32 {
        const prefix = "\\\\.\\PhysicalDrive";
        const digits = if (std.ascii.startsWithIgnoreCase(id, prefix)) id[prefix.len..] else id;
        return std.fmt.parseInt(u32, digits, 10) catch error.NoSuchDisk;
    }

    fn drivePath(arena: Allocator, n: u32) ![:0]const u16 {
        return std.unicode.utf8ToUtf16LeAllocZ(arena, try std.fmt.allocPrint(arena, "\\\\.\\PhysicalDrive{d}", .{n})) catch |e| switch (e) {
            error.InvalidUtf8 => unreachable,
            else => |oom| oom,
        };
    }

    /// Disk numbers a volume spans, or none if it isn't disk-backed.
    fn volumeDisks(h: HANDLE, out: []u32) []u32 {
        const max = 16;
        var buf: extern struct { head: w.VOLUME_DISK_EXTENTS, more: [max - 1]w.DISK_EXTENT } = undefined;
        _ = ioctl(h, w.IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS, null, 0, &buf, @sizeOf(@TypeOf(buf))) orelse return out[0..0];
        const extents: [*]const w.DISK_EXTENT = &buf.head.Extents;
        const n = @min(buf.head.NumberOfDiskExtents, max, out.len);
        for (out[0..n], extents[0..n]) |*d, e| d.* = e.DiskNumber;
        return out[0..n];
    }

    fn systemDisk() ?u32 {
        var dir: [260:0]u16 = undefined;
        if (w.GetSystemWindowsDirectoryW(&dir, dir.len) < 2) return null;
        var path = std.unicode.utf8ToUtf16LeStringLiteral("\\\\.\\C:").*;
        path[4] = dir[0];
        const h = openDevice(&path, .{}, .{}) orelse return null;
        defer _ = w.CloseHandle(h);
        var disks: [16]u32 = undefined;
        const d = volumeDisks(h, &disks);
        return if (d.len > 0) d[0] else null;
    }

    fn describe(arena: Allocator, n: u32) Error!?Disk {
        const h = openDevice(try drivePath(arena, n), .{}, .{}) orelse return null;
        defer _ = w.CloseHandle(h);

        var geo: w.DISK_GEOMETRY_EX = undefined;
        _ = ioctl(h, w.IOCTL_DISK_GET_DRIVE_GEOMETRY_EX, null, 0, &geo, @sizeOf(w.DISK_GEOMETRY_EX)) orelse return null;

        var query: w.STORAGE_PROPERTY_QUERY = .{ .PropertyId = w.StorageDeviceProperty, .QueryType = w.PropertyStandardQuery, .AdditionalParameters = .{0} };
        // Descriptor followed by its vendor/product strings.
        var desc: extern union { d: w.STORAGE_DEVICE_DESCRIPTOR, raw: [1024]u8 } = .{ .raw = @splat(0) };
        const got = ioctl(h, w.IOCTL_STORAGE_QUERY_PROPERTY, &query, @sizeOf(w.STORAGE_PROPERTY_QUERY), &desc, @sizeOf(@TypeOf(desc))) orelse 0;
        var model: std.ArrayList(u8) = .empty;
        var bus: Bus = .other;
        if (got >= @offsetOf(w.STORAGE_DEVICE_DESCRIPTOR, "RawPropertiesLength")) {
            // Read as an integer; drivers may report bus types newer than the enum.
            const bus_raw = std.mem.readInt(i32, desc.raw[@offsetOf(w.STORAGE_DEVICE_DESCRIPTOR, "BusType")..][0..4], .little);
            bus = if (bus_raw == @backingInt(w.BusTypeUsb))
                .usb
            else if (bus_raw == @backingInt(w.BusTypeSd) or bus_raw == @backingInt(w.BusTypeMmc))
                .sd
            else
                .other;
            for ([_]u32{ desc.d.VendorIdOffset, desc.d.ProductIdOffset }) |off| {
                if (off == 0 or off >= got) continue;
                const s = std.mem.trim(u8, std.mem.sliceTo(desc.raw[off..got], 0), " ");
                if (s.len == 0) continue;
                if (model.items.len > 0) try model.append(arena, ' ');
                try model.appendSlice(arena, s);
            }
        }
        return .{
            .id = try std.fmt.allocPrint(arena, "{d}", .{n}),
            .path = try std.fmt.allocPrint(arena, "\\\\.\\PhysicalDrive{d}", .{n}),
            .size = @intCast(geo.DiskSize.QuadPart),
            .sector_size = geo.Geometry.BytesPerSector,
            .bus = bus,
            .model = model.items,
            .system = systemDisk() == n,
        };
    }

    fn list(arena: Allocator) ![]Disk {
        var disks: std.ArrayList(Disk) = .empty;
        for (0..64) |n| {
            if (try describe(arena, @intCast(n))) |d| try disks.append(arena, d);
        }
        return disks.items;
    }

    const Writer = struct {
        drive: HANDLE,
        volumes: std.ArrayList(HANDLE),
        arena: Allocator,

        pub fn open(arena: Allocator, _: Io, disk: Disk) !Writer {
            const n = try parseId(disk.id);
            var t: Writer = .{ .drive = w.INVALID_HANDLE_VALUE, .volumes = .empty, .arena = arena };
            errdefer t.closeVolumes();
            try t.dismountVolumes(n);
            t.drive = openDevice(try drivePath(arena, n), generic_rw, w.FILE_FLAG_WRITE_THROUGH) orelse return fail("opening the disk");
            return t;
        }

        /// Locks and dismounts every volume on disk `n`; Windows refuses raw
        /// writes into a mounted volume's sectors.
        fn dismountVolumes(t: *Writer, n: u32) !void {
            var name: [64:0]u16 = undefined;
            const find_h = w.FindFirstVolumeW(&name, name.len);
            if (find_h == -1) return fail("listing volumes");
            defer _ = w.FindVolumeClose(find_h);
            while (true) {
                // "\\?\Volume{...}\" names the root dir; drop the '\' to get the volume.
                const len = std.mem.indexOfScalar(u16, &name, 0).?;
                name[len - 1] = 0;
                const vol = openDevice(name[0 .. len - 1 :0], generic_rw, .{}) orelse return fail("opening a volume");
                var disks: [16]u32 = undefined;
                if (std.mem.indexOfScalar(u32, volumeDisks(vol, &disks), n) != null) {
                    try t.volumes.append(t.arena, vol);
                    try lockVolume(vol);
                } else _ = w.CloseHandle(vol);
                if (w.FindNextVolumeW(find_h, &name, name.len) == 0) break;
            }
        }

        fn lockVolume(vol: HANDLE) !void {
            for (0..20) |_| {
                if (ioctl(vol, w.FSCTL_LOCK_VOLUME, null, 0, null, 0) != null) break;
                w.Sleep(250);
            } else {
                // Forced dismount invalidates open handles, after which the lock succeeds.
                _ = ioctl(vol, w.FSCTL_DISMOUNT_VOLUME, null, 0, null, 0);
                if (ioctl(vol, w.FSCTL_LOCK_VOLUME, null, 0, null, 0) == null) return fail("locking a volume on the disk (close anything using it)");
            }
            if (ioctl(vol, w.FSCTL_DISMOUNT_VOLUME, null, 0, null, 0) == null) return fail("dismounting a volume");
        }

        fn closeVolumes(t: *Writer) void {
            for (t.volumes.items) |v| _ = w.CloseHandle(v);
            t.volumes.clearRetainingCapacity();
        }

        pub fn write(t: *Writer, lba: u64, bytes: []const u8) !void {
            if (w.SetFilePointerEx(t.drive, .{ .QuadPart = @intCast(lba * 512) }, null, w.FILE_BEGIN) == 0) return fail("seeking on the disk");
            var rest = bytes;
            while (rest.len > 0) {
                const chunk: u32 = @intCast(@min(rest.len, 1 << 20));
                var done: u32 = 0;
                if (w.WriteFile(t.drive, rest.ptr, chunk, &done, null) == 0) return fail("writing to the disk");
                rest = rest[done..];
            }
        }

        pub fn close(t: *Writer) !void {
            defer t.closeVolumes();
            defer _ = w.CloseHandle(t.drive);
            if (w.FlushFileBuffers(t.drive) == 0) return fail("flushing the disk");
            // Have Windows re-read the new partition table.
            _ = ioctl(t.drive, w.IOCTL_DISK_UPDATE_PROPERTIES, null, 0, null, 0);
        }
    };
};

const linux = struct {
    fn readSys(arena: Allocator, io: Io, comptime fmt: []const u8, args: anytype) ![]const u8 {
        const path = try std.fmt.allocPrint(arena, fmt, args);
        const raw = try Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(4096));
        return std.mem.trim(u8, raw, " \n\t");
    }

    /// Mountpoints of `/dev/<name>` and its partitions, space separated.
    fn mountsOf(arena: Allocator, io: Io, name: []const u8) ![]const u8 {
        const mounts = try Io.Dir.cwd().readFileAlloc(io, "/proc/mounts", arena, .limited(1 << 20));
        var out: std.ArrayList(u8) = .empty;
        var lines = std.mem.tokenizeScalar(u8, mounts, '\n');
        while (lines.next()) |line| {
            var fields = std.mem.tokenizeScalar(u8, line, ' ');
            const dev = fields.next() orelse continue;
            const at = fields.next() orelse continue;
            if (!std.mem.startsWith(u8, dev, "/dev/") or !std.mem.startsWith(u8, dev[5..], name)) continue;
            const rest = dev[5 + name.len ..];
            if (rest.len > 0 and !std.ascii.isDigit(rest[0]) and rest[0] != 'p') continue;
            if (out.items.len > 0) try out.append(arena, ' ');
            try out.appendSlice(arena, at);
        }
        return out.items;
    }

    fn describe(arena: Allocator, io: Io, name: []const u8) !Disk {
        var link_buf: [4096]u8 = undefined;
        const link_path = try std.fmt.allocPrint(arena, "/sys/block/{s}", .{name});
        const link = link_buf[0..try Io.Dir.cwd().readLink(io, link_path, &link_buf)];
        const vendor = readSys(arena, io, "/sys/block/{s}/device/vendor", .{name}) catch "";
        const model = readSys(arena, io, "/sys/block/{s}/device/model", .{name}) catch "";
        const mounts = try mountsOf(arena, io, name);
        var system = false;
        var it = std.mem.tokenizeScalar(u8, mounts, ' ');
        while (it.next()) |m| {
            for ([_][]const u8{ "/", "/boot", "/boot/efi", "/usr", "/home" }) |sys| system = system or std.mem.eql(u8, m, sys);
        }
        return .{
            .id = try std.fmt.allocPrint(arena, "/dev/{s}", .{name}),
            .path = try std.fmt.allocPrint(arena, "/dev/{s}", .{name}),
            .size = 512 * try std.fmt.parseInt(u64, try readSys(arena, io, "/sys/block/{s}/size", .{name}), 10),
            .sector_size = try std.fmt.parseInt(u32, try readSys(arena, io, "/sys/block/{s}/queue/logical_block_size", .{name}), 10),
            .bus = if (std.mem.indexOf(u8, link, "/usb") != null) .usb else if (std.mem.indexOf(u8, link, "/mmc") != null) .sd else .other,
            .model = try std.mem.join(arena, " ", &.{ vendor, model }),
            .system = system,
            .mounts = mounts,
        };
    }

    fn list(arena: Allocator, io: Io) ![]Disk {
        var dir = try Io.Dir.cwd().openDir(io, "/sys/block", .{ .iterate = true });
        defer dir.close(io);
        var disks: std.ArrayList(Disk) = .empty;
        var it = dir.iterate();
        while (try it.next(io)) |e| {
            for ([_][]const u8{ "loop", "ram", "zram", "dm-", "md", "sr" }) |skip| {
                if (std.mem.startsWith(u8, e.name, skip)) break;
            } else {
                const name = try arena.dupe(u8, e.name);
                try disks.append(arena, describe(arena, io, name) catch continue);
            }
        }
        return disks.items;
    }

    const Writer = struct {
        file: Io.File,
        io: Io,

        pub fn open(_: Allocator, io: Io, disk: Disk) !Writer {
            const file = Io.Dir.cwd().openFile(io, disk.path, .{ .mode = .read_write }) catch |e| switch (e) {
                error.AccessDenied, error.PermissionDenied => return error.AccessDenied,
                else => |other| return other,
            };
            return .{ .file = file, .io = io };
        }

        pub fn write(t: *Writer, lba: u64, bytes: []const u8) !void {
            try t.file.writePositionalAll(t.io, bytes, lba * 512);
        }

        pub fn close(t: *Writer) !void {
            defer t.file.close(t.io);
            try t.file.sync(t.io);
            const blkrrpart = 0x125F;
            _ = std.os.linux.ioctl(t.file.handle, blkrrpart, 0);
        }
    };
};
