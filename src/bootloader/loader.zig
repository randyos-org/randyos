const std = @import("std");
const uefi = std.os.uefi;
const config = @import("./config.zig");
const text_out = @import("./text_out.zig");
const elf = @import("./elf.zig");
const efi_additional = @import("./efi_additional.zig");
const puts = text_out.puts;
const printf = text_out.printf;

pub fn loadSegment(kernel_img_file: *uefi.protocol.File, segment_file_offset: u64, segment_file_size: usize, segment_memory_size: usize, segment_physical_address: u64) uefi.Status {
    var status: uefi.Status = uefi.Status.Success;
    var program_data: ?*anyopaque = undefined;
    var buffer_read_size: usize = 0;
    var segment_page_count = efi_additional.efiSizeToPages(segment_memory_size);
    var zero_fill_start: u64 = 0;
    var zero_fill_count: usize = 0;
    const boot_services = uefi.system_table.boot_services.?;
    if (config.debug == true) {
        printf("Debug: Setting file pointer to segment offset '0x{x}'\r\n", .{segment_file_offset});
    }
    status = kernel_img_file.setPosition(segment_file_offset);
    if (status != uefi.Status.Success) {
        puts("Error: Setting file pointer to segment offset failed\r\n");
        return status;
    }
    if (config.debug == true) {
        printf("Debug: Allocating {} pages at address '0x{x}'\r\n", .{ segment_page_count, segment_physical_address });
    }
    status = boot_services.allocatePages(uefi.tables.AllocateType.AllocateAddress, uefi.tables.MemoryType.LoaderData, segment_page_count, @as(*[*]align(4096) u8, @ptrCast(@alignCast(@constCast(&&segment_physical_address)))));
    if (status != uefi.Status.Success) {
        puts("Error: Allocating pages for ELF segment failed\r\n");
        return status;
    }
    if (segment_file_size > 0) {
        buffer_read_size = segment_file_size;
        if (config.debug == true) {
            printf("Debug: Allocating segment buffer with size '0x{x}'\r\n", .{buffer_read_size});
        }
        status = boot_services.allocatePool(uefi.tables.MemoryType.LoaderCode, buffer_read_size, @as(*[*]align(8) u8, @ptrCast(@alignCast(&program_data))));
        if (status != uefi.Status.Success) {
            puts("Error: Allocating kernel segment buffer failed\r\n");
            return status;
        }
        if (config.debug == true) {
            printf("Debug: Reading segment data with file size '0x{x}'\r\n", .{buffer_read_size});
        }
        status = kernel_img_file.read(&buffer_read_size, @as([*]u8, @ptrCast(@alignCast(program_data))));
        if (status != uefi.Status.Success) {
            puts("Error: Reading segment data failed\r\n");
            return status;
        }
        if (config.debug == true) {
            printf("Debug: Copying segment to memory address '0x{x}'\r\n", .{segment_physical_address});
        }
        boot_services.copyMem(@as([*]u8, @ptrCast(@alignCast(@constCast(&segment_physical_address)))), @as([*]u8, @ptrCast(@alignCast(program_data))), segment_file_size);
        if (status != uefi.Status.Success) {
            puts("Error: Copying program section into memory failed\r\n");
            return status;
        }
        if (config.debug == true) {
            puts("Debug: Freeing program section data buffer\r\n");
        }
        status = boot_services.freePool(@as([*]align(8) u8, @ptrCast(@alignCast(program_data))));
        if (status != uefi.Status.Success) {
            puts("Error: Freeing program section data buffer failed\r\n");
            return status;
        }
    }
    zero_fill_start = segment_physical_address + segment_file_size;
    zero_fill_count = segment_memory_size - segment_file_size;
    if (zero_fill_count > 0) {
        if (config.debug == true) {
            printf("Debug: Zero-filling {} bytes at address '0x{x}'\r\n", .{ zero_fill_count, zero_fill_start });
        }
        boot_services.setMem(@as([*]u8, @ptrCast(@alignCast(@constCast(&zero_fill_start)))), zero_fill_count, 0);
        if (status != uefi.Status.Success) {
            puts("Error: Zero-filling segment failed\r\n");
            return status;
        }
    }
    return status;
}

