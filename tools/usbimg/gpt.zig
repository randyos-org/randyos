//! GPT partition tables with a protective MBR, 512-byte sectors only.

const std = @import("std");
const rstd = @import("rstd");
const bytes = rstd.bytes;

pub const sector = 512;
pub const entry_count = 128;
pub const entry_size = 128;
/// Sectors taken by the partition entry array.
pub const entry_sectors = entry_count * entry_size / sector;
/// Header + entry array; the backup copy sits in the disk's last sectors.
pub const table_sectors = 1 + entry_sectors;

/// EFI System Partition type, C12A7328-F81F-11D2-BA4B-00A0C93EC93B.
pub const esp_type = guid(0xC12A7328, 0xF81F, 0x11D2, 0xBA4B, 0x00A0C93EC93B);

/// Encodes a GUID in GPT's mixed-endian on-disk layout.
pub fn guid(a: u32, b: u16, c: u16, d: u16, e: u48) [16]u8 {
    var g: [16]u8 = undefined;
    bytes.writeIntLE(u32, g[0..], a);
    bytes.writeIntLE(u16, g[4..], b);
    bytes.writeIntLE(u16, g[6..], c);
    bytes.writeIntBE(u16, g[8..], d);
    bytes.writeIntBE(u48, g[10..], e);
    return g;
}

/// Version 4 GUID from 16 arbitrary bytes.
pub fn guidFromBytes(raw: [16]u8) [16]u8 {
    var g = raw;
    g[7] = (g[7] & 0x0F) | 0x40;
    g[8] = (g[8] & 0x3F) | 0x80;
    return g;
}

pub const Partition = struct {
    type_guid: [16]u8,
    unique_guid: [16]u8,
    first_lba: u64,
    /// Inclusive.
    last_lba: u64,
    name: []const u8,
};

/// Fills an entry array (`entry_sectors * sector` bytes) from `parts`.
pub fn writeEntries(entries: []u8, parts: []const Partition) void {
    @memset(entries, 0);
    for (parts, 0..) |p, i| {
        const e = entries[i * entry_size ..][0..entry_size];
        e[0..16].* = p.type_guid;
        e[16..32].* = p.unique_guid;
        bytes.writeIntLE(u64, e[32..], p.first_lba);
        bytes.writeIntLE(u64, e[40..], p.last_lba);
        for (p.name, 0..) |c, j| bytes.writeIntLE(u16, e[56 + 2 * j ..], c);
    }
}

/// Writes the protective MBR, both headers and both entry arrays for a disk
/// of `disk_sectors`. `entries` is the array as written by `writeEntries`.
pub fn writeTables(
    disk_guid: [16]u8,
    entries: []const u8,
    disk_sectors: u64,
    /// Receives (lba, bytes) pairs to write.
    sink: anytype,
) !void {
    const last = disk_sectors - 1;

    var mbr: [sector]u8 = @splat(0);
    const pe = mbr[446..462];
    pe[2] = 0x02; // CHS start 0/0/2
    pe[4] = 0xEE;
    @memset(pe[5..8], 0xFF);
    bytes.writeIntLE(u32, pe[8..], 1);
    bytes.writeIntLE(u32, pe[12..], @min(last, 0xFFFF_FFFF));
    mbr[510] = 0x55;
    mbr[511] = 0xAA;
    try sink.write(0, &mbr);

    const entries_crc = std.hash.Crc32.hash(entries);
    const backup_entries = last - entry_sectors;
    try sink.write(1, &header(disk_guid, 1, last, 2, entries_crc, disk_sectors));
    try sink.write(2, entries);
    try sink.write(backup_entries, entries);
    try sink.write(last, &header(disk_guid, last, 1, backup_entries, entries_crc, disk_sectors));
}

fn header(disk_guid: [16]u8, my_lba: u64, alt_lba: u64, entries_lba: u64, entries_crc: u32, disk_sectors: u64) [sector]u8 {
    var h: [sector]u8 = @splat(0);
    h[0..8].* = "EFI PART".*;
    bytes.writeIntLE(u32, h[8..], 0x0001_0000);
    bytes.writeIntLE(u32, h[12..], 92);
    bytes.writeIntLE(u64, h[24..], my_lba);
    bytes.writeIntLE(u64, h[32..], alt_lba);
    bytes.writeIntLE(u64, h[40..], 1 + table_sectors);
    bytes.writeIntLE(u64, h[48..], disk_sectors - 1 - table_sectors);
    h[56..72].* = disk_guid;
    bytes.writeIntLE(u64, h[72..], entries_lba);
    bytes.writeIntLE(u32, h[80..], entry_count);
    bytes.writeIntLE(u32, h[84..], entry_size);
    bytes.writeIntLE(u32, h[88..], entries_crc);
    bytes.writeIntLE(u32, h[16..], std.hash.Crc32.hash(h[0..92]));
    return h;
}

/// Disk GUID and entry array of an image's primary table.
pub const Parsed = struct {
    disk_guid: [16]u8,
    entries: []const u8,
    /// End of the last partition, exclusive.
    used_sectors: u64,
};

pub fn parse(image: []const u8) !Parsed {
    if (image.len < (1 + table_sectors) * sector) return error.NotGpt;
    const h = image[sector..][0..sector];
    if (!std.mem.eql(u8, h[0..8], "EFI PART")) return error.NotGpt;
    if (bytes.readIntLE(u32, h[80..]) != entry_count or
        bytes.readIntLE(u32, h[84..]) != entry_size or
        bytes.readIntLE(u64, h[72..]) != 2) return error.UnsupportedGpt;
    const entries = image[2 * sector ..][0 .. entry_sectors * sector];
    var used: u64 = 1 + table_sectors;
    for (0..entry_count) |i| {
        const e = entries[i * entry_size ..][0..entry_size];
        if (std.mem.allEqual(u8, e[0..16], 0)) continue;
        used = @max(used, bytes.readIntLE(u64, e[40..]) + 1);
    }
    return .{ .disk_guid = h[56..72].*, .entries = entries, .used_sectors = used };
}
