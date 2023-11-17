#!/bin/bash

zig build $@
if [ $? -eq 0 ]; then
  cp zig-out/bin/bootx64.efi systemroot/efi/boot/
  cp zig-out/bin/kernel systemroot/kernel.elf
  qemu-system-x86_64 -bios OVMF.fd -hdd fat:rw:systemroot -serial mon:stdio -display gtk -s
fi
