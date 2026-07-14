const std = @import("std");
const builtin = @import("builtin");

// common lib shared with bootloader
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

// The constants here are defined in the kernel linker script
pub extern const __kernel_start: u8;
pub extern const __kernel_end: u8;
/// End of the normal kernel stack.
pub extern const __stack_top: u8;
/// End of the dedicated IST1 stack `usesTrapStack` (idt.zig) switches to for
/// stack/GP/page-fault/double-fault exceptions -- see gdt.zig's `setIST`.
pub extern const __fault_stack_top: u8;

/// Pointer to `KernelBootInfo`, written by the bootloader at the very start
/// of the loaded image (see `.start` in the linker script).
pub extern const __boot_info_ptr: *KernelBootInfo;

/// Zig Standard Library Options
pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = logging.logFn,
    .page_size_min = pages.page_size,
    .page_size_max = pages.page_size,
};

// The default `std.Io` backing `std.debug` (stack trace capture, DWARF
// unwinding, etc.) is `std.Io.Threaded`, which unconditionally references
// OS-level primitives (e.g. POSIX `getrandom`, `IOV_MAX`) that don't exist
// for `.freestanding`, so it can't even be instantiated on this target.
pub const std_options_debug_threaded_io: ?*std.Io.Threaded = null;
pub const std_options_debug_io: std.Io = .failing;

/// Kernel Entry Point.  Entering from the bootloader, the calling
/// convention is naked, which limits our ability to call other functions from
/// here.  This function calls out to arch.plaform.setup(), which sets up the
/// stack and jumps to a C-calling-convention function (`_main`), which then
/// actually calls `kmain`. This is because the bootloader doesn't necessarily
/// set up a stack at all, and even if it does, it might not be in the shape we
/// want -- e.g. on x86_64, we want to switch to our own kernel stack instead
/// of using whatever the bootloader left us with, so we have to do that part
/// in naked assembly before we can call any normal Zig code at all.
/// The split also keeps `_main` as a named symbol with a proper
/// prologue/epilogue, which is helpful for debuggers and backtraces.
fn _start() linksection(".start") callconv(.naked) noreturn {
    // an inline function that eventually calls _main()
    arch.platform.setup();
}

/// Kernel C entry point, called by the naked `_start` after
/// the kernel stack has been set up.
fn _main() callconv(.c) noreturn {
    // This is in case we want to do any prep before calling kmain that requires
    // a stack now that we have one, but for now it, just calls kmain.
    kmain(__boot_info_ptr);
}

comptime {
    @export(&_start, .{ .name = "_start" });
    @export(&_main, .{ .name = "_main" });
}

/// This is our kernel main function.
/// The linker script's actual `ENTRY` is `_start` (the naked asm stub above
/// that sets up the stack and jumps to `_main`, which calls this) -- `kmain`
/// is still `export fn` so it stays a named, locatable symbol (e.g. for a
/// debugger), not because the linker enters here directly.
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

    // page allocator init and debugging info
    // needed before all other operations, including graphics
    kpa.init(boot_data);
    debug.init(kpa.allocator, boot_data.dwarf_info);

    // initialize graphics early so errors can be displayed to user without serial
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

    // The kernel's own page tables are up now, so it's finally safe to
    // allocate the graphics back buffer (see `GraphicsDev.drawTarget`'s doc
    // comment for why not any earlier) -- switches drawing over from the
    // direct-to-framebuffer path `initGfx`/early Ghostty logging used,
    // preserving whatever's already on screen.
    gd.initBackBuffer();

    // setup driver support here (this probably requires a few other things
    // before this, but starting to determine the order of operations now)
    initDriverSupport();

    // Check for firmware runtime pointers in kernel boot info.
    // If present, try to load the firmware driver.
    // This is allowed to fail without panic.
    initFwDriver(boot_data);

    if (build_options.run_demos) {
        // demos(&fbcon, uart_term, &gd);
    }

    kloop(term);
}

