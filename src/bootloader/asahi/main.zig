//! Placeholder for an Apple Silicon (arm64 Mac) boot path.
//!
//! STUB: nothing here is implemented. This file exists only to mark that
//! Apple Silicon Macs have no native UEFI firmware at all -- unlike the
//! Raspberry Pi (which at least has pftf's real UEFI firmware for the 3/4),
//! Apple's own boot chain (SecureROM -> iBoot stage 1 -> iBoot stage 2) has
//! no bootloader services whatsoever; iBoot loads and jumps to an OS image
//! directly. So `boot-aarch64` (plain aarch64 UEFI, correct for Raspberry Pi
//! 3/4) does not apply to this hardware.
//!
//! The Asahi Linux project's approach is the only known way onto this
//! hardware for a non-Apple OS: with the machine's Startup Security Utility
//! set to Reduced/Permissive Security, iBoot can be made to chainload
//! "m1n1" (a minimal bootloader that brings up Apple Silicon's non-standard
//! hardware -- memory controller, interrupts, etc. -- since a stock kernel
//! can't). m1n1 then loads U-Boot, which is what actually provides UEFI
//! services on top of all that. The chain is:
//!
//!   iBoot (proprietary) -> m1n1 (hardware bringup) -> U-Boot (UEFI) -> us
//!
//! This is a genuinely different, three-stage boot story from both
//! `src/bootloader/uefi/` (direct UEFI) and `src/bootloader/rpi/` (Raspberry
//! Pi 5's native boot sequence or U-Boot, but no m1n1-style hardware-bringup
//! shim needed there) -- not a retarget of either.
//!
//! Not implemented: none of the above is built yet.

const std = @import("std");
const log = std.log.scoped(.boot_asahi);
