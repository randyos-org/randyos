# randyos

Very basic OS for a very basic dude.

This project is a fork of [zig_os](https://codeberg.org/sfiedler/zig_os).

## Requirements

* qemu
* zig

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

## What is OVMF?

[OVMF](https://github.com/tianocore/tianocore.github.io/wiki/OVMF) is an [EDK II](https://github.com/tianocore/tianocore.github.io/wiki/EDK-II)-based project that enables UEFI support on Virtual Machines. In our case, this allows us to run our UEFI bootloader, which in turn loads our kernel, in QEMU for testing.

There are two OVMF files that are needed to run QEMU with UEFI support:

1. OVMF_CODE contains the static firmware code; it is marked as a read-only drive.
2. OVMF_VARS contains the variables that may be changed whilst in use; it is marked as a read-write drive.

These can also be combined into a single OVMF file, such as the one in this repository, which has its benefits and downsides.

You can read the license for the `OVMF.fd` BLOB in the `OVMF.fd.LICENSE.txt` file.
