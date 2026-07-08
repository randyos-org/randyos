//! Home for the parts of ACPI handling that are genuinely shared between a
//! bootloader and the kernel. Today that's just the shape of the boot-time
//! handoff itself (`AcpiHardwareDescription`, used by `HardwareDescription`
//! in `src/common/boot_info.zig`) -- real static table parsing (RSDP ->
//! XSDT -> MADT, checksum verification) still lives entirely in
//! `src/kernel/hw/acpi/` (`root.zig` + `header.zig`/`madt.zig`/
//! `rsdp.zig`/`xsdt.zig`), called from arch-specific kernel code
//! (`src/kernel/arch/x86_64/platform.zig`) only.
//!
//! That parsing logic doesn't actually depend on UEFI or any other
//! specific firmware, and could in principle be reused by any x86
//! bootloader target (a legacy-BIOS bootloader, if one is ever built,
//! would need the exact same RSDP-scanning/table-walking logic as
//! `src/bootloader/uefi/`) -- move it here if/when a second bootloader
//! target actually needs it. Don't move working code here speculatively.

const std = @import("std");
const log = std.log.scoped(.common_acpi);

/// Firmware's ACPI hardware description, as handed to the kernel via
/// `HardwareDescription.acpi` in `KernelBootInfo`. Just the RSDP pointer --
/// its own `revision` field (part of the RSDP structure itself, see
/// `src/kernel/hw/acpi/rsdp.zig`) is what determines RSDT vs. XSDT, so
/// there's nothing else to carry at this handoff layer.
pub const AcpiHardwareDescription = struct {
    rsdp: *anyopaque,
};
