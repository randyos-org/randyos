//! This is the main part of the bootloader.

const std = @import("std");
const uefi = std.os.uefi;
const log = std.log.scoped(.bootmain);

const loader = @import("loader/__root__.zig");
const memory = @import("memory.zig");
const logging = @import("logging.zig");
const graphics = @import("graphics.zig");
const bootinfomod = @import("bootinfo.zig");
const filesys = @import("filesys.zig");
const watchdog = @import("watchdog.zig");

// const bootloader = @import("demos/hello1.zig").bootloader;
// const bootloader = @import("demos/protocols2.zig").bootloader;
// const bootloader = @import("demos/events3.zig").bootloader;
// const bootloader = @import("demos/memory4.zig").bootloader;
// const bootloader = @import("demos/exit_boot_services5.zig").bootloader;
// const bootloader = @import("demos/efivars6.zig").bootloader;

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
    var kernel_boot_info = try bootinfomod.buildKernelBootInfo(system_table, gfx, &kernel.dwarf_info);

    // now that it looks likely we will boot into the kernel, disable watchdog
    // before finally exiting boot services
    try watchdog.disableWatchdogTimer(boot_services);

    // This is also the last point at which it's safe to log anything: once
    // exitBootServices() succeeds, con_out (and Boot Services in general)
    // are torn down and the firmware is free to reclaim that memory, so
    // touching them afterwards jumps into whatever now lives there instead.
    try memory.exitBootServices(boot_services, uefi.handle, &mm);
    logging.stopLogging(); // since con_out is freed, we can no longer log anything

    // update boot info with final memory details after exiting boot services
    try bootinfomod.finalizeKernelBootInfo(&kernel_boot_info, runtime_services, mm, kernel.plan.dest, kernel.plan.size);

    // Move the kernel image to its link address if it had to be staged
    // elsewhere while Boot Services still owned parts of that range
    // This MUST come after finalizeKernelBootInfo: the destination may cover
    // memory the firmware was still using at exit, and finalize is the last
    // thing that reads any of it.
    loader.moveKernelToDestination(kernel.plan);
    // write the boot info pointer at the beginning of kernel memory so the kernel can find it easily
    bootinfomod.writeBootInfoPointer(kernel.baseAddress(), &kernel_boot_info);
    // with the finalized boot info in place, jump to the kernel.
    // `kernel_entry_point` was read out of the ELF header by the loader;
    // the only thing that can't be done through a plain function pointer is
    // passing it arguments, hence `KernelBootInfo` being communicated via
    // `writeBootInfoPointer` instead.
    const kernel_entry: *const fn () callconv(.c) noreturn = @ptrFromInt(kernel.kernel_entry_point);
    kernel_entry();
}

/// This is a wrapper to call the bootloader function.
/// If nothing went wrong, this catch block should never run, because the
/// kernel should already be running by then...
pub fn main() void {
    bootloader() catch |err| {
        // The computer should never get here because everything should succeed.
        // But just in case anything happens, we print out the name of the
        // error that was responsible for that fail. In any function, we
        // always print out "Error: xyz failed", so we have something like a
        // stack trace.
        log.err("error occurred during bootloader main function: {s}", .{@errorName(err)});
    };
    while (true) {}
}
