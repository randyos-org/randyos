const std = @import("std");
const builtin = @import("builtin");

// shared w/ bootloader
const common = @import("common");
pub const build_options = common.build_options;
pub const KernelBootInfo = common.boot_info.KernelBootInfo;
pub const pages = common.pages;
pub const logging = common.logging;
pub const Terminal = common.Terminal;
pub const ansi = common.ansi;
pub const sgr = ansi.SgrCode;

// copied/updated from Loup OS
pub const arch = @import("arch/root.zig");
pub const mem = @import("mem/root.zig");
pub const kpa = mem.kernel_page_allocator;

// (re-)written for this kernel
const debug = @import("debug.zig");
pub const kassert = debug.kassert;
pub const kpanic = debug.kpanic;
const uart = @import("arch/x86_64/uart.zig");
const FBCon = @import("term/FBCon/root.zig");
const Ghostty = @import("term/Ghostty/root.zig");
const themes = @import("term/theme/root.zig").themes;

// new custom modules
pub const GraphicsDev = @import("gfx/Device.zig");
const drawLogo = @import("gfx/logo/draw.zig").drawLogo;
const time = @import("time/root.zig");
const hw = @import("hw/root.zig").interface;

// defined in linker script
pub extern const __kernel_start: u8;
pub extern const __kernel_end: u8;
/// end of normal kernel stack
pub extern const __stack_top: u8;
/// end of IST1 fault stack (idt.zig usesTrapStack); see gdt.zig setIST
pub extern const __fault_stack_top: u8;

/// KernelBootInfo ptr, written by bootloader at image start (.start section)
pub extern const __boot_info_ptr: *KernelBootInfo;

pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = logging.logFn,
    .page_size_min = pages.page_size,
    .page_size_max = pages.page_size,
};

// std.debug's default std.Io.Threaded needs OS primitives (POSIX
// getrandom, IOV_MAX) that don't exist on .freestanding
pub const std_options_debug_threaded_io: ?*std.Io.Threaded = null;
pub const std_options_debug_io: std.Io = .failing;

/// Kernel entry point. Naked calling convention (from bootloader) limits
/// what we can call, so this just calls arch.platform.setup(), which
/// sets up our own stack and jumps to _main (C convention). Bootloader
/// stack may not exist or may be the wrong shape, so the switch must
/// happen in naked asm before any normal Zig code runs. Split also
/// keeps _main a named symbol with a real prologue, useful for debuggers.
fn _start() linksection(".start") callconv(.naked) noreturn {
    // inline fn that eventually calls _main()
    arch.platform.setup();
}

/// C entry point, called by _start after the kernel stack is set up.
fn _main() callconv(.c) noreturn {
    // room for pre-kmain prep now that we have a stack; just calls kmain for now
    kmain(__boot_info_ptr);
}

comptime {
    @export(&_start, .{ .name = "_start" });
    @export(&_main, .{ .name = "_main" });
}

/// Kernel main. Linker ENTRY is _start (naked stub -> _main -> here);
/// kmain is export fn just to stay a named, locatable symbol for debuggers.
export fn kmain(boot_data: *KernelBootInfo) noreturn {
    const log = std.log.scoped(.kmain);
    const uart_term = initSerialTerm();
    var term = uart_term;
    if (term) |t| {
        t.cls();
    }
    initTimingServices(boot_data);

    // welcome messages
    log.debug("Kernel terminal initialized", .{});
    log.info("Welcome to RandyOS!", .{});
    time.logNow();

    // save the kernel size info
    const kernel_byte_size: usize = @intFromPtr(&__kernel_end) - @intFromPtr(&__kernel_start);
    const kernel_page_size: usize = std.math.divCeil(usize, kernel_byte_size, pages.page_size) catch unreachable;
    log.debug("kernel_start = 0x{x}, kernel_end = 0x{x}", .{ @as(usize, @intFromPtr(&__kernel_start)), @as(usize, @intFromPtr(&__kernel_end)) });

    // page allocator + debug info; needed before graphics or anything else
    kpa.init(boot_data);
    debug.init(kpa.allocator, boot_data.dwarf_info);

    // init graphics early so errors show without serial
    var gd: GraphicsDev = .{};
    initGfx(boot_data, &gd);

    // var fbcon: FBCon = .{};
    // term = initFBCon(&gd, &fbcon);

    var ghostty: Ghostty = .{};
    term = initGhostty(&gd, &ghostty);
    defer ghostty.deinit();

    parseHardwareDescription(boot_data);
    arch.platform.init(kpa.allocator, .{
        .kernel_boot_info = boot_data,
        .kernel_page_size = kernel_page_size,
    });

    // page tables up now, safe to allocate back buffer (see drawTarget);
    // switches over from direct-framebuffer path, preserving what's on screen
    gd.initBackBuffer();

    // driver support setup; ordering still TBD
    initDriverSupport();

    // load firmware driver if boot info has runtime ptrs; ok to fail silently
    initFwDriver(boot_data);

    if (build_options.run_demos) {
        // demos(&fbcon, uart_term, &gd);
    }

    kloop(term);
}

