//! This is the Build Script for our operating system. It is written directly in Zig, so we
//! don't have to learn multiple languages, we can just reuse our Zig knowledge for the build
//! system.

// Here, we import some things from the standard library, such as the targets or the functions
// from the build system.
const Build = @import("std").Build;
const Target = @import("std").Target;

/// This is our main build function. It is invoked by the build runner.
pub fn build(b: *Build) void {
    // This is the bootloader target query. We need this special target because bootloaders have
    // a different executable format (and so on) than normal native executables.
    const bootloader_query = Target.Query{
        // The bootloader will be for x86 processors with 64bit support
        .cpu_arch = .x86_64,
        // The OS we will run the executable on is UEFI (the Unified Extensible Firmware Interface)
        .os_tag = .uefi,
        // The Application Binary Interface, used for calling functions, will be the MSVC ABI,
        // the default for COFF (.exe / .efi) executables.
        .abi = .msvc,
        // The output format will be COFF. This is used for Windows executables and for EFI executables.
        // We will need the latter for our bootloader.
        .ofmt = .coff,
    };
    // This is the kernel target query. This one is also an x86_64 executable, but freestanding.
    // Normal executables communicate with an operating system to do things. The kernel is one
    // of the core parts for an operating system, so it hasn't any operating system abstractions.
    // It must provide everything by itself.
    const kernel_query = Target.Query{
        // The CPU architecture: x86 with 64bit support
        .cpu_arch = .x86_64,
        // As explained above, no OS
        .os_tag = .freestanding,
        // Also no ABI, because the ABI is only important for things like entry functions.
        .abi = .none,
        // Output format will be ELF, which is relatively easy to parse.
        .ofmt = .elf,
    };
    // This gets the standard optimize option (debug, releasesafe, releasesmall, releasefast)
    const optimize = b.standardOptimizeOption(.{});
    // This registers the bootloader executable.
    const bootloader = b.addExecutable(.{
        // It will be named "bootx64", because that's the regular path that can be found by UEFI.
        .name = "bootx64",
        // The root source file is "src/bootloader/main.zig".
        .root_source_file = b.path("src/bootloader/main.zig"),
        // The target is the resolved query of the bootloader target query, as described above.
        .target = b.resolveTargetQuery(bootloader_query),
        // And the optimization can be specified by the user.
        .optimize = optimize,
    });
    // This registers the kernel executable.
    const kernel = b.addExecutable(.{
        // We just name it "kernel", because we can specify the path in the bootloader.
        // However, how executables are named here isn't important because in the building and
        // running scripts, the executables are copied to the final destination, the emulated FAT disk.
        .name = "kernel",
        // The root source file is "src/kernel/main.zig".
        .root_source_file = b.path("src/kernel/main.zig"),
        // The target is the resolved query of the kernel target query, as described above.
        .target = b.resolveTargetQuery(kernel_query),
        // The optimization is user-specified.
        .optimize = optimize,
    });
    // Using this, we disable setting the entry function of the kernel automatically.
    // We want our own entry function named "kmain", not "_start".
    kernel.entry = .disabled;
    // Here, we set the linker script path. For normal executables (and UEFI ones), such linker scripts
    // are provided by the linker. However, this is OUR kernel, so WE want to specify what we want
    // to get in the kernel.
    kernel.setLinkerScriptPath(b.path("src/kernel/kernel.ld"));
    // This line of code installs the bootloader.
    b.installArtifact(bootloader);
    // This line of code installs the kernel.
    b.installArtifact(kernel);
}
