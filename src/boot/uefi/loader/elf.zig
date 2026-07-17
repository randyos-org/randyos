//! Parses the kernel's ELF64 image: header validation, program/section
//! header tables, section lookups. Acting on the parsed result lives in
//! segments.zig/loadaddr.zig/debug.zig instead.

const std = @import("std");
const builtin = @import("builtin");
const uefi = std.os.uefi;
const Io = std.Io;
const elf = std.elf;
const log = std.log.scoped(.bootelf);

const file_io = @import("file.zig");

/// Read+parse the ELF header (entry point, header table locations,
/// is_64/endian, etc). Returned by value -- unlike
/// `readProgramAndSectionHeaders` below, the buffer is freed before return.
///
/// `elf.Header.read` already validates magic/version/class/endianness.
pub fn readHeader(io: Io, file: Io.File) !elf.Header {
    const boot_services = uefi.system_table.boot_services.?;

    log.debug("loading ELF header", .{});
    var header_buffer: []u8 = undefined;
    file_io.readAndAllocate(io, file, 0, @sizeOf(elf.Elf64_Ehdr), &header_buffer) catch |err| {
        log.err("reading ELF header failed: {s}", .{@errorName(err)});
        return err;
    };
    defer boot_services.freePool(@alignCast(header_buffer.ptr)) catch {};

    // Header.read wants a reader, not a plain buffer
    var hdr_reader: std.Io.Reader = .fixed(header_buffer);
    const header = elf.Header.read(&hdr_reader) catch |err| {
        switch (err) {
            error.InvalidElfMagic => log.err("invalid ELF magic", .{}),
            error.InvalidElfVersion => log.err("invalid ELF version", .{}),
            error.InvalidElfEndian => log.err("invalid ELF endianness", .{}),
            error.InvalidElfClass => log.err("invalid ELF class", .{}),
            else => {},
        }
        return err;
    };
    log.debug("loading ELF header succeeded; entry point is 0x{x}", .{header.entry});

    // readProgramAndSectionHeaders below casts raw bytes straight to
    // Elf64.Phdr/Shdr instead of using std.elf's generic iterators -- only
    // sound for a same-toolchain, native-endian ELF64 kernel, so enforce
    // that here rather than silently misreading the tables.
    if (!header.is_64) {
        log.err("can only load 64-bit binaries", .{});
        return error.Unsupported;
    }
    if (header.endian != builtin.cpu.arch.endian()) {
        log.err("ELF endianness ({s}) does not match native endianness ({s})", .{ @tagName(header.endian), @tagName(builtin.cpu.arch.endian()) });
        return error.IncompatibleVersion;
    }
    return header;
}

/// The parsed program/section header tables, plus the raw allocations
/// backing them.
pub const ProgramAndSectionHeaders = struct {
    /// Unlike `readHeader`'s buffer, these must outlive this function --
    /// the header slices below are views into them, not copies -- so
    /// freeing them is the caller's responsibility.
    program_headers_buffer: []u8,
    section_headers_buffer: []u8,
    program_headers: []const elf.Elf64.Phdr,
    section_headers: []const elf.Elf64.Shdr,
};

/// Read the ELF program/section header tables, cast to proper types
/// (field access instead of manual byte math), sliced to `header`'s
/// entry counts.
pub fn readProgramAndSectionHeaders(io: Io, file: Io.File, header: elf.Header) !ProgramAndSectionHeaders {
    const boot_services = uefi.system_table.boot_services.?;

    log.debug("loading program headers", .{});
    var program_headers_buffer: []u8 = &.{};
    file_io.readAndAllocate(io, file, header.phoff, header.phentsize * header.phnum, &program_headers_buffer) catch |err| {
        log.err("reading ELF program headers failed: {s}", .{@errorName(err)});
        return err;
    };
    // free this buffer if the section-header read below fails; on success
    // ownership passes to the caller instead
    errdefer boot_services.freePool(@alignCast(program_headers_buffer.ptr)) catch {};

    var section_headers_buffer: []u8 = &.{};
    file_io.readAndAllocate(io, file, header.shoff, header.shentsize * header.shnum, &section_headers_buffer) catch |err| {
        log.err("reading ELF section headers failed: {s}", .{@errorName(err)});
        return err;
    };

    return .{
        .program_headers_buffer = program_headers_buffer,
        .section_headers_buffer = section_headers_buffer,
        .program_headers = @as([*]const elf.Elf64.Phdr, @ptrCast(@alignCast(program_headers_buffer)))[0..header.phnum],
        .section_headers = @as([*]const elf.Elf64.Shdr, @ptrCast(@alignCast(section_headers_buffer)))[0..header.shnum],
    };
}

pub fn getSectionContents(io: Io, file: Io.File, section_header: elf.Elf64.Shdr, buffer: *[]u8) !void {
    try file_io.readAndAllocate(io, file, section_header.offset, section_header.size, buffer);
}

pub fn getSectionName(string_table: []const u8, section_header: elf.Elf64.Shdr) ?[]const u8 {
    const len = std.mem.indexOf(u8, string_table[section_header.name..], "\x00") orelse return null;
    return string_table[section_header.name..][0..len];
}
