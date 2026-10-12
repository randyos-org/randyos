pub const rstd = @import("rstd");
pub const zon = @import("../build.zig.zon");

pub const targets = @import("targets.zig");
pub const sysroot = @import("sysroot.zig");
pub const qemu = @import("qemu.zig");
pub const options = @import("options.zig");
pub const rstdlib = @import("rstdlib.zig");
pub const boot = @import("boot.zig");
pub const usb = @import("usb.zig");

const rstdbuild = rstd.buildutils;

pub fn build(b: *rstdbuild.Build) !void {
    // standard build setup
    const optimize = rstdbuild.getOptimize(b);
    const docs = rstdbuild.addDocs(b);
    const randyos_target = targets.getRandyOSTarget(b);

    // setup qemu runtime
    const sysroot_paths = sysroot.addSysrootDirs(b);
    const usbimgtool = usb.addTool(b);
    const usb_image = usb.addUsb(b, usbimgtool, sysroot_paths);
    const signer = try usb.addSecureBoot(b, usbimgtool, sysroot_paths);
    try qemu.addQemu(b, sysroot_paths, usb_image);

    // build steps
    // rstd links BLAS objects built for its target, so each consumer gets its own instance.
    const build_options = try options.addBuildOptions(b, randyos_target);
    const boot_rstd = try rstdlib.addRstd(b, null, build_options, randyos_target.bootloader, optimize);
    _ = boot.addBootldr(b, optimize, randyos_target.bootloader, boot_rstd, sysroot_paths, signer, docs);

    // const abi_mod = modules_mod.addAbi(b, optimize, docs);
    const kernel_rstd = try rstdlib.addRstd(b, docs, build_options, randyos_target.rstd, optimize);
    _ = kernel_rstd; // until the kernel is built again
}
