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
and runs QEMU using it. You are expected to pass it the `OVMF_CODE[.m4].fd` and
`OVMF_VARS[.m4].fd` via the `-Dovmf-code` and `-Dovmf-vars` options, respectively.

As of now, the tagged Zig releases are targeted. This project is known to work with the
following Zig versions:

  - 0.15.1 (current project status)
  - 0.14.1 (commit 60034b0 in this project)
  - 0.14.0 (commit 60034b0 in this project)

Further Information
-------------------

This work is licensed under the MIT License. Read it in the `LICENSE` file.
You can read the license for the `OVMF.fd` BLOB in the `OVMF.fd.LICENSE.txt` file.
This repository was previously the place of development for the so-called "Loup OS", for which I
have now created a separate organisation: <https://codeberg.org/loup-os>.
