//! Placeholder for a PowerPC "Open Firmware" boot path.
//!
//! STUB: nothing here is implemented. This file exists only to mark that
//! classic PowerPC Macs (e.g. the iBook G3 750FX) boot via Open Firmware's
//! client interface, not UEFI -- so `src/bootloader/uefi/` (UEFI + PE/COFF)
//! cannot reach that hardware no matter how it's retargeted.
//!
//! The eventual approach here is expected to look like BootX/yaboot: Open
//! Firmware can directly `boot` a raw ELF (or a wrapped Mach-O) via its
//! client interface, without needing a PE/COFF loader at all. That means
//! this bootloader would talk to Open Firmware's "call-method"/client
//! interface (memory claim, device tree walk, `boot` the loaded ELF) instead
//! of `std.os.uefi`, which is a genuinely different bootloader, not a
//! retarget of the existing one.
//!
//! Not implemented: none of the above is built yet.
