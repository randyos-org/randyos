//! UEFI ELF Bootloader
//! 2023 by Samuel Fiedler

const std = @import("std");
const uefi = std.os.uefi;
pub const text_out = @import("./text_out.zig");
pub const config = @import("./config.zig");
pub const boot_info = @import("./boot_info.zig");
pub const loader = @import("./loader.zig");
const puts = text_out.puts;
const printf = text_out.printf;

/// Get a memory map
///   - all arguments are pointers to the arguments needed by std.os.uefi.system_table.boot_services.?.getMemoryMap
pub fn getMemoryMap(memory_map: *?[*]uefi.tables.MemoryDescriptor, memory_map_size: *usize, memory_map_key: *usize, descriptor_size: *usize, descriptor_version: *u32) uefi.Status {
    // set variables
    const boot_services = uefi.system_table.boot_services.?;
    var status: uefi.Status = uefi.Status.Success;
    // get memory map size
    if (config.debug == true) {
        puts("Debug: Getting memory map size\r\n");
    }
    status = boot_services.getMemoryMap(memory_map_size, memory_map.*, memory_map_key, descriptor_size, descriptor_version);
    if (status != uefi.Status.Success) {
        if (status != uefi.Status.BufferTooSmall) {
            puts("Fatal: Error getting memory map size\r\n");
            return status;
        }
    }
    // allocate memory map
    memory_map_size.* += 2 * (descriptor_size.*);
    if (config.debug == true) {
        puts("Debug: Allocating memory map\r\n");
    }
    status = boot_services.allocatePool(uefi.tables.MemoryType.LoaderData, memory_map_size.*, @as(*[*]align(8) u8, @ptrCast(@alignCast(memory_map))));
    if (status != uefi.Status.Success) {
        puts("Error: Allocating memory map failed\r\n");
        return status;
    }
    // get memory map
    if (config.debug == true) {
        puts("Debug: Getting memory map (again)\r\n");
    }
    status = boot_services.getMemoryMap(memory_map_size, memory_map.*, memory_map_key, descriptor_size, descriptor_version);
    if (status != uefi.Status.Success) {
        puts("Error: Getting memory map failed\r\n");
        return status;
    }
    return status;
}

