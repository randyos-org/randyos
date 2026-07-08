//! The "sysroot": a staging directory the bootloader/kernel binaries and any
//! extra boot-time files (OVMF, etc. -- see qemu.zig) are copied into, then
//! installed to `zig-out/systemroot/`. This is also what `zig build run`
//! attaches to QEMU as the emulated FAT boot drive.

const std = @import("std");
const log = std.log.scoped(.build_sysroot);
const Build = std.Build;
const Step = Build.Step;
const WriteFile = Step.WriteFile;
const InstallDir = Step.InstallDir;

pub const Sysroot = struct {
    build: *WriteFile,
    install: *InstallDir,
};

pub fn addSysroot(b: *Build) Sysroot {
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
