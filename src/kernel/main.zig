const std = @import("std");
const builtin = @import("builtin");

// common lib shared with bootloader
const common = @import("common");
pub const build_options = common.build_options;
pub const boot_info = common.boot_info;
pub const pages = common.pages;
pub const logging = common.logging;
pub const Terminal = common.Terminal;
pub const ansi = common.ansi;
pub const sgr = ansi.SgrCode;

// copied/updated from Loup OS
pub const acpi = @import("acpi.zig");
pub const arch = @import("arch.zig");
pub const memory = @import("memory.zig");

// (re-)written for this kernel
const debug = @import("debug.zig");
pub const kassert = debug.kassert;
pub const kpanic = debug.kpanic;
const uart = @import("terminal/uart.zig");
const FBCon = @import("terminal/FBCon.zig");

// new custom modules
pub const GraphicsDev = @import("graphics/Device.zig");
const drawLogo = @import("graphics/logo/draw.zig").drawLogo;
const time = @import("time.zig");

// The constants here are defined in the kernel linker script
pub extern const __kernel_start: u8;
pub extern const __kernel_end: u8;
pub extern const __trap_handler_start: u8;
pub extern const __trap_handler_end: u8;
pub extern const __text_start: u8;
pub extern const __text_end: u8;

pub extern const __stack_bottom: u8;
pub extern const __stack_top: u8;
pub extern const __trap_stack_bottom: u8;
pub extern const __trap_stack_top: u8;
pub extern var __trap_data: extern struct {};

pub extern const __debug_info_start: u8;
pub extern const __debug_info_end: u8;
pub extern const __debug_abbrev_start: u8;
pub extern const __debug_abbrev_end: u8;
pub extern const __debug_str_start: u8;
pub extern const __debug_str_end: u8;
pub extern const __debug_line_start: u8;
pub extern const __debug_line_end: u8;
pub extern const __debug_ranges_start: u8;
pub extern const __debug_ranges_end: u8;

/// Kernel Boot Info by UEFI
pub extern const __kernel_boot_info: *boot_info.KernelBootInfo;

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

/// Kernel Entry Point (setup)
fn _start() linksection(".start") callconv(.naked) noreturn {
    arch.platform.setup();
}

/// Kernel Entry
fn _main() callconv(.c) noreturn {
    // This is in case we want to do any prep before calling kmain
    kmain(__kernel_boot_info);
}

comptime {
    @export(&_start, .{ .name = "_start" });
    @export(&_main, .{ .name = "_main" });
}

/// This is our kernel main function.
/// As you may have seen in the linker script, it says "ENTRY(kmain)". We
/// export this function ("export fn"), so it is a public symbol that can be
/// included by the linker.
export fn kmain(boot_data: *boot_info.KernelBootInfo) noreturn {
    // Everything below is x86_64-specific today (UART port I/O, the TSC,
    // ACPI, and platform.init's IOAPIC params are all x86 concepts, not just
    // the platform-init call), so the other arch stubs gate here rather than
    // pretending to share a portable body they don't actually have yet.
    // `builtin.cpu.arch` is comptime-known, so only the taken branch of this
    // if/else gets semantically analyzed -- the same mechanism arch.zig's
    // own dispatch already relies on -- meaning the x86_64-only references
    // in the true branch don't need to exist for other targets.
    if (builtin.cpu.arch == .x86_64) {
        const log = std.log.scoped(.kmain);

        // Initialize UART terminal
        const uart_term = &uart.uart_term;
        logging.log_term = uart_term;
        uart_term.init(.{});

        // intentionally log before tsc to force -1 timestamp test
        log.info("-------------------------", .{});

        // init clock and set logging clock
        arch.platform.tsc.init();
        logging.get_time = &arch.platform.tsc.getTime;
        time.init(boot_data.runtime_services);

        // welcome messages
        uart_term.cls();
        log.debug("Kernel terminal initialized", .{});
        log.info("Welcome to RandyOS!", .{});
        if (time.now()) |dt| {
            log.info("Current wall time: {}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2} UTC", .{
                dt.year, dt.month.numeric(), dt.day, dt.hour, dt.minute, dt.second,
            });
        }

        // save the kernel size info
        const kernel_byte_size: usize = @intFromPtr(&__kernel_end) - @intFromPtr(&__kernel_start);
        const kernel_page_size: usize = std.math.divCeil(usize, kernel_byte_size, 0x1000) catch unreachable;
        log.debug("kernel_start = 0x{x}, kernel_end = 0x{x}", .{ @as(usize, @intFromPtr(&__kernel_start)), @as(usize, @intFromPtr(&__kernel_end)) });

        // page allocator init and debugging info
        // needed before all other operations, including graphics
        memory.kernel_page_allocator.init(boot_data);
        debug.init(memory.kernel_page_allocator.allocator, boot_data.dwarf_info);

        // initialize graphics early so errors can be displayed to user without uart
        var gd: GraphicsDev = .{};
        var fbcon: FBCon = .{};
        gd.init(boot_data);
        drawLogo(&gd);
        fbcon.init(&gd, false);
        const fbterm = &fbcon.term;
        logging.log_term = fbterm;

        // acpi init before platform to parse MADT addresses needed by platform
        const acpi_info = acpi.init(boot_data) catch {
            kpanic(@src(), "kernel can't continue without ACPI on this platform!\n");
        };

        // platform-specific codes
        arch.platform.init(memory.kernel_page_allocator.allocator, .{
            .ioapic_addr = acpi_info.ioapic_addr,
            .glob_sys_int_base = acpi_info.glob_sys_int_base,
            .kernel_boot_info = boot_data,
            .kernel_page_size = kernel_page_size,
        });

        // demos(&fbcon, uart_term, &gd);

        // Idle loop: drain deferred interrupt work, then halt until the next
        // interrupt. This is the shape a scheduler's idle task will also take
        // (drain pending work, block) -- becomes that task's body directly
        // once one exists.
        while (true) {
            arch.platform.ps2.processPending();
            arch.platform.registers.halt();
        }
    } else {
        @panic("TODO: kmain not yet implemented for this architecture");
    }
}

fn demos(fbcon: *FBCon, uart_term: *Terminal, gd: *GraphicsDev) void {
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
    uart_term.puts( //
        ansi.CSI ++ ansi.SgrCode.fg_indexed ++ ";100" ++ ansi.SGR //
        ++ ansi.CSI ++ ansi.CLS ++ ansi.CSI ++ ansi.HOME //
        ++ ansi.CSI ++ sgr.bold ++ ";" ++ sgr.underline ++ ";" ++ sgr.invert ++ ";" ++ sgr.fg_magenta ++ ansi.SGR //
        ++ "Hello World!\n" //
        ++ ansi.CSI ++ sgr.reset ++ ";" ++ sgr.fg_magenta ++ ansi.SGR //
        ++ "2026 by Randy Eckman\n" //
        ++ ansi.CSI ++ sgr.reset ++ ansi.SGR //
        ++ "Normal text\n" //
    );
    time.sleep(0.5);
    // draw a rectangle
    gd.drawRect(100, 500, 100, 100, .{
        .red = 0xff,
        .green = 0x66,
        .blue = 0x00,
        .reserved = 0x00,
    });

    if (time.now()) |dt| {
        log.info("Current wall time: {}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2} UTC", .{
            dt.year, dt.month.numeric(), dt.day, dt.hour, dt.minute, dt.second,
        });
    }
}

pub const panic = std.debug.FullPanic(debug.panic);
