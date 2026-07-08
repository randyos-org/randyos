//! Build steps for the real, working x86_64 PC/Mac targets: the UEFI
//! bootloader and the freestanding kernel. See arch_stubs.zig for the
//! roadmap (compile-only) architectures.

const std = @import("std");
const log = std.log.scoped(.build_exe);
const Build = std.Build;
const Target = std.Target;
const Step = Build.Step;
const WriteFile = Step.WriteFile;
const Module = Build.Module;
const OptimizeMode = std.builtin.OptimizeMode;

const docs_mod = @import("docs.zig");
const Docs = docs_mod.Docs;

pub fn addBootldr(
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

pub fn addKernel(
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
