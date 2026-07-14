//! The "sysroot": a staging directory the bootloader/kernel binaries and any
//! extra boot-time files (OVMF, etc. -- see qemu.zig) are copied into, then
//! installed to `zig-out/systemroot/`. This is also what `zig build run`
//! attaches to QEMU as the emulated FAT boot drive.

const buildroot = @import("__root__.zig");
const rstdbuild = buildroot.rstd.build;

pub const SysrootDirs = struct {
    build: *rstdbuild.BuildDir,
    install: *rstdbuild.InstallDir,
};

pub fn addSysrootDirs(b: *rstdbuild.Build) SysrootDirs {
    var sysroot_build = rstdbuild.addBuildDir(b);
    var sysroot_install = b.addInstallDirectory(.{
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
