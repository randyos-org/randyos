//! FAT32 formatter that lays a file tree into a partition-sized buffer.
//! Follows Microsoft's "FAT: General Overview of On-Disk Format" (v1.03);
//! cluster sizes and FAT sizing use that document's tables and formula.

const std = @import("std");
const rstd = @import("rstd");
const bytes = rstd.bytes;
const Allocator = std.mem.Allocator;

pub const sector = 512;
const reserved_sectors = 32;
const fat_count = 2;
const dirent = 32;
const fat32_min_clusters = 65525;
/// 2026-01-01 00:00; fixed so identical inputs give identical images.
const date: u16 = ((2026 - 1980) << 9) | (1 << 5) | 1;
const time: u16 = 0;

pub const Node = struct {
    name: []const u8,
    kind: union(enum) {
        file: []const u8,
        dir: []const Node,
    },
};

pub const Geometry = struct {
    sectors: u32,
    cluster_sectors: u32,
    fat_sectors: u32,
    clusters: u32,

    fn clusterBytes(g: Geometry) u32 {
        return g.cluster_sectors * sector;
    }

    fn clusterOffset(g: Geometry, cluster: u32) usize {
        return (reserved_sectors + fat_count * @as(usize, g.fat_sectors) + (cluster - 2) * @as(usize, g.cluster_sectors)) * sector;
    }
};

pub fn geometry(sectors: u64) !Geometry {
    if (sectors > std.math.maxInt(u32)) return error.PartitionTooLarge;
    const s: u32 = @intCast(sectors);
    const spc: u32 = if (s <= 532480) 1 else if (s <= 16777216) 8 else if (s <= 33554432) 16 else if (s <= 67108864) 32 else 64;
    const tmp2 = (256 * spc + fat_count) / 2;
    const fat_sectors = std.math.divCeil(u32, s - reserved_sectors, tmp2) catch unreachable;
    const clusters = (s - reserved_sectors - fat_count * fat_sectors) / spc;
    if (clusters < fat32_min_clusters) return error.PartitionTooSmall;
    return .{ .sectors = s, .cluster_sectors = spc, .fat_sectors = fat_sectors, .clusters = clusters };
}

/// Flattened tree with on-disk names; index 0 is the root.
pub const Plan = struct {
    items: []Item,

    const Item = struct {
        node: *const Node,
        parent: u32,
        children: []const u32 = &.{},
        sfn: [11]u8 = @splat(' '),
        case: u8 = 0,
        lfn: ?[]const u16 = null,
        /// Directory slots used by this directory's own entries.
        slots: u32 = 0,
        first: u32 = 0,
        clusters: u32 = 0,
    };

    pub fn init(arena: Allocator, root: *const Node) !Plan {
        var items: std.ArrayList(Item) = .empty;
        try items.append(arena, .{ .node = root, .parent = 0 });
        try addChildren(arena, &items, 0);
        return .{ .items = items.items };
    }

    fn addChildren(arena: Allocator, items: *std.ArrayList(Item), index: u32) !void {
        const kids = items.items[index].node.kind.dir;
        const first: u32 = @intCast(items.items.len);
        const ids = try arena.alloc(u32, kids.len);
        for (kids, ids, 0..) |*kid, *id, i| {
            id.* = first + @as(u32, @intCast(i));
            try items.append(arena, .{ .node = kid, .parent = index });
        }
        try nameSiblings(arena, items.items[first..]);

        var slots: u32 = if (index == 0) 1 else 2; // volume label, or "." and ".."
        for (items.items[first..]) |it| slots += 1 + lfnSlots(it.lfn);
        items.items[index].children = ids;
        items.items[index].slots = slots;
        for (ids) |id| {
            if (items.items[id].node.kind == .dir) try addChildren(arena, items, id);
        }
    }

    /// Assigns clusters in plan order; returns how many are used.
    pub fn allocate(p: Plan, cluster_bytes: u32) u32 {
        var next: u32 = 2;
        for (p.items) |*it| {
            it.clusters = switch (it.node.kind) {
                .file => |data| @intCast(std.math.divCeil(usize, data.len, cluster_bytes) catch unreachable),
                .dir => @max(1, std.math.divCeil(u32, it.slots * dirent, cluster_bytes) catch unreachable),
            };
            it.first = if (it.clusters == 0) 0 else next;
            next += it.clusters;
        }
        return next - 2;
    }
};

