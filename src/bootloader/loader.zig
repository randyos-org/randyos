//! Core image loading functionality
//! 2023 by Samuel Fiedler

const std = @import("std");
const uefi = std.os.uefi;
const config = @import("./config.zig");
const text_out = @import("./text_out.zig");
const elf = std.elf;
const efi_additional = @import("./efi_additional.zig");
const puts = text_out.puts;
const printf = text_out.printf;

/// Read a UEFI file
pub fn readFile(file: *uefi.protocol.File, position: u64, size: usize, buffer: *[*]align(8) u8) uefi.Status {
    var status: uefi.Status = uefi.Status.Success;
    status = file.setPosition(position);
    if (status != uefi.Status.Success) {
        puts("Error: Setting file position failed\r\n");
        return status;
    }
    return file.read(@as(*usize, @constCast(&size)), buffer.*);
}

/// Read a UEFI file and allocate free memory for it
pub fn readAndAllocate(file: *uefi.protocol.File, position: u64, size: usize, buffer: *[*]align(8) u8) uefi.Status {
    const boot_services = uefi.system_table.boot_services.?;
    var status: uefi.Status = uefi.Status.Success;
    status = boot_services.allocatePool(uefi.tables.MemoryType.LoaderData, size, buffer);
    if (status != uefi.Status.Success) {
        puts("Error: Allocating space for file failed\r\n");
        return status;
    }
    return readFile(file, position, size, buffer);
}

/// Load an ELF program segment
pub fn loadSegment(
    file: *uefi.protocol.File,
    segment_file_offset: u64,
    segment_file_size: usize,
    segment_memory_size: usize,
    segment_virtual_address: u64,
) uefi.Status {
    // set some variables
    var status: uefi.Status = uefi.Status.Success;
    if (segment_virtual_address & 4095 != 0) {
        puts("Warning: segment_virtual_address is not well aligned, returning with Success\r\n");
        return status;
    }
    var segment_buffer: [*]align(4096) u8 = @as([*]align(4096) u8, @ptrFromInt(segment_virtual_address));
    const segment_page_count = efi_additional.efiSizeToPages(segment_memory_size);
    var zero_fill_start: u64 = 0;
    var zero_fill_count: usize = 0;
    const boot_services = uefi.system_table.boot_services.?;
    // allocate pages at right physical address
    if (config.debug == true) {
        printf("Debug: Allocating {} pages at address '0x{x}'\r\n", .{ segment_page_count, segment_virtual_address });
    }
    status = boot_services.allocatePages(
        uefi.tables.AllocateType.AllocateAddress,
        uefi.tables.MemoryType.LoaderData,
        segment_page_count,
        &segment_buffer,
    );
    if (status != uefi.Status.Success) {
        puts("Error: Allocating pages for ELF segment failed\r\n");
        return status;
    }
    // read ELF segment data from file
    if (segment_file_size > 0) {
        if (config.debug == true) {
            printf("Debug: Reading segment data with file size '0x{x}'\r\n", .{segment_file_size});
        }
        status = readFile(file, segment_file_offset, segment_file_size, &segment_buffer);
        if (status != uefi.Status.Success) {
            puts("Error: Reading segment data failed\r\n");
            return status;
        }
    }
    // zero-fill free bytes, as according to the ELF spec
    zero_fill_start = segment_virtual_address + segment_file_size;
    zero_fill_count = segment_memory_size - segment_file_size;
    if (zero_fill_count > 0) {
        if (config.debug == true) {
            printf("Debug: Zero-filling {} bytes at address '0x{x}'\r\n", .{ zero_fill_count, zero_fill_start });
        }
        boot_services.setMem(@as([*]u8, @ptrFromInt(zero_fill_start)), zero_fill_count, 0);
        puts("Debug: Zero-filling bytes succeeded\r\n");
    }
    return status;
}

/// Load all ELF program segments
pub fn loadProgramSegments(
    file: *uefi.protocol.File,
    header: *elf.Header,
    program_headers: [*]const elf.Elf64_Phdr,
    base_physical_address: u64,
    kernel_start_address: *u64,
) uefi.Status {
    // set variables
    var status: uefi.Status = uefi.Status.Success;
    const n_program_headers = header.phnum;
    var n_segments_loaded: u64 = 0;
    var set_start_address: bool = true;
    var base_address_difference: u64 = 0;
    var index: usize = 0;
    if (n_program_headers == 0) {
        puts("Error: No program segments to load\r\n");
        return uefi.Status.InvalidParameter;
    }
    if (config.debug == true) {
        printf("Debug: Loading {} segments\r\n", .{n_program_headers});
    }
    // iterate over all program segments
    while (index < n_program_headers) : (index += 1) {
        if (program_headers[index].p_type == elf.PT_LOAD) {
            if (config.debug == true) {
                printf("Debug: Loading program segment {}\r\n", .{index});
            }
            // seg kernel start address (but only one time)
            if (set_start_address) {
                set_start_address = false;
                kernel_start_address.* = program_headers[index].p_vaddr;
                base_address_difference = program_headers[index].p_vaddr - base_physical_address;
                if (config.debug == true) {
                    printf("Debug: Set kernel start address to 0x{x} and base address difference to 0x{x}\r\n", .{ kernel_start_address.*, base_address_difference });
                }
            }
            // the actual loading logic is in a dedicated function
            status = loadSegment(
                file,
                program_headers[index].p_offset,
                program_headers[index].p_filesz,
                program_headers[index].p_memsz,
                program_headers[index].p_vaddr - base_address_difference,
            );
            if (status != uefi.Status.Success) {
                printf("Error: Loading program segment {} failed\r\n", .{index});
                return status;
            }
            n_segments_loaded += 1;
        }
    }
    if (n_segments_loaded == 0) {
        puts("Error: No loadable program segments found in executable\r\n");
        return uefi.Status.NotFound;
    }
    return status;
}

