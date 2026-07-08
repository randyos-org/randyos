//! Build script entry point. Build logic is split by concern into
//! `src/build/` (docs, sysroot, QEMU/OVMF, shared modules, real x86_64
//! targets, roadmap arch stubs) -- see each file's own doc comment. This
//! file is just the orchestration: wiring those pieces together in the
//! right order.

const std = @import("std");
const Build = std.Build;

const docs_mod = @import("src/build/docs.zig");
const sysroot_mod = @import("src/build/sysroot.zig");
const qemu_mod = @import("src/build/qemu.zig");
const modules_mod = @import("src/build/modules.zig");
const exe_mod = @import("src/build/exe.zig");
const arch_stubs_mod = @import("src/build/arch_stubs.zig");
const options_mod = @import("src/build/options.zig");

pub fn build(b: *Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const sysroot = sysroot_mod.addSysroot(b);
    const qemu_cmds = qemu_mod.addQemuCmds(b);
    qemu_mod.addOvmf(b, sysroot.build, qemu_cmds);
    qemu_mod.addQemuSysroot(b, sysroot.install, qemu_cmds);
    qemu_mod.addMonitorCmd(b);

    const docs = docs_mod.addDocs(b);
    const options = options_mod.addOptions(b);
    const common_mod = modules_mod.addCommon(b, optimize, docs, options);
    const abi_mod = modules_mod.addAbi(b, optimize, docs);
    _ = exe_mod.addBootldr(b, sysroot.build, optimize, common_mod, abi_mod, docs);
    _ = exe_mod.addKernel(b, sysroot.build, optimize, common_mod, abi_mod, docs);

    // Roadmap stubs -- see ArchStub's doc comment (src/build/arch_stubs.zig).
    // These still don't touch the default install step, the sysroot, or the
    // QEMU pipeline above, but each one's own step (`kernel-<name>`/
    // `boot-<name>`) also builds and installs its docs, so a stub that
    // doesn't compile yet can't break the shared "docs" step (part of the
    // default install step above).
    for (arch_stubs_mod.arch_stubs) |stub| {
        arch_stubs_mod.addStubKernel(b, optimize, common_mod, abi_mod, stub);
        arch_stubs_mod.addStubBootloader(b, optimize, common_mod, abi_mod, stub);
    }
}
