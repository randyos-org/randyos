//! Top-level ELF kernel image loading: opens the file and drives
//! elf.zig/loadaddr.zig/segments.zig/debug.zig to get it into memory.

const std = @import("std");
const uefi = std.os.uefi;
const Io = std.Io;
const log = std.log.scoped(.bootimg);

const memory = @import("../memory.zig");
const elf_image = @import("elf.zig");
const segments = @import("segments.zig");
const debug_info = @import("debug.zig");
const load_address = @import("loadaddr.zig");

pub fn loadKernelImage(
    io: Io,
    /// boot volume root (see io/ impl's `openRootDir`)
    root_dir: Io.Dir,
    /// kernel path relative to volume root, UTF-8 (Io layer handles the
    /// UCS-2/backslash conversion UEFI wants)
    kernel_image_path: []const u8,
    /// current UEFI memory map, used to plan kernel load/staging (see
    /// `load_address.planKernelLoad`)
    mm: memory.MemoryMap,
    /// out: load plan (staging/dest/size, see loadaddr.zig)
    plan_out: *load_address.KernelLoadPlan,
    /// out: kernel entry point
    kernel_entry_point: *u64,
    /// out: DWARF debug info
    dwarf_info: *?std.debug.Dwarf,
) !void {
    const boot_services = uefi.system_table.boot_services.?;

    log.debug("opening kernel image", .{});
    const kernel_img_file = root_dir.openFile(io, kernel_image_path, .{}) catch |err| {
        log.err("opening kernel image failed: {s}", .{@errorName(err)});
        return err;
    };
    defer kernel_img_file.close(io);

    const header = try elf_image.readHeader(io, kernel_img_file);
    kernel_entry_point.* = header.entry;

    const headers = try elf_image.readProgramAndSectionHeaders(io, kernel_img_file, header);
    defer boot_services.freePool(@alignCast(headers.program_headers_buffer.ptr)) catch {};
    defer boot_services.freePool(@alignCast(headers.section_headers_buffer.ptr)) catch {};

    // secure memory for the image: at link address if firmware allows,
    // staged elsewhere (moved after exitBootServices) if not
    const plan = try load_address.planKernelLoad(mm, headers.program_headers);
    plan_out.* = plan;
    if (plan.staging == plan.dest) {
        log.info("loading kernel at physical address 0x{x}", .{plan.dest});
    } else {
        log.info("staging kernel at 0x{x}; it moves to 0x{x} after boot services exit", .{ plan.staging, plan.dest });
    }

    // load segments, then whatever debug info is alongside them
    try segments.loadProgramSegments(
        io,
        kernel_img_file,
        headers.program_headers,
        plan,
    );
    try debug_info.loadDebugInfo(io, kernel_img_file, &header, headers.section_headers, dwarf_info);
}

/// Where the kernel ended up and how to jump into it.
pub const LoadedKernel = struct {
    /// staging/dest/size; main.zig moves the image post-exit when
    /// `plan.staging != plan.dest`
    plan: load_address.KernelLoadPlan,
    kernel_entry_point: u64,
    dwarf_info: ?std.debug.Dwarf,

    /// Physical (== virtual, non-relocatable kernel) address the kernel
    /// runs at; `__boot_info_ptr` lives here.
    pub fn baseAddress(self: *const LoadedKernel) u64 {
        return self.plan.dest;
    }
};

/// Load `\kernel.elf` from `root_dir` into memory described by `mm`.
pub fn loadKernel(io: Io, root_dir: Io.Dir, mm: memory.MemoryMap) !LoadedKernel {
    log.info("loading kernel image", .{});

    var loaded: LoadedKernel = .{
        .plan = undefined,
        .kernel_entry_point = undefined,
        .dwarf_info = null,
    };

    // pointers since fields must be modified but args are const; see
    // loadKernelImage above
    loadKernelImage(
        io,
        root_dir,
        "kernel.elf",
        mm,
        &loaded.plan,
        &loaded.kernel_entry_point,
        &loaded.dwarf_info,
    ) catch |err| {
        // fatal: fields above are still undefined without a loaded kernel
        log.err("loading kernel image failed: {s}", .{@errorName(err)});
        return err;
    };
    log.debug("loadKernelImage returned OK", .{});
    log.debug("kernel entry point is: '0x{x:0>16}'", .{loaded.kernel_entry_point});
    log.debug("kernel base address is: '0x{x:0>16}'", .{loaded.baseAddress()});
    return loaded;
}
