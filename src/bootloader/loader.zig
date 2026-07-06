//! This is the core kernel loading functionality

// We have the imports from the standard library…
const builtin = @import("builtin");
const std = @import("std");
const uefi = std.os.uefi;
const elf = std.elf;
const log = std.log.scoped(.bootload);

// …and imports from our programs
const common = @import("common");
const pages = common.pages;
const efi_additional = @import("efi.zig");

/// Read a UEFI file
pub fn readFile(
    /// This is our file we want to read
    file: *uefi.protocol.File,
    /// This is the start position we want to read from
    position: u64,
    /// And the buffer we want to read into
    buffer: []u8,
) !void {
    // We set the position in the file we want to read from
    file.setPosition(position) catch |err| {
        log.err("setting file position failed: {s}", .{@errorName(err)});
        return err;
    };
    // Now, we can read the file. The function in UEFI wants to have the size
    // variable, but we don't. So we @constCast it.
    // You may have recognized I return the error immediately (not handling it
    // as above). But this is the last thing we do, so we may as well just
    // "try" it.
    _ = try file.read(buffer);
}

/// Read a UEFI file and allocate free memory for it
pub fn readAndAllocate(
    /// This is our file we want to read
    file: *uefi.protocol.File,
    /// This is the start position we want to read from
    position: u64,
    /// How much we want to read
    size: usize,
    /// And the buffer we want to read into
    buffer: *[]u8,
) !void {
    // We need the boot services to do that.
    const boot_services = uefi.system_table.boot_services.?;
    // Then, we allocate some memory for the file. However, the memory "type"
    // we give the allocate function is a bit special: We will never free this
    // memory, as it holds the data of the kernel.
    buffer.* = boot_services.allocatePool(.loader_data, size) catch |err| {
        log.err("allocating space for file failed: {s}", .{@errorName(err)});
        return err;
    };
    // As described above (in readFile), we just return the status of another
    // function.
    try readFile(file, position, buffer.*);
}

/// Load an ELF program segment
pub fn loadSegment(
    /// This is the ELF file
    file: *uefi.protocol.File,
    /// This is the offset of the program segment we want to load
    segment_file_offset: u64,
    /// How big the segment is (in the file)
    segment_file_size: usize,
    /// How big the segment is (in the executable)
    segment_memory_size: usize,
    /// Where the segment will be stored in (virtual) memory
    segment_virtual_address: u64,
) !void {
    // A small thing that ensures the segment virtual address is aligned to a
    // page (4KB)
    if (segment_virtual_address & pages.page_mask != 0) {
        log.err("Warning: segment_virtual_address is not well aligned, returning", .{});
        return;
    }
    // We get a segment buffer which we can write to.
    var segment_buffer: []u8 = &.{};
    // Because we will allocate pages (4KB regions of memory) and not bytes, we
    // want to know the page count needed for this segment.
    const segment_page_count = efi_additional.efiSizeToPages(segment_memory_size);
    // Also, as the ELF documentation requests it, we need to zero-fill all
    // unused bytes. For that, we have to know where we should start
    // zero-filling and how many bytes are going to be zero-filled.
    var zero_fill_start: u64 = 0;
    var zero_fill_count: usize = 0;
    const boot_services = uefi.system_table.boot_services.?;
    // At the beginning, we allocate pages for that program code. Why do we
    // allocate pages and not single bytes? Because the ELF specification
    // requires that all "unused" bytes in a page are zero (and so we need
    // control over them). And we allocate those bytes at the exact location
    // the ELF spec wants us to (at the `segment_virtual_address`)
    log.debug("allocating {} pages at address '0x{x}'", .{ segment_page_count, segment_virtual_address });
    const segbuf = boot_services.allocatePages(
        .{ .address = @ptrFromInt(segment_virtual_address) },
        .loader_data,
        segment_page_count,
    ) catch |err| {
        log.err("allocating pages for ELF segment failed: {s}", .{@errorName(err)});
        return err;
    };
    // The problem however is that the segment buffer we want to write to
    // consists of slices (runtime-sized arrays) of arrays and we want to write
    // to a slice of bytes. So we do a little magic (we first get the pointer
    // of our first slice, and because everything is well-ordered in memory, we
    // can just set the length of the resulting slice to 4096 * input slice
    // length).
    // BE VERY CAUTIOUS WITH USING SUCH MANIPULATION CODE IN YOUR OWN PROGRAMS,
    // IT MAY BE A HELL TO DEBUG ERRORS FROM THIS!
    segment_buffer.ptr = @ptrCast(segbuf.ptr);
    segment_buffer.len = segbuf.len * pages.page_size;
    // Now, we will read the segment data from the file directly into the
    // segment buffer we just allocated, but only if the segment file size is
    // bigger than 0. This is a great example of the difference between
    // segment_file_size and segment_memory_size: Probably the program needs
    // some memory that is already known at compile-time, but there aren't any
    // start values in the ELF file. So we have to allocate this part of
    // memory, but it will not contain any data (except for zeroes).
    if (segment_file_size > 0) {
        log.debug("reading segment data with file size '0x{x}'", .{segment_file_size});
        readFile(file, segment_file_offset, segment_buffer) catch |err| {
            log.err("reading segment data failed: {s}", .{@errorName(err)});
            return err;
        };
    }
    // Now, as you might have read above, we will zero-fill all unused space.

    // We zero-fill everything after our segment, so it will be the segment
    // virtual address plus the segment file size.
    zero_fill_start = segment_virtual_address + segment_file_size;
    // How much we will zero-fill is the memory size minus the file size.
    zero_fill_count = segment_memory_size - segment_file_size;
    // And if zero_fill_count is bigger than 0 (so we have to zero-fill
    // something)…
    if (zero_fill_count > 0) {
        log.debug("zero-filling 0x{x} bytes at address '0x{x}'", .{ zero_fill_count, zero_fill_start });
        @memset(@as([*]u8, @ptrFromInt(zero_fill_start))[0..zero_fill_count], 0);
    }
}

