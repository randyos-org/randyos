const Build = @import("std").Build;
const Target = @import("std").Target;

pub fn build(b: *Build) void {
    const optimize = b.standardOptimizeOption(.{});

    // This is the bootloader target query. We need this special target because
    // bootloaders have a different executable format (and so on) than normal
    // native executables.
    const bootloader_query = Target.Query{
        .cpu_arch = .x86_64,
        // The OS we will run the executable on is UEFI (the Unified Extensible
        // Firmware Interface)
        .os_tag = .uefi,
        // The Application Binary Interface, used for calling functions, will
        // be the MSVC ABI, the default for COFF (.exe / .efi) executables.
        .abi = .msvc,
        // The output format will be COFF. This is used for Windows executables
        // and for EFI executables. We will need the latter for our bootloader.
        .ofmt = .coff,
    };
    const bootloader_mod = b.createModule(.{
        .root_source_file = b.path("src/bootloader/main.zig"),
        .target = b.resolveTargetQuery(bootloader_query),
        .optimize = optimize,
    });
    const bootloader_exe = b.addExecutable(.{
        // It will be named "bootx64", because that's the regular path that can
        // be found by UEFI.
        .name = "bootx64",
        .root_module = bootloader_mod,
    });
    b.installArtifact(bootloader_exe);

    // This is the kernel target query. This one is also an x86_64 executable,
    // but freestanding. Normal executables communicate with an operating
    // system to do things. The kernel is one of the core parts for an
    // operating system, so it hasn't any operating system abstractions. It
    // must provide everything by itself.
    const kernel_query = Target.Query{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        // Also no ABI, because the ABI is only important for things like entry
        // functions.
        .abi = .none,
        .ofmt = .elf,
    };
    const kernel_mod = b.createModule(.{
        .root_source_file = b.path("src/kernel/main.zig"),
        .target = b.resolveTargetQuery(kernel_query),
        .optimize = optimize,
    });
    const kernel_exe = b.addExecutable(.{
        // We name it "kernel.elf" since that is what the bootloader expects.
        .name = "kernel.elf",
        .root_module = kernel_mod,
        // For now, we want to use LLVM and its linker LLD to compile the
        // kernel, as the self-hosted linker can't work with so-called "Linker
        // Scripts" (you'll learn about them a few lines below).
        .use_lld = true,
        .use_llvm = true,
    });
    // Using this, we disable setting the entry function of the kernel
    // automatically. We want our own entry function named "kmain", not
    // "_start".
    kernel_exe.entry = .disabled;
    // Here, we set the linker script path. For normal executables (and UEFI
    // ones), such linker scripts are provided by the linker. However, this is
    // OUR kernel, so WE want to specify what we want to get in the kernel.
    kernel_exe.setLinkerScript(b.path("src/kernel/kernel.ld"));
    b.installArtifact(kernel_exe);

    // Add an option to supply the OVMF_CODE file…
    const ovmf_code = b.option(
        Build.LazyPath,
        "ovmf-code",
        "The OVMF_CODE file to use",
    );
    // …and the same for the OVMF_VARS file.
    const ovmf_vars = b.option(
        Build.LazyPath,
        "ovmf-vars",
        "The OVMF_VARS file to use",
    );

    // After that, we create a directory in the zig cache into which we can copy
    // files…
    const boot_dir = b.addWriteFiles();
    // …including the bootloader executable into a folder that will be
    // recognized by the UEFI firmware…
    _ = boot_dir.addCopyFile(
        bootloader_exe.getEmittedBin(),
        b.pathJoin(&.{
            "efi",
            "boot",
            bootloader_exe.out_filename,
        }),
    );
    // …and the kernel executable to the location expected by the bootloader.
    _ = boot_dir.addCopyFile(
        kernel_exe.getEmittedBin(),
        kernel_exe.out_filename,
    );

    const qemu_cmd = b.addSystemCommand(&.{"qemu-system-x86_64"});
    // standard output mapped to COM1
    qemu_cmd.addArg("-serial");
    qemu_cmd.addArg("mon:stdio");

    // GTK-based window for display
    qemu_cmd.addArg("-display");
    qemu_cmd.addArg("gtk");

    // GDB connection available at localhost:1234 via TCP.
    qemu_cmd.addArg("-s");

    if (ovmf_code) |ocp| {
        // note that the destination is just a name, nothing special.
        const oc = boot_dir.addCopyFile(
            ocp,
            "ovmf_code.fd",
        );
        if (ovmf_vars) |ovp| {
            const ov = boot_dir.addCopyFile(
                ovp,
                "ovmf_vars.fd",
            );

            // add OVMF_CODE file first as ro
            qemu_cmd.addArg("-drive");
            qemu_cmd.addPrefixedFileArg(
                "format=raw,if=pflash,readonly=on,file=",
                oc,
            );

            // then add OVMF_VARS file
            qemu_cmd.addArg("-drive");
            qemu_cmd.addPrefixedFileArg("format=raw,if=pflash,file=", ov);
        } else {
            // Otherwise, add what is expected to be the combined OVMF file.
            qemu_cmd.addArg("-drive");
            qemu_cmd.addPrefixedFileArg("format=raw,if=pflash,file=", ocp);
        }
    } else {
        //  use the default from the repo
        const ocp = b.path("OVMF.fd");
        const oc = boot_dir.addCopyFile(
            ocp,
            "ovmf.fd",
        );
        qemu_cmd.addArg("-drive");
        qemu_cmd.addPrefixedFileArg(
            "format=raw,if=pflash,file=",
            oc,
        );
    }
    // Finally, add an emulated FAT drive using the boot directory we made
    // above (UEFI requires FAT)
    qemu_cmd.addArg("-drive");
    qemu_cmd.addPrefixedDirectoryArg(
        "format=raw,index=3,media=disk,file=fat:rw:",
        boot_dir.getDirectory(),
    );
    const qemu_step = b.step("qemu", "Run the kernel via QEMU");
    qemu_step.dependOn(&qemu_cmd.step);
}
