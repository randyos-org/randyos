//! Fedora's Microsoft-signed shim and its MokManager, cached in
//! `<cache>/shim/` and refreshed when Fedora ships a newer build.
//!
//! Every run asks Fedora which `shim-x64` the newest stable release carries
//! (Bodhi for the release, mdapi for the package) and downloads that build
//! from Koji when the cache is missing, stale or fails its checks. Offline, a
//! cache that passes its checks is used as is.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Sha256 = std.crypto.hash.sha2.Sha256;
const authenticode = @import("authenticode.zig");
const rpm = @import("rpm.zig");

const releases_url = "https://bodhi.fedoraproject.org/releases/?state=current&rows_per_page=100";
const mdapi_url = "https://mdapi.fedoraproject.org/{s}/pkg/shim-x64";
const koji_url = "https://kojipkgs.fedoraproject.org/packages/shim/{s}/{s}/x86_64/shim-x64-{s}-{s}.x86_64.rpm";
const manifest_name = "shim.txt";
/// Cached files and where the RPM keeps them.
const files = [_]struct { name: []const u8, rpm_suffix: []const u8 }{
    .{ .name = "shimx64.efi", .rpm_suffix = "/EFI/fedora/shimx64.efi" },
    .{ .name = "mmx64.efi", .rpm_suffix = "/EFI/fedora/mmx64.efi" },
};

fn note(comptime f: []const u8, args: anytype) void {
    std.debug.print("usbimg: shim: " ++ f ++ "\n", args);
}

/// Brings `<cache_dir>/shim/` up to date and copies its files into `out_dir`.
pub fn sync(arena: Allocator, io: Io, cache_dir: []const u8, out_dir: []const u8) !void {
    const cwd = Io.Dir.cwd();
    const dir = try std.fs.path.join(arena, &.{ cache_dir, "shim" });
    const cached = loadCache(arena, io, dir);

    var client: std.http.Client = .{ .allocator = arena, .io = io };
    defer client.deinit();
    const latest: ?[]const u8 = latestVersion(arena, &client) catch |e| blk: {
        note("can't reach Fedora ({t})", .{e});
        break :blk null;
    };

    const contents: [files.len][]const u8 = if (cached) |c| blk: {
        if (latest == null) {
            note("using cached {s} offline", .{c.version});
            break :blk c.contents;
        }
        if (std.mem.eql(u8, c.version, latest.?)) break :blk c.contents;
        note("updating {s} -> {s}", .{ c.version, latest.? });
        break :blk try download(arena, io, &client, dir, latest.?);
    } else blk: {
        const v = latest orelse {
            note("no usable cache in {s} and Fedora is unreachable; build once with network access", .{dir});
            return error.NoShim;
        };
        note("downloading {s}", .{v});
        break :blk try download(arena, io, &client, dir, v);
    };

    try cwd.createDirPath(io, out_dir);
    for (files, contents) |f, data| {
        try cwd.writeFile(io, .{ .sub_path = try std.fs.path.join(arena, &.{ out_dir, f.name }), .data = data });
    }
}

const Cache = struct {
    /// "<version>-<release>", e.g. "16.1-7".
    version: []const u8,
    contents: [files.len][]const u8,
};

/// The cache, or null if it is missing or any check fails.
fn loadCache(arena: Allocator, io: Io, dir: []const u8) ?Cache {
    const cwd = Io.Dir.cwd();
    const manifest = cwd.readFileAlloc(io, std.fs.path.join(arena, &.{ dir, manifest_name }) catch return null, arena, .limited(4096)) catch return null;
    var lines = std.mem.tokenizeScalar(u8, manifest, '\n');
    var c: Cache = .{ .version = std.mem.trim(u8, lines.next() orelse return null, " \r"), .contents = undefined };
    for (files, &c.contents) |f, *data| {
        const line = std.mem.trim(u8, lines.next() orelse return null, " \r");
        const path = std.fs.path.join(arena, &.{ dir, f.name }) catch return null;
        data.* = cwd.readFileAlloc(io, path, arena, .limited(16 << 20)) catch return null;
        if (!std.mem.eql(u8, line, &hexDigest(data.*))) {
            note("{s} doesn't match its recorded hash", .{path});
            return null;
        }
    }
    check(arena, c.contents) catch |e| {
        note("cached files fail their checks ({t})", .{e});
        return null;
    };
    return c;
}

