const std = @import("std");
const Build = std.Build;
const Target = std.Target;
const Step = Build.Step;
const Run = Step.Run;
const OptimizeMode = std.builtin.OptimizeMode;
const WriteFile = Step.WriteFile;
const InstallDir = Step.InstallDir;
const Module = Build.Module;

const LoggerScpIgn: type = []const []const u8;
const Sysroot = struct {
    build: *WriteFile,
    install: *InstallDir,
};
const QemuCmds = struct {
    run: *Run,
    debug: *Run,
};

/// Install `compile`'s emitted docs under `zig-out/docs/<name>/` and make
/// `target_step` depend on that install.
fn addModuleDocsTo(b: *Build, target_step: *Step, compile: *Step.Compile, name: []const u8) void {
    const install = b.addInstallDirectory(.{
        .source_dir = compile.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = b.fmt("docs/{s}", .{name}),
    });
    target_step.dependOn(&install.step);
}

/// Shared handle each `addX` function attaches its own generated docs to,
/// rather than a single function reaching into already-built `*Step.Compile`
/// handles after the fact.
const Docs = struct {
    step: *Step,

    /// Install `compile`'s emitted docs under `zig-out/docs/<name>/` and
    /// make the shared "docs" step (part of the default install step) depend
    /// on that install. Only for things that are always expected to build
    /// (common/abi/bootloader/kernel) -- the roadmap arch stubs use
    /// `addModuleDocsTo` directly against their own per-arch step instead,
    /// so a stub that doesn't build yet can't break the default build.
    fn addModuleDocs(docs: Docs, b: *Build, compile: *Step.Compile, name: []const u8) void {
        addModuleDocsTo(b, docs.step, compile, name);
    }
};