/// Formats `part` (exactly `g.sectors` sectors) and copies the planned tree in.
pub fn write(part: []u8, g: Geometry, p: Plan, hidden_sectors: u32, label: [11]u8, serial: u32) !void {
    std.debug.assert(part.len == @as(usize, g.sectors) * sector);
    const used = p.allocate(g.clusterBytes());
    if (used > g.clusters) return error.PartitionTooSmall;
    @memset(part, 0);

    const boot = bootSector(g, hidden_sectors, label, serial);
    const info = fsInfo(g.clusters - used, used + 2);
    for ([_]usize{ 0, 6 }) |at| {
        @memcpy(part[at * sector ..][0..sector], &boot);
        @memcpy(part[(at + 1) * sector ..][0..sector], &info);
    }

    const fat = part[reserved_sectors * sector ..][0 .. g.fat_sectors * sector];
    setFat(fat, 0, 0x0FFF_FFF8);
    setFat(fat, 1, 0x0FFF_FFFF);
    for (p.items) |it| {
        if (it.clusters == 0) continue;
        for (it.first..it.first + it.clusters - 1) |c| setFat(fat, c, @intCast(c + 1));
        setFat(fat, it.first + it.clusters - 1, 0x0FFF_FFFF);
    }
    @memcpy(part[(reserved_sectors + g.fat_sectors) * sector ..][0..fat.len], fat);

    for (p.items, 0..) |it, index| {
        const data = part[g.clusterOffset(@max(it.first, 2))..][0 .. it.clusters * g.clusterBytes()];
        switch (it.node.kind) {
            .file => |contents| @memcpy(data[0..contents.len], contents),
            .dir => writeDir(data, p, index, label),
        }
    }
}

fn writeDir(data: []u8, p: Plan, index: usize, label: [11]u8) void {
    const self = p.items[index];
    var at: usize = 0;
    if (index == 0) {
        entry(data[0..dirent], label, 0x08, 0, 0, 0);
        at = 1;
    } else {
        const parent = if (self.parent == 0) 0 else p.items[self.parent].first;
        entry(data[0..dirent], ".          ".*, 0x10, 0, self.first, 0);
        entry(data[dirent..][0..dirent], "..         ".*, 0x10, 0, parent, 0);
        at = 2;
    }
    for (self.children) |id| {
        const kid = p.items[id];
        if (kid.lfn) |name| {
            const n = lfnSlots(name);
            const sum = checksum(kid.sfn);
            var k = n;
            while (k > 0) : (k -= 1) {
                lfnEntry(data[at * dirent ..][0..dirent], name, k, k == n, sum);
                at += 1;
            }
        }
        const size: u32 = switch (kid.node.kind) {
            .file => |contents| @intCast(contents.len),
            .dir => 0,
        };
        const attr: u8 = if (kid.node.kind == .dir) 0x10 else 0x20;
        entry(data[at * dirent ..][0..dirent], kid.sfn, attr, kid.case, kid.first, size);
        at += 1;
    }
}

fn entry(e: *[dirent]u8, name: [11]u8, attr: u8, case: u8, cluster: u32, size: u32) void {
    e.* = @splat(0);
    e[0..11].* = name;
    e[11] = attr;
    e[12] = case;
    if (attr & 0x08 == 0) {
        bytes.writeIntLE(u16, e[14..], time);
        bytes.writeIntLE(u16, e[16..], date);
        bytes.writeIntLE(u16, e[18..], date);
        bytes.writeIntLE(u16, e[20..], cluster >> 16);
    }
    bytes.writeIntLE(u16, e[22..], time);
    bytes.writeIntLE(u16, e[24..], date);
    bytes.writeIntLE(u16, e[26..], @as(u16, @truncate(cluster)));
    bytes.writeIntLE(u32, e[28..], size);
}

