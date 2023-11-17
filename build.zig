const Builder = @import("std").build.Builder;
const Target = @import("std").Target;
const CrossTarget = @import("std").zig.CrossTarget;
const builtin = @import("builtin");

pub fn build(b: *Builder) void {
    const bootloader_target = CrossTarget{
        .cpu_arch = Target.Cpu.Arch.x86_64,
        .os_tag = Target.Os.Tag.uefi,
        .abi = Target.Abi.msvc,
    };
    const kernel_target = CrossTarget{
        .cpu_arch = Target.Cpu.Arch.x86_64,
        .os_tag = Target.Os.Tag.freestanding,
        .abi = Target.Abi.none,
    };
    const optimize = b.standardOptimizeOption(.{});
    const bootloader = b.addExecutable(.{
        .name = "bootx64",
        .root_source_file = .{
            .path = "src/bootloader/main.zig",
        },
        .target = bootloader_target,
        .optimize = optimize,
    });
    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = .{
            .path = "src/kernel/main.zig",
        },
        .target = kernel_target,
        .optimize = optimize,
    });
    kernel.setLinkerScriptPath(.{
        .path = "kernel.ld",
    });
    b.installArtifact(bootloader);
    b.installArtifact(kernel);
    b.installDirectory(.{
        .source_dir = bootloader.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "doc",
    });
}
