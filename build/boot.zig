const std = @import("std");
const buildroot = @import("__root__.zig");
const rstd = @import("rstd");
const rstdbuild = rstd.buildutils;

const Build = rstdbuild.Build;
const RunStep = rstdbuild.RunStep;
const ResolvedTarget = rstdbuild.ResolvedTarget;
const Module = rstdbuild.Module;
const OptimizeMode = rstdbuild.OptimizeMode;
const BuildOptions = rstdbuild.BuildOptions;
const Docs = rstdbuild.Docs;
const CompileStep = rstdbuild.CompileStep;

const SysrootDirs = buildroot.sysroot.SysrootDirs;
const Signer = buildroot.usb.Signer;

pub fn addBootldr(
    b: *Build,
    optimize: OptimizeMode,
    target: ResolvedTarget,
    rstdlib: ?*Module,
    sysroot: SysrootDirs,
    signer: ?Signer,
    docs: Docs,
) *CompileStep {
    const bootloader_mod = b.createModule(.{
        .root_source_file = b.path("src/boot/__root__.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (rstdlib) |rstdlib_mod| {
        bootloader_mod.addImport("rstd", rstdlib_mod);
    }

    // For the SBAT section shim requires.
    const boot_options = b.addOptions();
    boot_options.addOption([]const u8, "version", buildroot.zon.version);
    bootloader_mod.addOptions("boot_options", boot_options);

    const bootloader_exe = b.addExecutable(.{
        // Name expected by UEFI.
        .name = "bootx64",
        .root_module = bootloader_mod,
    });
    b.installArtifact(bootloader_exe);
    const bin = bootloader_exe.getEmittedBin();
    if (signer) |s| s.installLoader(b, sysroot, bin) else {
        _ = sysroot.build.addCopyFile(bin, b.pathJoin(&.{ "efi", "boot", bootloader_exe.out_filename }));
    }
    docs.addCompileStepDocs(b, bootloader_exe, "bootloader");
    return bootloader_exe;
}
