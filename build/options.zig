const std = @import("std");
const buildroot = @import("__root__.zig");
const rstd = @import("rstd");
const rstdbuild = rstd.buildutils;

const targets = buildroot.targets;
const RandyOSTarget = targets.RandyOSTarget;

const Build = rstdbuild.Build;
const BuildOptions = rstdbuild.BuildOptions;
const MachineTargetInfo = targets.MachineTargetInfo;

const LoggerScopeIgnore: type = []const []const u8;

pub fn addLogScopeOptions(b: *Build, build_options: *BuildOptions) void {
    const default_no_log_scopes: LoggerScopeIgnore = &.{
        "arch_paging",
        "kp_alloc",
        "acpi",
        "arch_lapic",
        "arch_ioapic",
        "term_fbcon",
        "arch_idt_frame",
    };
    const no_log_scope_args = b.option(
        LoggerScopeIgnore,
        "no-log-scope",
        "Add a scope to ignore in the logger, on top of the default list (repeatable; pass with no value to clear the list, including defaults)",
    ) orelse &.{};
    const log_scope_args = b.option(
        LoggerScopeIgnore,
        "log-scope",
        "Remove a scope from the ignored-scope list, whitelisting it out of the defaults or -Dno-log-scope (repeatable)",
    ) orelse &.{};

    const reset_no_log_scopes = for (no_log_scope_args) |scope| {
        if (scope.len == 0) break true;
    } else false;

    var no_log_scopes: std.ArrayList([]const u8) = .empty;
    if (!reset_no_log_scopes) try no_log_scopes.appendSlice(b.allocator, default_no_log_scopes);
    for (no_log_scope_args) |scope| {
        if (scope.len == 0) continue;
        try no_log_scopes.append(b.allocator, scope);
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
    const logger_scopes_ignore: LoggerScopeIgnore = no_log_scopes.items;
    build_options.addOption(LoggerScopeIgnore, "logger_scopes_ignore", logger_scopes_ignore);
}

pub fn addBuildOptions(b: *Build, tgt: RandyOSTarget) *BuildOptions {
    const build_options = rstdbuild.addBuildOptionsModule(b);
    addLogScopeOptions(b, build_options);

    // const debug_scheduler: bool = b.option(bool, "debug-scheduler", "Print out scheduler debug information") orelse false;
    // options.addOption(bool, "debug_scheduler", debug_scheduler);
    const run_demos: bool = b.option(bool, "run-demos", "Run kernel demos") orelse false;
    build_options.addOption(bool, "run_demos", run_demos);
    const has_acpi: bool = b.option(bool, "acpi", "Compile in ACPI hardware-description support") orelse (tgt.hardware_interface == .acpi);
    build_options.addOption(bool, "has_acpi", has_acpi);
    const has_devicetree: bool = b.option(bool, "devicetree", "Compile in devicetree hardware-description support") orelse (tgt.hardware_interface == .dtb);
    build_options.addOption(bool, "has_devicetree", has_devicetree);

    return build_options;
}