/// Main bootloader function
/// This function is not in the main function to do some separation and to process the resulting status.
/// I know I could do that also in other ways, but I decided to use one thing for everything here.
pub fn bootloader() uefi.Status {
    // declare the variables
    const boot_services = uefi.system_table.boot_services.?;
    const runtime_services = uefi.system_table.runtime_services;
    const kernel_executable_path: [*:0]const u16 = std.unicode.utf8ToUtf16LeStringLiteral("\\kernel.elf");
    var status: uefi.Status = uefi.Status.Success;
    var root_file_system: *uefi.protocol.File = undefined;
    var memory_map: ?[*]uefi.tables.MemoryDescriptor = undefined;
    var memory_map_key: usize = 0;
    var memory_map_size: usize = 0;
    var descriptor_size: usize = undefined;
    var descriptor_version: u32 = undefined;
    var kernel_entry_point: u64 = undefined;
    var kernel_start_address: u64 = undefined;
    var kernel_entry: ?*const fn (*const boot_info.KernelBootInfo) void = undefined;
    var kernel_boot_info: boot_info.KernelBootInfo = undefined;
    var file_system: *uefi.protocol.SimpleFileSystem = undefined;
    var video_mode_info: *uefi.protocol.GraphicsOutput.Mode.Info = undefined;
    var graphics_output: *uefi.protocol.GraphicsOutput = undefined;
    // locate protocols
    if (config.debug == true) {
        puts("Debug: Locating graphics output protocol\r\n");
    }
    status = boot_services.locateProtocol(&uefi.protocol.GraphicsOutput.guid, null, @as(*?*anyopaque, @ptrCast(&graphics_output)));
    if (status != uefi.Status.Success) {
        puts("Error: Locating graphics output protocol failed\r\n");
        return status;
    }
    if (config.debug == true) {
        puts("Debug: Querying graphics mode info\r\n");
    }
    status = graphics_output.queryMode(graphics_output.mode.mode, &graphics_output.mode.size_of_info, &video_mode_info);
    if (status != uefi.Status.Success) {
        puts("Error: Querying graphics mode info failed\r\n");
        return status;
    }
    if (config.debug == true) {
        puts("Debug: Locating simple file system protocol\r\n");
    }
    status = boot_services.locateProtocol(&uefi.protocol.SimpleFileSystem.guid, null, @as(*?*anyopaque, @ptrCast(&file_system)));
    if (status != uefi.Status.Success) {
        puts("Error: Locating simple file system protocol failed\r\n");
        return status;
    }
    if (config.debug == true) {
        puts("Debug: Opening root volume\r\n");
    }
    // prepare file system
    status = file_system.openVolume(&root_file_system);
    if (status != uefi.Status.Success) {
        puts("Error: Opening root volume failed\r\n");
        return status;
    }
    // get memory map the first time
    // necessary to find free memory for the kernel
    if (config.debug == true) {
        puts("Debug: Getting memory map to find free addresses\r\n");
    }
    status = getMemoryMap(&memory_map, &memory_map_size, &memory_map_key, &descriptor_size, &descriptor_version);
    if (status != uefi.Status.Success) {
        puts("Error: Getting memory map failed\r\n");
    }
    // find free address
    if (config.debug == true) {
        puts("Debug: Finding free kernel base address\r\n");
    }
    var mem_index: usize = 0;
    var mem_count: usize = undefined;
    var mem_point: *uefi.tables.MemoryDescriptor = undefined;
    var base_address: u64 = 0x100000;
    var num_pages: usize = 0;
    mem_count = memory_map_size / descriptor_size;
    if (config.debug == true) {
        printf("Debug: mem_count is {}\r\n", .{mem_count});
    }
    while (mem_index < mem_count) : (mem_index += 1) {
        if (config.debug == true) {
            printf("Debug: mem_index is {}\r\n", .{mem_index});
        }
        mem_point = @as(*uefi.tables.MemoryDescriptor, @ptrFromInt(@intFromPtr(memory_map) + (mem_index * descriptor_size)));
        if (mem_point.type == uefi.tables.MemoryType.ConventionalMemory and mem_point.physical_start >= base_address) {
            base_address = mem_point.physical_start;
            num_pages = mem_point.number_of_pages;
            if (config.debug == true) {
                printf("Debug: Found {} free pages at 0x{x}\r\n", .{ num_pages, base_address });
            }
            break;
        }
    }
    // load kernel image
    if (config.debug == true) {
        puts("Debug: Loading kernel image\r\n");
    }
    status = loader.loadKernelImage(
        root_file_system,
        kernel_executable_path,
        base_address,
        &kernel_entry_point,
        &kernel_start_address,
    );
    if (status != uefi.Status.Success) {
        puts("Error: Loading kernel image failed\r\n");
        return status;
    }
    if (config.debug == true) {
        printf("Debug: Set Kernel Entry Point to: '0x{x}'\r\n", .{kernel_entry_point});
    }
    // set kernel boot info
    kernel_boot_info.video_mode_info.framebuffer_pointer = @as(*anyopaque, @ptrFromInt(graphics_output.mode.frame_buffer_base));
    kernel_boot_info.video_mode_info.horizontal_resolution = video_mode_info.horizontal_resolution;
    kernel_boot_info.video_mode_info.vertical_resolution = video_mode_info.vertical_resolution;
    kernel_boot_info.video_mode_info.pixels_per_scanline = video_mode_info.pixels_per_scan_line;
    if (config.debug == true) {
        puts("Debug: Disabling watchdog timer\r\n");
    }
    status = boot_services.setWatchdogTimer(0, 0, 0, null);
    if (status != uefi.Status.Success) {
        puts("Error: Disabling watchdog timer failed\r\n");
        return status;
    }
    // get memory map to exit boot services
    status = getMemoryMap(&memory_map, &memory_map_size, &memory_map_key, &descriptor_size, &descriptor_version);
    if (status != uefi.Status.Success) {
        puts("Error: Getting memory map failed\r\n");
        return status;
    } else {
        puts("Getting memory map succeeded; exiting boot services now\r\n");
    }
    status = boot_services.exitBootServices(uefi.handle, memory_map_key);
    if (status != uefi.Status.Success) {
        puts("Error: Exiting boot services failed\r\n");
        return status;
    }
    // make memory map available to kernel params
    kernel_boot_info.memory_map = @as(*uefi.tables.MemoryDescriptor, @ptrCast(memory_map));
    kernel_boot_info.memory_map_size = memory_map_size;
    kernel_boot_info.memory_map_descriptor_size = descriptor_size;
    // prepare memory map for virtual memory
    mem_index = 0;
    mem_count = memory_map_size / descriptor_size;
    while (mem_index < mem_count) : (mem_index += 1) {
        mem_point = @as(*uefi.tables.MemoryDescriptor, @ptrFromInt(@intFromPtr(memory_map) + (mem_index * descriptor_size)));
        if (mem_point.type == uefi.tables.MemoryType.LoaderData) {
            mem_point.virtual_start = kernel_start_address;
        } else {
            mem_point.virtual_start = mem_point.physical_start;
        }
    }
    status = runtime_services.setVirtualAddressMap(memory_map_size, descriptor_size, descriptor_version, memory_map.?);
    if (status != uefi.Status.Success) {
        return uefi.Status.LoadError;
    }
    // jump into kernel
    kernel_entry = @as(*const fn (*const boot_info.KernelBootInfo) void, @ptrFromInt(kernel_entry_point));
    kernel_entry.?(&kernel_boot_info);
    return uefi.Status.LoadError;
}

/// Wrapper to call bootloader function
/// If nothing went wrong, it should not get after `status = bootloader()` because kernel should be called...
pub fn main() void {
    var status: uefi.Status = uefi.Status.Success;
    status = bootloader();
    puts("Status: ");
    puts(@tagName(status));
    puts("\r\n");
    while (1 == 1) {}
}
