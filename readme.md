Simple Operating System in ZIG
==============================

This is a (very simple) example on how to write a bootloader that loads a kernel in the
programming language ZIG.

It is designed to help starters understand how an operating system works, so sources are
explained well.  
If you want to improve the explanations, feel free to open an issue or a pull request!

Building and Running
--------------------

Just run `zig build` to build the bootloader and kernel.

If you have `qemu-system-x86_64` installed, then you can run `zig build qemu` to build and
run the kernel. It sets up a directory in the build cache to use as the emulated FAT disk
and runs QEMU using it.

By default, it will use the combined OVMF file found in this repository. You can also choose
to provide your own OVMF files in two ways:

  1. Supply `-Dovmf-code` with a combined OVMF file.
  2. Supply `-Dovmf-code` and `-Dovmf-vars` with separate OVMF_CODE and OVMF_VARS files,
     respectively.

All OVMF files used by `zig build qemu` will be copied so that their original versions are
not modified. You can access the copied files in the build cache in the same directory used
as the FAT boot drive.

As of now, the tagged Zig releases are targeted. This project is known to work with the
following Zig versions:

  - 0.15.1 (current project status)
  - 0.14.1 (commit 60034b0 in this project)
  - 0.14.0 (commit 60034b0 in this project)

What is OVMF?
-----------------------

[OVMF](https://github.com/tianocore/tianocore.github.io/wiki/OVMF) is an
[EDK II](https://github.com/tianocore/tianocore.github.io/wiki/EDK-II)-based project that
enables UEFI support on Virtual Machines. In our case, this allows us to run our UEFI
bootloader, which in turn loads our kernel, in QEMU for testing.

There are two OVMF files that are needed to run QEMU with UEFI support:

  1. OVMF_CODE contains the static firmware code; it is marked as a read-only drive.
  2. OVMF_VARS contains the variables that may be changed whilst in use; it is marked as a
     read-write drive.

These can also be combined into a single OVMF file, such as the one in this repository,
which has its benefits and downsides.

Further Information
-------------------

This work is licensed under the MIT License. Read it in the `LICENSE` file.  
You can read the license for the `OVMF.fd` BLOB in the `OVMF.fd.LICENSE.txt` file.  
This repository was previously the place of development for the so-called "Loup OS", for which I
have now created a separate organisation: <https://codeberg.org/loup-os>.
