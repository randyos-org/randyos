zig build
if errorlevel 0 (
  copy zig-out\bin\bootx64.efi systemroot\efi\boot\
  copy zig-out\bin\kernel systemroot\kernel.elf
  qemu-system-x86_64 -bios OVMF.fd -hdd fat:rw:systemroot -serial mon:stdio -display gtk -s
)
