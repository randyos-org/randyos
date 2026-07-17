//! STUB: future driver wrapping the UEFI Runtime Services pointer
//! (`KernelBootInfo.fw_runtime_ptr`, `.uefi`, see `src/common/boot_info.zig`).
//! Would expose NVRAM var access and firmware/capsule updates -- the two
//! capabilities that genuinely need firmware (reset/shutdown/clock use
//! ACPI/PSCI/hardware directly, no driver needed).
//!
//! Not implemented: low priority, and needs a kernel driver-loading
//! mechanism that doesn't exist yet. Should be a *dynamically* loaded
//! driver (present only when `fw_runtime_ptr != null` and tagged `.uefi`),
//! not gated on `builtin.cpu.arch` -- UEFI runs on x86_64 and aarch64
//! (Pi 3/4 via pftf) alike. `src/kernel/main.zig`'s `init_fw_driver` just
//! checks `fw_runtime_ptr` for now; wire this in once driver loading exists.
const std = @import("std");
const log = std.log.scoped(.drivers_uefi);
