//! QEMU run/debug commands, OVMF firmware wiring, attaching the sysroot as
//! QEMU's FAT boot drive, and the `socat`-based QEMU monitor helper.

const std = @import("std");
const Build = std.Build;
const Step = Build.Step;
const Run = Step.Run;
const WriteFile = Step.WriteFile;
const InstallDir = Step.InstallDir;

pub const QemuCmds = struct {
    run: *Run,
    debug: *Run,
};

pub fn addQemuCmds(b: *Build) QemuCmds {
    const base_cmd = &.{"qemu-system-x86_64"};
    const base_args = &.{
        "-s", // GDB connection available at localhost:1234 via TCP.

        // standard output mapped to COM1
        "-serial",
        "mon:stdio",

        // GTK-based window for display
        "-display",
        "gtk",

        // add socat monitor socket
        "-monitor",
        "unix:qemu-monitor-socket,server,nowait",

        // A triple fault normally makes QEMU silently reset the VM and
        // re-run firmware/bootloader/kernel from scratch, which looks like
        // an infinite bootloop. Halt instead so the failure is visible and
        // the machine state can be inspected.
        "-no-reboot",
        "-no-shutdown",
    };
    const cmds = QemuCmds{
        .run = b.addSystemCommand(base_cmd),
        .debug = b.addSystemCommand(base_cmd),
    };
    cmds.run.addArgs(base_args);
    cmds.debug.addArgs(base_args);
    cmds.debug.addArg("-S"); // wait for GDB connection

    const run_step = b.step("run", "Run the kernel via QEMU");
    run_step.dependOn(&cmds.run.step);

    const debug_step = b.step("debug", "Run the kernel via QEMU, wait for GDB connection");
    debug_step.dependOn(&cmds.debug.step);

    return cmds;
}

pub fn addOvmf(b: *Build, sysroot: *WriteFile, qemu_cmds: QemuCmds) void {
    const ovmf_code = b.option(
        Build.LazyPath,
        "ovmf-code",
        "The OVMF_CODE file to use",
    );
    const ovmf_vars = b.option(
        Build.LazyPath,
        "ovmf-vars",
        "The OVMF_VARS file to use",
    );
    if (ovmf_code) |ocp| {
        // note that the destination is just a name, nothing special.
        const oc = sysroot.addCopyFile(
            ocp,
            "ovmf_code.fd",
        );
        if (ovmf_vars) |ovp| {
            const ov = sysroot.addCopyFile(
                ovp,
                "ovmf_vars.fd",
            );

            inline for (comptime std.meta.fieldNames(QemuCmds)) |field_name| {
                // add OVMF_CODE file first as ro
                const cmd = @field(qemu_cmds, field_name);
                cmd.addArg("-drive");
                cmd.addPrefixedFileArg(
                    "format=raw,if=pflash,readonly=on,file=",
                    oc,
                );

                // then add OVMF_VARS file
                cmd.addArg("-drive");
                cmd.addPrefixedFileArg("format=raw,if=pflash,file=", ov);
            }
        } else {
            // Otherwise, add what is expected to be the combined OVMF file.
            inline for (comptime std.meta.fieldNames(QemuCmds)) |field_name| {
                const cmd = @field(qemu_cmds, field_name);
                cmd.addArg("-drive");
                cmd.addPrefixedFileArg("format=raw,if=pflash,file=", ocp);
            }
        }
    } else {
        //  use the default from the repo
        const ocp = b.path("OVMF.fd");
        const oc = sysroot.addCopyFile(
            ocp,
            "ovmf.fd",
        );
        inline for (comptime std.meta.fieldNames(QemuCmds)) |field_name| {
            const cmd = @field(qemu_cmds, field_name);
            cmd.addArg("-drive");
            cmd.addPrefixedFileArg(
                "format=raw,if=pflash,file=",
                oc,
            );
        }
    }
}

// fn addQemuSysroot(sysroot_install: *InstallDir, qemu_cmds: QemuCmds) void {
//     inline for (comptime std.meta.fieldNames(QemuCmds)) |field_name| {
//         const cmd = @field(qemu_cmds, field_name);
//         cmd.addArg("-drive");
//         cmd.addPrefixedDirectoryArg("format=raw,index=3,media=disk,file=fat:rw:", .{
//             .relative = .{
//                 .base = .install_prefix,
//                 .sub_path = "systemroot",
//             },
//         });
//         cmd.step.dependOn(&sysroot_install.step);
//     }
// }

pub fn addQemuSysroot(b: *Build, sysroot_install: *InstallDir, qemu_cmds: QemuCmds) void {
    const sysroot_path = b.getInstallPath(
        sysroot_install.options.install_dir,
        sysroot_install.options.install_subdir,
    );
    inline for (comptime std.meta.fieldNames(QemuCmds)) |field_name| {
        const cmd = @field(qemu_cmds, field_name);
        cmd.addArg("-drive");
        cmd.addPrefixedDirectoryArg(
            "format=raw,index=3,media=disk,file=fat:rw:",
            .{ .cwd_relative = sysroot_path },
        );
        cmd.step.dependOn(&sysroot_install.step);
    }
}

pub fn addMonitorCmd(b: *Build) void {
    const monitor = b.addSystemCommand(&.{"socat"});
    monitor.addArgs(&.{
        "-,echo=0,icanon=0",
        "unix-connect:qemu-monitor-socket",
    });
    const monitor_step = b.step("monitor", "Launch socat to interact with qemu-monitor");
    monitor_step.dependOn(&monitor.step);
}