/// Idle loop: drain interrupt work, redraw if changed, halt till next
/// interrupt. Shape a future scheduler idle task can reuse directly.
///
/// term.render() also runs synchronously after every puts so log output
/// shows immediately even without returning here (e.g. panic mid-boot).
/// This call is a cheap no-op-if-unchanged safety net for state changes
/// outside puts (future keyboard echo, cursor blink).
fn kloop(term: ?*Terminal) noreturn {
    const log = std.log.scoped(.kmain_loop);
    log.info("Kernel initialized!  Idling...", .{});
    time.logNow();
    while (true) {
        if (builtin.cpu.arch == .x86_64) {
            arch.platform.ps2.processPending();
            if (term) |t| {
                t.inputs();
                t.render();
            }
            arch.platform.registers.halt();
        }
    }
}

fn initSerialTerm() ?*Terminal {
    const log = std.log.scoped(.kmain_serial);
    var term: ?*Terminal = null;
    switch (builtin.cpu.arch) {
        .x86_64 => {
            const uart_term = &uart.uart_term;
            uart_term.init(.{});
            term = uart_term;
        },
        else => return null,
    }
    logging.log_term = term;
    // log before timing init, forces -1 timestamp (for testing)
    log.info("-------------------------", .{});
    return term;
}

fn initTimingServices(boot_data: *KernelBootInfo) void {
    const log = std.log.scoped(.kmain_time);
    switch (builtin.cpu.arch) {
        .x86_64 => {
            // init clock, wire logging clock
            arch.platform.tsc.init();
            logging.get_time = &arch.platform.tsc.getTime;
            time.init(boot_data.boot_wall_clock_unix_seconds);
        },
        else => return,
    }
    log.debug("timing services started", .{});
}

/// Runs before page tables are up (see kmain), so no back buffer yet --
/// clear/drawLogo draw straight to the real framebuffer (drawTarget),
/// already visible immediately, so no presentAll needed here.
fn initGfx(boot_data: *KernelBootInfo, gd: *GraphicsDev) void {
    // const log = std.log.scoped(.kmain_gfx);
    gd.init(boot_data);
    // framebuffer starts as firmware/bootloader garbage; clear first so
    // the logo draws onto a clean backdrop
    gd.clear(themes.get_current().primary.background);
    drawLogo(gd);
}

fn initFBCon(gd: *GraphicsDev, fbcon: *FBCon) *Terminal {
    const log = std.log.scoped(.kmain_fbcon);
    fbcon.init(gd, false);
    const term = &fbcon.term;
    logging.log_term = term;
    log.debug("fbcon initialized", .{});
    return term;
}

fn initGhostty(gd: *GraphicsDev, ghostty: *Ghostty) *Terminal {
    const log = std.log.scoped(.kmain_ghostty);
    ghostty.init(gd, false);
    const term = &ghostty.term;
    logging.log_term = term;
    log.debug("ghostty initialized", .{});
    return term;
}

fn initDriverSupport() void {
    const log = std.log.scoped(.kmain_drv);
    log.debug("initialize driver support", .{});
    // TODO: driver support init
}

/// STUB: eventual load site for a firmware runtime driver (e.g.
/// src/drivers/uefi/root.zig) once fw_runtime_ptr is present -- see
/// FirmwareRuntimeData (common/boot_info.zig) for why it's a raw opaque
/// ptr, and drivers/uefi/root.zig for why loading is deferred. Only
/// checks presence today. Never gate on cpu.arch == .x86_64 -- UEFI
/// isn't x86_64-only (aarch64 too), so driver selection is its own
/// axis, independent of arch.zig's dispatch.
///
/// Allowed to fail/no-op silently: every capability here is optional
/// and rare (ACPI FADT reset, PSCI, direct HW access cover common cases).
fn initFwDriver(boot_data: *KernelBootInfo) void {
    const log = std.log.scoped(.kmain_fw);
    log.debug("initialize firmware driver", .{});
    if (boot_data.fw_runtime_ptr) |ptrs| {
        // TODO: load driver from ptrs
        _ = ptrs; // unused for now
    }
}