const lfn_offsets = [13]u8{ 1, 3, 5, 7, 9, 14, 16, 18, 20, 22, 24, 28, 30 };

/// Long-name slot `ord` (1-based) holding characters `(ord-1)*13 ..`.
fn lfnEntry(e: *[dirent]u8, name: []const u16, ord: u32, last: bool, sum: u8) void {
    e.* = @splat(0);
    e[0] = @as(u8, @intCast(ord)) | if (last) @as(u8, 0x40) else 0;
    e[11] = 0x0F;
    e[13] = sum;
    for (lfn_offsets, 0..) |off, j| {
        const i = (ord - 1) * 13 + j;
        const c: u16 = if (i < name.len) name[i] else if (i == name.len) 0 else 0xFFFF;
        bytes.writeIntLE(u16, e[off..], c);
    }
}

fn lfnSlots(name: ?[]const u16) u32 {
    const n = name orelse return 0;
    return @intCast(std.math.divCeil(usize, n.len, 13) catch unreachable);
}

fn checksum(sfn: [11]u8) u8 {
    var sum: u8 = 0;
    for (sfn) |c| sum = ((sum & 1) << 7) +% (sum >> 1) +% c;
    return sum;
}

fn setFat(fat: []u8, index: usize, value: u32) void {
    bytes.writeIntLE(u32, fat[index * 4 ..], value);
}

fn bootSector(g: Geometry, hidden: u32, label: [11]u8, serial: u32) [sector]u8 {
    var s: [sector]u8 = @splat(0);
    s[0..3].* = .{ 0xEB, 0x58, 0x90 };
    s[3..11].* = "RANDYOS ".*;
    bytes.writeIntLE(u16, s[11..], sector);
    s[13] = @intCast(g.cluster_sectors);
    bytes.writeIntLE(u16, s[14..], reserved_sectors);
    s[16] = fat_count;
    s[21] = 0xF8;
    bytes.writeIntLE(u16, s[24..], 63);
    bytes.writeIntLE(u16, s[26..], 255);
    bytes.writeIntLE(u32, s[28..], hidden);
    bytes.writeIntLE(u32, s[32..], g.sectors);
    bytes.writeIntLE(u32, s[36..], g.fat_sectors);
    bytes.writeIntLE(u32, s[44..], 2); // root cluster
    bytes.writeIntLE(u16, s[48..], 1); // FSInfo sector
    bytes.writeIntLE(u16, s[50..], 6); // backup boot sector
    s[64] = 0x80;
    s[66] = 0x29;
    bytes.writeIntLE(u32, s[67..], serial);
    s[71..82].* = label;
    s[82..90].* = "FAT32   ".*;
    // Not BIOS bootable: int 18h ("no bootable disk"), then halt.
    s[90..95].* = .{ 0xCD, 0x18, 0xF4, 0xEB, 0xFD };
    s[510] = 0x55;
    s[511] = 0xAA;
    return s;
}

fn fsInfo(free: u32, next_free: u32) [sector]u8 {
    var s: [sector]u8 = @splat(0);
    bytes.writeIntLE(u32, s[0..], 0x4161_5252);
    bytes.writeIntLE(u32, s[484..], 0x6141_7272);
    bytes.writeIntLE(u32, s[488..], free);
    bytes.writeIntLE(u32, s[492..], next_free);
    bytes.writeIntLE(u32, s[508..], 0xAA55_0000);
    return s;
}

// Names

const sfn_specials = "$%'-_@~`!(){}^#&";

fn sfnChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or std.mem.indexOfScalar(u8, sfn_specials, c) != null;
}

