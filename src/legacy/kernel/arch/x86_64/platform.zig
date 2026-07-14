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

/// Replace the bootloader stack with the kernel stack and then call _main with
/// the C calling convention. This is an inline expanded in a naked function!
pub inline fn setup() void {
    asm volatile (

    // push our hard-coded stack top into RSP.
    // RSP is the stack pointer register, so this replaces the bootloader
    // stack with our own by overwriting the register.
        \\mov $__stack_top, %rsp

        // The System V x86-64 ABI requires RSP to be 16-byte aligned
        // immediately *before* a `call` -- `call` itself pushes an 8-byte
        // return address, so the callee's very first instruction always
        // sees RSP sitting 8 bytes off a 16-byte boundary (RSP % 16 == 8).
        // `__stack_top` is 16-byte aligned on its own, so a single `push`
        // here (however many bytes it pushes) throws that off: one 8-byte
        // push leaves RSP 16-aligned going into `call`, which then leaves
        // `_main` starting at a 16-aligned RSP instead of the required
        // 8-off-16 -- silently wrong for ordinary integer/pointer code, but
        // a hard #GP fault the first time anything in the call chain uses
        // an SSE instruction with a strict 16-byte-aligned memory operand
        // (confirmed via GDB: `Io.Writer.print`'s `movaps` inside the very
        // first UART log call in `kmain`, before our own IDT is even
        // installed, so the fault has nowhere real to go).
        //
        // Two pushes fixes the arithmetic (two 8-byte pushes = 16 bytes,
        // preserving 16-alignment through to `call`) and also gives an
        // RBP-chain unwinder a cleaner base frame: a null return address
        // *and* a null saved RBP at the very bottom of the stack, matching
        // the usual "outermost frame" sentinel convention, rather than
        // just the return address alone.
        \\push $0
        \\push $0

        // call _main with the C calling convention
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