/// Load the kernel image
///   - root_file_system: Pointer pointing to the root file system
///   - kernel_image_filename: UEFI (16-bit) string with the file name of the kernel
///   - base_physical_address: Physical base address to load the bootloader
///   - kernel_entry_point: Pointer to the "kernel_entry_point" variable to be set
///   - kernel_start_address: Pointer to the "kernel_start_address" variable for virtual memory mapping
pub fn loadKernelImage(
    root_file_system: *uefi.protocol.File,
    kernel_image_filename: [*:0]const u16,
    base_physical_address: u64,
    kernel_entry_point: *u64,
    kernel_start_address: *u64,
) uefi.Status {
    // set variables
    const boot_services = uefi.system_table.boot_services.?;
    var status: uefi.Status = uefi.Status.Success;
    var kernel_img_file: *uefi.protocol.File = undefined;
    var header_buffer: [*]align(8) u8 = undefined;
    if (config.debug == true) {
        puts("Debug: Opening kernel image\r\n");
    }
    // open the kernel image file
    status = root_file_system.open(
        &kernel_img_file,
        kernel_image_filename,
        uefi.protocol.File.efi_file_mode_read,
        uefi.protocol.File.efi_file_read_only,
    );
    if (status != uefi.Status.Success) {
        puts("Error: Opening kernel file failed\r\n");
        return status;
    }
    // check ELF identity
    if (config.debug == true) {
        puts("Debug: Checking ELF identity\r\n");
    }
    status = readAndAllocate(kernel_img_file, 0, elf.EI_NIDENT, &header_buffer);
    if (status != uefi.Status.Success) {
        puts("Error: Reading ELF identity failed\r\n");
        return status;
    }
    if ((header_buffer[0] != 0x7f) or
        (header_buffer[1] != 0x45) or
        (header_buffer[2] != 0x4c) or
        (header_buffer[3] != 0x46))
    {
        puts("Error: Invalid ELF magic\r\n");
        return uefi.Status.InvalidParameter;
    }
    if (header_buffer[elf.EI_CLASS] != elf.ELFCLASS64) {
        puts("Error: Can only load 64-bit binaries\r\n");
        return uefi.Status.Unsupported;
    }
    if (header_buffer[elf.EI_DATA] != elf.ELFDATA2LSB) {
        puts("Error: Can only load little-endian binaries\r\n");
        return uefi.Status.IncompatibleVersion;
    }
    status = boot_services.freePool(header_buffer);
    if (status != uefi.Status.Success) {
        puts("Error: Freeing ELF identity buffer failed\r\n");
        return status;
    }
    if (config.debug == true) {
        puts("Debug: ELF identity is good; continuing loading\r\n");
    }
    // load ELF header
    if (config.debug == true) {
        puts("Debug: Loading ELF header\r\n");
    }
    status = readAndAllocate(kernel_img_file, 0, @sizeOf(elf.Elf64_Ehdr), &header_buffer);
    if (status != uefi.Status.Success) {
        puts("Error: Reading ELF header failed\r\n");
        return status;
    }
    var header = elf.Header.parse(header_buffer[0..64]) catch |err| {
        switch (err) {
            error.InvalidElfMagic => {
                puts("Error: Invalid ELF magic\r\n");
                return uefi.Status.InvalidParameter;
            },
            error.InvalidElfVersion => {
                puts("Error: Invalid ELF version\r\n");
                return uefi.Status.IncompatibleVersion;
            },
            error.InvalidElfEndian => {
                puts("Error: Invalid ELF endianness\r\n");
                return uefi.Status.IncompatibleVersion;
            },
            error.InvalidElfClass => {
                puts("Error: Invalid ELF endianness\r\n");
                return uefi.Status.IncompatibleVersion;
            },
        }
    };
    // save kernel entry point
    if (config.debug == true) {
        printf("Debug: Loading ELF header succeeded; entry point is {x}\r\n", .{header.entry});
    }
    kernel_entry_point.* = header.entry;
    // load program headers
    if (config.debug == true) {
        puts("Debug: Loading program headers\r\n");
    }
    var program_headers_buffer: [*]align(8) u8 = undefined;
    status = readAndAllocate(kernel_img_file, header.phoff, header.phentsize * header.phnum, &program_headers_buffer);
    if (status != uefi.Status.Success) {
        puts("Error: Reading ELF program headers failed\r\n");
        return status;
    }
    const program_headers = @as([*]const elf.Elf64_Phdr, @ptrCast(program_headers_buffer));
    status = loadProgramSegments(kernel_img_file, &header, program_headers, base_physical_address, kernel_start_address);
    // close and free everything
    _ = kernel_img_file.close();
    _ = boot_services.freePool(header_buffer);
    _ = boot_services.freePool(program_headers_buffer);
    return status;
}
