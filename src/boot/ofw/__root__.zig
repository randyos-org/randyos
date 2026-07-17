//! STUB: PowerPC Open Firmware boot path. Not implemented.
//!
//! Classic PowerPC Macs (e.g. iBook G3 750FX) boot via Open Firmware's
//! client interface, not UEFI -- so uefi/ (UEFI + PE/COFF) can't reach
//! this hardware no matter how it's re-targeted.
//!
//! Planned approach (BootX/yaboot-style): OF can `boot` a raw ELF (or
//! wrapped Mach-O) directly via its client interface, no PE/COFF loader
//! needed. Talks to OF's call-method/client interface (memory claim,
//! device tree walk, boot the ELF) instead of std.os.uefi -- a genuinely
//! different bootloader, not a re-target.

const std = @import("std");
const log = std.log.scoped(.boot_ofw);
