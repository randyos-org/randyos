pub const rstd = @import("rstd");
pub const targets = @import("targets.zig");
pub const sysroot = @import("sysroot.zig");
pub const qemu = @import("qemu.zig");
pub const options = @import("options.zig");
pub const rstdlib = @import("rstdlib.zig");
// pub const ghostty = @import("ghostty.zig");
// pub const abi = @import("abi.zig");
// pub const exe = @import("exe.zig");
// pub const arch_stubs = @import("arch_stubs.zig");
pub const boot = @import("boot.zig");

const rstdbuild = rstd.buildutils;

pub fn build(b: *rstdbuild.Build) void {
    // standard build setup
    const optimize = rstdbuild.getOptimize(b);
    const docs = rstdbuild.addDocs(b);
    const randyos_target = targets.getRandyOSTarget(b);

    // setup qemu runtime
    const sysroot_paths = sysroot.addSysrootDirs(b);
    qemu.addQemu(b, sysroot_paths);

    // build steps
    const build_options = options.addBuildOptions(b, randyos_target);
    const rstd_module = rstdlib.addRstd(b, docs, build_options, randyos_target.rstd);
    // const abi_mod = modules_mod.addAbi(b, optimize, docs);
    // _ = exe_mod.addBootldr(b, sysroot.build, optimize, common_mod, abi_mod, docs);
    // _ = exe_mod.addKernel(b, sysroot.build, optimize, common_mod, abi_mod, docs);
    _ = boot.addBootldr(b, optimize, randyos_target.bootloader, rstd_module, sysroot_paths, docs);
}
