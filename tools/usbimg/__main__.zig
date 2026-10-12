//! Builds a GPT disk image whose single EFI System Partition (FAT32) holds a
//! directory tree, and writes such images to removable drives.
//!
//!     usbimg mkimg <dir> <out.img>
//!     usbimg list
//!     usbimg burn <image> [<disk>] [--yes] [--any-bus]
//!
//! `<disk>` is a disk number on Windows (as in `\\.\PhysicalDriveN`) or a
//! `/dev/sdX` path on Linux. Without one, `burn` lists candidates and fails.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const fat = @import("fat.zig");
const gpt = @import("gpt.zig");
const rawdisk = @import("rawdisk.zig");

const mib_sectors = (1 << 20) / gpt.sector;
/// ESP starts 1 MiB in; the last 1 MiB holds the backup GPT.
const lead_sectors = mib_sectors;
const tail_sectors = mib_sectors;
const min_esp_mib = 64;
const label = "RANDYOS    ".*;

fn die(comptime f: []const u8, args: anytype) noreturn {
    std.debug.print("usbimg: " ++ f ++ "\n", args);
    std.process.exit(1);
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 2) die("usage: usbimg mkimg <dir> <out.img> | list | burn <image> [<disk>] [--yes] [--any-bus]", .{});
    const cmd = args[1];
    if (std.mem.eql(u8, cmd, "mkimg")) {
        if (args.len != 4) die("usage: usbimg mkimg <dir> <out.img>", .{});
        try mkimg(arena, io, args[2], args[3]);
    } else if (std.mem.eql(u8, cmd, "list")) {
        printDisks(try rawdisk.list(arena, io));
    } else if (std.mem.eql(u8, cmd, "burn")) {
        var pos: std.ArrayList([]const u8) = .empty;
        var yes = false;
        var any_bus = false;
        for (args[2..]) |a| {
            if (std.mem.eql(u8, a, "--yes")) yes = true else if (std.mem.eql(u8, a, "--any-bus")) any_bus = true else try pos.append(arena, a);
        }
        if (pos.items.len == 0 or pos.items.len > 2) die("usage: usbimg burn <image> [<disk>] [--yes] [--any-bus]", .{});
        if (pos.items.len == 1) {
            printDisks(try rawdisk.list(arena, io));
            die("no disk given; pick one above (zig build burn -Dusb-disk=<disk>)", .{});
        }
        try burn(arena, io, pos.items[0], pos.items[1], yes, any_bus);
    } else die("unknown command '{s}'", .{cmd});
}

// mkimg

fn loadDir(arena: Allocator, io: Io, dir: Io.Dir) ![]fat.Node {
    var nodes: std.ArrayList(fat.Node) = .empty;
    var it = dir.iterate();
    while (try it.next(io)) |e| {
        const name = try arena.dupe(u8, e.name);
        switch (e.kind) {
            .directory => {
                var sub = try dir.openDir(io, name, .{ .iterate = true });
                defer sub.close(io);
                try nodes.append(arena, .{ .name = name, .kind = .{ .dir = try loadDir(arena, io, sub) } });
            },
            .file, .sym_link => try nodes.append(arena, .{ .name = name, .kind = .{ .file = try dir.readFileAlloc(io, name, arena, .unlimited) } }),
            else => die("{s}: not a file or directory", .{name}),
        }
    }
    std.mem.sort(fat.Node, nodes.items, {}, struct {
        fn lt(_: void, a: fat.Node, b: fat.Node) bool {
            return std.mem.lessThan(u8, a.name, b.name);
        }
    }.lt);
    return nodes.items;
}

fn hashTree(h: *std.crypto.hash.sha2.Sha256, nodes: []const fat.Node) void {
    for (nodes) |n| {
        h.update(n.name);
        h.update(&.{0});
        switch (n.kind) {
            .file => |data| h.update(data),
            .dir => |kids| hashTree(h, kids),
        }
    }
}

const BufSink = struct {
    image: []u8,

    pub fn write(s: BufSink, lba: u64, bytes: []const u8) !void {
        @memcpy(s.image[lba * gpt.sector ..][0..bytes.len], bytes);
    }
};

