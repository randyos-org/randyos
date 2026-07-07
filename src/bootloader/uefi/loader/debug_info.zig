//! DWARF debug-info loading from the kernel ELF image: locates the
//! `.debug_*` sections via the section headers -- as opposed to
//! segments.zig, which only ever looks at program headers -- and opens them
//! via `std.debug.Dwarf`.

const std = @import("std");
const builtin = @import("builtin");
const uefi = std.os.uefi;
const elf = std.elf;
const log = std.log.scoped(.bootdbg);

const elf_image = @import("elf.zig");

/// Scan `section_headers` for DWARF debug sections and, if any are found,
/// open them into `dwarf_info`.
pub fn loadDebugInfo(
    /// Our Kernel file
    file: *uefi.protocol.File,
    header: *const elf.Header,
    /// The ELF Section Headers (where we will get information about the
    /// sections from)
    section_headers: []const elf.Elf64.Shdr,
    /// A pointer to the DWARF debug information structure (if available)
    /// This allows the loader to pass debug information to the kernel.
    dwarf_info: *?std.debug.Dwarf,
) !void {
    log.debug("loading DWARF debug info sections", .{});
    var section_string_table: []u8 = &.{};
    // not just "debug_info" but general debug information (so abbrev etc. too)
    var found_debug_info: bool = false;
    var sections: std.debug.Dwarf.SectionArray = @splat(null);
    try elf_image.getSectionContents(file, section_headers[header.shstrndx], &section_string_table);
    log.debug("section string table length is '{}'", .{section_string_table.len});
    // iterate over sections to find debug sections and load them to open dwarf info
    for (section_headers[0..header.shnum]) |shdr| {
        const section_name = elf_image.getSectionName(section_string_table, shdr) orelse continue;
        log.debug("section name is {s}", .{section_name});
        if (std.mem.eql(u8, section_name, ".debug_info")) {
            var buf: []u8 = &.{};
            log.debug("found .debug_info!", .{});
            found_debug_info = true;
            try elf_image.getSectionContents(file, shdr, &buf);
            sections[@intFromEnum(std.debug.Dwarf.Section.Id.debug_info)] = .{
                .data = buf,
                .owned = false,
            };
        }
        if (std.mem.eql(u8, section_name, ".debug_abbrev")) {
            var buf: []u8 = &.{};
            log.debug("found .debug_abbrev!", .{});
            found_debug_info = true;
            try elf_image.getSectionContents(file, shdr, &buf);
            sections[@intFromEnum(std.debug.Dwarf.Section.Id.debug_abbrev)] = .{
                .data = buf,
                .owned = false,
            };
        }
        if (std.mem.eql(u8, section_name, ".debug_line")) {
            var buf: []u8 = &.{};
            log.debug("found .debug_line!", .{});
            found_debug_info = true;
            try elf_image.getSectionContents(file, shdr, &buf);
            sections[@intFromEnum(std.debug.Dwarf.Section.Id.debug_line)] = .{
                .data = buf,
                .owned = false,
            };
        }
        if (std.mem.eql(u8, section_name, ".debug_str")) {
            var buf: []u8 = &.{};
            log.debug("found .debug_str!", .{});
            found_debug_info = true;
            try elf_image.getSectionContents(file, shdr, &buf);
            sections[@intFromEnum(std.debug.Dwarf.Section.Id.debug_str)] = .{
                .data = buf,
                .owned = false,
            };
        }
        if (std.mem.eql(u8, section_name, ".debug_ranges")) {
            var buf: []u8 = &.{};
            log.debug("found .debug_ranges!", .{});
            found_debug_info = true;
            try elf_image.getSectionContents(file, shdr, &buf);
            sections[@intFromEnum(std.debug.Dwarf.Section.Id.debug_ranges)] = .{
                .data = buf,
                .owned = false,
            };
        }
    }
    log.debug("found_debug_info={}", .{found_debug_info});
    if (found_debug_info) {
        dwarf_info.* = std.debug.Dwarf{
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
