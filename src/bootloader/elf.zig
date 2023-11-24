//! Working with ELF executable files
//! 2023 by Samuel Fiedler

const text_out = @import("./text_out.zig");
const config = @import("./config.zig");
const std = @import("std");
const uefi = std.os.uefi;
const puts = text_out.puts;
const printf = text_out.printf;

pub const EI_NIDENT: usize = 16;

pub const EI_MAG0: usize = 0x0;
pub const EI_MAG1: usize = 0x1;
pub const EI_MAG2: usize = 0x2;
pub const EI_MAG3: usize = 0x3;
pub const EI_CLASS: usize = 0x4;
pub const EI_DATA: usize = 0x5;
pub const EI_VERSION: usize = 0x6;
pub const EI_OSABI: usize = 0x7;
pub const EI_ABIVERSION: usize = 0x8;

pub const PT_NULL: usize = 0;
pub const PT_LOAD: usize = 1;
pub const PT_DYNAMIC: usize = 2;
pub const PT_INTERP: usize = 3;
pub const PT_NOTE: usize = 4;
pub const PT_SHLIB: usize = 5;
pub const PT_PHDR: usize = 6;
pub const PT_TLS: usize = 7;

pub const ElfFileClass = enum(usize) {
    ElfFileClassNone = 0,
    ElfFileClass32 = 1,
    ElfFileClass64 = 2,
};

pub const Elf32_Ehdr = struct {
    e_ident: [EI_NIDENT]u8,
    e_type: u16,
    e_machine: u16,
    e_version: u32,
    e_entry: u32,
    e_phoff: u32,
    e_shoff: u32,
    e_flags: u32,
    e_ehsize: u16,
    e_phentsize: u16,
    e_phnum: u16,
    e_shentsize: u16,
    e_shnum: u16,
    e_shstrndx: u16,
};

pub const Elf64_Ehdr = struct {
    e_ident: [EI_NIDENT]u8,
    e_type: u16,
    e_machine: u16,
    e_version: u32,
    e_entry: u64,
    e_phoff: u64,
    e_shoff: u64,
    e_flags: u32,
    e_ehsize: u16,
    e_phentsize: u16,
    e_phnum: u16,
    e_shentsize: u16,
    e_shnum: u16,
    e_shstrndx: u16,
};

pub const Elf32_Phdr = struct {
    p_type: u32,
    p_offset: u32,
    p_vaddr: u32,
    p_paddr: u32,
    p_filesz: u32,
    p_memsz: u32,
    p_flags: u32,
    p_align: u32,
};

pub const Elf64_Phdr = struct {
    p_type: u32,
    p_offset: u32,
    p_vaddr: u64,
    p_paddr: u64,
    p_filesz: u64,
    p_memsz: u64,
    p_flags: u64,
    p_align: u64,
};