fn mkimg(arena: Allocator, io: Io, src: []const u8, out: []const u8) !void {
    var dir = try Io.Dir.cwd().openDir(io, src, .{ .iterate = true });
    defer dir.close(io);
    const root: fat.Node = .{ .name = "", .kind = .{ .dir = try loadDir(arena, io, dir) } };
    const plan = try fat.Plan.init(arena, &root);

    var esp_mib: u64 = min_esp_mib;
    const g = while (true) : (esp_mib *= 2) {
        const geo = try fat.geometry(esp_mib * mib_sectors);
        if (plan.allocate(geo.cluster_sectors * fat.sector) <= geo.clusters) break geo;
    };

    // Content-derived ids keep the image reproducible.
    var h: std.crypto.hash.sha2.Sha256 = .init(.{});
    hashTree(&h, root.kind.dir);
    const digest = h.finalResult();

    const total = lead_sectors + g.sectors + tail_sectors;
    const image = try arena.alloc(u8, total * gpt.sector);
    @memset(image, 0);
    try fat.write(image[lead_sectors * gpt.sector ..][0 .. g.sectors * gpt.sector], g, plan, lead_sectors, label, std.mem.readInt(u32, digest[0..4], .little));

    var entries: [gpt.entry_sectors * gpt.sector]u8 = undefined;
    gpt.writeEntries(&entries, &.{.{
        .type_guid = gpt.esp_type,
        .unique_guid = gpt.guidFromBytes(digest[16..32].*),
        .first_lba = lead_sectors,
        .last_lba = lead_sectors + g.sectors - 1,
        .name = "EFI System Partition",
    }});
    try gpt.writeTables(gpt.guidFromBytes(digest[0..16].*), &entries, total, BufSink{ .image = image });

    var file = try Io.Dir.cwd().createFile(io, out, .{});
    defer file.close(io);
    try file.writePositionalAll(io, image, 0);
    // stdout, not stderr: the build reports a run step's stderr as a warning
    var buf: [256]u8 = undefined;
    var stdout = Io.File.stdout().writerStreaming(io, &buf);
    try stdout.interface.print("usbimg: {s}: {d} MiB image, {d} MiB ESP\n", .{ out, total / mib_sectors, esp_mib });
    try stdout.interface.flush();
}

// list / burn

fn printDisks(disks: []const rawdisk.Disk) void {
    std.debug.print("{s:<12} {s:>9}  {s:<5}  {s}\n", .{ "disk", "size", "bus", "model" });
    for (disks) |d| {
        std.debug.print("{s:<12} {d:>6} GB  {s:<5}  {s}{s}{s}{s}\n", .{
            d.id,
            d.size / 1_000_000_000,
            @tagName(d.bus),
            d.model,
            if (d.system) "  [system disk]" else "",
            if (d.mounts.len > 0) "  mounted: " else "",
            d.mounts,
        });
    }
}

fn burn(arena: Allocator, io: Io, image_path: []const u8, id: []const u8, yes: bool, any_bus: bool) !void {
    const image = try Io.Dir.cwd().readFileAlloc(io, image_path, arena, .unlimited);
    const parsed = gpt.parse(image) catch die("{s}: not a GPT image made by usbimg", .{image_path});

    const disk = rawdisk.find(arena, io, id) catch |e| switch (e) {
        error.NoSuchDisk => die("no disk '{s}'; see `zig build usb-list`", .{id}),
        else => |other| return other,
    };
    printDisks(&.{disk});
    if (disk.system) die("refusing: that disk holds the running OS", .{});
    if (!disk.bus.eligible() and !any_bus) die("refusing: not a USB/SD disk (pass --any-bus / -Dusb-any-bus to override)", .{});
    if (disk.mounts.len > 0) die("unmount its partitions first: {s}", .{disk.mounts});
    if (disk.sector_size != gpt.sector) die("unsupported logical sector size {d}", .{disk.sector_size});
    const disk_sectors = disk.size / gpt.sector;
    if (disk_sectors < parsed.used_sectors + gpt.table_sectors) die("disk too small for this image", .{});

    if (!yes) {
        std.debug.print("\nALL DATA on disk {s} ({s}) will be erased. Type the disk id again to continue: ", .{ disk.id, disk.model });
        var buf: [256]u8 = undefined;
        const n = Io.File.stdin().readStreaming(io, &.{&buf}) catch 0;
        if (!std.mem.eql(u8, std.mem.trim(u8, buf[0..n], " \r\n\t"), disk.id)) die("aborted", .{});
    }

    var target = rawdisk.Target.open(arena, io, disk) catch |e| switch (e) {
        error.AccessDenied => die("access denied; run from an elevated (Administrator) terminal, or as root on Linux", .{}),
        else => |other| return other,
    };
    // Partition data first, then tables re-laid out for the disk's real size.
    const data = image[0 .. parsed.used_sectors * gpt.sector];
    const step = 16 << 20;
    var at: usize = 0;
    while (at < data.len) : (at += step) {
        const chunk = data[at..@min(at + step, data.len)];
        try target.write(at / gpt.sector, chunk);
        std.debug.print("\rusbimg: wrote {d}/{d} MiB", .{ (at + chunk.len) >> 20, data.len >> 20 });
    }
    try gpt.writeTables(parsed.disk_guid, parsed.entries, disk_sectors, &target);
    try target.close();
    std.debug.print("\nusbimg: done; disk {s} is ready to boot.\n", .{disk.id});
}

test {
    _ = fat;
    _ = gpt;
}
