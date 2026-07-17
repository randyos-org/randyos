//! STUB: Raspberry Pi boot paths without real UEFI. Not implemented.
//!
//! Two targets land here:
//!  - Pi 5, any bitness: no working UEFI firmware (rpi5-uefi effort was
//!    archived Feb 2025). Pi 3/4 have real UEFI via pftf (`boot-aarch64`).
//!  - Pi 3 running a 32-bit OS: Pi 3 has real aarch64 UEFI, but it boots
//!    64-bit only -- no ARM UEFI 32-bit compat mode -- so needs the same
//!    non-UEFI story as Pi 5.
//!
//! Practical approach: Pi's native boot sequence -- GPU ROM reads
//! config.txt, loads a firmware blob (start*.elf/bootcode.bin), which loads
//! kernel*.img as a flat binary at a fixed address -- no ELF, no UEFI.
//! Likely real path: point that slot at U-Boot for extlinux.conf/UEFI
//! support, rather than a raw flat-binary kernel.

const std = @import("std");
const log = std.log.scoped(.boot_rpi);