fn addCommon(
    b: *Build,
    optimize: OptimizeMode,
    docs: Docs,
) *Module {
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
    const debug_scheduler: bool = b.option(bool, "debug-scheduler", "Print out scheduler debug information") orelse false;

    // options module
    const options = b.addOptions();
    options.addOption(LoggerScpIgn, "logger_scopes_ignore", logger_scopes_ignore);
    options.addOption(bool, "debug_scheduler", debug_scheduler);

    const common_mod = b.createModule(.{
        .root_source_file = b.path("src/common/root.zig"),
        // .target = b.resolveTargetQuery(bootloader_query),
        .optimize = optimize,
    });
    common_mod.addOptions("build_options", options);

    // Same "docs-only, host-targeted" trick as `abi` below -- `common_mod`
    // has no fixed target of its own (only ever imported into other
    // target-specific modules), so it needs its own compile object to run
    // `getEmittedDocs()` against.
    const common_docs_mod = b.createModule(.{
        .root_source_file = b.path("src/common/root.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    common_docs_mod.addOptions("build_options", options);
    const common_docs_obj = b.addObject(.{
        .name = "common",
        .root_module = common_docs_mod,
    });
    docs.addModuleDocs(b, common_docs_obj, "common");

    return common_mod;
}

/// The "abi" module: Linux syscall/ABI compatibility reference data (see
/// src/abi/README.md). Kept separate from "common" -- it's reference data
/// about an *external* (Linux's) contract, not code shared between the
/// bootloader and kernel.
fn addAbi(
    b: *Build,
    optimize: OptimizeMode,
    docs: Docs,
) *Module {
    const abi_mod = b.createModule(.{
        .root_source_file = b.path("src/abi/root.zig"),
        .optimize = optimize,
    });

    // `abi_mod` above has no fixed target (it's only ever imported into
    // other target-specific modules), so it has nothing of its own to run
    // `getEmittedDocs()` against. Build a docs-only object targeting the
    // host natively just so `zig build docs` has something to extract
    // abi's own doc comments from. This only affects which single
    // architecture's `syscall` data shows up in the docs, not anything
    // that ships.
    const abi_docs_mod = b.createModule(.{
        .root_source_file = b.path("src/abi/root.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    const abi_docs_obj = b.addObject(.{
        .name = "abi",
        .root_module = abi_docs_mod,
    });
    docs.addModuleDocs(b, abi_docs_obj, "abi");

    return abi_mod;
}

fn addBootldr(
    b: *Build,
    sysroot: *WriteFile,
    optimize: OptimizeMode,
    common_mod: *Module,
    abi_mod: *Module,
    docs: Docs,
) *Step.Compile {
    // This is the bootloader target query. We need this special target because
    // bootloaders have a different executable format (and so on) than normal
    // native executables.
    const bootloader_query = Target.Query{
        .cpu_arch = .x86_64,
        // The OS we will run the executable on is UEFI (the Unified Extensible
        // Firmware Interface)
        .os_tag = .uefi,
        // The Application Binary Interface, used for calling functions, will
        // be the MSVC ABI, the default for COFF (.exe / .efi) executables.
        .abi = .msvc,
        // The output format will be COFF. This is used for Windows executables
        // and for EFI executables. We will need the latter for our bootloader.
        .ofmt = .coff,
    };

    const bootloader_mod = b.createModule(.{
        .root_source_file = b.path("src/bootloader/root.zig"),
        .target = b.resolveTargetQuery(bootloader_query),
        .optimize = optimize,
    });
    bootloader_mod.addImport("common", common_mod);
    bootloader_mod.addImport("abi", abi_mod);

    const bootloader_exe = b.addExecutable(.{
        // It will be named "bootx64", because that's the regular path that can
        // be found by UEFI.
        .name = "bootx64",
        .root_module = bootloader_mod,
    });
    b.installArtifact(bootloader_exe);
    _ = sysroot.addCopyFile(
        bootloader_exe.getEmittedBin(),
        b.pathJoin(&.{
            "efi",
            "boot",
            bootloader_exe.out_filename,
        }),
    );
    docs.addModuleDocs(b, bootloader_exe, "bootloader");
    return bootloader_exe;
}

fn addKernel(
    b: *Build,
    sysroot: *WriteFile,
    optimize: OptimizeMode,
    common_mod: *Module,
    abi_mod: *Module,
    docs: Docs,
) *Step.Compile {
    // This is the kernel target query. This one is also an x86_64 executable,
    // but freestanding. Normal executables communicate with an operating
    // system to do things. The kernel is one of the core parts for an
    // operating system, so it hasn't any operating system abstractions. It
    // must provide everything by itself.
    const kernel_query = Target.Query{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        // Also no ABI, because the ABI is only important for things like entry
        // functions.
        .abi = .none,
        .ofmt = .elf,
    };

    const kernel_mod = b.createModule(.{
        .root_source_file = b.path("src/kernel/main.zig"),
        .target = b.resolveTargetQuery(kernel_query),
        .code_model = .kernel,
        .optimize = optimize,
    });
    kernel_mod.addImport("common", common_mod);
    kernel_mod.addImport("abi", abi_mod);

    const kernel_exe = b.addExecutable(.{
        // We name it "kernel.elf" since that is what the bootloader expects.
        .name = "kernel.elf",
        .root_module = kernel_mod,
        // For now, we want to use LLVM and its linker LLD to compile the
        // kernel, as the self-hosted linker can't work with so-called "Linker
        // Scripts" (you'll learn about them a few lines below).
        .use_lld = true,
        .use_llvm = true,
    });
    // Using this, we disable setting the entry function of the kernel
    // automatically.
    kernel_exe.entry = .disabled;
    // Here, we set the linker script path. For normal executables (and UEFI
    // ones), such linker scripts are provided by the linker. However, this is
    // OUR kernel, so WE want to specify what we want to get in the kernel.
    const arch = "x86_64";
    kernel_exe.setLinkerScript(b.path(b.fmt("src/kernel/arch/{s}/kernel.ld", .{arch})));
    b.installArtifact(kernel_exe);
    _ = sysroot.addCopyFile(
        kernel_exe.getEmittedBin(),
        kernel_exe.out_filename,
    );
    docs.addModuleDocs(b, kernel_exe, "kernel");
    return kernel_exe;
}

fn addQemuCmds(b: *Build) QemuCmds {
    const base_cmd = &.{"qemu-system-x86_64"};
    const base_args = &.{
        "-s", // GDB connection available at localhost:1234 via TCP.

        // standard output mapped to COM1
        "-serial",
        "mon:stdio",

        // GTK-based window for display
        "-display",
        "gtk",

        // add socat monitor socket
        "-monitor",
        "unix:qemu-monitor-socket,server,nowait",

        // A triple fault normally makes QEMU silently reset the VM and
        // re-run firmware/bootloader/kernel from scratch, which looks like
        // an infinite bootloop. Halt instead so the failure is visible and
        // the machine state can be inspected.
        "-no-reboot",
        "-no-shutdown",
    };
    const cmds = QemuCmds{
        .run = b.addSystemCommand(base_cmd),
        .debug = b.addSystemCommand(base_cmd),
    };
    cmds.run.addArgs(base_args);
    cmds.debug.addArgs(base_args);
    cmds.debug.addArg("-S"); // wait for GDB connection

    const run_step = b.step("run", "Run the kernel via QEMU");
    run_step.dependOn(&cmds.run.step);

    const debug_step = b.step("debug", "Run the kernel via QEMU, wait for GDB connection");
    debug_step.dependOn(&cmds.debug.step);

    return cmds;
}

fn addOvmf(b: *Build, sysroot: *WriteFile, qemu_cmds: QemuCmds) void {
    const ovmf_code = b.option(
        Build.LazyPath,
        "ovmf-code",
        "The OVMF_CODE file to use",
    );
    const ovmf_vars = b.option(
        Build.LazyPath,
        "ovmf-vars",
        "The OVMF_VARS file to use",
    );
    if (ovmf_code) |ocp| {
        // note that the destination is just a name, nothing special.
        const oc = sysroot.addCopyFile(
            ocp,
            "ovmf_code.fd",
        );
        if (ovmf_vars) |ovp| {
            const ov = sysroot.addCopyFile(
                ovp,
                "ovmf_vars.fd",
            );

            inline for (comptime std.meta.fieldNames(QemuCmds)) |field_name| {
                // add OVMF_CODE file first as ro
                const cmd = @field(qemu_cmds, field_name);
                cmd.addArg("-drive");
                cmd.addPrefixedFileArg(
                    "format=raw,if=pflash,readonly=on,file=",
                    oc,
                );

                // then add OVMF_VARS file
                cmd.addArg("-drive");
                cmd.addPrefixedFileArg("format=raw,if=pflash,file=", ov);
            }
        } else {
            // Otherwise, add what is expected to be the combined OVMF file.
            inline for (comptime std.meta.fieldNames(QemuCmds)) |field_name| {
                const cmd = @field(qemu_cmds, field_name);
                cmd.addArg("-drive");
                cmd.addPrefixedFileArg("format=raw,if=pflash,file=", ocp);
            }
        }
    } else {
        //  use the default from the repo
        const ocp = b.path("OVMF.fd");
        const oc = sysroot.addCopyFile(
            ocp,
            "ovmf.fd",
        );
        inline for (comptime std.meta.fieldNames(QemuCmds)) |field_name| {
            const cmd = @field(qemu_cmds, field_name);
            cmd.addArg("-drive");
            cmd.addPrefixedFileArg(
                "format=raw,if=pflash,file=",
                oc,
            );
        }
    }
}

// fn addQemuSysroot(sysroot_install: *InstallDir, qemu_cmds: QemuCmds) void {
//     inline for (comptime std.meta.fieldNames(QemuCmds)) |field_name| {
//         const cmd = @field(qemu_cmds, field_name);
//         cmd.addArg("-drive");
//         cmd.addPrefixedDirectoryArg("format=raw,index=3,media=disk,file=fat:rw:", .{
//             .relative = .{
//                 .base = .install_prefix,
//                 .sub_path = "systemroot",
//             },
//         });
//         cmd.step.dependOn(&sysroot_install.step);
//     }
// }

fn addQemuSysroot(b: *Build, sysroot_install: *InstallDir, qemu_cmds: QemuCmds) void {
    const sysroot_path = b.getInstallPath(
        sysroot_install.options.install_dir,
        sysroot_install.options.install_subdir,
    );
    inline for (comptime std.meta.fieldNames(QemuCmds)) |field_name| {
        const cmd = @field(qemu_cmds, field_name);
        cmd.addArg("-drive");
        cmd.addPrefixedDirectoryArg(
            "format=raw,index=3,media=disk,file=fat:rw:",
            .{ .cwd_relative = sysroot_path },
        );
        cmd.step.dependOn(&sysroot_install.step);
    }
}

fn addMonitorCmd(b: *Build) void {
    const monitor = b.addSystemCommand(&.{"socat"});
    monitor.addArgs(&.{
        "-,echo=0,icanon=0",
        "unix-connect:qemu-monitor-socket",
    });
    const monitor_step = b.step("monitor", "Launch socat to interact with qemu-monitor");
    monitor_step.dependOn(&monitor.step);
}

fn addDocs(b: *Build) Docs {
    const docs_step = b.step("docs", "Generate and install API documentation");
    // Also run as part of the default `zig build`/`zig build install`, not
    // just when `zig build docs` is requested explicitly.
    b.getInstallStep().dependOn(docs_step);

    const docs_port = b.option(u16, "docs-port", "Port for `zig build run-docs` to serve documentation on") orelse 3000;
    const run_docs_step = b.step("run-docs", "Serve the generated documentation locally");
    const server_cmd = b.addSystemCommand(&.{
        "python", "-m", "http.server", b.fmt("{d}", .{docs_port}), "-b", "127.0.0.1", "-d", "zig-out/docs/",
    });
    server_cmd.step.dependOn(docs_step);
    run_docs_step.dependOn(&server_cmd.step);

    return .{ .step = docs_step };
}

fn addSysroot(b: *Build) Sysroot {
    const sysroot_build = b.addWriteFiles();
    const sysroot_install = b.addInstallDirectory(.{
        .source_dir = sysroot_build.getDirectory(),
        .install_dir = .{ .custom = "systemroot" },
        .install_subdir = "",
    });
    b.getInstallStep().dependOn(&sysroot_install.step);
    return .{
        .build = sysroot_build,
        .install = sysroot_install,
    };
}

pub fn build(b: *Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const sysroot = addSysroot(b);
    const qemu_cmds = addQemuCmds(b);
    addOvmf(b, sysroot.build, qemu_cmds);
    addQemuSysroot(b, sysroot.install, qemu_cmds);
    addMonitorCmd(b);

    const docs = addDocs(b);
    const common_mod = addCommon(b, optimize, docs);
    const abi_mod = addAbi(b, optimize, docs);
    _ = addBootldr(b, sysroot.build, optimize, common_mod, abi_mod, docs);
    _ = addKernel(b, sysroot.build, optimize, common_mod, abi_mod, docs);

    // Roadmap stubs -- see ArchStub's doc comment. These still don't touch
    // the default install step, the sysroot, or the QEMU pipeline above, but
    // each one's own step (`kernel-<name>`/`boot-<name>`) also builds and
    // installs its docs, so a stub that doesn't compile yet can't break the
    // shared "docs" step (part of the default install step above).
    for (arch_stubs) |stub| {
        addStubKernel(b, optimize, common_mod, abi_mod, stub);
        addStubBootloader(b, optimize, common_mod, abi_mod, stub);
    }
}

/// Roadmap descriptor for a not-yet-implemented arch stub. Unlike x86_64
/// (wired into the default install step, the sysroot, and the QEMU
/// pipeline), these are pure compile-and-link roadmap markers: `zig build
/// kernel-<name>` (and `boot-<name>`, where applicable) just proves the stub
/// arch module + linker script actually build, without touching the working
/// x86_64 boot flow at all.
const ArchStub = struct {
    /// Used in step names (e.g. "aarch64" -> "kernel-aarch64") and to locate
    /// `src/kernel/arch/<name>/kernel.ld`.
    name: []const u8,
    kernel_query: Target.Query,
    kernel_code_model: std.builtin.CodeModel = .default,
    /// `null` means this arch has no bootloader step yet -- either because
    /// there's no UEFI firmware worth targeting at all (powerpc: classic
    /// Macs use Open Firmware, see src/bootloader/ofw/), or because the
    /// real target board's UEFI firmware doesn't actually help this
    /// particular OS (arm: Pi 3 does have aarch64 UEFI via pftf, but that
    /// firmware runs the board in 64-bit mode and doesn't boot a 32-bit OS;
    /// aarch64's Raspberry Pi 5 case is similar but for a different reason
    /// -- its UEFI effort was archived entirely. Both go through
    /// src/bootloader/rpi/ instead; Pi 3/4 running aarch64 do have real
    /// UEFI, hence aarch64 itself still has a `bootloader_query` below).
    bootloader_query: ?Target.Query = null,
};

const arch_stubs = [_]ArchStub{
    .{
        .name = "aarch64",
        .kernel_query = .{ .cpu_arch = .aarch64, .os_tag = .freestanding, .abi = .none, .ofmt = .elf },
        // Real UEFI firmware -- correct for Raspberry Pi 3/4 (pftf). Does
        // NOT apply to Raspberry Pi 5 (community UEFI effort archived Feb
        // 2025 -- see src/bootloader/rpi/) or Apple Silicon Macs (no native
        // UEFI at all -- see src/bootloader/asahi/). All three target
        // machines share this same kernel-side stub since the CPU
        // instruction set is identical across them.
        .bootloader_query = .{ .cpu_arch = .aarch64, .os_tag = .uefi, .abi = .msvc, .ofmt = .coff },
    },
    .{
        .name = "arm",
        .kernel_query = .{ .cpu_arch = .arm, .os_tag = .freestanding, .abi = .eabi, .ofmt = .elf },
        // Real target: Raspberry Pi 3 running a 32-bit OS. Its aarch64 UEFI
        // firmware (pftf) boots the board in 64-bit mode only -- no path
        // from there to a 32-bit OS -- so this goes through
        // src/bootloader/rpi/ same as Pi 5, not a UEFI bootloader query.
        .bootloader_query = null,
    },
    .{
        .name = "powerpc",
        .kernel_query = .{ .cpu_arch = .powerpc, .os_tag = .freestanding, .abi = .eabi, .ofmt = .elf },
        .bootloader_query = null,
    },
};

/// Builds (but does not install into the default step, sysroot, or QEMU
/// pipeline) a stub kernel for one `ArchStub`. Every real function in it
/// panics -- this only proves the arch module + linker script link.
fn addStubKernel(b: *Build, optimize: OptimizeMode, common_mod: *Module, abi_mod: *Module, stub: ArchStub) void {
    const kernel_mod = b.createModule(.{
        .root_source_file = b.path("src/kernel/main.zig"),
        .target = b.resolveTargetQuery(stub.kernel_query),
        .code_model = stub.kernel_code_model,
        .optimize = optimize,
    });
    kernel_mod.addImport("common", common_mod);
    kernel_mod.addImport("abi", abi_mod);

    const kernel_exe = b.addExecutable(.{
        .name = b.fmt("kernel-{s}.elf", .{stub.name}),
        .root_module = kernel_mod,
        .use_lld = true,
        .use_llvm = true,
    });
    kernel_exe.entry = .disabled;
    kernel_exe.setLinkerScript(b.path(b.fmt("src/kernel/arch/{s}/kernel.ld", .{stub.name})));

    const install = b.addInstallArtifact(kernel_exe, .{});
    const step = b.step(
        b.fmt("kernel-{s}", .{stub.name}),
        b.fmt("Build the (stub, not bootable) {s} kernel", .{stub.name}),
    );
    step.dependOn(&install.step);
    // Docs hang off this stub's own step, not the shared "docs" step (part
    // of the default install step) -- so a stub that doesn't compile yet
    // can't break the real build.
    addModuleDocsTo(b, step, kernel_exe, b.fmt("kernel-{s}", .{stub.name}));
}

/// Builds (but does not install into the default step, sysroot, or QEMU
/// pipeline) a stub UEFI bootloader for one `ArchStub`, if it has a
/// `bootloader_query` at all.
fn addStubBootloader(b: *Build, optimize: OptimizeMode, common_mod: *Module, abi_mod: *Module, stub: ArchStub) void {
    const query = stub.bootloader_query orelse return;
    const bootloader_mod = b.createModule(.{
        .root_source_file = b.path("src/bootloader/root.zig"),
        .target = b.resolveTargetQuery(query),
        .optimize = optimize,
    });
    bootloader_mod.addImport("common", common_mod);
    bootloader_mod.addImport("abi", abi_mod);

    const bootloader_exe = b.addExecutable(.{
        .name = b.fmt("boot-{s}.efi", .{stub.name}),
        .root_module = bootloader_mod,
    });

    const install = b.addInstallArtifact(bootloader_exe, .{});
    const step = b.step(
        b.fmt("boot-{s}", .{stub.name}),
        b.fmt("Build the (stub, not wired to any boot flow) {s} UEFI bootloader", .{stub.name}),
    );
    step.dependOn(&install.step);
    // Docs hang off this stub's own step, not the shared "docs" step (part
    // of the default install step) -- so a stub that doesn't compile yet
    // can't break the real build.
    addModuleDocsTo(b, step, bootloader_exe, b.fmt("boot-{s}", .{stub.name}));
}
