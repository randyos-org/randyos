# RandyOS

![RandyOS logo](src/kernel/gfx/logo/randyos-logo.svg)

Very basic OS for a very basic dude.

## Target Machines

RandyOS is being built toward this specific set of machines, not general
multi-platform support. "Working" means `zig build` (default step) produces
a bootable image today; everything else is a compile-only roadmap stub (see
`src/abi/README.md` and the `src/bootloader-*/` placeholders for the reasoning
behind each one).

| Machine | Kernel target triple | Kernel build step | Bootloader | Bootloader target triple | Bootloader build step | Status |
| --- | --- | --- | --- | --- | --- | --- |
| PC | `x86_64-freestanding-none` | `zig build` (default) | UEFI | `x86_64-uefi-msvc` | `zig build` (default) | Working |
| Mac (Intel) | `x86_64-freestanding-none` | `zig build` (default, shared with PC) | UEFI (same firmware family, plain non-fat `.efi`) | `x86_64-uefi-msvc` | `zig build` (default, shared with PC) | Working |
| Raspberry Pi 3/4 (64-bit) | `aarch64-freestanding-none` | `zig build kernel-aarch64` | UEFI (pftf firmware) | `aarch64-uefi-msvc` | `zig build boot-aarch64` | Stub |
| Raspberry Pi 5 | `aarch64-freestanding-none` | `zig build kernel-aarch64` (shared with Pi 3/4) | none yet -- see `src/bootloader/rpi/` | TBD | none yet | Stub |
| Raspberry Pi 3 (32-bit OS) | `arm-freestanding-eabi` | `zig build kernel-arm` | none yet -- see `src/bootloader/rpi/` | TBD | none yet | Stub |
| Mac (Apple Silicon) | `aarch64-freestanding-none` | `zig build kernel-aarch64` (shared with Pi 3/4/5) | none yet -- see `src/bootloader/asahi/` | TBD | none yet | Stub |
| iBook G3 (PowerPC 750FX) | `powerpc-freestanding-eabi` | `zig build kernel-powerpc` | none yet -- see `src/bootloader/ofw/` | TBD | none yet | Stub |

## Requirements

* qemu
* zig
* gdb

## Usage

```bash
git clone https://codeberg.org/emanspeaks/randyos.git
cd randyos
zig build
# git submodule update --init --recursive
```

If you have `qemu-system-x86_64` installed, then you can run `zig build qemu` to build and run the kernel. It sets up a directory in the build cache to use as the emulated FAT disk and runs QEMU using it.

By default, it will use the combined OVMF file found in this repository. You can also choose to provide your own OVMF files in two ways:

  1. Supply `-Dovmf-code` with a combined OVMF file.
  2. Supply `-Dovmf-code` and `-Dovmf-vars` with separate OVMF_CODE and OVMF_VARS files, respectively.

All OVMF files used by `zig build qemu` will be copied so that their original versions are not modified. You can access the copied files in the build cache in the same directory used as the FAT boot drive.

### What is OVMF?

[OVMF](https://github.com/tianocore/tianocore.github.io/wiki/OVMF) is an [EDK II](https://github.com/tianocore/tianocore.github.io/wiki/EDK-II)-based project that enables UEFI support on Virtual Machines. In our case, this allows us to run our UEFI bootloader, which in turn loads our kernel, in QEMU for testing.

There are two OVMF files that are needed to run QEMU with UEFI support:

1. OVMF_CODE contains the static firmware code; it is marked as a read-only drive.
2. OVMF_VARS contains the variables that may be changed whilst in use; it is marked as a read-write drive.

These can also be combined into a single OVMF file, such as the one in this repository, which has its benefits and downsides.

You can read the license for the `OVMF.fd` BLOB in the `OVMF.fd.LICENSE.txt` file.

## Licensing and Source Code Availability

This project uses the MIT License.

RandyOS started as a hard fork of [zig_os](https://codeberg.org/sfiedler/zig_os) and [loup-os](https://codeberg.org/loup-os).  LoupOS has since changed to a GPL3 license, so this was forked at the last MIT commit to preserve our license.

The source code is primarily hosted at [Codeberg](https://codeberg.org/randyos/randyos) and is mirrored on [GitHub](https://github.com/randyos-org/randyos).

## Development details

### Code organization

This repo emulates a Python packaging scheme, where each package is defined by a `__root__.zig` file (in lieu of `__init__.py`).  This shall contain mostly import statements to other files in the directory or other packages to be make public for that package.  The file containing the entry point for executables shall be named `__main__.zig`.

Package names shall be less than eight lowercased alphanumeric characters.  Where possible, filenames should strive to be kept as short as possible.  Files defining module-level structs shall use PascalCased (aka TitleCased) names.

### Building the vendored Ghostty terminal (Windows target)

On Windows, `zig build -fincremental` against the vendored Ghostty terminal in `vendor/ghostty` reliably hangs partway through a full build when using the default (full-core) job count, both with and without `--watch`. This was root-caused with gdb to an upstream Zig bug in the `-fincremental` build-runner's scheduler under concurrency: a compiler worker process finishes compiling and sits waiting for the runner to tell it to proceed to linking, while the runner's own dispatch thread is asleep waiting on an internal signal that never arrives (a "lost wakeup"). It is not caused by anything in Ghostty's own `build.zig` or build tooling.

Passing `-j4` (or lower, e.g. `-j1`) avoids the hang; `-j8` still hangs. Non-incremental builds (plain `zig build`) are unaffected. This is specific to this project's pinned Zig toolchain -- re-test if that pin ever moves.

### Windows Hypervisor Platform

To use the WHPX with QEMU, you must first open an administrative `cmd` and then run:

```bat
DISM /online /Enable-Feature /FeatureName:HypervisorPlatform /All
```

per the instruction on the [QEMU website](https://www.qemu.org/docs/master/system/whpx.html).
