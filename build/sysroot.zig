//! The "sysroot": a staging directory holding exactly the ESP contents (the
//! bootloader/kernel binaries and other boot-time files), installed to
//! `zig-out/sysroot/`. `zig build run` attaches it to QEMU as the emulated FAT
//! boot drive, and `zig build image` packs it into the USB image.

const buildroot = @import("__root__.zig");
const rstd = @import("rstd");
const rstdbuild = rstd.buildutils;

pub const SysrootDirs = struct {
    build: *rstdbuild.BuildDir,
    install: *rstdbuild.InstallDir,
};

pub fn addSysrootDirs(b: *rstdbuild.Build) SysrootDirs {
    var sysroot_build = rstdbuild.addBuildDir(b);
    var sysroot_install = b.addInstallDirectory(.{
        .source_dir = sysroot_build.getDirectory(),
        .install_dir = .{ .custom = "sysroot" },
        .install_subdir = "",
    });
    b.getInstallStep().dependOn(&sysroot_install.step);
    return .{
        .build = sysroot_build,
        .install = sysroot_install,
    };
}
