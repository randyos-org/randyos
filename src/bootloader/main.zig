//! This is the main part of the bootloader.

// Firstly, we have some imports.

// The Standard Library and its components
const std = @import("std");
const uefi = std.os.uefi;

// Things I programmed
const text_out = @import("./text_out.zig");
const config = @import("./config.zig");
const loader = @import("./loader.zig");
const puts = text_out.puts;
const printf = text_out.printf;

/// This is the main bootloader function, not to be confused with the bootloader entry point.
/// It is just separated from the main function because it is separated.
fn bootloader() uefi.Status {
    // At the beginning, we declare some variables.

    // We gain access to the UEFI Boot Services
    const boot_services = uefi.system_table.boot_services.?;
    // And we get the runtime services.
    const runtime_services = uefi.system_table.runtime_services;
    // UEFI strings are UTF-16LE, but Zig strings are UTF-8, so we need to convert it.
    const kernel_executable_path: [*:0]const u16 = std.unicode.utf8ToUtf16LeStringLiteral("\\kernel.elf");
    // In this variable, we capture the status of each function we call. In case that function fails,
    // we return the status.
    var status: uefi.Status = .Success;
    // The root file system is a FAT filesystem, in our case it's the emulated one with systemroot as root folder.
    var root_file_system: *const uefi.protocol.File = undefined;
    // The memory map is important to find free memory. We will use it later.
    var memory_map: [*]uefi.tables.MemoryDescriptor = undefined;
    // Some other memory map variables...
    var memory_map_key: usize = 0;
    var memory_map_size: usize = 0;
    var descriptor_size: usize = undefined;
    var descriptor_version: u32 = undefined;
    // The kernel entry point and the kernel start address. This will be set when the kernel ELF file is
    // parsed and loaded into the memory.
    var kernel_entry_point: u64 = undefined;
    var kernel_start_address: u64 = undefined;
    // This is the type of the kernel entry function. We can't deliver arguments to it, however.
    var kernel_entry: *const fn () callconv(.C) void = undefined;
    // This is the file system protocol. Using that protocol, we can gain access to the root file system.
    var file_system: *uefi.protocol.SimpleFileSystem = undefined;
    // Now, we locate that protocol. We will do that very often in the future.
    // Protocols are located because every protocol implementation varies from computer to computer,
    // so we can't link them at compile-time but instead resolve everything at runtime.
    // To say the computer which protocol we want to be located, we pass a GUID, a unique number that,
    // in this case, identifies a protocol.

    // Firstly, we put out some debug output.
    if (config.debug == true) {
        puts("Debug: Locating simple file system protocol\r\n");
    }
    // Then, we locate the protocol.
    status = boot_services.locateProtocol(&uefi.protocol.SimpleFileSystem.guid, null, @as(*?*anyopaque, @ptrCast(&file_system)));
    // And finally, we handle errors.
    if (status != .Success) {
        puts("Error: Locating simple file system protocol failed\r\n");
        return status;
    }
    // You will see such a structure very often here.

    // After locating the simple file system protocol, we want to actually open the root file system.
    if (config.debug == true) {
        puts("Debug: Opening root volume\r\n");
    }
    status = file_system.openVolume(&root_file_system);
    // Again, error handling.
    if (status != .Success) {
        puts("Error: Opening root volume failed\r\n");
        return status;
    }
    // We will now find free space in the memory for the kernel.
    // Firstly, we will get the current memory map.
    if (config.debug == true) {
        puts("Debug: Getting memory map to find free addresses\r\n");
    }
    // This needs to repeated some times because the memory map size is unknown the first time, so the buffer the memory map is stored in is too small.
    while (boot_services.getMemoryMap(&memory_map_size, memory_map, &memory_map_key, &descriptor_size, &descriptor_version) == .BufferTooSmall) {
        // After we called getMemoryMap once, we know the size of the memory map, so we can allocate the exact size.
        status = boot_services.allocatePool(uefi.tables.MemoryType.BootServicesData, memory_map_size, @as(*[*]align(8) u8, @ptrCast(@alignCast(&memory_map))));
        // But, if allocating fails, it is an error.
        if (status != .Success) {
            puts("Error: Allocating memory map failed\r\n");
            return status;
        }
    }
    // There is also an error if getMemoryMap doesn't return BufferTooSmall but something else that is not Success.
    if (status != .Success) {
        puts("Error: Getting memory map failed\r\n");
        return status;
    }
    // Now that we've got the memory map, we need to find a free base address where we can load the kernel.
    if (config.debug == true) {
        puts("Debug: Finding free kernel base address\r\n");
    }
    // We need to declare some variables.

    // Our index to the memory map entries.
    var mem_index: usize = 0;
    // The count of entries we have.
    var mem_count: usize = undefined;
    // The current entry we will be pointing to.
    var mem_point: *uefi.tables.MemoryDescriptor = undefined;
    // Our base (minimum) address.
    var base_address: u64 = 0x100000;
    // The count of free 4KB pages we have there.
    var num_pages: usize = 0;
    // We calculate the count of entries.
    mem_count = memory_map_size / descriptor_size;
    if (config.debug == true) {
        printf("Debug: mem_count is {}\r\n", .{mem_count});
    }
    // Now, we basically iterate over the entries in the memory map.
    while (mem_index < mem_count) : (mem_index += 1) {
        if (config.debug == true) {
            printf("Debug: mem_index is {}\r\n", .{mem_index});
        }
        // Here, we calculate the new entry we will be pointing to.
        mem_point = @ptrFromInt(@intFromPtr(memory_map) + (mem_index * descriptor_size));
        // Now, we need to ensure that the memory described in that part of the memory map is free memory (ConventionalMemory)
        // and that the start of that region is bigger than our base address.
        if (mem_point.type == .ConventionalMemory and mem_point.physical_start >= base_address) {
            // And if all those conditions are fulfilled, we can set the base address to our new base address,
            // say how many free pages we have and break the loop because we don't have to search more free memory.
            base_address = mem_point.physical_start;
            num_pages = mem_point.number_of_pages;
            if (config.debug == true) {
                printf("Debug: Found {} free pages at 0x{x}\r\n", .{ num_pages, base_address });
            }
            break;
        }
    }
    // After we have found the kernel base address, we can now load the kernel image.
    if (config.debug == true) {
        puts("Debug: Loading kernel image\r\n");
    }
    // To do this, we need to pass the root file system, the kernel executable path, the base address (from our memory map),
    // a pointer to the kernel entry point and a pointer to the kernel start address.
    // Why a pointer for the latter two? Because they have to be modified, but function arguments are constant.
    // So we use our five-head strategy to say the function where the value is but still let it be modifiable.
    //
    // Feel free to look into the function "loadKernelImage" in src/bootloader/loader.zig!
    status = loader.loadKernelImage(
        root_file_system,
        kernel_executable_path,
        base_address,
        &kernel_entry_point,
        &kernel_start_address,
    );
    if (status != .Success) {
        puts("Error: Loading kernel image failed\r\n");
        return status;
    }
    // After the loader loaded the kernel, we can do some final steps in the bootloader before we jump into the kernel.
    if (config.debug == true) {
        printf("Debug: Set Kernel Entry Point to: '0x{x}'\r\n", .{kernel_entry_point});
    }
    // For example, we need to disable the watchdog timer. The watchdog timer basically kills the program after a given timespan.
    // But because the bootloader jumps into the kernel, the bootloader is *technically* still running,
    // so after 5 minutes (as default) the operating system will just shut down.
    // So we set the timer to 0 seconds, which disables it.
    if (config.debug == true) {
        puts("Debug: Disabling watchdog timer\r\n");
    }
    status = boot_services.setWatchdogTimer(0, 0, 0, null);
    if (status != .Success) {
        puts("Error: Disabling watchdog timer failed\r\n");
        return status;
    }
    // Now, we are preparing to exit the boot services. The boot services are those things that located the protocols.
    // But when we jump into the kernel, we want to have full control over our computer and
    // don't want to have a "supervisor" like the boot services who has more control than we.
    // The exitBootServices function takes two arguments: the UEFI handle and a memory map key.
    // The UEFI handle is delivered directly, but we need to obtain the memory map key.

    // Probably exitBootServices will fail, so we will retry it. This first "status = .NoResponse" is basically the same as
    // a "do {} while ()"…
    status = .NoResponse;
    while (status != .Success) {
        puts("Getting memory map and trying to exit boot services\r\n");
        // Now, we will get the memory map as described above.
        while (boot_services.getMemoryMap(&memory_map_size, memory_map, &memory_map_key, &descriptor_size, &descriptor_version) == .BufferTooSmall) {
            status = boot_services.allocatePool(.BootServicesData, memory_map_size, @as(*[*]align(8) u8, @ptrCast(@alignCast(&memory_map))));
            if (status != .Success) {
                puts("Error: Getting memory map failed\r\n");
                return status;
            }
        }
        // And now that we have the memory map key, we can try to exit the boot services.
        status = boot_services.exitBootServices(uefi.handle, memory_map_key);
    }
    // In the kernel linker script, we set the start of the kernel to 1M (0x100000). Earlier here, we discovered free memory.
    // That free memory does NOT have to be at 0x100000. But the executable thinks that it is at 0x100000. So if it isn't, there will be
    // many errors.
    // Our solution to that is relatively simple. We say the computer it should act like the kernel is at 0x100000 (using virtual addresses),
    // but the kernel can be loaded somewhere else (where that "else" is a physical address).
    // That's why we need to enable virtual addressing here.
    mem_index = 0;
    mem_count = memory_map_size / descriptor_size;
    while (mem_index < mem_count) : (mem_index += 1) {
        mem_point = @ptrFromInt(@intFromPtr(memory_map) + (mem_index * descriptor_size));
        // So, in loadSegment in loader.zig, we allocated some pages for the kernel code and data.
        // That region is marked with LoaderData, so we can check that our current segment of the memory map
        // is LoaderData as type.
        if (mem_point.type == .LoaderData) {
            // If the type is LoaderData, then we set the virtual start to the kernel start address,
            mem_point.virtual_start = kernel_start_address;
        } else {
            // And if not, we can just use the physical address.
            mem_point.virtual_start = mem_point.physical_start;
        }
    }
    // After we manipulated the memory map, we will set the memory map with virtual addressing as virtual address map.
    status = runtime_services.setVirtualAddressMap(memory_map_size, descriptor_size, descriptor_version, memory_map);
    if (status != .Success) {
        return status;
    }
    // And finally, we can jump into the kernel.
    // Because we know the start address of the kernel, we can create a function pointer. Function pointers are great.
    // In the kernel, we defined the kmain function. And that kmain function has an address which is saved in kernel_entry_point.
    // Now, we can say "there is a function at [kernel_entry_point]" and then just call it.
    // The only thing we can't do is passing arguments to that function.
    kernel_entry = @ptrFromInt(kernel_entry_point);
    kernel_entry();
    return .LoadError;
}

/// This is a wrapper to call the bootloader function.
pub fn main() void {
    var status: uefi.Status = .Success;
    status = bootloader();
    // The computer should never get here because everything should succeed.
    // But just in case anything happens, we print out the tag name of the status (for .LoadError it will be "LoadError").
    // In any function, we always print out "Error: xyz failed", so we have something like a stack trace.
    // Here, we just print out the error name that was responsible for that fail.
    puts("Status: ");
    puts(@tagName(status));
    puts("\r\n");
    while (true) {}
}
