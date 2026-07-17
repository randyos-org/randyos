//! Loads DWARF debug info from the kernel ELF via section headers
//! (segments.zig uses program headers instead), then opens it via
//! `std.debug.Dwarf`.

const std = @import("std");
const builtin = @import("builtin");
const uefi = std.os.uefi;
const Io = std.Io;
const elf = std.elf;
const Dwarf = std.debug.Dwarf;
const DwarfSectionId = Dwarf.Section.Id;
const log = std.log.scoped(.bootdbg);

const elf_image = @import("elf.zig");

/// Scan `section_headers` for DWARF sections, open into `dwarf_info` if found.
pub fn loadDebugInfo(
    io: Io,
    /// kernel file
    file: Io.File,
    header: *const elf.Header,
    /// ELF section headers
    section_headers: []const elf.Elf64.Shdr,
    /// out: DWARF debug info, for the loader to pass to the kernel
    dwarf_info: *?Dwarf,
) !void {
    log.debug("loading DWARF debug info sections", .{});
    var section_string_table: []u8 = &.{};

    // covers all debug sections, not just .debug_info
    var found_debug_info: bool = false;

    var sections: Dwarf.SectionArray = @splat(null);
    try elf_image.getSectionContents(io, file, section_headers[header.shstrndx], &section_string_table);
    log.debug("section string table length is '{}'", .{section_string_table.len});

    // find and load debug sections
    for (section_headers[0..header.shnum]) |shdr| {
        const section_name = elf_image.getSectionName(section_string_table, shdr) orelse continue;
        log.debug("section name is {s}", .{section_name});
        if (std.mem.eql(u8, section_name, ".debug_info")) {
            var buf: []u8 = &.{};
            log.debug("found .debug_info!", .{});
            found_debug_info = true;

            try elf_image.getSectionContents(io, file, shdr, &buf);
            sections[@intFromEnum(DwarfSectionId.debug_info)] = .{
                .data = buf,
                .owned = false,
            };
        }
        if (std.mem.eql(u8, section_name, ".debug_abbrev")) {
            var buf: []u8 = &.{};
            log.debug("found .debug_abbrev!", .{});
            found_debug_info = true;

            try elf_image.getSectionContents(io, file, shdr, &buf);
            sections[@intFromEnum(DwarfSectionId.debug_abbrev)] = .{
                .data = buf,
                .owned = false,
            };
        }
        if (std.mem.eql(u8, section_name, ".debug_line")) {
            var buf: []u8 = &.{};
            log.debug("found .debug_line!", .{});
            found_debug_info = true;

            try elf_image.getSectionContents(io, file, shdr, &buf);
            sections[@intFromEnum(DwarfSectionId.debug_line)] = .{
                .data = buf,
                .owned = false,
            };
        }
        if (std.mem.eql(u8, section_name, ".debug_str")) {
            var buf: []u8 = &.{};
            log.debug("found .debug_str!", .{});
            found_debug_info = true;

            try elf_image.getSectionContents(io, file, shdr, &buf);
            sections[@intFromEnum(DwarfSectionId.debug_str)] = .{
                .data = buf,
                .owned = false,
            };
        }
        if (std.mem.eql(u8, section_name, ".debug_ranges")) {
            var buf: []u8 = &.{};
            log.debug("found .debug_ranges!", .{});
            found_debug_info = true;

            try elf_image.getSectionContents(io, file, shdr, &buf);
            sections[@intFromEnum(DwarfSectionId.debug_ranges)] = .{
                .data = buf,
                .owned = false,
            };
        }
    }
    log.debug("found_debug_info={}", .{found_debug_info});
    if (found_debug_info) {
        dwarf_info.* = Dwarf{
            .sections = sections,
        };
        log.debug("about to call Dwarf.open", .{});
        dwarf_info.*.?.open(uefi.pool_allocator, builtin.cpu.arch.endian()) catch |err| {
            log.err("opening debug info failed: {s}", .{@errorName(err)});
            dwarf_info.* = null;
            return error.LoadError;
        };
        log.debug("Dwarf.open returned OK", .{});
    } else {
        dwarf_info.* = null;
    }
    log.debug("loadDebugInfo about to return", .{});
}
