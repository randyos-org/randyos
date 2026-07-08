//! Home for the parts of devicetree (DTB) handling that would be shared
//! between a bootloader and the kernel, mirroring `src/common/acpi.zig`.
//! Unused today -- no bootloader target produces a devicetree yet (`rpi`/
//! `ofw`/`asahi` are all still stubs) -- this exists so `HardwareDescription`
//! in `src/common/boot_info.zig` has a real payload type for its
//! `.devicetree` variant instead of an inline anonymous struct.

const std = @import("std");
const log = std.log.scoped(.common_dtb);

/// Firmware's devicetree hardware description, as handed to the kernel via
/// `HardwareDescription.devicetree` in `KernelBootInfo`. Just the
/// flattened devicetree (FDT) blob's physical address -- parsing it is
/// entirely future work, done by whatever kernel-side consumer a
/// devicetree-based bootloader target eventually gets (see the `.acpi`
/// consumer, `src/kernel/hw/acpi/root.zig`, for the shape that'll likely
/// take).
pub const Dtb = struct {
    blob: *anyopaque,
};
