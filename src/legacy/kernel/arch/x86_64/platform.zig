//! x86_64 platform
//! 2024 by Samuel Fiedler

const std = @import("std");
const log = std.log.scoped(.arch_platform);

const common = @import("common");
const KernelBootInfo = common.boot_info.KernelBootInfo;

pub const port_io = @import("port_io.zig");
pub const registers = @import("registers.zig");
pub const gdt = @import("gdt.zig");
pub const idt = @import("idt.zig");
pub const ps2 = @import("ps2.zig");
pub const lapic = @import("lapic.zig");
pub const ioapic = @import("ioapic.zig");
pub const pic = @import("pic.zig");
pub const paging = @import("paging.zig");
pub const tsc = @import("tsc.zig");
// pub const term = @import("term.zig");
// pub extern const kernel_boot_info: *boot_info.KernelBootInfo;

/// first vector given to the remapped PIC master's 8 IRQs; past the 32 CPU
/// exception vectors so a stray legacy IRQ can't collide with one
const pic_master_vector_offset: u8 = 32;
/// first vector given to the PIC slave, right after master's 8
const pic_slave_vector_offset: u8 = pic_master_vector_offset + 8;
/// first vector for I/O APIC redirection entries (idt.zig's
/// keyboard_vector depends on this exact value)
const ioapic_vector_offset: u8 = 48;

pub const InitParams = struct {
    kernel_boot_info: *KernelBootInfo,
    /// kernel size in 4KB pages
    kernel_page_size: usize,
};

/// Swap bootloader stack for kernel stack, then call _main (C callconv).
/// Inline-expanded into a naked function!
pub inline fn setup() void {
    asm volatile (

    // point RSP at our stack top, replacing the bootloader's
        \\mov $__stack_top, %rsp

        // SysV ABI needs RSP 16-aligned right before `call` (call's own
        // push leaves the callee 8-off-16). __stack_top is 16-aligned, so
        // one push would leave `_main` wrongly 16-aligned instead of
        // 8-off-16 -- fine for normal code, but a hard #GP the first time
        // an SSE instr with an aligned operand runs (hit via movaps in the
        // first UART log call, before our IDT even exists). Two pushes
        // fixes the arithmetic and gives unwinders a clean null-RBP/null-
        // return-addr base frame.
        \\push $0
        \\push $0

        \\call _main
    );
}

pub fn init(allocator: std.mem.Allocator, params: InitParams) void {
    const kern_info = params.kernel_boot_info;
    log.info("Platform-specific initialization... ", .{});
    gdt.init();
    idt.init();
    log.info("PIC disabling... ", .{});
    // remap before disable: a stray legacy IRQ in the gap lands above
    // vector 31 instead of colliding with a CPU exception
    pic.remap(pic_master_vector_offset, pic_slave_vector_offset);
    pic.disable();
    log.info("PIC disabling successful! ", .{});
    paging.init(
        allocator,
        kern_info.memory_map,
        kern_info.kernel_phys_start,
        params.kernel_page_size,
    );
    lapic.init();

    // ACPI tables already parsed generically by kmain (hw/acpi/root.zig);
    // ioapic.init does the arch-specific MADT I/O-APIC-entry interpretation
    ioapic.init(ioapic_vector_offset);
    log.debug("CR0 contents: {}", .{registers.CR0.get()});
    log.info("Platform-specific initialization successful! ", .{});
}
