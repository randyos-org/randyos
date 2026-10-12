//! Bootable USB image of the sysroot (GPT + FAT32 ESP), built and burned by
//! the host-side `tools/usbimg` program, which also signs EFI images for
//! Secure Boot.

const std = @import("std");
const buildroot = @import("__root__.zig");
const rstd = @import("rstd");
const rstdbuild = rstd.buildutils;
const SysrootDirs = buildroot.sysroot.SysrootDirs;

const Build = rstdbuild.Build;
const LazyPath = rstdbuild.LazyPath;
const CompileStep = rstdbuild.CompileStep;

/// Secure Boot key from `zig build sb-keygen`; gitignored, never commit it.
const key_dir = "sbkeys";

pub fn addTool(b: *Build) *CompileStep {
    const tool_mod = b.createModule(.{
        .root_source_file = b.path("tools/usbimg/__main__.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    });
    // Host-configured rstd; also provides win32 (rstd.win32) on Windows.
    const rstd_dep = b.dependency("rstd", .{ .target = b.graph.host });
    tool_mod.addImport("rstd", rstd_dep.module("rstd"));
    return b.addExecutable(.{ .name = "usbimg", .root_module = tool_mod });
}

/// Adds the `image`, `usb-list` and `burn` steps; returns the image.
pub fn addUsb(b: *Build, tool: *CompileStep, sysroot: SysrootDirs) LazyPath {
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

    const disk = b.option([]const u8, "usb-disk", "Disk for `burn`: number on Windows (PhysicalDriveN), /dev/sdX on Linux; may be omitted when the only other disk is the target");
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

pub const Signer = struct {
    tool: *CompileStep,
    key: LazyPath,
    cert: LazyPath,
    /// Fedora's shim and MokManager (shimx64.efi, mmx64.efi), or null to boot
    /// the loader directly.
    shim: ?LazyPath,

    /// `efi` Authenticode-signed with the Secure Boot key.
    pub fn sign(s: Signer, b: *Build, efi: LazyPath, name: []const u8) LazyPath {
        const run = b.addRunArtifact(s.tool);
        run.addArg("sign");
        run.addFileArg(efi);
        run.addFileArg(s.key);
        run.addFileArg(s.cert);
        return run.addOutputFileArg(name);
    }

    /// Signs `efi` and puts it on the ESP: behind shim as grubx64.efi (the
    /// name shim loads), else as the removable-media default BOOTX64.EFI.
    pub fn installLoader(s: Signer, b: *Build, sysroot: SysrootDirs, efi: LazyPath) void {
        const signed = s.sign(b, efi, "loader.efi");
        const shim = s.shim orelse {
            _ = sysroot.build.addCopyFile(signed, "efi/boot/bootx64.efi");
            return;
        };
        _ = sysroot.build.addCopyFile(signed, "efi/boot/grubx64.efi");
        _ = sysroot.build.addCopyFile(shim.path(b, "shimx64.efi"), "efi/boot/bootx64.efi");
        _ = sysroot.build.addCopyFile(shim.path(b, "mmx64.efi"), "efi/boot/mmx64.efi");
    }
};

/// Adds `sb-keygen`. Returns a signer when `-Dsecure-boot` (default: a key
/// exists), and puts the key's certificate on the ESP for enrolling into db.
pub fn addSecureBoot(b: *Build, tool: *CompileStep, sysroot: SysrootDirs) !?Signer {
    const keygen = b.addRunArtifact(tool);
    keygen.addArg("keygen");
    keygen.addDirectoryArg(b.path(key_dir));
    keygen.stdio = .inherit;
    b.step("sb-keygen", "Create the Secure Boot signing key in sbkeys/ (once; enroll sbkeys/db.cer in firmware)").dependOn(&keygen.step);

    const key = b.pathJoin(&.{ key_dir, "db.key" });
    const cert = b.pathJoin(&.{ key_dir, "db.crt" });
    const cer = b.pathJoin(&.{ key_dir, "db.cer" });
    // Configuration is cached; re-run it when keys come or go.
    b.dependOnDirectoryContents(b.path(key_dir));
    const have_key = rstdbuild.io.fileExists(b.graph.io, try b.root.joinString(b.allocator, key));
    const enabled = b.option(bool, "secure-boot", "Sign EFI images for Secure Boot (default: when sbkeys/db.key exists)") orelse have_key;
    if (!enabled) return null;
    if (!have_key) {
        std.debug.print("-Dsecure-boot needs a key; run `zig build sb-keygen` first\n", .{});
        return error.NoSecureBootKey;
    }
    _ = sysroot.build.addCopyFile(b.path(cer), "randyos-db.cer");

    // shim + MokManager: machines without our key in db get a prompt to
    // enroll randyos-db.cer instead of a Secure Boot violation.
    const use_shim = b.option(bool, "shim", "Boot through Fedora's signed shim, offering MokManager to enroll the key (default: true)") orelse true;
    const shim: ?LazyPath = if (use_shim) blk: {
        const run = b.addRunArtifact(tool);
        run.addArg("shim");
        run.addDirectoryArg(b.path(key_dir));
        const out = run.addOutputDirectoryArg("shim");
        // Checks Fedora for a newer shim on every build.
        run.has_side_effects = true;
        break :blk out;
    } else null;
    return .{ .tool = tool, .key = b.path(key), .cert = b.path(cert), .shim = shim };
}
