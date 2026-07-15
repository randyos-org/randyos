//! Materializing ELF `PT_LOAD` program segments into the memory reserved by
//! `load_address.planKernelLoad` -- the part of kernel image loading that
//! walks program headers, as opposed to debug_info.zig, which walks section
//! headers instead.
//!
//! Memory for the whole image span is allocated (and zeroed) up front by
//! the load plan, so all this file does is read each segment's file bytes
//! into place. Segments land at `plan.staging + (vaddr - plan.dest)`: when
//! the destination was free that's just `vaddr` itself, and in the staging
//! case `main.zig` moves the finished image down to `plan.dest` after
//! `exitBootServices` -- see load_address.zig for the full story.

const std = @import("std");
const uefi = std.os.uefi;
const Io = std.Io;
const elf = std.elf;
const log = std.log.scoped(.bootseg);

const rstd = @import("rstd");
const pages = rstd.memory;
const file_io = @import("file.zig");
const KernelLoadPlan = @import("loadaddr.zig").KernelLoadPlan;

/// Load an ELF program segment's file bytes to `load_address`. The
/// zero-fill of `memsz - filesz` (.bss) that the ELF spec requires already
/// happened when the load plan zeroed the whole image span, so only the
/// file-backed bytes need reading here.
pub fn loadSegment(
    io: Io,
    /// This is the ELF file
    file: Io.File,
    /// This is the offset of the program segment we want to load
    segment_file_offset: u64,
    /// How big the segment is (in the file)
    segment_file_size: usize,
    /// Where the segment's bytes go (staging-adjusted physical address)
    load_address: u64,
) !void {
    // Nothing to read for pure-bss segments; the plan's zeroing already
    // produced their final contents.
    if (segment_file_size == 0) return;

    var segment_buffer: []u8 = &.{};
    segment_buffer.ptr = @ptrFromInt(load_address);
    segment_buffer.len = segment_file_size;

    log.debug("reading segment data with file size '0x{x}' to 0x{x}", .{ segment_file_size, load_address });
    file_io.readFile(io, file, segment_file_offset, segment_buffer) catch |err| {
        log.err("reading segment data failed: {s}", .{@errorName(err)});
        return err;
    };
}

/// Load all ELF program segments according to `plan`.
pub fn loadProgramSegments(
    io: Io,
    /// Our Kernel file
    file: Io.File,
    /// The ELF Program Headers (where we will get information about the
    /// program segments from)
    /// This is a slice, which is basically a pointer associated with a length.
    program_headers: []const elf.Elf64.Phdr,
    /// Where the image lives now (staging) and must end up (dest) -- see
    /// load_address.zig
    plan: KernelLoadPlan,
) !void {
    // Running count of segments actually loaded so far (used below to catch
    // an ELF with no LOAD-type program headers at all)
    var n_segments_loaded: u64 = 0;

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

            // Page alignment is a hard requirement of the load plan's
            // page-granular allocation; a misaligned segment would silently
            // share pages with its neighbor.
            if (phdr.vaddr & pages.page_mask != 0) {
                log.err("segment {} vaddr 0x{x} is not page-aligned", .{ index, phdr.vaddr });
                return error.Unaligned;
            }

            // `vaddr >= plan.dest` always holds (plan.dest is the minimum
            // LOAD vaddr by construction), so this can't underflow --
            // unlike the previous `vaddr - base` scheme, which underflowed
            // whenever the image had to be staged above its link address.
            const load_address = plan.staging + (phdr.vaddr - plan.dest);
            loadSegment(
                io,
                file,
                phdr.offset,
                phdr.filesz,
                load_address,
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