pub fn printElfFileInfo(header_ptr: ?*anyopaque, program_headers_ptr: ?*anyopaque, elf_file_class: ElfFileClass) void {
    const header: *Elf32_Ehdr = @as(*Elf32_Ehdr, @ptrCast(@alignCast(header_ptr)));
    const header64: *Elf64_Ehdr = @as(*Elf64_Ehdr, @ptrCast(@alignCast(header_ptr)));
    puts("Debug: ELF Header Info: \r\n");
    puts("  Magic:                    ");
    var i: usize = 0;
    // var buf: [128]u8 = 0;
    while (i < 4) : (i += 1) {
        printf("0x{x} ", .{header.e_ident[i]});
    }
    puts("\r\n");
    const file_class = switch (header.e_ident[EI_CLASS]) {
        @intFromEnum(ElfFileClass.ElfFileClass32) => "32bit",
        @intFromEnum(ElfFileClass.ElfFileClass64) => "64bit",
        else => "Unknown",
    };
    printf("  Class:                    {s}\r\n", .{file_class});
    const endian = switch (header.e_ident[EI_DATA]) {
        1 => "Little-Endian",
        2 => "Big-Endian",
        else => "Unknown",
    };
    printf("  Endianness:               {s}\r\n", .{endian});
    printf("  Version:                  0x{x}\r\n", .{header.e_ident[EI_VERSION]});
    const os_abi = switch (header.e_ident[EI_OSABI]) {
        0x00 => "System V",
        0x01 => "HP-UX",
        0x02 => "NetBSD",
        0x03 => "Linux",
        0x04 => "GNU Hurd",
        0x06 => "Solaris",
        0x07 => "AIX",
        0x08 => "IRIX",
        0x09 => "FreeBSD",
        0x0a => "Tru64",
        0x0b => "Novell Modesto",
        0x0c => "OpenBSD",
        0x0d => "OpenVMS",
        0x0e => "NonStop Kernel",
        0x0f => "AROS",
        0x10 => "Fenix OS",
        0x11 => "CloudABI",
        else => "Unknown",
    };
    printf("  OS ABI:                   {s}\r\n", .{os_abi});
    const file_type = switch (header.e_type) {
        0x00 => "None",
        0x01 => "Relocatable",
        0x02 => "Executable",
        0x03 => "Dynamic",
        else => "Other",
    };
    printf("  File Type:                {s}\r\n", .{file_type});
    const machtype = switch (header.e_machine) {
        0x00 => "No specific instruction set",
        0x02 => "SPARC",
        0x03 => "x86",
        0x08 => "MIPS",
        0x14 => "PowerPC",
        0x16 => "S390",
        0x28 => "ARM",
        0x2a => "SuperH",
        0x32 => "IA-64",
        0x3e => "x86-64",
        0xb7 => "AArch64",
        0xf3 => "RISC-V",
        else => "Unknown",
    };
    printf("  Machine Type:             {s}\r\n", .{machtype});
    if (elf_file_class == ElfFileClass.ElfFileClass32) {
        printf("  Entry point:              0x{x}\r\n", .{header.e_entry});
        printf("  Program header offset:    0x{x}\r\n", .{header.e_phoff});
        printf("  Section header offset:    0x{x}\r\n", .{header.e_shoff});
        printf("  Program header count:     {}\r\n", .{header.e_phnum});
        printf("  Section header count:     {}\r\n", .{header.e_shnum});
        const program_headers: [*]Elf32_Phdr = @as([*]Elf32_Phdr, @ptrCast(@alignCast(program_headers_ptr)));
        puts("\r\nDebug: Program Headers: \r\n");
        var p: usize = 0;
        while (p < header.e_phnum) : (p += 1) {
            printf("[{}]: \r\n", .{p});
            printf("  p_type:                   0x{x}\r\n", .{program_headers[p].p_type});
            printf("  p_offset:                 0x{x}\r\n", .{program_headers[p].p_offset});
            printf("  p_vaddr:                  0x{x}\r\n", .{program_headers[p].p_vaddr});
            printf("  p_paddr:                  0x{x}\r\n", .{program_headers[p].p_paddr});
            printf("  p_filesz:                 0x{x}\r\n", .{program_headers[p].p_filesz});
            printf("  p_memsz:                  0x{x}\r\n", .{program_headers[p].p_memsz});
            printf("  p_flags:                  0x{x}\r\n", .{program_headers[p].p_flags});
            printf("  p_align:                  0x{x}\r\n", .{program_headers[p].p_align});
            puts("\r\n");
        }
    } else if (elf_file_class == ElfFileClass.ElfFileClass64) {
        printf("  Entry point:              0x{x}\r\n", .{header64.e_entry});
        printf("  Program header offset:    0x{x}\r\n", .{header64.e_phoff});
        printf("  Section header offset:    0x{x}\r\n", .{header64.e_shoff});
        printf("  Program header count:     {}\r\n", .{header64.e_phnum});
        printf("  Section header count:     {}\r\n", .{header64.e_shnum});
        const program_headers: [*]Elf64_Phdr = @as([*]Elf64_Phdr, @ptrCast(@alignCast(program_headers_ptr)));
        puts("\r\nProgram Headers: \r\n");
        var p: usize = 0;
        while (p < header.e_phnum) : (p += 1) {
            printf("[{}]: \r\n", .{p});
            printf("  p_type:                   0x{x}\r\n", .{program_headers[p].p_type});
            printf("  p_offset:                 0x{x}\r\n", .{program_headers[p].p_offset});
            printf("  p_vaddr:                  0x{x}\r\n", .{program_headers[p].p_vaddr});
            printf("  p_paddr:                  0x{x}\r\n", .{program_headers[p].p_paddr});
            printf("  p_filesz:                 0x{x}\r\n", .{program_headers[p].p_filesz});
            printf("  p_memsz:                  0x{x}\r\n", .{program_headers[p].p_memsz});
            printf("  p_flags:                  0x{x}\r\n", .{program_headers[p].p_flags});
            printf("  p_align:                  0x{x}\r\n", .{program_headers[p].p_align});
            puts("\r\n");
        }
    }
}