pub fn loadProgramSegments(kernel_img_file: *uefi.protocol.File, file_class: elf.ElfFileClass, kernel_header_buffer: ?*anyopaque, kernel_program_headers_buffer: ?*anyopaque) uefi.Status {
    var status: uefi.Status = uefi.Status.Success;
    var n_program_headers: u16 = 0;
    var n_segments_loaded: u16 = 0;
    var p: usize = 0;
    if (file_class == .ElfFileClass32) {
        n_program_headers = @as(*elf.Elf32_Ehdr, @ptrCast(@alignCast(kernel_header_buffer))).e_phnum;
    } else if (file_class == .ElfFileClass64) {
        n_program_headers = @as(*elf.Elf64_Ehdr, @ptrCast(@alignCast(kernel_header_buffer))).e_phnum;
    }
    if (n_program_headers == 0) {
        puts("Error: No program segments to load\r\n");
        return uefi.Status.InvalidParameter;
    }
    if (config.debug == true) {
        printf("Debug: Loading {} segments\r\n", .{n_program_headers});
    }
    if (file_class == .ElfFileClass32) {
        const program_headers: [*]elf.Elf32_Phdr = @as([*]elf.Elf32_Phdr, @ptrCast(@alignCast(kernel_program_headers_buffer)));
        while (p < n_program_headers) : (p += 1) {
            if (program_headers[p].p_type == elf.PT_LOAD) {
                status = loadSegment(kernel_img_file, program_headers[p].p_offset, program_headers[p].p_filesz, program_headers[p].p_memsz, program_headers[p].p_paddr);
                if (status != uefi.Status.Success) {
                    printf("Error: Loading program segment {} failed\r\n", .{p});
                    return status;
                }
                n_segments_loaded += 1;
            }
        }
    } else if (file_class == .ElfFileClass64) {
        const program_headers: [*]elf.Elf64_Phdr = @as([*]elf.Elf64_Phdr, @ptrCast(@alignCast(kernel_program_headers_buffer)));
        while (p < n_program_headers) : (p += 1) {
            if (program_headers[p].p_type == elf.PT_LOAD) {
                status = loadSegment(kernel_img_file, program_headers[p].p_offset, program_headers[p].p_filesz, program_headers[p].p_memsz, program_headers[p].p_paddr);
                if (status != uefi.Status.Success) {
                    printf("Error: Loading program segment {} failed\r\n", .{p});
                    return status;
                }
                n_segments_loaded += 1;
            }
        }
    }
    if (n_segments_loaded == 0) {
        puts("Error: No loadable program segments found in executable\r\n");
        return uefi.Status.NotFound;
    }
    return status;
}

pub fn loadKernelImage(root_file_system: *uefi.protocol.File, kernel_image_filename: [*:0]const u16, kernel_entry_point: *u64) uefi.Status {
    var status: uefi.Status = uefi.Status.Success;
    var kernel_img_file: *uefi.protocol.File = undefined;
    var kernel_header: ?*anyopaque = undefined;
    var kernel_program_headers: ?*anyopaque = undefined;
    var elf_identity_buffer: [*]u8 = undefined;
    var file_class: elf.ElfFileClass = elf.ElfFileClass.ElfFileClassNone;
    const boot_services = uefi.system_table.boot_services.?;
    if (config.debug == true) {
        puts("Debug: Reading kernel image file\r\n");
    }
    status = root_file_system.open(&kernel_img_file, kernel_image_filename, uefi.protocol.File.efi_file_mode_read, uefi.protocol.File.efi_file_read_only);
    if (status != uefi.Status.Success) {
        puts("Error: Opening kernel file failed\r\n");
        return status;
    }
    status = elf.readElfIdentity(kernel_img_file, &elf_identity_buffer);
    if (status != uefi.Status.Success) {
        puts("Error: Reading executable identity failed\r\n");
        return status;
    }
    file_class = @as(elf.ElfFileClass, @enumFromInt(elf_identity_buffer[elf.EI_CLASS]));
    status = elf.validateElfIdentity(elf_identity_buffer);
    if (status != uefi.Status.Success) {
        puts("Error: Validating executable identity failed\r\n");
        return status;
    }
    if (config.debug == true) {
        puts("Debug: ELF identity is valid\r\n");
    }
    status = boot_services.freePool(@as([*]align(8) u8, @alignCast(elf_identity_buffer)));
    if (status != uefi.Status.Success) {
        puts("Error: Freeing ELF identity buffer failed\r\n");
        return status;
    }
    status = elf.readElfFile(kernel_img_file, file_class, &kernel_header, &kernel_program_headers);
    if (status != uefi.Status.Success) {
        puts("Error: Reading ELF file failed\r\n");
        return status;
    }
    if (config.debug == true) {
        elf.printElfFileInfo(kernel_header, kernel_program_headers);
    }
    if (file_class == .ElfFileClass32) {
        kernel_entry_point.* = @as(*elf.Elf32_Ehdr, @ptrCast(@alignCast(kernel_header))).e_entry;
    } else if (file_class == .ElfFileClass64) {
        kernel_entry_point.* = @as(*elf.Elf64_Ehdr, @ptrCast(@alignCast(kernel_header))).e_entry;
    } else {
        puts("Error: Invalid executable\r\n");
        return uefi.Status.Unsupported;
    }
    status = loadProgramSegments(kernel_img_file, file_class, kernel_header, kernel_program_headers);
    return status;
}
