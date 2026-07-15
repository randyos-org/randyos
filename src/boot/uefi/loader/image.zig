//! Top-level ELF kernel image loading: opens the file and drives
//! elf.zig/load_address.zig/segments.zig/debug_info.zig to get it into
//! memory.

const std = @import("std");
const uefi = std.os.uefi;
const Io = std.Io;
const log = std.log.scoped(.bootimg);

const memory = @import("../memory.zig");
const elf_image = @import("elf.zig");
const segments = @import("segments.zig");
const debug_info = @import("debug.zig");
const load_address = @import("loadaddr.zig");

/// Load the kernel image
pub fn loadKernelImage(
    io: Io,
    /// The boot volume root (see the io/ implementation's `openRootDir`)
    root_dir: Io.Dir,
    /// Path of the kernel image relative to the volume root, UTF-8; the Io
    /// layer handles the UCS-2/backslash conversion UEFI wants
    kernel_image_path: []const u8,
    /// The current UEFI memory map, used to plan where the kernel gets
    /// loaded/staged once its segment sizes are known (see
    /// `load_address.planKernelLoad`)
    mm: memory.MemoryMap,
    /// Pointer to the load-plan variable to be set -- where the image was
    /// staged, where it must end up, and how big it is (see
    /// load_address.zig)
    plan_out: *load_address.KernelLoadPlan,
    /// Pointer to the "kernel_entry_point" variable to be set
    kernel_entry_point: *u64,
    /// Pointer to the "dwarf_info" variable for kernel debug information processing inside the bootloader
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

    // Now that we know the segments' sizes, secure memory for the image --
    // directly at its link address if the firmware allows, staged elsewhere
    // (to be moved after exitBootServices) if not.
    const plan = try load_address.planKernelLoad(mm, headers.program_headers);
    plan_out.* = plan;
    if (plan.staging == plan.dest) {
        log.info("loading kernel at physical address 0x{x}", .{plan.dest});
    } else {
        log.info("staging kernel at 0x{x}; it moves to 0x{x} after boot services exit", .{ plan.staging, plan.dest });
    }

    // Load the segments themselves, then whatever debug info happens to be
    // alongside them.
    try segments.loadProgramSegments(
        io,
        kernel_img_file,
        headers.program_headers,
        plan,
    );
    try debug_info.loadDebugInfo(io, kernel_img_file, &header, headers.section_headers, dwarf_info);
}

/// Everything `loadKernelImage` hands back about where the kernel ended up
/// and how to jump into it.
const LoadedKernel = struct {
    /// Where the image is staged while Boot Services still run, where it
    /// must end up before the jump, and its size -- `main.zig` performs the
    /// post-exitBootServices move when `plan.staging != plan.dest`.
    plan: load_address.KernelLoadPlan,
    kernel_entry_point: u64,
    dwarf_info: ?std.debug.Dwarf,

    /// The physical (and, for this non-relocatable kernel, virtual) address
    /// the image occupies when the kernel runs -- the `__boot_info_ptr`
    /// slot lives at this address.
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

    // Why pointers for the LoadedKernel fields? Because they have to be
    // modified, but function arguments are constant. So we use our
    // five-head strategy to say the function where the value is but still
    // let it be modifiable.
    //
    // Feel free to look into the function "loadKernelImage" above!
    loadKernelImage(
        io,
        root_dir,
        "kernel.elf",
        mm,
        &loaded.plan,
        &loaded.kernel_entry_point,
        &loaded.dwarf_info,
    ) catch |err| {
        // Fatal: the LoadedKernel fields above are still undefined without
        // a successfully loaded kernel, so we must not continue past this
        // point.
        log.err("loading kernel image failed: {s}", .{@errorName(err)});
        return err;
    };
    log.debug("loadKernelImage returned OK", .{});
    log.debug("kernel entry point is: '0x{x:0>16}'", .{loaded.kernel_entry_point});
    log.debug("kernel base address is: '0x{x:0>16}'", .{loaded.baseAddress()});
    return loaded;
}
