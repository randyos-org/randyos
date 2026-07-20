const std = @import("std");
const buildroot = @import("__root__.zig");
const rstd = buildroot.rstd;
const rstdbuild = rstd.buildutils;

const Build = rstdbuild.Build;
const TargetQuery = rstdbuild.TargetQuery;
const Firmware = rstd.machine.Firmware;
const HardwareInterface = rstd.machine.HardwareInterface;
const ResolvedTarget = rstdbuild.ResolvedTarget;

pub const KernelTargets = struct {
    pub const x64: TargetQuery = .{ .cpu_arch = .x86_64, .os_tag = .freestanding, .abi = .none, .ofmt = .elf };
    pub const arm64: TargetQuery = .{ .cpu_arch = .aarch64, .os_tag = .freestanding, .abi = .none, .ofmt = .elf };
    pub const arm32: TargetQuery = .{ .cpu_arch = .arm, .os_tag = .freestanding, .abi = .eabi, .ofmt = .elf };
    pub const ppc32: TargetQuery = .{ .cpu_arch = .powerpc, .os_tag = .freestanding, .abi = .eabi, .ofmt = .elf };
};

pub const BootloaderTargets = struct {
    pub const x64_uefi: TargetQuery = .{ .cpu_arch = .x86_64, .os_tag = .uefi, .abi = .msvc, .ofmt = .coff };
    pub const arm64_pftf: TargetQuery = .{ .cpu_arch = .aarch64, .os_tag = .uefi, .abi = .msvc, .ofmt = .coff };
    pub const arm64_asahi: TargetQuery = .{ .cpu_arch = .aarch64, .os_tag = .none, .abi = .none, .ofmt = .elf };
    pub const arm64_rpi: TargetQuery = .{ .cpu_arch = .aarch64, .os_tag = .none, .abi = .none, .ofmt = .elf };
    pub const arm32_rpi: TargetQuery = .{ .cpu_arch = .arm, .os_tag = .none, .abi = .none, .ofmt = .elf };
    pub const ppc32_ofw: TargetQuery = .{ .cpu_arch = .powerpc, .os_tag = .none, .abi = .eabi, .ofmt = .elf };
};

pub const MachineTargetQuery = struct {
    bootloader: TargetQuery,
    kernel: TargetQuery,
    firmware: Firmware,
    hardware_interface: HardwareInterface,
};

pub const RandyOSTarget = struct {
    bootloader: ResolvedTarget,
    kernel: ResolvedTarget,
    firmware: Firmware,
    hardware_interface: HardwareInterface,
    rstd: ResolvedTarget,
};

pub const MachineTargets = struct {
    pub const x64: MachineTargetQuery = .{
        .bootloader = BootloaderTargets.x64_uefi,
        .kernel = KernelTargets.x64,
        .firmware = Firmware.uefi,
        .hardware_interface = HardwareInterface.acpi,
    };
    pub const rpi64_uefi: MachineTargetQuery = .{
        .bootloader = BootloaderTargets.arm64_pftf, // pftf firmware is UEFI-based, and we can build a UEFI bootloader for it just fine -- see src/bootloader/rpi/
        .kernel = KernelTargets.arm64,
        .firmware = Firmware.pftf,
        .hardware_interface = HardwareInterface.dtb,
    };
    pub const rpi64: MachineTargetQuery = .{
        .bootloader = BootloaderTargets.arm64_rpi, // not a UEFI firmware at all, and no bootloader implemented yet -- see src/bootloader/rpi/
        .kernel = KernelTargets.arm64,
        .firmware = Firmware.rpi,
        .hardware_interface = HardwareInterface.dtb,
    };
    pub const rpi32: MachineTargetQuery = .{
        .bootloader = BootloaderTargets.arm32_rpi, // no bootloader implemented yet -- see src/bootloader/rpi/
        .kernel = KernelTargets.arm32,
        .firmware = Firmware.rpi,
        .hardware_interface = HardwareInterface.dtb,
    };
    pub const apple_aarch64: MachineTargetQuery = .{
        .bootloader = BootloaderTargets.arm64_asahi, // no UEFI firmware at all, and no bootloader implemented yet -- see src/bootloader/asahi/
        .kernel = KernelTargets.arm64,
        .firmware = Firmware.asahi,
        .hardware_interface = HardwareInterface.none,
    };
    pub const mac_ppc32: MachineTargetQuery = .{
        .bootloader = BootloaderTargets.ppc32_ofw, // no bootloader implemented yet -- see src/bootloader/ofw/
        .kernel = KernelTargets.ppc32,
        .firmware = Firmware.ofw,
        .hardware_interface = HardwareInterface.dtb,
    };
};

// Also no ABI, because the ABI is only important for things like entry functions.
pub const default_machine = MachineTargets.x64;

pub fn getKernelTarget(b: *Build) ResolvedTarget {
    return b.resolveTargetQuery(default_machine.kernel);
}

pub fn getBootloaderTarget(b: *Build) ResolvedTarget {
    return b.resolveTargetQuery(default_machine.bootloader);
}

pub fn getRandyOSTarget(b: *Build) RandyOSTarget {
    return RandyOSTarget{
        .bootloader = b.resolveTargetQuery(default_machine.bootloader),
        .kernel = b.resolveTargetQuery(default_machine.kernel),
        .firmware = default_machine.firmware,
        .hardware_interface = default_machine.hardware_interface,
        .rstd = b.resolveTargetQuery(default_machine.kernel),
    };
}
