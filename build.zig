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
        // The bootloader will be for x86 processors with 64-bit support
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
        // The CPU architecture: x86 with 64-bit support
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
    // This creates the bootloader module.
    const bootloader_mod = b.createModule(.{
        // The root source file is "src/bootloader/main.zig".
        .root_source_file = b.path("src/bootloader/main.zig"),
        // The target is the resolved query of the bootloader target query, as described above.
        .target = b.resolveTargetQuery(bootloader_query),
        // And the optimization can be specified by the user.
        .optimize = optimize,
    });
    // This creates the kernel module.
    const kernel_mod = b.createModule(.{
        // The root source file is "src/kernel/main.zig".
        .root_source_file = b.path("src/kernel/main.zig"),
        // The target is the resolved query of the kernel target query, as described above.
        .target = b.resolveTargetQuery(kernel_query),
        // The optimization is user-specified.
        .optimize = optimize,
    });
    // This registers the bootloader executable.
    const bootloader_exe = b.addExecutable(.{
        // It will be named "bootx64", because that's the regular path that can be found by UEFI.
        .name = "bootx64",
        // The root module is the bootloader module, as created above.
        .root_module = bootloader_mod,
    });
    // This registers the kernel executable.
    const kernel_exe = b.addExecutable(.{
        // We just name it "kernel", because we can specify the path in the bootloader.
        // However, how executables are named here isn't important because in the building and
        // running scripts, the executables are copied to the final destination, the emulated FAT disk.
        .name = "kernel",
        // The root module is the kernel module, as created above.
        .root_module = kernel_mod,
    });
    // Using this, we disable setting the entry function of the kernel automatically.
    // We want our own entry function named "kmain", not "_start".
    kernel_exe.entry = .disabled;
    // Here, we set the linker script path. For normal executables (and UEFI ones), such linker scripts
    // are provided by the linker. However, this is OUR kernel, so WE want to specify what we want
    // to get in the kernel.
    kernel_exe.setLinkerScript(b.path("src/kernel/kernel.ld"));
    // This line of code installs the bootloader.
    b.installArtifact(bootloader_exe);
    // This line of code installs the kernel.
    b.installArtifact(kernel_exe);
    // After that, we create a directory in the zig cache into which we can copy files.
    const boot_dir = b.addWriteFiles();
    // Now, we copy the bootloader executable into a folder that will be recognized by UEFI.
    _ = boot_dir.addCopyFile(bootloader_exe.getEmittedBin(), b.pathJoin(&.{"efi/boot", bootloader_exe.out_filename}));
    // Here, we copy the kernel executable to a custom location, and make sure it has the `.elf`
    // extension that the bootloader expects.
    _ = boot_dir.addCopyFile(kernel_exe.getEmittedBin(), b.fmt("{s}.elf", .{kernel_exe.out_filename}));
    // With this command, we start QEMU (a computer emulator)...
    const qemu_cmd = b.addSystemCommand(&.{"qemu-system-x86_64"});
    // ...that depends on the bootloader and kernel install steps we defined above...
    qemu_cmd.step.dependOn(b.getInstallStep());
    // ...with UEFI as firware using the OVMF.fd file...
    qemu_cmd.addArg("-bios");
    qemu_cmd.addFileArg(b.path("OVMF.fd"));
    // ...an emulated FAT drive using the directory we made in the above...
    qemu_cmd.addArg("-hdd");
    qemu_cmd.addPrefixedDirectoryArg("fat:rw:", boot_dir.getDirectory());
    // ...the standard output mapped to the COM1, allowing us to see messages from the operating
    // system directly on our console...
    qemu_cmd.addArg("-serial");
    qemu_cmd.addArg("mon:stdio");
    // ...a GTK-based window for display...
    qemu_cmd.addArg("-display");
    qemu_cmd.addArg("gtk");
    // ...and a GDB (a debugger tool) remote-connection client available on localhost:1234 via TCP.
    qemu_cmd.addArg("-s");
    // The we create a subcommand (`zig build qemu`) to run the above system command...
    const qemu_step = b.step("qemu", "Run the kernel via QEMU");
    // ...and make sure it depends on that command's step.
    qemu_step.dependOn(&qemu_cmd.step);
}