/// Get contents of an ELF section
pub fn getSectionContents(file: *uefi.protocol.File, section_header: elf.Elf64.Shdr, buffer: *[]u8) !void {
    try readAndAllocate(file, section_header.offset, section_header.size, buffer);
}

/// Get the name of an ELF section
pub fn getSectionName(string_table: []const u8, section_header: elf.Elf64.Shdr) ?[]const u8 {
    const len = std.mem.indexOf(u8, string_table[section_header.name..], "\x00") orelse return null;
    return string_table[section_header.name..][0..len];
}

/// Load all ELF program segments
pub fn loadProgramSegments(
    /// Our Kernel file
    file: *uefi.protocol.File,
    header: *elf.Header,
    /// The ELF Program Headers (where we will get information about the
    /// program segments from)
    /// This is a slice, which is basically a pointer associated with a length.
    program_headers: []const elf.Elf64.Phdr,
    /// The ELF Section Headers (where we will get information about the
    /// sections from)
    section_headers: []const elf.Elf64.Shdr,
    /// The base physical address of the kernel
    base_physical_address: u64,
    /// A pointer to the address where the kernel entry point will be located.
    /// Because it's a pointer, we can write to it.
    kernel_start_address: *u64,
    /// A pointer to the DWARF debug information structure (if available)
    /// This allows the loader to pass debug information to the kernel.
    dwarf_info: *?std.debug.Dwarf,
) !void {
    // How many segments (described by program headers) we should load
    var n_segments_loaded: u64 = 0;
    // Used in the loop that iterates over the program headers
    var set_start_address: bool = true;
    // The difference between our base address (where free memory is, it can
    // start at 0x100000) and the first loadable segment (which is expected to
    // be the kernel code).
    var base_address_difference: u64 = 0;
    // If the ELF file has no program headers, then the kernel is probably
    // empty.
    if (header.phnum == 0) {
        log.err("no program segments to load", .{});
        return error.InvalidParameter;
    }
    log.debug("loading {} segments", .{header.phnum});
    // Because we have the program headers as a slice, we can easily iterate
    // over it using "for". If we used a many-item pointer, we would have to
    // use a separate index.
    for (program_headers, 0..) |phdr, index| {
        // We only load the segment if ELF tells us to do so.
        // There are some segments that are in the ELF file but that we don't
        // have to load.
        if (phdr.type == .LOAD) {
            log.debug("loading program segment {}", .{index});
            // We can expect the first segment that will be loaded to be the
            // kernel code segment. Thus, we can do the following only the
            // first time.
            if (set_start_address) {
                // When we enter this condition, set_start_address is true. If
                // we set it to false, we will not enter this condition another
                // time. So we will enter this condition exactly once.
                set_start_address = false;
                // We set the kernel start address to the virtual address of
                // that segment.
                kernel_start_address.* = program_headers[index].vaddr;
                // And we set the difference between the base address and the
                // virtual address.
                base_address_difference = program_headers[index].vaddr - base_physical_address;
                log.debug("set kernel start address to 0x{x} and base address difference to 0x{x}", .{ kernel_start_address.*, base_address_difference });
            }
            // Then, we call loadSegment which contains the core loading
            // functionality.
            loadSegment(
                // We give it the kernel executable…
                file,
                // …and some data from the program header
                phdr.offset,
                phdr.filesz,
                phdr.memsz,
                phdr.vaddr - base_address_difference,
            ) catch |err| {
                log.err("loading program segment {} failed: {s}", .{ index, @errorName(err) });
                return err;
            };
            // And if everything succeeded, we increase the number of segments
            // that were loaded.
            // We need this because not all program segments want to be loaded,
            // but we have to ensure that there is at least something.
            n_segments_loaded += 1;
        }
    }
    // We do not only have to return an error (above) if there are no segments
    // we can iterate over, but also if we find no loadable segments.
    if (n_segments_loaded == 0) {
        log.err("no loadable program segments found in executable", .{});
        return error.NotFound;
    }
    log.debug("loading DWARF debug info sections", .{});
    var section_string_table: []u8 = &.{};
    // not just "debug_info" but general debug information (so abbrev etc. too)
    var found_debug_info: bool = false;
    var sections: std.debug.Dwarf.SectionArray = @splat(null);
    try getSectionContents(file, section_headers[header.shstrndx], &section_string_table);
    log.debug("section string table length is '{}'", .{section_string_table.len});
    // iterate over sections to find debug sections and load them to open dwarf info
    for (section_headers[0..header.shnum]) |shdr| {
        const section_name = getSectionName(section_string_table, shdr) orelse continue;
        log.debug("section name is {s}", .{section_name});
        if (std.mem.eql(u8, section_name, ".debug_info")) {
            var buf: []u8 = &.{};
            log.debug("found .debug_info!", .{});
            found_debug_info = true;
            try getSectionContents(file, shdr, &buf);
            sections[@intFromEnum(std.debug.Dwarf.Section.Id.debug_info)] = .{
                .data = buf,
                .owned = false,
            };
        }
        if (std.mem.eql(u8, section_name, ".debug_abbrev")) {
            var buf: []u8 = &.{};
            log.debug("found .debug_abbrev!", .{});
            found_debug_info = true;
            try getSectionContents(file, shdr, &buf);
            sections[@intFromEnum(std.debug.Dwarf.Section.Id.debug_abbrev)] = .{
                .data = buf,
                .owned = false,
            };
        }
        if (std.mem.eql(u8, section_name, ".debug_line")) {
            var buf: []u8 = &.{};
            log.debug("found .debug_line!", .{});
            found_debug_info = true;
            try getSectionContents(file, shdr, &buf);
            sections[@intFromEnum(std.debug.Dwarf.Section.Id.debug_line)] = .{
                .data = buf,
                .owned = false,
            };
        }
        if (std.mem.eql(u8, section_name, ".debug_str")) {
            var buf: []u8 = &.{};
            log.debug("found .debug_str!", .{});
            found_debug_info = true;
            try getSectionContents(file, shdr, &buf);
            sections[@intFromEnum(std.debug.Dwarf.Section.Id.debug_str)] = .{
                .data = buf,
                .owned = false,
            };
        }
        if (std.mem.eql(u8, section_name, ".debug_ranges")) {
            var buf: []u8 = &.{};
            log.debug("found .debug_ranges!", .{});
            found_debug_info = true;
            try getSectionContents(file, shdr, &buf);
            sections[@intFromEnum(std.debug.Dwarf.Section.Id.debug_ranges)] = .{
                .data = buf,
                .owned = false,
            };
        }
    }
    if (found_debug_info) {
        dwarf_info.* = std.debug.Dwarf{
            .sections = sections,
        };
        dwarf_info.*.?.open(uefi.pool_allocator, builtin.cpu.arch.endian()) catch |err| {
            log.err("opening debug info failed: {s}", .{@errorName(err)});
            dwarf_info.* = null;
            return error.LoadError;
        };
    } else {
        dwarf_info.* = null;
    }
}

