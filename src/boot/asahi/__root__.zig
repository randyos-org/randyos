//! STUB: Apple Silicon (arm64 Mac) boot path. Not implemented.
//!
//! Apple Macs have no UEFI firmware -- SecureROM -> iBoot -> iBoot2, no
//! bootloader services, iBoot jumps straight to an OS image. So plain
//! aarch64 UEFI (`boot-aarch64`, correct for Pi 3/4) doesn't apply here.
//!
//! Asahi's approach: iBoot chainloads m1n1 (bootstraps the SoC: memory
//! controller, interrupts, etc.), which loads U-Boot (provides UEFI).
//! Chain: iBoot -> m1n1 -> U-Boot -> us. Different 3-stage story from both
//! uefi/ and rpi/ -- not a retarget of either.

const std = @import("std");
const log = std.log.scoped(.boot_asahi);