/// Idle loop: drain deferred interrupt work, redraw the terminal if
/// anything changed, then halt until the next interrupt. This is the
/// shape a scheduler's idle task will also take (drain pending work,
/// block) -- becomes that task's body directly once one exists.
///
/// `term.render()` is also called synchronously after every `puts`
/// (see Terminal.puts) so log output shows up immediately even if the
/// kernel never makes it back here (e.g. a panic mid-boot). The call here
/// is a cheap safety net -- `render()` no-ops when nothing changed -- for
/// state changes that don't flow through `puts`, such as future keyboard
/// echo or cursor blinking.
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
            // Initialize UART terminal
            const uart_term = &uart.uart_term;
            uart_term.init(.{});
            term = uart_term;
        },
        else => return null,
    }
    logging.log_term = term;
    // intentionally log before timing services init'd to force -1 timestamp for testing
    log.info("-------------------------", .{});
    return term;
}

fn initTimingServices(boot_data: *KernelBootInfo) void {
    const log = std.log.scoped(.kmain_time);
    switch (builtin.cpu.arch) {
        .x86_64 => {
            // init clock and set logging clock
            arch.platform.tsc.init();
            logging.get_time = &arch.platform.tsc.getTime;
            time.init(boot_data.boot_wall_clock_unix_seconds);
        },
        else => return,
    }
    log.debug("timing services started", .{});
}

/// Runs before `arch.platform.init` sets up the kernel's own page tables
/// (see `kmain`), so the graphics device's back buffer doesn't exist yet
/// either -- both `clear` and `drawLogo` below draw straight to the real
/// framebuffer instead (see `GraphicsDev.drawTarget`), which is why
/// there's no `presentAll` call here: a direct-target draw is already
/// visible the moment it happens, nothing needs presenting.
fn initGfx(boot_data: *KernelBootInfo, gd: *GraphicsDev) void {
    // const log = std.log.scoped(.kmain_gfx);
    gd.init(boot_data);
    // The framebuffer starts as whatever garbage the firmware/bootloader
    // left in it, not the theme's background color -- clear it first so
    // the logo is drawn onto a clean backdrop instead of leftover memory
    // contents.
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
    // Implementation-specific driver support initialization goes here
}

/// STUB: intended eventual call site for loading a firmware runtime driver
/// (e.g. `src/drivers/uefi/root.zig`) once `boot_data.fw_runtime_ptr` is
/// present -- see `FirmwareRuntimeData` in `src/common/boot_info.zig` for
/// why that field is a raw, opaque, firmware-native pointer rather than a
/// kernel-callable capability struct, and `src/drivers/uefi/root.zig` for
/// why loading it is deferred until a real (dynamic, not `arch`-gated)
/// driver-loading mechanism exists. Not implemented: this only checks
/// presence today. Must never grow an `if (builtin.cpu.arch == .x86_64)`
/// check or similar -- UEFI isn't x86_64-specific (aarch64 has real UEFI
/// too, see `src/bootloader/rpi/main.zig`), so which driver(s) get linked
/// in has to be its own axis, independent of `arch.zig`'s CPU-architecture
/// dispatch.
///
/// This is allowed to fail/no-op silently (no panic) -- every capability a
/// firmware runtime driver would provide is optional and rare (see the
/// reset/shutdown design discussion: ACPI's FADT reset register, PSCI, and
/// direct hardware access cover the common, load-bearing cases without
/// this at all).
fn initFwDriver(boot_data: *KernelBootInfo) void {
    const log = std.log.scoped(.kmain_fw);
    log.debug("initialize firmware driver", .{});
    if (boot_data.fw_runtime_ptr) |ptrs| {
        // Load the firmware driver using the provided pointers
        // Implementation-specific details go here
        _ = ptrs; // suppress unused variable warning
    }
}

/// Breaking down/parsing the raw hardware description (ACPI table
/// walking today; devicetree parsing eventually) is firmware-format
/// -specific but *not* CPU-architecture-specific -- ACPI's table
/// formats don't change based on which CPU is reading them (some
/// arm64 servers use ACPI too) -- so that parsing happens here, in
/// the shared body, rather than inside `arch.platform.init`. What
/// *is* architecture-specific is what to do with the parsed result
/// (e.g. interpreting MADT's I/O APIC entries only makes sense on
/// x86 -- ARM's MADT variant has GIC entries instead); that part is
/// left to `arch.platform.init` and the drivers underneath it
/// (`ioapic.zig` reads `hw_acpi.madt_ptr` directly once this has
/// run).
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

    // print it to uart as well for testing purposes
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
