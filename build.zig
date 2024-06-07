const Build = @import("std").Build;
const Target = @import("std").Target;
const builtin = @import("builtin");

pub fn build(b: *Build) void {
    const bootloader_query = Target.Query{
        .cpu_arch = .x86_64,
        .os_tag = .uefi,
        .abi = .msvc,
        .ofmt = .coff,
    };
    const kernel_query = Target.Query{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
        .ofmt = .elf,
    };
    const optimize = b.standardOptimizeOption(.{});
    const bootloader = b.addExecutable(.{
        .name = "bootx64",
        .root_source_file = b.path("src/bootloader/main.zig"),
        .target = b.resolveTargetQuery(bootloader_query),
        .optimize = optimize,
    });
    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = b.path("src/kernel/main.zig"),
        .target = b.resolveTargetQuery(kernel_query),
        .optimize = optimize,
    });
    kernel.entry = .disabled;
    kernel.setLinkerScriptPath(b.path("src/kernel/kernel.ld"));
    b.installArtifact(bootloader);
    b.installArtifact(kernel);
}
