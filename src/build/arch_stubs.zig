//! Roadmap arch stubs -- see `ArchStub`'s doc comment. Unlike x86_64 (see
//! targets.zig; wired into the default install step, the sysroot, and the
//! QEMU pipeline), these are pure compile-and-link roadmap markers: `zig
//! build kernel-<name>` (and `boot-<name>`, where applicable) just proves the
//! stub arch module + linker script actually build, without touching the
//! working x86_64 boot flow at all.

const std = @import("std");
const Build = std.Build;
const Target = std.Target;
const Module = Build.Module;
const OptimizeMode = std.builtin.OptimizeMode;

const docs_mod = @import("docs.zig");
const addModuleDocsTo = docs_mod.addModuleDocsTo;

/// Roadmap descriptor for a not-yet-implemented arch stub. Unlike x86_64
/// (wired into the default install step, the sysroot, and the QEMU
/// pipeline), these are pure compile-and-link roadmap markers: `zig build
/// kernel-<name>` (and `boot-<name>`, where applicable) just proves the stub
/// arch module + linker script actually build, without touching the working
/// x86_64 boot flow at all.
pub const ArchStub = struct {
    /// Used in step names (e.g. "aarch64" -> "kernel-aarch64") and to locate
    /// `src/kernel/arch/<name>/kernel.ld`.
    name: []const u8,
    kernel_query: Target.Query,
    kernel_code_model: std.builtin.CodeModel = .default,
    /// `null` means this arch has no bootloader step yet -- either because
    /// there's no UEFI firmware worth targeting at all (powerpc: classic
    /// Macs use Open Firmware, see src/bootloader/ofw/), or because the
    /// real target board's UEFI firmware doesn't actually help this
    /// particular OS (arm: Pi 3 does have aarch64 UEFI via pftf, but that
    /// firmware runs the board in 64-bit mode and doesn't boot a 32-bit OS;
    /// aarch64's Raspberry Pi 5 case is similar but for a different reason
    /// -- its UEFI effort was archived entirely. Both go through
    /// src/bootloader/rpi/ instead; Pi 3/4 running aarch64 do have real
    /// UEFI, hence aarch64 itself still has a `bootloader_query` below).
    bootloader_query: ?Target.Query = null,
};

pub const arch_stubs = [_]ArchStub{
    .{
        .name = "aarch64",
        .kernel_query = .{ .cpu_arch = .aarch64, .os_tag = .freestanding, .abi = .none, .ofmt = .elf },
        // Real UEFI firmware -- correct for Raspberry Pi 3/4 (pftf). Does
        // NOT apply to Raspberry Pi 5 (community UEFI effort archived Feb
        // 2025 -- see src/bootloader/rpi/) or Apple Silicon Macs (no native
        // UEFI at all -- see src/bootloader/asahi/). All three target
        // machines share this same kernel-side stub since the CPU
        // instruction set is identical across them.
        .bootloader_query = .{ .cpu_arch = .aarch64, .os_tag = .uefi, .abi = .msvc, .ofmt = .coff },
    },
    .{
        .name = "arm",
        .kernel_query = .{ .cpu_arch = .arm, .os_tag = .freestanding, .abi = .eabi, .ofmt = .elf },
        // Real target: Raspberry Pi 3 running a 32-bit OS. Its aarch64 UEFI
        // firmware (pftf) boots the board in 64-bit mode only -- no path
        // from there to a 32-bit OS -- so this goes through
        // src/bootloader/rpi/ same as Pi 5, not a UEFI bootloader query.
        .bootloader_query = null,
    },
    .{
        .name = "powerpc",
        .kernel_query = .{ .cpu_arch = .powerpc, .os_tag = .freestanding, .abi = .eabi, .ofmt = .elf },
        .bootloader_query = null,
    },
};

/// Builds (but does not install into the default step, sysroot, or QEMU
/// pipeline) a stub kernel for one `ArchStub`. Every real function in it
/// panics -- this only proves the arch module + linker script link.
pub fn addStubKernel(b: *Build, optimize: OptimizeMode, common_mod: *Module, abi_mod: *Module, stub: ArchStub) void {
    const kernel_mod = b.createModule(.{
        .root_source_file = b.path("src/kernel/main.zig"),
        .target = b.resolveTargetQuery(stub.kernel_query),
        .code_model = stub.kernel_code_model,
        .optimize = optimize,
    });
    kernel_mod.addImport("common", common_mod);
    kernel_mod.addImport("abi", abi_mod);

    const kernel_exe = b.addExecutable(.{
        .name = b.fmt("kernel-{s}.elf", .{stub.name}),
        .root_module = kernel_mod,
        .use_lld = true,
        .use_llvm = true,
    });
    kernel_exe.entry = .disabled;
    kernel_exe.setLinkerScript(b.path(b.fmt("src/kernel/arch/{s}/kernel.ld", .{stub.name})));

    const install = b.addInstallArtifact(kernel_exe, .{});
    const step = b.step(
        b.fmt("kernel-{s}", .{stub.name}),
        b.fmt("Build the (stub, not bootable) {s} kernel", .{stub.name}),
    );
    step.dependOn(&install.step);
    // Docs hang off this stub's own step, not the shared "docs" step (part
    // of the default install step) -- so a stub that doesn't compile yet
    // can't break the real build.
    addModuleDocsTo(b, step, kernel_exe, b.fmt("kernel-{s}", .{stub.name}));
}

/// Builds (but does not install into the default step, sysroot, or QEMU
/// pipeline) a stub UEFI bootloader for one `ArchStub`, if it has a
/// `bootloader_query` at all.
pub fn addStubBootloader(b: *Build, optimize: OptimizeMode, common_mod: *Module, abi_mod: *Module, stub: ArchStub) void {
    const query = stub.bootloader_query orelse return;
    const bootloader_mod = b.createModule(.{
        .root_source_file = b.path("src/bootloader/root.zig"),
        .target = b.resolveTargetQuery(query),
        .optimize = optimize,
    });
    bootloader_mod.addImport("common", common_mod);
    bootloader_mod.addImport("abi", abi_mod);

    const bootloader_exe = b.addExecutable(.{
        .name = b.fmt("boot-{s}.efi", .{stub.name}),
        .root_module = bootloader_mod,
    });

    const install = b.addInstallArtifact(bootloader_exe, .{});
    const step = b.step(
        b.fmt("boot-{s}", .{stub.name}),
        b.fmt("Build the (stub, not wired to any boot flow) {s} UEFI bootloader", .{stub.name}),
    );
    step.dependOn(&install.step);
    // Docs hang off this stub's own step, not the shared "docs" step (part
    // of the default install step) -- so a stub that doesn't compile yet
    // can't break the real build.
    addModuleDocsTo(b, step, bootloader_exe, b.fmt("boot-{s}", .{stub.name}));
}