pub fn readElfFile(kernel_img_file: *uefi.protocol.File, file_class: ElfFileClass, kernel_header_buffer: *?*anyopaque, kernel_program_headers_buffer: *?*anyopaque) uefi.Status {
    const boot_services = uefi.system_table.boot_services.?;
    var buffer_read_size: u64 = 0;
    var program_headers_offset: u64 = 0;
    var status: uefi.Status = uefi.Status.Success;
    if (config.debug == true) {
        puts("Debug: Setting file pointer to read executable header\r\n");
    }
    status = kernel_img_file.setPosition(0);
    if (status != uefi.Status.Success) {
        puts("Error: Failed to set file pointer position\r\n");
        return status;
    }
    if (file_class == ElfFileClass.ElfFileClass32) {
        buffer_read_size = @sizeOf(Elf32_Ehdr);
    } else if (file_class == ElfFileClass.ElfFileClass64) {
        buffer_read_size = @sizeOf(Elf64_Ehdr);
    } else {
        puts("Error: Invalid file class\r\n");
        return uefi.Status.InvalidParameter;
    }
    if (config.debug == true) {
        printf("Debug: Allocating '0x{x}' bytes for kernel executable header\r\n", .{buffer_read_size});
    }
    status = boot_services.allocatePool(uefi.tables.MemoryType.LoaderData, buffer_read_size, @as(*[*]align(8) u8, @ptrCast(@alignCast(kernel_header_buffer))));
    if (status != uefi.Status.Success) {
        puts("Error: Failed to allocate kernel header buffer\r\n");
        return status;
    }
    if (config.debug == true) {
        puts("Debug: Reading kernel executable header\r\n");
    }
    status = kernel_img_file.read(&buffer_read_size, @as([*]align(8) u8, @ptrCast(@alignCast(kernel_header_buffer.*))));
    if (status != uefi.Status.Success) {
        puts("Error: Failed to read kernel header\r\n");
        return status;
    } else {
        puts("Debug: Reading kernel executable header worked\r\n");
    }
    if (file_class == ElfFileClass.ElfFileClass32) {
        program_headers_offset = @as(*Elf32_Ehdr, @ptrCast(@alignCast(kernel_header_buffer.*))).e_phoff;
        buffer_read_size = @sizeOf(Elf32_Phdr) *% @as(*Elf32_Ehdr, @ptrCast(@alignCast(kernel_header_buffer.*))).e_phnum;
    } else if (file_class == ElfFileClass.ElfFileClass64) {
        program_headers_offset = @as(*Elf64_Ehdr, @ptrCast(@alignCast(kernel_header_buffer.*))).e_phoff;
        buffer_read_size = @sizeOf(Elf64_Phdr) *% @as(*Elf64_Ehdr, @ptrCast(@alignCast(kernel_header_buffer.*))).e_phnum;
    }
    if (config.debug == true) {
        printf("Debug: Setting file offset to '0x{x}' to read program headers\r\n", .{program_headers_offset});
    }
    status = kernel_img_file.setPosition(program_headers_offset);
    if (status != uefi.Status.Success) {
        puts("Error: Setting file pointer position failed\r\n");
        return status;
    }
    if (config.debug == true) {
        printf("Debug: Allocating '0x{x}' bytes for program headers buffer\r\n", .{buffer_read_size});
    }
    status = boot_services.allocatePool(uefi.tables.MemoryType.LoaderData, buffer_read_size, @as(*[*]align(8) u8, @ptrCast(@alignCast(kernel_program_headers_buffer))));
    if (status != uefi.Status.Success) {
        puts("Error: Allocating program header buffer failed\r\n");
        return status;
    }
    if (config.debug == true) {
        puts("Debug: Reading program headers\r\n");
    }
    status = kernel_img_file.read(&buffer_read_size, @as([*]u8, @ptrCast(@alignCast(kernel_program_headers_buffer.*))));
    if (status != uefi.Status.Success) {
        puts("Error: Reading program headers failed\r\n");
    }
    puts("Debug: Reading ELF file worked\r\n");
    return status;
}

