//! Bootable USB image of the sysroot (GPT + FAT32 ESP), built and burned by
//! the host-side `tools/usbimg` program.

const buildroot = @import("__root__.zig");
const rstd = @import("rstd");
const rstdbuild = rstd.buildutils;
const SysrootDirs = buildroot.sysroot.SysrootDirs;

const Build = rstdbuild.Build;
const LazyPath = rstdbuild.LazyPath;

/// Adds the `image`, `usb-list` and `burn` steps; returns the image.
pub fn addUsb(b: *Build, sysroot: SysrootDirs) LazyPath {
    const tool_mod = b.createModule(.{
        .root_source_file = b.path("tools/usbimg/__main__.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    });
    // Host-configured rstd; win32 resolves through rstd's own dependencies.
    const rstd_dep = b.dependency("rstd", .{ .target = b.graph.host });
    tool_mod.addImport("rstd", rstd_dep.module("rstd"));
    rstdbuild.addWin32ToModIfWinTgt(rstd_dep.builder, b.graph.host, tool_mod);
    const tool = b.addExecutable(.{ .name = "usbimg", .root_module = tool_mod });

    const mkimg = b.addRunArtifact(tool);
    mkimg.addArg("mkimg");
    mkimg.addDirectoryArg(sysroot.build.getDirectory());
    const image = mkimg.addOutputFileArg("randyos.img");
    const install = b.addInstallFile(image, "randyos.img");
    b.step("image", "Build a bootable USB disk image of the sysroot (zig-out/randyos.img)").dependOn(&install.step);

    const list = b.addRunArtifact(tool);
    list.addArg("list");
    list.stdio = .inherit;
    b.step("usb-list", "List disks that `burn` can target").dependOn(&list.step);

    const disk = b.option([]const u8, "usb-disk", "Disk for `burn`: number on Windows (PhysicalDriveN), /dev/sdX on Linux");
    const yes = b.option(bool, "usb-yes", "Skip `burn`'s typed confirmation") orelse false;
    const any_bus = b.option(bool, "usb-any-bus", "Let `burn` target non-USB/SD disks (never the system disk)") orelse false;
    const burn = b.addRunArtifact(tool);
    burn.addArg("burn");
    burn.addFileArg(image);
    if (disk) |d| burn.addArg(d);
    if (yes) burn.addArg("--yes");
    if (any_bus) burn.addArg("--any-bus");
    burn.stdio = .inherit;
    b.step("burn", "Write the USB image to -Dusb-disk=<disk> (needs Administrator/root)").dependOn(&burn.step);

    return image;
}