/// Load the kernel image
pub fn loadKernelImage(
    /// Pointer pointing to the root file system
    root_file_system: *const uefi.protocol.File,
    /// UEFI (16-bit) string with the file name of the kernel
    kernel_image_filename: [*:0]const u16,
    /// Physical base address to load the bootloader
    base_physical_address: u64,
    /// Pointer to the "kernel_entry_point" variable to be set
    kernel_entry_point: *u64,
    /// Pointer to the "kernel_start_address" variable for virtual memory
    /// mapping
    kernel_start_address: *u64,
    /// Pointer to the "dwarf_info" variable for kernel debug information processing inside the bootloader
    dwarf_info: *?std.debug.Dwarf,
) !void {
    // The boot services
    const boot_services = uefi.system_table.boot_services.?;
    // The kernel executable file.
    var kernel_img_file: *uefi.protocol.File = undefined;
    // And a buffer for the ELF Executable header, not to be confused with the
    // program headers:
    //   - The Executable Header holds metadata for the entire executable
    //   - The Program Header holds (or the program headers hold) metadata for
    //     a program segment
    var header_buffer: []u8 = undefined;
    log.debug("opening kernel image", .{});
    // As we want to do things with the kernel executable, we need to open the
    // file.
    kernel_img_file = root_file_system.open(
        // The filename that (hopefully) exists in our root file system
        kernel_image_filename,
        // We want to open it read-only
        .read,
        .{ .read_only = true },
    ) catch |err| {
        log.err("opening kernel file failed: {s}", .{@errorName(err)});
        return err;
    };
    // and we will close it at the end of our function
    defer kernel_img_file.close() catch {};
    // We put the following logic in a block so that we can work with `defer`.
    {
        // Now, we have to ensure that the kernel can be an ELF file.
        log.debug("checking ELF identity", .{});
        // So we read the identity bytes of the kernel executable (also called
        // image).
        readAndAllocate(kernel_img_file, 0, elf.EI_NIDENT, &header_buffer) catch |err| {
            log.err("reading ELF identity failed: {s}", .{@errorName(err)});
            return err;
        };
        // After we checked everything (and went out of this block), we can
        // free the header buffer
        defer boot_services.freePool(@alignCast(header_buffer.ptr)) catch {};
        // Now we check the ELF magic…
        if ((header_buffer[0] != 0x7f) or
            (header_buffer[1] != 0x45) or
            (header_buffer[2] != 0x4c) or
            (header_buffer[3] != 0x46))
        {
            log.err("invalid ELF magic", .{});
            return error.InvalidParameter;
        }
        // …and we ensure that the kernel image is a 64bit one, not a 32bit or whatever one.
        if (header_buffer[elf.EI_CLASS] != elf.ELFCLASS64) {
            log.err("can only load 64-bit binaries", .{});
            return error.Unsupported;
        }
        // Finally, we want to ensure that the kernel image is little-endian
        // because that's how we are going to work with it.
        if (header_buffer[elf.EI_DATA] != elf.ELFDATA2LSB) {
            log.err("can only load little-endian binaries", .{});
            return error.IncompatibleVersion;
        }
        log.debug("ELF identity is good; continuing loading", .{});
    }
    // Now, we will load the ELF header.
    log.debug("loading ELF header", .{});
    // At first, we have to read the header from the executable and allocate
    // memory for it.
    readAndAllocate(kernel_img_file, 0, @sizeOf(elf.Elf64_Ehdr), &header_buffer) catch |err| {
        log.err("reading ELF header failed: {s}", .{@errorName(err)});
        return err;
    };
    // We will free this header at the end of our function
    defer boot_services.freePool(@alignCast(header_buffer.ptr)) catch {};
    // Then, we parse the ELF header.
    // It contains informations such as the kernel entry point or informations
    // about where the program headers will be.
    // For reading this Header, the Zig standard library wants a reader where
    // it can read bytes from. That's why we'll construct a matching reader for
    // it.
    var hdr_reader: std.Io.Reader = .fixed(header_buffer[0..64]);
    var header = elf.Header.read(&hdr_reader) catch |err| {
        switch (err) {
            error.InvalidElfMagic => {
                log.err("Invalid ELF magic", .{});
            },
            error.InvalidElfVersion => {
                log.err("Invalid ELF version", .{});
            },
            error.InvalidElfEndian => {
                log.err("Invalid ELF endianness", .{});
            },
            error.InvalidElfClass => {
                log.err("Invalid ELF endianness", .{});
            },
            else => {},
        }
        return err;
    };
    // save kernel entry point
    log.debug("loading ELF header succeeded; entry point is 0x{x}", .{header.entry});
    // If parsing the ELF header succeeds, we will save the entry point in the
    // matching variable. This is done by dereferencing the pointer to the kernel
    // entry point.
    // If you want to know why pointers are needed for mutable values in
    // functions in Zig, take a look at the following video:
    // https://youtube.com/watch?v=8xjSvGd_IXU (relevant part at around 9:00
    // minutes).
    kernel_entry_point.* = header.entry;
    // Now we will load program headers.
    log.debug("loading program headers", .{});
    // We need a buffer for the program header bytes.
    var program_headers_buffer: []u8 = &.{};
    // And we read the program headers and allocate space for them.
    readAndAllocate(kernel_img_file, header.phoff, header.phentsize * header.phnum, &program_headers_buffer) catch |err| {
        log.err("reading ELF program headers failed: {s}", .{@errorName(err)});
        return err;
    };
    // And when we exit this function, we want to free the program headers.
    defer boot_services.freePool(@alignCast(program_headers_buffer.ptr)) catch {};
    var section_headers_buffer: []u8 = &.{};
    readAndAllocate(kernel_img_file, header.shoff, header.shentsize * header.shnum, &section_headers_buffer) catch |err| {
        log.err("reading ELF section headers failed: {s}", .{@errorName(err)});
        return err;
    };
    defer boot_services.freePool(@alignCast(section_headers_buffer.ptr)) catch {};
    // Now, we cast them into a more usable type (the program header type which
    // allows us to access fields directly without doing binary magic :D).
    // And we slice that many-item pointer because a many-item pointer just
    // says "Hey, the memory I am pointing to is something indexable and can
    // have infinite entries" but the slice says "Hey, the memory I am pointing
    // to is something indexable and has N entries", so it is safer and we can
    // iterate more easily over it.
    const program_headers: []const elf.Elf64.Phdr = @as([*]const elf.Elf64.Phdr, @ptrCast(@alignCast(program_headers_buffer)))[0..header.phnum];
    const section_headers: []const elf.Elf64.Shdr = @as([*]const elf.Elf64.Shdr, @ptrCast(@alignCast(section_headers_buffer)))[0..header.shnum];
    // And now, we call our helper function.
    try loadProgramSegments(
        kernel_img_file,
        &header,
        program_headers,
        section_headers,
        base_physical_address,
        kernel_start_address,
        dwarf_info,
    );
}
