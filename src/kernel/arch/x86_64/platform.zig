//! Arch x86-64 main platform
//! 2024 by Samuel Fiedler

const std = @import("std");
const log = std.log.scoped(.arch_platform);

const common = @import("common");
const KernelBootInfo = common.boot_info.KernelBootInfo;

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

/// First interrupt vector the (remapped) legacy PIC's master chip is given
/// for its 8 IRQ lines -- placed just past the 32 CPU exception vectors
/// (0-31) so a stray legacy IRQ can't collide with one.
const pic_master_vector_offset: u8 = 32;
/// First vector the PIC's slave chip is given -- immediately after the
/// master's 8 vectors.
const pic_slave_vector_offset: u8 = pic_master_vector_offset + 8;
/// First vector the I/O APIC's redirection table entries are given (see
/// `idt.zig`'s `keyboard_vector`, which depends on this exact value).
const ioapic_vector_offset: u8 = 48;

/// Arguments passed to the platform init
pub const InitParams = struct {
    /// Kernel Boot Information
    kernel_boot_info: *KernelBootInfo,
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
    // Remap before disabling: if a legacy PIC interrupt sneaks in during the
    // brief window before disable() takes effect, it lands above vector 31
    // instead of colliding with a CPU exception vector.
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

    // ACPI's static tables (RSDP/XSDT/MADT) are already validated and
    // parsed by the time this runs -- `kmain` does that generically before
    // calling here, since table parsing itself isn't architecture-specific
    // (see `hw/acpi/root.zig`). What *is* architecture-specific is
    // interpreting a particular MADT entry type -- `ioapic.init` does that
    // for x86_64's I/O APIC entries, reading the already-populated
    // `hw.acpi.madt_ptr` itself rather than being handed pre-extracted
    // values here.
    ioapic.init(ioapic_vector_offset);
    log.debug("CR0 contents: {}", .{registers.CR0.get()});
    log.info("Platform-specific initialization successful! ", .{});
}
