//! Pulls files out of an RPM package (v3 lead, zstd-compressed newc cpio
//! payload), per rpm.org's "Package format" and cpio(5).

const std = @import("std");
const Allocator = std.mem.Allocator;

const tag_payload_compressor = 1125;

/// Contents of the files whose paths end with `suffixes[i]`, in that order.
pub fn extract(arena: Allocator, rpm: []const u8, suffixes: []const []const u8) ![][]const u8 {
    if (rpm.len < 96 or !std.mem.eql(u8, rpm[0..4], "\xed\xab\xee\xdb")) return error.NotRpm;
    const sig = try header(rpm, 96);
    const main = try header(rpm, std.mem.alignForward(usize, sig.end, 8));
    const compressor = main.string(tag_payload_compressor) orelse "gzip";
    if (!std.mem.eql(u8, compressor, "zstd")) return error.UnsupportedRpmCompression;

    var in: std.Io.Reader = .fixed(rpm[main.end..]);
    var zstd: std.compress.zstd.Decompress = .init(&in, &.{}, .{});
    const cpio = try zstd.reader.allocRemaining(arena, .unlimited);
    return extractCpio(arena, cpio, suffixes);
}

const Header = struct {
    rpm: []const u8,
    index: usize,
    count: usize,
    store: usize,
    end: usize,

    fn string(h: Header, tag: u32) ?[]const u8 {
        for (0..h.count) |i| {
            const e = h.rpm[h.index + 16 * i ..][0..16];
            if (std.mem.readInt(u32, e[0..4], .big) != tag) continue;
            const off = h.store + std.mem.readInt(u32, e[8..12], .big);
            if (off >= h.end) return null;
            return std.mem.sliceTo(h.rpm[off..h.end], 0);
        }
        return null;
    }
};

fn header(rpm: []const u8, at: usize) !Header {
    if (rpm.len < at + 16 or !std.mem.eql(u8, rpm[at..][0..3], "\x8e\xad\xe8")) return error.NotRpm;
    const count = std.mem.readInt(u32, rpm[at + 8 ..][0..4], .big);
    const size = std.mem.readInt(u32, rpm[at + 12 ..][0..4], .big);
    const store = at + 16 + 16 * @as(usize, count);
    if (rpm.len < store + size) return error.NotRpm;
    return .{ .rpm = rpm, .index = at + 16, .count = count, .store = store, .end = store + size };
}

/// newc archive. Hard-linked files carry their data on one entry only, so
/// matches are resolved through inode numbers.
fn extractCpio(arena: Allocator, cpio: []const u8, suffixes: []const []const u8) ![][]const u8 {
    const inodes = try arena.alloc(?u32, suffixes.len);
    @memset(inodes, null);
    var data: std.AutoHashMapUnmanaged(u32, []const u8) = .empty;

    var at: usize = 0;
    while (true) {
        if (cpio.len < at + 110 or !std.mem.eql(u8, cpio[at..][0..6], "070701")) return error.BadCpio;
        const h = cpio[at..][0..110];
        const ino = try hex(h[6..14]);
        const size = try hex(h[54..62]);
        const name_len = try hex(h[94..102]);
        const name_at = at + 110;
        const data_at = std.mem.alignForward(usize, name_at + name_len, 4);
        if (cpio.len < data_at + size or name_len == 0) return error.BadCpio;
        const name = cpio[name_at .. name_at + name_len - 1];
        if (std.mem.eql(u8, name, "TRAILER!!!")) break;
        if (size > 0) try data.put(arena, ino, cpio[data_at..][0..size]);
        for (suffixes, inodes) |suffix, *slot| {
            if (std.mem.endsWith(u8, name, suffix)) slot.* = ino;
        }
        at = std.mem.alignForward(usize, data_at + size, 4);
    }

    const out = try arena.alloc([]const u8, suffixes.len);
    for (inodes, out) |ino, *o| {
        o.* = data.get(ino orelse return error.FileNotInRpm) orelse return error.FileNotInRpm;
    }
    return out;
}

fn hex(field: *const [8]u8) !u32 {
    return std.fmt.parseInt(u32, field, 16) catch error.BadCpio;
}