/// Parsing the hardware description (ACPI today, devicetree later) is
/// firmware-format specific but not CPU-arch specific (some arm64
/// servers use ACPI too), so it happens here, not in arch.platform.init.
/// Interpreting the result IS arch-specific (e.g. MADT's I/O APIC
/// entries are x86-only), left to arch.platform.init and its drivers
/// (ioapic.zig reads hw_acpi.madt_ptr after this runs).
fn parseHardwareDescription(boot_data: *KernelBootInfo) void {
    const log = std.log.scoped(.kmain_hw);
    log.debug("parsing hardware description", .{});
    switch (boot_data.hardware_description orelse @panic("no hardware description provided by the bootloader at all")) {
        .acpi => |a| {
            if (!build_options.has_acpi) {
                @panic("bootloader provided an ACPI hardware description, but this kernel was built with -Dacpi=false");
            }
            hw.init(a.rsdp) catch @panic("no usable ACPI tables found");
        },
        .devicetree => |d| {
            if (!build_options.has_devicetree) {
                @panic("bootloader provided a Device Tree hardware description, but this kernel was built with -Ddevicetree=false");
            }
            hw.init(d.blob) catch @panic("no usable Device Tree found");
        },
    }
}

fn demos(fbcon: *FBCon, uart_term: ?*Terminal, gd: *GraphicsDev) void {
    const log = std.log.scoped(.kmain_demos);
    time.sleep(0.3);
    for (0..50) |i| {
        log.warn("Hello world from kernel (fbcon) (iteration {})!", .{i});
        time.sleepMs(250);
    }
    time.sleep(0.5);

    // test fbcon for escape sequence
    fbcon.*.puts("fbcon test\n");
    const fbterm = &fbcon.*.term;
    fbterm.puts( //
        ansi.CSI ++ ansi.SgrCode.fg_indexed ++ ";100" ++ ansi.SGR //
        ++ ansi.CSI ++ ansi.CLS ++ ansi.CSI ++ ansi.HOME //
        ++ ansi.CSI ++ sgr.bold ++ ";" ++ sgr.underline ++ ";" ++ sgr.invert ++ ";" ++ sgr.fg_magenta ++ ansi.SGR //
        ++ "Hello World!\n" //
        ++ ansi.CSI ++ sgr.reset ++ ";" ++ sgr.fg_magenta ++ ansi.SGR //
        ++ "2026 by Randy Eckman\n" //
        ++ ansi.CSI ++ sgr.reset ++ ansi.SGR //
        ++ "Normal text\n" //
    );

    // also print to uart for testing
    if (uart_term) |t| {
        t.puts( //
            ansi.CSI ++ ansi.SgrCode.fg_indexed ++ ";100" ++ ansi.SGR //
            ++ ansi.CSI ++ ansi.CLS ++ ansi.CSI ++ ansi.HOME //
            ++ ansi.CSI ++ sgr.bold ++ ";" ++ sgr.underline ++ ";" ++ sgr.invert ++ ";" ++ sgr.fg_magenta ++ ansi.SGR //
            ++ "Hello World!\n" //
            ++ ansi.CSI ++ sgr.reset ++ ";" ++ sgr.fg_magenta ++ ansi.SGR //
            ++ "2026 by Randy Eckman\n" //
            ++ ansi.CSI ++ sgr.reset ++ ansi.SGR //
            ++ "Normal text\n" //
        );
    }
    time.sleep(0.5);
    // draw a rectangle
    gd.drawRect(100, 500, 100, 100, .{
        .red = 0xff,
        .green = 0x66,
        .blue = 0x00,
    });

    if (time.now()) |dt| {
        log.info("Current wall time: {}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2} UTC", .{
            dt.year, dt.month.numeric(), dt.day, dt.hour, dt.minute, dt.second,
        });
    }
}

pub const panic = std.debug.FullPanic(debug.panic);
