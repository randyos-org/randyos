//! QEMU run/debug commands, OVMF firmware wiring, attaching the sysroot as
//! QEMU's FAT boot drive, and the `socat`-based QEMU monitor helper.

const std = @import("std");
const buildroot = @import("__root__.zig");
const rstd = @import("rstd");
const rstdbuild = rstd.buildutils;
const SysrootDirs = buildroot.sysroot.SysrootDirs;

const Build = rstdbuild.Build;
const RunStep = rstdbuild.RunStep;

pub const QemuCmds = struct {
    run: *RunStep,
    debug: *RunStep,
};

pub fn addQemu(b: *Build, sysroot: SysrootDirs) void {
    const cmds = addQemuCmds(b);
    addOvmfToQemu(b, sysroot, cmds);
    addSysrootToQemu(b, sysroot, cmds);
    addPersistentDriveToQemu(b, cmds);

    addMonitorCmd(b);
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

fn addQemuCmds(b: *Build) QemuCmds {
    const base_cmd = &.{"qemu-system-x86_64"};
    const base_args = &.{
        "-s", // GDB connection available at localhost:1234 via TCP.

        // standard output mapped to COM1
        "-serial",
        "mon:stdio",

        // add socat monitor socket
        "-monitor",
        "unix:qemu-monitor-socket,server,nowait",

        // A triple fault normally makes QEMU silently reset the VM and
        // re-run firmware/bootloader/kernel from scratch, which looks like
        // an infinite bootloop. Halt instead so the failure is visible and
        // the machine state can be inspected.
        "-no-reboot",
        "-no-shutdown",

        // accelerate with Windows Hypervisor Platform (WHPX) if available, otherwise use TCG
        "-accel",
        "whpx",
        // "-accel",
        // "tcg",

        // "-cpu max" GP-faults OVMF under WHPX on this machine. "-cpu host"
        // is supposed to do real hardware CPUID passthrough, but that's only
        // actually implemented for KVM/HVF in QEMU; under TCG it's correctly
        // rejected ("CPU model 'host' requires KVM or HVF"), but WHPX lets it
        // through anyway and falls back to something resembling "max" --
        // confirmed by it reporting Intel APX as available on this AMD host,
        // which is impossible. EPYC-Milan matches this machine's actual
        // silicon generation (AMD Zen3, no AVX-512/APX to falsely claim) and
        // boots clean under WHPX with no feature-conflict warnings at all.
        "-cpu",
        "EPYC-Milan-v3",

        // use some reasonable defaults for our VM to match a modern PC
        "-machine",
        "q35",

        "-smp",
        "2",

        "-m",
        "4G",

        // virtio-vga: VGA-compatible (so OVMF can drive it before the kernel
        // loads) wrapping a real virtio-gpu 2D scanout -- this is the actual
        // foundation a software compositor needs (mode setting + a linear
        // framebuffer to blit into). Single output by default; swap to the
        // -device form below for multi-monitor compositor testing, or the
        // -gl variant (together with "gl=on" on -display above) once there's
        // a kernel-side virtio-gpu 3D/virgl driver to exercise it.
        "-vga",
        "virtio",

        // multi-monitor, still no GL -- comment out "-vga virtio" above if using this
        // "-device",
        // "virtio-vga,max_outputs=2",

        // GTK-based window for display. zoom-to-fit=off makes the window
        // follow the guest's native resolution instead of stretching the
        // framebuffer to whatever size the window is dragged to.
        "-display",
        "gtk,zoom-to-fit=off",

        // needed alongside the virtio-vga-gl swap below, once there's a kernel-side virtio-gpu 3D/virgl driver to exercise it
        // "gtk,zoom-to-fit=off,gl=on",

        // + gl=on on -display above -- comment out "-vga virtio" above if using this
        // "-device",
        // "virtio-vga-gl,max_outputs=2",

        // USB 3.0 (xHCI) controller, plus keyboard and mouse on it -- real
        // modern desktops are USB-first for HID (PS/2 is legacy-only), and
        // xhci also gives us a generic bus other USB devices can be attached
        // to later without needing a different controller.
        "-device",
        "qemu-xhci",
        "-device",
        "usb-kbd",
        "-device",
        "usb-mouse",

        // Intel HD Audio, matching the ICH9 southbridge this q35 machine
        // already emulates.
        "-audiodev",
        "dsound,id=snd0",
        "-device",
        "ich9-intel-hda",
        "-device",
        "hda-duplex,audiodev=snd0",

        // virtio-rng, backed by the host's own CSPRNG (rng-builtin, unlike
        // rng-random, doesn't depend on a host file path like /dev/urandom
        // that doesn't exist as such on Windows). Unlike the GL/TPM/IOMMU
        // features we're deferring, this is a trivial driver (read bytes off
        // one virtqueue, no mode-setting/protocol negotiation) and something
        // a kernel plausibly wants early (stack-protector canaries, ASLR).
        "-object",
        "rng-builtin,id=rng0",
        "-device",
        "virtio-rng-pci,rng=rng0",
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

fn addOvmfToQemu(b: *Build, sysroot: SysrootDirs, qemu_cmds: QemuCmds) void {
    const ovmf_code = b.option(Build.LazyPath, "ovmf-code", "The OVMF_CODE file to use");
    const ovmf_vars = b.option(Build.LazyPath, "ovmf-vars", "The OVMF_VARS file to use");

    const ovmf_rw_args = "format=raw,if=pflash,file=";
    const ovmf_ro_args = "readonly=on," ++ ovmf_rw_args;

    // note that the destinations here can be any name
    const srcpath = if (ovmf_code) |src| src else b.path("OVMF.fd");
    const ovmf_code_path = sysroot.build.addCopyFile(srcpath, "ovmf.fd");
    const ovmf_code_args = if (ovmf_vars != null) ovmf_ro_args else ovmf_rw_args;
    inline for (comptime std.meta.fieldNames(QemuCmds)) |field_name| {
        const cmd: *RunStep = @field(qemu_cmds, field_name);
        cmd.addArg("-drive");
        cmd.addPrefixedFileArg(ovmf_code_args, ovmf_code_path);
    }

    if (ovmf_vars) |varspath| {
        const ovmf_vars_path = sysroot.build.addCopyFile(varspath, "ovmf_vars.fd");
        inline for (comptime std.meta.fieldNames(QemuCmds)) |field_name| {
            const cmd: *RunStep = @field(qemu_cmds, field_name);
            cmd.addArg("-drive");
            cmd.addPrefixedFileArg(ovmf_rw_args, ovmf_vars_path);
        }
    }
}

fn addSysrootToQemu(b: *Build, sysroot: SysrootDirs, qemu_cmds: QemuCmds) void {
    const sysroot_install = sysroot.install;
    const sysroot_path = rstdbuild.installDirLazyPath(b, sysroot_install);
    inline for (comptime std.meta.fieldNames(QemuCmds)) |field_name| {
        const cmd: *RunStep = @field(qemu_cmds, field_name);
        cmd.addArg("-drive");
        cmd.addPrefixedDirectoryArg(
            "format=raw,index=3,media=disk,file=fat:rw:",
            sysroot_path,
        );
        cmd.step.dependOn(&sysroot_install.step);
    }
}

fn addPersistentDriveToQemu(b: *Build, qemu_cmds: QemuCmds) void {
    const drive_args = "format=qcow2,if=virtio,file=";
    const drive_pathstr = "disk.qcow2";
    const drive_abs_path = b.root.joinString(b.allocator, drive_pathstr) catch @panic("OOM");
    const drive_lazypath = b.path(drive_pathstr);

    // check if this file exists, if not, create it using the command:
    // qemu-img create -f qcow2 disk.qcow2 40G
    const create_drive_step = b.step("create-drive", "Create persistent drive for QEMU");
    if (!rstd.io.fileExists(b.graph.io, drive_abs_path)) {
        const create_drive_cmd = b.addSystemCommand(&.{"qemu-img"});
        create_drive_cmd.addArgs(&.{ "create", "-f", "qcow2" });
        create_drive_cmd.addFileArg(drive_lazypath);
        create_drive_cmd.addArg("40G");
        create_drive_step.dependOn(&create_drive_cmd.step);
    }

    inline for (comptime std.meta.fieldNames(QemuCmds)) |field_name| {
        const cmd: *RunStep = @field(qemu_cmds, field_name);
        cmd.addArg("-drive");
        cmd.addPrefixedFileArg(drive_args, drive_lazypath);
        cmd.step.dependOn(create_drive_step);
    }
}
