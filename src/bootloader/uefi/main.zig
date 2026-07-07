//! This is the main part of the bootloader.

const std = @import("std");
const uefi = std.os.uefi;
const log = std.log.scoped(.bootmain);

pub const loader = @import("loader/root.zig");
pub const memory = @import("memory.zig");
pub const logging = @import("logging.zig");
pub const graphics = @import("graphics.zig");
pub const bootinfomod = @import("bootinfo.zig");
pub const filesys = @import("filesys.zig");

/// Standard Library Options
pub const std_options = std.Options{
    .log_level = .info,
    .logFn = logging.logFn,
};

/// Disable the watchdog timer. Boot Services normally kill the running
/// image after 5 minutes by default; since jumping into the kernel doesn't
/// stop boot services from *thinking* the bootloader image is still
/// running, the watchdog would otherwise fire under the kernel later.
fn disableWatchdogTimer(boot_services: *uefi.tables.BootServices) !void {
    // A zero timeout (in seconds) disables the watchdog entirely; the
    // watchdog code is only meaningful when re-arming it, so it's left 0.
    const watchdog_disabled_timeout_seconds: usize = 0;
    const watchdog_code: u64 = 0;
    log.debug("disabling watchdog timer", .{});
    boot_services.setWatchdogTimer(watchdog_disabled_timeout_seconds, watchdog_code, null) catch |err| {
        log.err("disabling watchdog timer failed: {s}", .{@errorName(err)});
        return err;
    };
    log.debug("watchdog timer disabled", .{});
}

/// Jump into the kernel. `kernel_entry_point` was read out of the ELF
/// header by the loader; the only thing that can't be done through a plain
/// function pointer is passing it arguments, hence `KernelBootInfo` being
/// communicated via `writeBootInfoPointer` instead.
fn jumpToKernel(kernel_entry_point: u64) noreturn {
    const kernel_entry: *const fn () callconv(.c) noreturn = @ptrFromInt(kernel_entry_point);
    kernel_entry();
}

/// This is the main bootloader function, not to be confused with the bootloader
/// entry point. It is just separated from the main function so the main entry
/// point can catch errors, though we are unlikely to be able to handle them.
pub fn bootloader() !void {
    // in case of error, initialize logging before anything else
    logging.initLogging();

    const system_table = uefi.system_table;
    const boot_services = system_table.boot_services.?;
    const runtime_services = system_table.runtime_services;

    // get essential system services initialized
    const gfx = try graphics.locateGraphicsOutput(boot_services);
    const root_file_system = try filesys.openRootFileSystem(boot_services);

    // The loader needs the memory map to pick a physical location for the
    // kernel once it knows how big the kernel's segments actually are (see
    // loader.findKernelLoadAddress); it's reused again below to prepare the
    // virtual address map before exiting boot services.
    log.debug("getting memory map to find free addresses", .{});
    var mm = try memory.fetch(boot_services, 0);

    var kernel = try loader.loadKernel(root_file_system, mm);
    var kernel_boot_info = bootinfomod.buildKernelBootInfo(system_table, gfx, &kernel.dwarf_info);

    // now that it looks likely we will boot into the kernel, disable watchdog
    // before finally exiting boot services
    try disableWatchdogTimer(boot_services);

    // This is also the last point at which it's safe to log anything: once
    // exitBootServices() succeeds, con_out (and Boot Services in general)
    // are torn down and the firmware is free to reclaim that memory, so
    // touching them afterwards jumps into whatever now lives there instead.
    try memory.exitBootServices(boot_services, uefi.handle, &mm);
    logging.stopLogging(); // since con_out is freed, we can no longer log anything

    // update boot info with final memory details after exiting boot services
    try bootinfomod.finalizeKernelBootInfo(&kernel_boot_info, runtime_services, mm, kernel.kernel_start_address);
    // write the boot info pointer at the beginning of kernel memory so the kernel can find it easily
    bootinfomod.writeBootInfoPointer(kernel.base_address, &kernel_boot_info);
    // with the finalized boot info in place, jump to the kernel
    jumpToKernel(kernel.kernel_entry_point);
}

/// This is a wrapper to call the bootloader function.
/// If nothing went wrong, this catch block should never run, because the
/// kernel should already be running by then...
pub fn main() void {
    bootloader() catch |err| {
        // The computer should never get here because everything should
        // succeed.
        // But just in case anything happens, we print out the name of the
        // error that was responsible for that fail. In any function, we
        // always print out "Error: xyz failed", so we have something like a
        // stack trace.
        log.err("error occurred during bootloader main function: {s}", .{@errorName(err)});
    };
    while (true) {}
}
