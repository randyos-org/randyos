//! Top-level ELF kernel image loading: opens the file and drives
//! elf.zig/load_address.zig/segments.zig/debug_info.zig to get it into
//! memory.

const std = @import("std");
const uefi = std.os.uefi;
const log = std.log.scoped(.bootload);

const memory = @import("../memory.zig");
const file_io = @import("file_io.zig");
const elf_image = @import("elf.zig");
const segments = @import("segments.zig");
const debug_info = @import("debug_info.zig");
const load_address = @import("load_address.zig");

/// Load the kernel image
pub fn loadKernelImage(
    /// Pointer pointing to the root file system
    root_file_system: *const uefi.protocol.File,
    /// UEFI (16-bit) string with the file name of the kernel
    kernel_image_filename: [*:0]const u16,
    /// The current UEFI memory map, used to pick a physical address to load
    /// the kernel at once its segment sizes are known (see
    /// `load_address.findKernelLoadAddress`)
    mm: memory.MemoryMap,
    /// Pointer to the physical base address variable to be set, once
    /// `findKernelLoadAddress` picks one -- the caller needs this same
    /// address separately (it's where the kernel's `__boot_info_ptr` slot
    /// lives, at the very start of the image)
    kernel_physical_start: *u64,
    /// Pointer to the "kernel_entry_point" variable to be set
    kernel_entry_point: *u64,
    /// Pointer to the "kernel_start_address" variable for virtual memory
    /// mapping
    kernel_start_address: *u64,
    /// Pointer to the "dwarf_info" variable for kernel debug information processing inside the bootloader
    dwarf_info: *?std.debug.Dwarf,
) !void {
    const boot_services = uefi.system_table.boot_services.?;

    log.debug("opening kernel image", .{});
    const kernel_img_file = try file_io.openFile(root_file_system, kernel_image_filename);
    defer kernel_img_file.close() catch {};

    const header = try elf_image.readHeader(kernel_img_file);
    kernel_entry_point.* = header.entry;

    const headers = try elf_image.readProgramAndSectionHeaders(kernel_img_file, header);
    defer boot_services.freePool(@alignCast(headers.program_headers_buffer.ptr)) catch {};
    defer boot_services.freePool(@alignCast(headers.section_headers_buffer.ptr)) catch {};

    // Now that we know the segments' sizes, pick a physical location that's
    // actually big enough to hold all of them.
    const base_physical_address = try load_address.findKernelLoadAddress(mm, headers.program_headers);
    log.info("loading kernel at physical address 0x{x}", .{base_physical_address});
    kernel_physical_start.* = base_physical_address;

    // Load the segments themselves, then whatever debug info happens to be
    // alongside them.
    try segments.loadProgramSegments(
        kernel_img_file,
        headers.program_headers,
        base_physical_address,
        kernel_start_address,
    );
    try debug_info.loadDebugInfo(kernel_img_file, &header, headers.section_headers, dwarf_info);
}

/// Everything `loadKernelImage` hands back about where the kernel ended up
/// and how to jump into it.
const LoadedKernel = struct {
    base_address: u64,
    kernel_entry_point: u64,
    kernel_start_address: u64,
    dwarf_info: ?std.debug.Dwarf,
};

/// Load `\kernel.elf` from `root_file_system` into memory described by `mm`.
pub fn loadKernel(root_file_system: *const uefi.protocol.File, mm: memory.MemoryMap) !LoadedKernel {
    log.info("loading kernel image", .{});

    // UEFI strings are UTF-16LE, but Zig strings are UTF-8, so we need to
    // convert it.
    const kernel_executable_path: [*:0]const u16 = std.unicode.utf8ToUtf16LeStringLiteral("\\kernel.elf");

    var loaded: LoadedKernel = .{
        .base_address = undefined,
        .kernel_entry_point = undefined,
        .kernel_start_address = undefined,
        .dwarf_info = null,
    };

    // Why pointers for the LoadedKernel fields? Because they have to be
    // modified, but function arguments are constant. So we use our
    // five-head strategy to say the function where the value is but still
    // let it be modifiable.
    //
    // Feel free to look into the function "loadKernelImage" above!
    loadKernelImage(
        root_file_system,
        kernel_executable_path,
        mm,
        &loaded.base_address,
        &loaded.kernel_entry_point,
        &loaded.kernel_start_address,
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
    log.debug("kernel start address is: '0x{x:0>16}'", .{loaded.kernel_start_address});
    return loaded;
}
