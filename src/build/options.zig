const std = @import("std");
const log = std.log.scoped(.build_opts);
const Build = std.Build;
const Options = Build.Step.Options;

const LoggerScpIgn: type = []const []const u8;

pub fn addOptions(
    b: *Build,
) *Options {
    // Default set of scopes to ignore in the logger. -Dno-log-scope adds a
    // scope to the ignore list on top of this default and may be given
    // multiple times (e.g. -Dno-log-scope=arch_paging -Dno-log-scope=acpi_madt).
    // Passing it with no value (-Dno-log-scope=) clears the list, including
    // the defaults. -Dlog-scope removes a scope from the ignore list,
    // whitelisting it back out of the defaults or a -Dno-log-scope, and may
    // likewise be given multiple times.
    const default_no_log_scopes: LoggerScpIgn = &.{
        "arch_paging",
        "kp_alloc",
        "acpi",
        "arch_lapic",
        "arch_ioapic",
        "term_fbcon",
    };
    const no_log_scope_args = b.option(
        LoggerScpIgn,
        "no-log-scope",
        "Add a scope to ignore in the logger, on top of the default list (repeatable; pass with no value to clear the list, including defaults)",
    ) orelse &.{};
    const log_scope_args = b.option(
        LoggerScpIgn,
        "log-scope",
        "Remove a scope from the ignored-scope list, whitelisting it out of the defaults or -Dno-log-scope (repeatable)",
    ) orelse &.{};

    const reset_no_log_scopes = for (no_log_scope_args) |scope| {
        if (scope.len == 0) break true;
    } else false;

    var no_log_scopes = std.array_list.Managed([]const u8).init(b.allocator);
    if (!reset_no_log_scopes) no_log_scopes.appendSlice(default_no_log_scopes) catch @panic("OOM");
    for (no_log_scope_args) |scope| {
        if (scope.len == 0) continue;
        no_log_scopes.append(scope) catch @panic("OOM");
    }
    for (log_scope_args) |scope| {
        var i: usize = 0;
        while (i < no_log_scopes.items.len) {
            if (std.mem.eql(u8, no_log_scopes.items[i], scope)) {
                _ = no_log_scopes.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }
    const logger_scopes_ignore: LoggerScpIgn = no_log_scopes.items;
    // const use_llvm: bool = b.option(bool, "use-llvm", "Use the LLVM backend for code generation (instead of the in-house solution)") orelse true;
    // const use_lld: bool = b.option(bool, "use-lld", "Use the LLD Linker for linking (instead of the in-house solution)") orelse true;
    // const debug_scheduler: bool = b.option(bool, "debug-scheduler", "Print out scheduler debug information") orelse false;
    const run_demos: bool = b.option(bool, "run-demos", "Run kernel demos") orelse false;

    // Which `HardwareDescription` backend(s) (see src/common/boot_info.zig)
    // get compiled into the kernel at all -- independent of `builtin.cpu.arch`.
    // ACPI is not a CPU-ISA guarantee (see the ACPI/IOAPIC design discussion),
    // it's a platform/firmware convention that happens to be universal on
    // real PC-class x86_64 hardware -- so this is a real, separate axis from
    // architecture selection, not something that should be implicitly
    // decided by which arch you're building for. Defaults match what the
    // one real target (x86_64 PC/Mac) actually needs today: ACPI, no
    // devicetree. `src/kernel/arch/x86_64/platform.zig` turns `-Dacpi=false`
    // into a `@compileError` (no alternative hardware-description backend is
    // implemented for x86_64 yet) rather than a silent no-op or a runtime
    // failure. `-Ddevicetree` is currently inert (no kernel-side devicetree
    // consumer exists yet, see src/kernel/hw/dtb/) but threaded through now
    // so a future devicetree-based bootloader/consumer has a real switch to
    // land on instead of another hardcoded assumption.
    const has_acpi: bool = b.option(bool, "acpi", "Compile in ACPI hardware-description support") orelse true;
    const has_devicetree: bool = b.option(bool, "devicetree", "Compile in devicetree hardware-description support") orelse false;

    // options module
    const options = b.addOptions();
    options.addOption(LoggerScpIgn, "logger_scopes_ignore", logger_scopes_ignore);
    options.addOption(bool, "has_acpi", has_acpi);
    options.addOption(bool, "has_devicetree", has_devicetree);
    options.addOption(bool, "run_demos", run_demos);
    // options.addOption(bool, "debug_scheduler", debug_scheduler);

    return options;
}
