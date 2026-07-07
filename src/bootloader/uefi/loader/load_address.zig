//! Picking a physical memory location to load the kernel's ELF `PT_LOAD`
//! segments into.

const std = @import("std");
const uefi = std.os.uefi;
const elf = std.elf;
const log = std.log.scoped(.bootaddr);

const common = @import("common");
const pages = common.pages;
const memory = @import("../memory.zig");

/// Errors from picking a physical location to load the kernel at
pub const FindLoadAddressError = error{NoSuitableMemory};

/// Physical regions below this address are never considered for the kernel
/// load location -- the legacy 1MiB low-memory area (BIOS data area,
/// VGA/option ROM windows, etc.), same boundary the kernel's own page
/// allocator applies later.
const min_kernel_load_address: u64 = 0x100000;

/// Compute how many bytes of physical memory the kernel's PT_LOAD segments
/// span (from the lowest segment's vaddr to the end of the highest one),
/// then find a UEFI conventional-memory region at/above 1MB that's actually
/// big enough to hold the whole thing -- rather than trusting the first
/// such region regardless of size, which can leave later segments spilling
/// past the end of a too-small region and into memory the firmware is
/// still using (silent heap corruption, surfacing as a fault deep inside
/// some later, unrelated boot service call).
pub fn findKernelLoadAddress(
    mm: memory.MemoryMap,
    program_headers: []const elf.Elf64.Phdr,
) FindLoadAddressError!u64 {
    var min_vaddr: u64 = std.math.maxInt(u64);
    var max_vaddr_end: u64 = 0;
    var any_load = false;
    for (program_headers) |phdr| {
        if (phdr.type != .LOAD) continue;
        any_load = true;
        if (phdr.vaddr < min_vaddr) min_vaddr = phdr.vaddr;
        const segment_end = phdr.vaddr + phdr.memsz;
        if (segment_end > max_vaddr_end) max_vaddr_end = segment_end;
    }
    if (!any_load) {
        log.err("no LOAD segments to size the kernel image from", .{});
        return error.NoSuitableMemory;
    }
    const required_size = max_vaddr_end - min_vaddr;
    log.debug("kernel image needs {} bytes of physical memory", .{required_size});

    var mem_index: usize = 0;
    while (mem_index < mm.info.len) : (mem_index += 1) {
        const mem_point: *uefi.tables.MemoryDescriptor = @ptrCast(@alignCast(mm.map.ptr + (mem_index * mm.info.descriptor_size)));
        if (mem_point.type == .conventional_memory and
            mem_point.physical_start >= min_kernel_load_address and
            mem_point.number_of_pages * @as(u64, pages.page_size) >= required_size)
        {
            log.debug("found {} free pages (>= {} bytes needed) at 0x{x}", .{ mem_point.number_of_pages, required_size, mem_point.physical_start });
            return mem_point.physical_start;
        }
    }
    log.err("no conventional memory region >= 1M big enough for the kernel image ({} bytes)", .{required_size});
    return error.NoSuitableMemory;
}