/// 8.3 name and case flags when `name` fits as-is (one case per part).
fn exact83(name: []const u8) ?struct { [11]u8, u8 } {
    if (name.len == 0 or name[0] == '.') return null;
    const dot = std.mem.lastIndexOfScalar(u8, name, '.');
    const base = name[0 .. dot orelse name.len];
    const ext = if (dot) |d| name[d + 1 ..] else "";
    if (base.len > 8 or ext.len > 3 or (dot != null and ext.len == 0)) return null;
    var sfn: [11]u8 = @splat(' ');
    var case: u8 = 0;
    for ([_][]const u8{ base, ext }, [_]usize{ 0, 8 }, [_]u8{ 0x08, 0x10 }) |part, at, flag| {
        var lower = false;
        var upper = false;
        for (part, 0..) |c, i| {
            if (!sfnChar(c)) return null;
            lower = lower or std.ascii.isLower(c);
            upper = upper or std.ascii.isUpper(c);
            sfn[at + i] = std.ascii.toUpper(c);
        }
        if (lower and upper) return null;
        if (lower) case |= flag;
    }
    return .{ sfn, case };
}

/// Uppercased 8.3-safe characters of `s`, others replaced by '_'.
fn sfnBasis(buf: []u8, s: []const u8) []u8 {
    var n: usize = 0;
    for (s) |c| {
        if (n == buf.len) break;
        if (c == ' ' or c == '.' or (c & 0xC0) == 0x80) continue;
        buf[n] = if (sfnChar(c)) std.ascii.toUpper(c) else '_';
        n += 1;
    }
    return buf[0..n];
}

/// Picks unique short names for siblings, adding long names where needed.
fn nameSiblings(arena: Allocator, sibs: []Plan.Item) !void {
    for (sibs, 0..) |*a, i| {
        for (sibs[0..i]) |b| {
            if (std.ascii.eqlIgnoreCase(a.node.name, b.node.name)) return error.DuplicateName;
        }
    }
    var taken: std.AutoHashMapUnmanaged([11]u8, void) = .empty;
    for (sibs) |*it| {
        const sfn, const case = exact83(it.node.name) orelse continue;
        it.sfn = sfn;
        it.case = case;
        try taken.put(arena, sfn, {});
    }
    for (sibs) |*it| {
        if (exact83(it.node.name) != null) continue;
        const utf16 = try std.unicode.utf8ToUtf16LeAlloc(arena, it.node.name);
        if (utf16.len > 255) return error.NameTooLong;
        it.lfn = utf16;

        const name = it.node.name;
        const dot = std.mem.lastIndexOfScalar(u8, name, '.');
        const has_ext = dot != null and dot.? > 0;
        var base_buf: [8]u8 = undefined;
        const base = sfnBasis(&base_buf, if (has_ext) name[0..dot.?] else name);
        var ext_buf: [3]u8 = undefined;
        const ext = if (has_ext) sfnBasis(&ext_buf, name[dot.? + 1 ..]) else ext_buf[0..0];

        var n: u32 = 1;
        while (true) : (n += 1) {
            if (n > 999_999) return error.TooManyShortNames;
            var tail_buf: [8]u8 = undefined;
            const tail = std.fmt.bufPrint(&tail_buf, "~{d}", .{n}) catch unreachable;
            const keep = @min(base.len, 8 - tail.len);
            var sfn: [11]u8 = @splat(' ');
            @memcpy(sfn[0..keep], base[0..keep]);
            @memcpy(sfn[keep..][0..tail.len], tail);
            @memcpy(sfn[8..][0..ext.len], ext);
            const gop = try taken.getOrPut(arena, sfn);
            if (gop.found_existing) continue;
            it.sfn = sfn;
            break;
        }
    }
}

test "exact 8.3 names keep case via NT flags" {
    const sfn, const case = exact83("bootx64.efi").?;
    try std.testing.expectEqualStrings("BOOTX64 EFI", &sfn);
    try std.testing.expectEqual(@as(u8, 0x18), case);
    try std.testing.expect(exact83("Kernel.elf") == null);
    try std.testing.expect(exact83("ovmf_vars.fd") == null);
}

test "lfn checksum" {
    // Reference value from the spec's ChkSum algorithm.
    var expect: u8 = 0;
    for ("FOO     BAR") |c| expect = (if (expect & 1 != 0) @as(u8, 0x80) else 0) +% (expect >> 1) +% c;
    try std.testing.expectEqual(expect, checksum("FOO     BAR".*));
}
