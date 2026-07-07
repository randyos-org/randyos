//! Parsing the kernel's ELF64 image: identity/header validation, the
//! program/section header tables, and section lookups. Everything here
//! only reads and interprets bytes -- what to *do* with the parsed result
//! (materialize segments, pick a load address, load DWARF info) lives in
//! segments.zig/load_address.zig/debug_info.zig instead.

const std = @import("std");
const builtin = @import("builtin");
const uefi = std.os.uefi;
const elf = std.elf;
const log = std.log.scoped(.bootelf);

const file_io = @import("file_io.zig");

/// Read and parse the ELF executable header (`Ehdr`) -- entry point, where
/// the program/section header tables live, `is_64`/`endian`, etc. Returned
/// by value: unlike `readProgramAndSectionHeaders` below, nothing here
/// points back into the read buffer, so it's freed before this function
/// even returns.
///
/// `elf.Header.read` already validates the magic/version/class/endianness
/// bytes itself (see its `ReadError` set below) -- there's nothing left for
/// us to check by hand before parsing.
pub fn readHeader(file: *uefi.protocol.File) !elf.Header {
    const boot_services = uefi.system_table.boot_services.?;
    log.debug("loading ELF header", .{});
    var header_buffer: []u8 = undefined;
    file_io.readAndAllocate(file, 0, @sizeOf(elf.Elf64_Ehdr), &header_buffer) catch |err| {
        log.err("reading ELF header failed: {s}", .{@errorName(err)});
        return err;
    };
    defer boot_services.freePool(@alignCast(header_buffer.ptr)) catch {};

    // elf.Header.read wants a reader rather than a plain buffer.
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

    // readProgramAndSectionHeaders below casts raw bytes directly into
    // `Elf64.Phdr`/`Elf64.Shdr` rather than going through std.elf's own
    // (endian/bitness-generic, but far less ergonomic -- raw integers, no
    // `PT`/`PF` enums) iterators. That cast is only sound because this
    // bootloader only ever loads a same-toolchain, native-endian ELF64
    // kernel image, whose on-disk layout already matches those types'
    // in-memory layout exactly -- so enforce that assumption explicitly
    // here, reusing what `Header.read` above already determined, instead of
    // silently misreading the tables if it's ever violated.
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

/// The parsed program/section header tables, together with the raw
/// allocations backing them.
pub const ProgramAndSectionHeaders = struct {
    /// Unlike `readHeader`'s buffer, these two have to outlive this
    /// function -- `program_headers`/`section_headers` below are views into
    /// them, not copies -- so freeing them is the caller's responsibility.
    program_headers_buffer: []u8,
    section_headers_buffer: []u8,
    program_headers: []const elf.Elf64.Phdr,
    section_headers: []const elf.Elf64.Shdr,
};

/// Read the ELF program and section header tables and cast them to their
/// proper types (letting callers use field access instead of manual byte
/// math), sliced down to however many entries `header` says are present.
pub fn readProgramAndSectionHeaders(file: *uefi.protocol.File, header: elf.Header) !ProgramAndSectionHeaders {
    const boot_services = uefi.system_table.boot_services.?;

    log.debug("loading program headers", .{});
    var program_headers_buffer: []u8 = &.{};
    file_io.readAndAllocate(file, header.phoff, header.phentsize * header.phnum, &program_headers_buffer) catch |err| {
        log.err("reading ELF program headers failed: {s}", .{@errorName(err)});
        return err;
    };
    // If reading the section headers below fails, this buffer would
    // otherwise never get freed -- on success, ownership passes to the
    // caller (via the returned struct) instead, so this doesn't run then.
    errdefer boot_services.freePool(@alignCast(program_headers_buffer.ptr)) catch {};

    var section_headers_buffer: []u8 = &.{};
    file_io.readAndAllocate(file, header.shoff, header.shentsize * header.shnum, &section_headers_buffer) catch |err| {
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

/// Get contents of an ELF section
pub fn getSectionContents(file: *uefi.protocol.File, section_header: elf.Elf64.Shdr, buffer: *[]u8) !void {
    try file_io.readAndAllocate(file, section_header.offset, section_header.size, buffer);
}

/// Get the name of an ELF section
pub fn getSectionName(string_table: []const u8, section_header: elf.Elf64.Shdr) ?[]const u8 {
    const len = std.mem.indexOf(u8, string_table[section_header.name..], "\x00") orelse return null;
    return string_table[section_header.name..][0..len];
}