/// shim must carry an intact signature from Microsoft's UEFI CA; MokManager
/// an intact signature from anyone (shim checks it against its vendor key).
fn check(arena: Allocator, contents: [files.len][]const u8) !void {
    const issuer = try authenticode.signerIssuer(arena, contents[0]);
    if (std.mem.indexOf(u8, issuer, "Microsoft") == null or std.mem.indexOf(u8, issuer, "UEFI CA") == null)
        return error.ShimNotSignedByMicrosoft;
    _ = try authenticode.signerIssuer(arena, contents[1]);
}

fn hexDigest(data: []const u8) [64]u8 {
    var d: [32]u8 = undefined;
    Sha256.hash(data, &d, .{});
    return std.fmt.bytesToHex(d, .lower);
}

fn get(arena: Allocator, client: *std.http.Client, url: []const u8) ![]u8 {
    var out: Io.Writer.Allocating = .init(arena);
    const res = try client.fetch(.{ .location = .{ .url = url }, .response_writer = &out.writer });
    if (res.status != .ok) return error.HttpError;
    return out.toOwnedSlice();
}

/// Version-release of `shim-x64` in the newest stable Fedora.
fn latestVersion(arena: Allocator, client: *std.http.Client) ![]const u8 {
    const Releases = struct { releases: []const struct { name: []const u8, id_prefix: []const u8 } };
    const rels = try std.json.parseFromSliceLeaky(Releases, arena, try get(arena, client, releases_url), .{ .ignore_unknown_fields = true });
    var newest: u32 = 0;
    for (rels.releases) |r| {
        // "F44"; container and flatpak releases carry other prefixes or suffixes
        if (!std.mem.eql(u8, r.id_prefix, "FEDORA") or r.name.len < 2 or r.name[0] != 'F') continue;
        newest = @max(newest, std.fmt.parseInt(u32, r.name[1..], 10) catch continue);
    }
    if (newest == 0) return error.NoFedoraRelease;

    const Pkg = struct { version: []const u8, release: []const u8 };
    const url = try std.fmt.allocPrint(arena, mdapi_url, .{try std.fmt.allocPrint(arena, "f{d}", .{newest})});
    const pkg = try std.json.parseFromSliceLeaky(Pkg, arena, try get(arena, client, url), .{ .ignore_unknown_fields = true });
    return std.fmt.allocPrint(arena, "{s}-{s}", .{ pkg.version, pkg.release });
}

/// Fetches `version` from Koji, checks it and replaces the cache.
fn download(arena: Allocator, io: Io, client: *std.http.Client, dir: []const u8, version: []const u8) ![files.len][]const u8 {
    const dash = std.mem.lastIndexOfScalar(u8, version, '-') orelse return error.BadVersion;
    const v = version[0..dash];
    const r = version[dash + 1 ..];
    const pkg = try get(arena, client, try std.fmt.allocPrint(arena, koji_url, .{ v, r, v, r }));

    var suffixes: [files.len][]const u8 = undefined;
    for (files, &suffixes) |f, *s| s.* = f.rpm_suffix;
    const extracted = try rpm.extract(arena, pkg, &suffixes);
    var contents: [files.len][]const u8 = undefined;
    @memcpy(&contents, extracted);
    try check(arena, contents);

    // Manifest out, files, manifest back in: an interrupted write leaves no
    // manifest, which reads as no cache.
    const cwd = Io.Dir.cwd();
    try cwd.createDirPath(io, dir);
    const manifest_path = try std.fs.path.join(arena, &.{ dir, manifest_name });
    cwd.deleteFile(io, manifest_path) catch {};
    var manifest: std.ArrayList(u8) = .empty;
    try manifest.print(arena, "{s}\n", .{version});
    for (files, contents) |f, data| {
        try cwd.writeFile(io, .{ .sub_path = try std.fs.path.join(arena, &.{ dir, f.name }), .data = data });
        try manifest.print(arena, "{s}\n", .{&hexDigest(data)});
    }
    try cwd.writeFile(io, .{ .sub_path = manifest_path, .data = manifest.items });
    return contents;
}
