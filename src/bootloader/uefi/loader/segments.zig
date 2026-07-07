//! Materializing ELF `PT_LOAD` program segments into UEFI-allocated pages --
//! the part of kernel image loading that walks program headers, as opposed
//! to debug_info.zig, which walks section headers instead.

const std = @import("std");
const uefi = std.os.uefi;
const elf = std.elf;
const log = std.log.scoped(.bootseg);

const common = @import("common");
const pages = common.pages;
const memory = @import("../memory.zig");
const file_io = @import("file_io.zig");

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
    // page (4KB). This must be a hard error, not a skip: the caller
    // (loadProgramSegments) has no other way to know this segment wasn't
    // actually allocated/loaded, and would otherwise count it as loaded and
    // carry on as if the kernel image were intact.
    if (segment_virtual_address & pages.page_mask != 0) {
        log.err("segment_virtual_address 0x{x} is not page-aligned", .{segment_virtual_address});
        return error.Unaligned;
    }
    // We get a segment buffer which we can write to.
    var segment_buffer: []u8 = &.{};
    // Because we will allocate pages (4KB regions of memory) and not bytes, we
    // want to know the page count needed for this segment.
    const segment_page_count = memory.efiSizeToPages(segment_memory_size);
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
        file_io.readFile(file, segment_file_offset, segment_buffer) catch |err| {
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

/// Load all ELF program segments
pub fn loadProgramSegments(
    /// Our Kernel file
    file: *uefi.protocol.File,
    /// The ELF Program Headers (where we will get information about the
    /// program segments from)
    /// This is a slice, which is basically a pointer associated with a length.
    program_headers: []const elf.Elf64.Phdr,
    /// The base physical address of the kernel
    base_physical_address: u64,
    /// A pointer to the address where the kernel entry point will be located.
    /// Because it's a pointer, we can write to it.
    kernel_start_address: *u64,
) !void {
    // Running count of segments actually loaded so far (used below to catch
    // an ELF with no LOAD-type program headers at all)
    var n_segments_loaded: u64 = 0;
    // Used in the loop that iterates over the program headers
    var set_start_address: bool = true;
    // The difference between our base address (where free memory is, it can
    // start at 0x100000) and the first loadable segment (which is expected to
    // be the kernel code).
    var base_address_difference: u64 = 0;
    // If the ELF file has no program headers, then the kernel is probably
    // empty.
    if (program_headers.len == 0) {
        log.err("no program segments to load", .{});
        return error.InvalidParameter;
    }
    log.debug("loading {} segments", .{program_headers.len});
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
}
