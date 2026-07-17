//! Materializes ELF `PT_LOAD` segments into memory reserved by
//! `load_address.planKernelLoad` -- walks program headers (debug.zig walks
//! section headers instead).
//!
//! Image span is already allocated+zeroed by the load plan, so this just
//! reads each segment's file bytes into place at
//! `plan.staging + (vaddr - plan.dest)`. See loadaddr.zig for the full
//! staging story.

const std = @import("std");
const uefi = std.os.uefi;
const Io = std.Io;
const elf = std.elf;
const log = std.log.scoped(.bootseg);

const rstd = @import("rstd");
const pages = rstd.memory;
const file_io = @import("file.zig");
const KernelLoadPlan = @import("loadaddr.zig").KernelLoadPlan;

/// Load a segment's file bytes to `load_address`. .bss zero-fill already
/// happened when the load plan zeroed the whole image span, so only
/// file-backed bytes need reading here.
pub fn loadSegment(
    io: Io,
    /// ELF file
    file: Io.File,
    /// segment file offset
    segment_file_offset: u64,
    /// segment size in file
    segment_file_size: usize,
    /// Where the segment's bytes go (staging-adjusted physical address)
    load_address: u64,
) !void {
    // pure-bss segment: plan's zeroing already produced final contents
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
    /// kernel file
    file: Io.File,
    /// ELF program headers
    program_headers: []const elf.Elf64.Phdr,
    /// staging/dest info, see loadaddr.zig
    plan: KernelLoadPlan,
) !void {
    // count of segments loaded so far
    var n_segments_loaded: u64 = 0;

    // no program headers means an empty/invalid kernel
    if (program_headers.len == 0) {
        log.err("no program segments to load", .{});
        return error.InvalidParameter;
    }
    log.debug("loading {} segments", .{program_headers.len});

    for (program_headers, 0..) |phdr, index| {
        // only LOAD-type segments get loaded
        if (phdr.type == .LOAD) {
            log.debug("loading program segment {}", .{index});

            // page alignment required; a misaligned segment would share
            // pages with its neighbor
            if (phdr.vaddr & pages.page_mask != 0) {
                log.err("segment {} vaddr 0x{x} is not page-aligned", .{ index, phdr.vaddr });
                return error.Unaligned;
            }

            // vaddr >= plan.dest always holds (dest is the min LOAD vaddr
            // by construction), so this can't underflow
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

            // track count: not all segments are LOAD-type, need at least one
            n_segments_loaded += 1;
        }
    }

    // also error if headers existed but none were loadable
    if (n_segments_loaded == 0) {
        log.err("no loadable program segments found in executable", .{});
        return error.NotFound;
    }
}
