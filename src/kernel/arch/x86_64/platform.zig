//! Arch x86-64 main platform
//! 2024 by Samuel Fiedler

const std = @import("std");
const log = std.log.scoped(.arch_platform);

const common = @import("common");
const boot_info = common.boot_info;
// const boot_info = @import("../../../boot_info.zig");

/// Port Input / Output
pub const port_io = @import("port_io.zig");
/// CPU Registers
pub const registers = @import("registers.zig");
/// Global Descriptor Table
pub const gdt = @import("gdt.zig");
/// Interrupt Descriptor Table
pub const idt = @import("idt.zig");
/// PS/2 Keyboard Controller
pub const ps2 = @import("ps2.zig");
/// Advanced Programmable Interrupt Controller
pub const lapic = @import("lapic.zig");
/// I/O Advanced Programmable Interrupt Controller
pub const ioapic = @import("ioapic.zig");
/// Programmable Interrupt Controller
pub const pic = @import("pic.zig");
/// Paging
pub const paging = @import("paging.zig");
/// TSC-based timekeeping
pub const tsc = @import("tsc.zig");
/// UART terminal
// pub const term = @import("term.zig");
/// Kernel Boot Info by UEFI
// pub extern const kernel_boot_info: *boot_info.KernelBootInfo;

/// Arguments passed to the platform init
pub const InitParams = struct {
    /// I/O APIC Address
    ioapic_addr: usize,
    /// Global System Interrupt Base
    glob_sys_int_base: u32,
    /// Kernel Boot Information
    kernel_boot_info: *boot_info.KernelBootInfo,
    /// Kernel Size in 4KB pages
    kernel_page_size: usize,
};

/// Do some essential work (where the processor can't continue without that work)
pub inline fn setup() void {
    asm volatile (
        \\mov %rsp, __stack_top
        \\push $0
        \\call _main
    );
}

/// Platform-specific init
pub fn init(allocator: std.mem.Allocator, params: InitParams) void {
    const kern_info = params.kernel_boot_info;
    log.info("Platform-specific initialization... ", .{});
    gdt.init();
    idt.init();
    log.info("PIC disabling... ", .{});
    pic.remap(32, 40);
    pic.disable();
    log.info("PIC disabling successful! ", .{});
    paging.init(
        allocator,
        kern_info.map,
        kern_info.map_info,
        kern_info.kernel_phys_start,
        params.kernel_page_size,
    );
    lapic.init();
    ioapic.init(params.ioapic_addr, params.glob_sys_int_base, 48);
    log.debug("CR0 contents: {}", .{registers.CR0.get()});
    log.info("Platform-specific initialization successful! ", .{});
}
