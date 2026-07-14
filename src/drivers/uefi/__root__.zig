//! STUB: intended eventual home for a driver that wraps the UEFI Runtime
//! Services pointer handed off via `KernelBootInfo.fw_runtime_ptr`
//! (`.uefi`, see `src/common/boot_info.zig`) and exposes whatever ongoing
//! UEFI-specific capabilities the kernel eventually wants -- NVRAM
//! variable access and in-OS firmware/capsule updates are the two
//! concrete candidates identified so far, since both are genuinely
//! irreducible to firmware (no ACPI table or direct hardware access can
//! substitute for either, unlike reset/shutdown or wall-clock time, which
//! don't need this driver at all -- see the reset/shutdown design
//! discussion: ACPI's FADT reset register, PSCI, and direct hardware
//! pokes cover that without any firmware runtime dependency).
//!
//! Not implemented, deliberately: this is low priority (the capabilities
//! it would provide are rarely needed) and it depends on a kernel driver-
//! loading mechanism that doesn't exist yet. The intended shape is a
//! *dynamically* loaded driver -- linked in only on builds/boots where a
//! UEFI runtime is actually present (`fw_runtime_ptr != null` and tagged
//! `.uefi`) -- not something tied to any particular CPU architecture:
//! UEFI exists on x86_64 today in this repo, but also on real aarch64
//! hardware (e.g. Raspberry Pi 3/4 via pftf UEFI, per
//! `src/bootloader/rpi/main.zig`), so this must never be gated on
//! `builtin.cpu.arch` the way `src/kernel/arch/` is. `src/kernel/main.zig`
//! (`init_fw_driver`) currently only checks whether `fw_runtime_ptr` is
//! present and does nothing further -- wire this driver in once real
//! driver loading exists, not before.
const std = @import("std");
const log = std.log.scoped(.drivers_uefi);
