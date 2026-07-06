//! This is the main part of the bootloader.

// Firstly, we have some imports.

// The Standard Library and its components
const std = @import("std");
const uefi = std.os.uefi;
const log = std.log.scoped(.bootmain);

// Our code
const common = @import("common");
pub const build_options = common.build_options;
const boot_info = common.boot_info;
const logging = common.logging;

const uefi_term_mod = @import("uefi_term.zig");
const uefi_time = @import("uefi_time.zig");
const loader = @import("loader.zig");

/// Standard Library Options
pub const std_options = std.Options{
    .log_level = .info,
    .logFn = logging.logFn,
};

fn initLogging() void {
    const term = &uefi_term_mod.uefi_term;
    logging.log_term = term;
    term.init(.{});
    // make terminal connection first so we can log if there's an error starting the clock
    uefi_time.init(uefi.system_table.boot_services.?) catch |err| {
        // an error, but not fatal, no need to panic
        log.err("starting bootloader timer failed: {s}", .{@errorName(err)});
    };
    logging.get_time = &uefi_time.getTime;
}

fn stopLogging() void {
    logging.log_term = null;
    logging.get_time = null;
}

/// This is the main bootloader function, not to be confused with the
/// bootloader entry point. It is just separated from the main function because
/// it is separated.
fn bootloader() !void {
    // initialize terminal connection
    initLogging();

    // declare the variables
    const system_table = uefi.system_table;
    // First gain access to the UEFI Boot Services
    const boot_services = system_table.boot_services.?;
    // And we get the runtime services.
    const runtime_services = system_table.runtime_services;
    // UEFI strings are UTF-16LE, but Zig strings are UTF-8, so we need to
    // convert it.
    const kernel_executable_path: [*:0]const u16 = std.unicode.utf8ToUtf16LeStringLiteral("\\kernel.elf");
    // The kernel entry point, kernel start address, and physical base
    // address the kernel actually got loaded at. These get set when the
    // kernel ELF file is parsed and loaded into memory.
    var kernel_entry_point: u64 = undefined;
    var kernel_start_address: u64 = undefined;
    var base_address: u64 = undefined;
    // This is the type of the kernel entry function. We can't deliver
    // arguments to it, however.
    var kernel_entry: *const fn () callconv(.c) noreturn = undefined;

    var kernel_boot_info: boot_info.KernelBootInfo = undefined;
    var dwarf_info: ?std.debug.Dwarf = null;
    // locate protocols
    var graphics_output = blk: {
        log.debug("locating graphics output protocol", .{});
        const res = boot_services.locateProtocol(uefi.protocol.GraphicsOutput, null) catch |err| {
            log.err("locating graphics output protocol failed: {s}", .{@errorName(err)});
            return err;
        };
        if (res) |graphics| {
            break :blk graphics;
        } else {
            log.err("graphics output protocol not found!", .{});
            return error.NotFound;
        }
    };
    log.debug("querying graphics mode info", .{});
    // check supported resolutions
    var i: u32 = 0;
    log.info("current graphics mode = {}", .{graphics_output.mode.mode});
    var video_mode_info: *uefi.protocol.GraphicsOutput.Mode.Info = undefined;
    while (i < graphics_output.mode.max_mode) : (i += 1) {
        video_mode_info = graphics_output.queryMode(i) catch |err| {
            log.err("querying graphics mode failed: {s}", .{@errorName(err)});
            return err;
        };
        if (graphics_output.mode.mode == i) {
            log.info("  resolution and pixel format: {}x{} {s}", .{ video_mode_info.horizontal_resolution, video_mode_info.vertical_resolution, @tagName(video_mode_info.pixel_format) });
        }
    }
    video_mode_info = graphics_output.queryMode(graphics_output.mode.mode) catch |err| {
        log.err("querying graphics mode failed: {s}", .{@errorName(err)});
        return err;
    };

    // We need the file system protocol. Using that protocol, we can gain
    // access to the root file system.
    // Now, we locate that protocol. We will do that very often in the future.
    // Protocols are located because every protocol implementation varies from
    // computer to computer, so we can't link them at compile-time but instead
    // resolve everything at runtime. To say the computer which protocol we
    // want to be located, we pass a GUID, a unique number that, in this case,
    // identifies a protocol.
    var file_system = blk: {
        // Firstly, we put out some debug output.
        log.debug("locating simple file system protocol", .{});
        // Then, we locate the protocol. Possible errors are handled here.
        const res = boot_services.locateProtocol(uefi.protocol.SimpleFileSystem, null) catch |err| {
            log.err("locating simple file system protocol failed", .{});
            return err;
        };
        if (res) |fs| {
            break :blk fs;
        } else {
            log.err("simple file system protocol not found!", .{});
            return error.NotFound;
        }
    };
    // After locating the simple file system protocol, we want to actually open
    // the root file system.
    log.debug("opening root volume", .{});
    // prepare file system
    const root_file_system = file_system.openVolume() catch |err| {
        log.err("opening root volume failed: {s}", .{@errorName(err)});
        return err;
    };
    // We will now get the current memory map. The loader needs it to pick a
    // physical location for the kernel once it knows how big the kernel's
    // segments actually are (see loader.findKernelLoadAddress); we also
    // reuse it below when preparing the virtual address map before exiting
    // boot services.
    log.debug("getting memory map to find free addresses", .{});
    // For that, we start with getting information about the memory map.
    // And when no error happened we can save all information about the memory map.
    var map_info = boot_services.getMemoryMapInfo() catch |err| {
        log.err("getting memory map info failed: {s}", .{@errorName(err)});
        return err;
    };
    // Now, we know the size, so we can allocate a matching amount of bytes for our memory map.
    var memory_map_buffer = boot_services.allocatePool(.boot_services_data, map_info.descriptor_size * map_info.len) catch |err| {
        log.err("allocating memory map failed: {s}", .{@errorName(err)});
        return err;
    };
    // Once we know the size, we can actually get the memory map.
    var memory_map = boot_services.getMemoryMap(memory_map_buffer) catch |err| {
        log.err("getting memory map failed: {s}", .{@errorName(err)});
        return err;
    };
    // Now we can load the kernel image.
    log.info("loading kernel image", .{});
    // Why a pointer for kernel_entry_point/kernel_start_address? Because
    // they have to be modified, but function arguments are constant. So we
    // use our five-head strategy to say the function where the value is but
    // still let it be modifiable.
    //
    // Feel free to look into the function "loadKernelImage" in
    // src/bootloader/loader.zig!
    loader.loadKernelImage(
        root_file_system,
        kernel_executable_path,
        memory_map,
        map_info,
        &base_address,
        &kernel_entry_point,
        &kernel_start_address,
        &dwarf_info,
    ) catch |err| {
        // Fatal: kernel_entry_point/kernel_start_address below are still
        // undefined without a successfully loaded kernel, so we must not
        // continue past this point.
        log.err("loading kernel image failed: {s}", .{@errorName(err)});
        return err;
    };
    // After the loader loaded the kernel, we can do some final steps in the
    // bootloader before we jump into the kernel.
    log.debug("kernel entry point is: '0x{x:0>16}'", .{kernel_entry_point});
    log.debug("kernel start address is: '0x{x:0>16}'", .{kernel_start_address});

    // find RSDP: check both GUIDs, since ACPI-1.0-only firmware won't
    // publish the 2.0 one, and the kernel decides which version to trust.
    for (0..system_table.number_of_table_entries) |index| {
        const entry = system_table.configuration_table[index];
        if (entry.vendor_guid.eql(uefi.tables.ConfigurationTable.acpi_10_table_guid)) {
            kernel_boot_info.rsdp_10 = entry.vendor_table;
        }
        if (entry.vendor_guid.eql(uefi.tables.ConfigurationTable.acpi_20_table_guid)) {
            kernel_boot_info.rsdp_20 = entry.vendor_table;
        }
    }
    // set kernel boot info
    kernel_boot_info.video_mode_info.framebuffer_pointer = @as([*]volatile u32, @ptrFromInt(graphics_output.mode.frame_buffer_base));
    kernel_boot_info.video_mode_info.horizontal_resolution = video_mode_info.horizontal_resolution;
    kernel_boot_info.video_mode_info.vertical_resolution = video_mode_info.vertical_resolution;
    kernel_boot_info.video_mode_info.pixels_per_scanline = video_mode_info.pixels_per_scan_line;
    kernel_boot_info.video_mode_info.pixel_format = @intFromEnum(video_mode_info.pixel_format);
    kernel_boot_info.dwarf_info = &dwarf_info;

    // For example, we need to disable the watchdog timer. The watchdog timer
    // basically kills the program after a given timespan.
    // But because the bootloader jumps into the kernel, the bootloader is
    // *technically* still running, so after 5 minutes (as default) the
    // operating system will just shut down.
    // So we set the timer to 0 seconds, which disables it.
    log.debug("disabling watchdog timer", .{});
    boot_services.setWatchdogTimer(0, 0, null) catch |err| {
        log.err("disabling watchdog timer failed: {s}", .{@errorName(err)});
        return err;
    };
    // Now, we are preparing to exit the boot services. The boot services are
    // those things that located the protocols. But when we jump into the
    // kernel, we want to have full control over our computer and don't want to
    // have a "supervisor" like the boot services who has more control than we.
    // The exitBootServices function takes two arguments: the UEFI handle and a
    // memory map key.
    // The UEFI handle is delivered directly, but we need to obtain the memory
    // map key.
    //
    // Probably exitBootServices will fail, so we will retry it.
    //
    // This is also the last point at which it's safe to log anything:
    // once exitBootServices() succeeds, con_out (and Boot Services in
    // general) are torn down and the firmware is free to reclaim that
    // memory, so touching them afterwards jumps into whatever now lives
    // there instead.

    // get memory map to exit boot services
    while (blk: {
        boot_services.exitBootServices(uefi.handle, map_info.key) catch break :blk true;
        break :blk false;
    }) {
        log.info("getting memory map and trying to exit boot services", .{});
        // Now, we will get the memory map as described above.
        map_info = boot_services.getMemoryMapInfo() catch |err| {
            log.debug("getting memory map info failed: {s}", .{@errorName(err)});
            return err;
        };
        // Now, we know the size, so we can allocate a matching amount of bytes
        // for our memory map.
        memory_map_buffer = boot_services.allocatePool(.boot_services_data, (map_info.descriptor_size + 4) * map_info.len) catch |err| {
            log.err("allocating memory map buffer failed: {s}", .{@errorName(err)});
            return err;
        };
        // And when no error happened we can save all information about the
        // memory map.
        map_info = boot_services.getMemoryMapInfo() catch |err| {
            log.debug("getting memory map info failed: {s}", .{@errorName(err)});
            return err;
        };
        // Finally, we can actually get the memory map.
        memory_map = boot_services.getMemoryMap(memory_map_buffer) catch |err| {
            log.err("getting memory map failed: {s}", .{@errorName(err)});
            return err;
        };
        // And now that we have the memory map key, we can try to exit the boot
        // services by entering the loop again
    }
    stopLogging();

    // set value at base address of kernel (kernel_boot_info) to a ptr to kernel_boot_info
    const boot_info_ptr: *usize = @ptrFromInt(base_address);
    boot_info_ptr.* = @intFromPtr(&kernel_boot_info);

    // In the kernel linker script, we set the start of the kernel to 1M
    // (0x100000). Earlier here, we discovered free memory. That free memory
    // does NOT have to be at 0x100000. But the executable thinks that it is at
    // 0x100000. So if it isn't, there will be many errors.
    // Our solution to that is relatively simple. We say the computer it should
    // act like the kernel is at 0x100000 (using virtual addresses), but the
    // kernel can be loaded somewhere else (where that "else" is a physical
    // address). That's why we need to enable virtual addressing here.
    var mem_index: usize = 0;
    const mem_count: usize = map_info.len;
    var mem_point: *uefi.tables.MemoryDescriptor = undefined;
    while (mem_index < mem_count) : (mem_index += 1) {
        mem_point = @ptrCast(@alignCast(memory_map.ptr + (mem_index * map_info.descriptor_size)));
        // So, in loadSegment in loader.zig, we allocated some pages for the
        // kernel code and data. That region is marked with LoaderData, so we
        // can check that our current segment of the memory map is LoaderData
        // as type.
        if (mem_point.type == .loader_data) {
            // If the type is LoaderData, then we set the virtual start to the
            // kernel start address,
            mem_point.virtual_start = kernel_start_address;
            // and make kernel phys start available to kernel
            kernel_boot_info.kernel_phys_start = mem_point.physical_start;
        } else {
            // And if not, we can just use the physical address (so this won't
            // be a region mapped exclusively for the kernel).
            mem_point.virtual_start = mem_point.physical_start;
        }
    }
    // After we manipulated the memory map, we will set the memory map with
    // virtual addressing as virtual address map.
    try runtime_services.setVirtualAddressMap(memory_map);

    // make memory map available to kernel params
    kernel_boot_info.map = memory_map;
    kernel_boot_info.map_info = map_info;
    kernel_boot_info.runtime_services = runtime_services;

    // And finally, we can jump into the kernel.
    // Because we know the start address of the kernel, we can create a
    // function pointer. Function pointers are great. In the kernel, we defined
    // the kmain function. And that kmain function has an address which is
    // saved in kernel_entry_point. Now, we can say "there is a function at
    // [kernel_entry_point]" and then just call it.
    // The only thing we can't do is passing arguments to that function.
    // `kernel_entry` is `noreturn`, so control never comes back here -- there
    // is nothing left to return once this call is made.
    kernel_entry = @ptrFromInt(kernel_entry_point);
    kernel_entry();
}

/// This is a wrapper to call the bootloader function.
/// If nothing went wrong, this catch block should never run, because the
/// kernel should already be running by then...
pub fn main() void {
    bootloader() catch |err| {
        // The computer should never get here because everything should
        // succeed.
        // But just in case anything happens, we print out the name of the
        // error that was responsible for that fail. In any function, we
        // always print out "Error: xyz failed", so we have something like a
        // stack trace.
        log.err("error occurred during bootloader main function: {s}", .{@errorName(err)});
    };
    while (true) {}
}