pub fn readElfIdentity(kernel_img_file: *uefi.protocol.File, elf_identity_buffer: *[*]u8) uefi.Status {
    var buffer_read_size: usize = EI_NIDENT;
    var status: uefi.Status = uefi.Status.Success;
    const boot_services = uefi.system_table.boot_services.?;
    if (config.debug == true) {
        puts("Debug: Setting file pointer position to read ELF identity\r\n");
    }
    status = kernel_img_file.setPosition(0);
    if (status != uefi.Status.Success) {
        puts("Error: Resetting file pointer position failed\r\n");
        return status;
    }
    if (config.debug == true) {
        puts("Debug: Allocating buffer for ELF identity\r\n");
    }
    // @as(*[*]align(8) u8, @ptrCast(@alignCast(elf_identity_buffer)))
    status = boot_services.allocatePool(uefi.tables.MemoryType.LoaderData, EI_NIDENT, @as(*[*]align(8) u8, @ptrCast(@alignCast(elf_identity_buffer))));
    if (status != uefi.Status.Success) {
        puts("Error: Allocating buffer for ELF identity failed\r\n");
        return status;
    }
    if (config.debug == true) {
        puts("Debug: Reading ELF identity\r\n");
    }
    status = kernel_img_file.read(&buffer_read_size, @as([*]u8, @ptrCast(elf_identity_buffer.*)));
    if (status != uefi.Status.Success) {
        puts("Error: Reading ELF identity failed\r\n");
        return status;
    }
    return status;
}

pub fn validateElfIdentity(elf_identity_buffer: [*]u8) uefi.Status {
    if ((elf_identity_buffer[EI_MAG0] != 0x7f) or (elf_identity_buffer[EI_MAG1] != 0x45) or (elf_identity_buffer[EI_MAG2] != 0x4c) or (elf_identity_buffer[EI_MAG3] != 0x46)) {
        puts("Error: Invalid ELF header\r\n");
        return uefi.Status.InvalidParameter;
    }
    if (elf_identity_buffer[EI_CLASS] == @intFromEnum(ElfFileClass.ElfFileClass32)) {
        if (config.debug == true) {
            puts("Debug: Found 32bit executable\r\n");
        }
    } else if (elf_identity_buffer[EI_CLASS] == @intFromEnum(ElfFileClass.ElfFileClass64)) {
        if (config.debug == true) {
            puts("Debug: Found 64bit executable\r\n");
        }
    } else {
        puts("Error: Invalid executable\r\n");
        return uefi.Status.Unsupported;
    }
    if (elf_identity_buffer[EI_DATA] != 1) {
        puts("Error: Only LSB ELF executables currently supported\r\n");
        return uefi.Status.IncompatibleVersion;
    }
    return uefi.Status.Success;
}
