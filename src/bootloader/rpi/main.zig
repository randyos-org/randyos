//! Placeholder for Raspberry Pi boot paths that don't go through real UEFI
//! firmware.
//!
//! STUB: nothing here is implemented. This file covers two distinct real
//! targets that both end up here for different reasons:
//!
//!  - Raspberry Pi 5, any bitness: has no working UEFI firmware right now.
//!    Pi 3/4 have real UEFI via pftf (see `boot-aarch64` in build.zig, which
//!    is correct for those two boards running a 64-bit OS), but the
//!    community's Pi 5 UEFI effort (`worproject/rpi5-uefi`) was archived in
//!    Feb 2025, so that path can't be assumed for this board.
//!  - Raspberry Pi 3 running a 32-bit OS: Pi 3 *does* have real aarch64 UEFI
//!    firmware, but that firmware boots the board in 64-bit mode only --
//!    there's no path from an aarch64 UEFI firmware to a 32-bit OS (ARM UEFI
//!    has no real "32-bit compat mode" the way x86's CSM works). So a 32-bit
//!    OS on this same board needs the same non-UEFI story as Pi 5, despite
//!    the hardware having working 64-bit UEFI.
//!
//! The practical approach for both is the Pi's own native boot sequence: the
//! GPU boot ROM reads `config.txt` and loads a firmware blob
//! (`start.elf`/`start4.elf`/`bootcode.bin`, generation-dependent), which
//! then loads whatever `kernel.img`/`kernel7.img`/`kernel8.img`/
//! `kernel_2712.img` names as a flat binary at a fixed address -- no ELF
//! parsing, no UEFI, no boot services. Many distros point that slot at
//! U-Boot instead of a raw kernel, since U-Boot then offers
//! `extlinux.conf`/its own UEFI payload support on top -- that's the more
//! likely real path if this ever gets built out, rather than a raw
//! flat-binary kernel image directly.
//!
//! Not implemented: none of the above is built yet.

const std = @import("std");
const log = std.log.scoped(.boot_rpi);
