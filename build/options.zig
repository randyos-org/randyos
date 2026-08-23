const buildroot = @import("__root__.zig");
const rstd = @import("rstd");
const rstdbuild = rstd.buildutils;

const targets = buildroot.targets;
const RandyOSTarget = targets.RandyOSTarget;

const Build = rstdbuild.Build;
const BuildOptions = rstdbuild.BuildOptions;
const MachineTargetInfo = targets.MachineTargetInfo;

/// Scopes noisy enough to want error-only by default -- see
/// `rstdbuild.addLogScopeOptions`'s doc comment for the `-Dno-log-scope`/
/// `-Dlog-scope`/`-Dlog-scope-level` build options this seeds.
const default_log_scope_levels: []const rstdbuild.ScopeLevel = &.{
    .{ .scope = "boot:uefi.__main__.bootloader.preinit", .level = .err },
    .{ .scope = "boot:uefi.graphics", .level = .info },
    .{ .scope = "boot:uefi.loader.image", .level = .info },
    .{ .scope = "rstd:_os.uefi.io.dir", .level = .info },
    .{ .scope = "arch_paging", .level = .err },
    .{ .scope = "kp_alloc", .level = .err },
    .{ .scope = "acpi", .level = .err },
    .{ .scope = "arch_lapic", .level = .err },
    .{ .scope = "arch_ioapic", .level = .err },
    .{ .scope = "term_fbcon", .level = .err },
    .{ .scope = "arch_idt_frame", .level = .err },
};

pub fn addBuildOptions(b: *Build, tgt: RandyOSTarget) !*BuildOptions {
    const build_options = rstdbuild.addBuildOptionsModule(b);
    try rstdbuild.addLogScopeOptions(b, build_options, default_log_scope_levels);

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
