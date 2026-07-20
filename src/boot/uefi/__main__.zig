//! Main bootloader logic.

const std = @import("std");
const uefi = std.os.uefi;
const log = std.log.scoped(.bootmain);

const rstd = @import("rstd");
const rio = rstd.io;

const loader = @import("loader/__root__.zig");
const memory = @import("memory.zig");
const logging = @import("logging.zig");
const graphics = @import("graphics.zig");
const bootinfomod = @import("bootinfo.zig");
const watchdog = @import("watchdog.zig");

// const main = @import("demos/hello1.zig").bootloader;
// const main = @import("demos/protocols2.zig").bootloader;
// const main = @import("demos/events3.zig").bootloader;
// const main = @import("demos/memory4.zig").bootloader;
// const main = @import("demos/exit_boot_services5.zig").bootloader;
// const main = @import("demos/efivars6.zig").bootloader;

const BootData = struct {
    mm: memory.MemoryMap,
    kernel: loader.LoadedKernel,
    kernel_boot_info: rstd.machine.KernelBootInfo,
};

/// Main bootloader logic, separate from `main` so errors can be caught
/// (unlikely we can do much about them).
pub fn bootloader() !BootData {
    // init console/logging early, in case of error
    const io = rio.io_inst;
    rio.init.?();
    defer rio.stop.?();

    log.debug("pre-init log test", .{});
    logging.initLogging();
    defer logging.stopLogging();

    const system_table = uefi.system_table;
    const boot_services = system_table.boot_services.?;

    // init essential system services
    const gfx = try graphics.locateGraphicsOutput(boot_services);
    const root_dir = rstd.io.cwd();

    // loader needs the memory map to place the kernel once segment sizes
    // are known; reused below for the virtual addr map before exit
    log.debug("getting memory map to find free addresses", .{});
    var mm = try memory.fetch(boot_services, 0);

    var kernel = try loader.loadKernel(io, root_dir, mm);
    const kernel_boot_info = try bootinfomod.buildKernelBootInfo(system_table, gfx, &kernel.dwarf_info);

    // disable watchdog before exiting boot services
    try watchdog.disableWatchdogTimer(boot_services);

    // last safe point to log: exitBootServices() tears down con_out and
    // Boot Services, so touching them after reads reclaimed memory instead
    try memory.exitBootServices(boot_services, uefi.handle, &mm);

    return .{ .mm = mm, .kernel = kernel, .kernel_boot_info = kernel_boot_info };
}

/// Wrapper calling `bootloader()`; the catch below should be unreachable --
/// the kernel should already be running by then.
pub fn main() void {
    const bootdata: BootData = bootloader() catch |err| {
        // should never happen; log error name as a poor-man's stack trace
        log.err("error occurred during bootloader main function: {s}", .{@errorName(err)});
        while (true) {}
    };

    const kernel = bootdata.kernel;
    var kernel_boot_info = bootdata.kernel_boot_info;

    // finalize boot info with post-exit memory details.
    // with no boot services, there's nothing safe left to do on error but halt.
    bootinfomod.finalizeKernelBootInfo(&kernel_boot_info, uefi.system_table.runtime_services, bootdata.mm, kernel.plan.dest, kernel.plan.size) catch {
        while (true) {}
    };
    // Move staged kernel to its link address. MUST run after
    // finalizeKernelBootInfo: dest may cover memory firmware still used at
    // exit, and finalize is the last thing that reads any of it.
    loader.moveKernelToDestination(kernel.plan);
    // write boot info pointer for the kernel to find
    bootinfomod.writeBootInfoPointer(kernel.baseAddress(), &kernel_boot_info);
    // jump to kernel; entry point read from ELF header by the loader. args
    // can't pass through a plain fn ptr, hence KernelBootInfo via
    // writeBootInfoPointer instead.
    const kernel_entry: *const fn () callconv(.c) noreturn = @ptrFromInt(kernel.kernel_entry_point);
    kernel_entry();

    while (true) {}
}
