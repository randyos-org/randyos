const std = @import("std");
const buildroot = @import("__root__.zig");
const rstdbuild = buildroot.rstd.buildutils;

const Build = rstdbuild.Build;
const RunStep = rstdbuild.RunStep;
const ResolvedTarget = rstdbuild.ResolvedTarget;
const Module = rstdbuild.Module;
const OptimizeMode = rstdbuild.OptimizeMode;
const BuildOptions = rstdbuild.BuildOptions;
const Docs = rstdbuild.Docs;
const CompileStep = rstdbuild.CompileStep;

const SysrootDirs = buildroot.sysroot.SysrootDirs;

pub fn addBootldr(
    b: *Build,
    optimize: OptimizeMode,
    target: ResolvedTarget,
    rstdlib: *Module,
    sysroot: SysrootDirs,
    docs: Docs,
) *CompileStep {
    const bootloader_mod = b.createModule(.{
        .root_source_file = b.path("src/boot/__root__.zig"),
        .target = target,
        .optimize = optimize,
    });
    bootloader_mod.addImport("rstd", rstdlib);

    const bootloader_exe = b.addExecutable(.{
        // It will be named "bootx64", because that's the regular path that can
        // be found by UEFI.
        .name = "bootx64",
        .root_module = bootloader_mod,
    });
    b.installArtifact(bootloader_exe);
    _ = sysroot.build.addCopyFile(
        bootloader_exe.getEmittedBin(),
        b.pathJoin(&.{
            "efi",
            "boot",
            bootloader_exe.out_filename,
        }),
    );
    docs.addCompileStepDocs(b, bootloader_exe, "bootloader");
    return bootloader_exe;
}
