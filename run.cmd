@echo off
rem This is a batch script which first builds the operating system and then runs it. 

rem Using this command, we build the operating system, but at the command line we can specify 
rem additional arguments to build the system with. 
zig build
rem Here, we check that the exit code of the previous command is 0, so we ensure that the build 
rem command succeeded. 
if errorlevel 0 (
    rem After that, we create the directory "systemroot/efi/boot" and all of its parent 
    rem directories. 
    mkdir systemroot\
    mkdir systemroot\efi\
    mkdir systemroot\efi\boot\
    rem Now, we copy the bootloader executable to a folder that will be recognized by UEFI. 
    copy zig-out\bin\bootx64.efi systemroot\efi\boot\
    rem Here, we copy the kernel executable to a custom location
    copy zig-out\bin\kernel systemroot\kernel.elf
    rem With this command, we start QEMU (a computer emulator) with UEFI as firmware (`-bios OVMF.fd`),
    rem an emulated FAT drive with "systemroot" as directory and the standard output mapped to the COM1. 
    rem Doing so will allow us to see messages from the operating system directly on our console. 
    qemu-system-x86_64 -bios OVMF.fd -hdd fat:rw:systemroot -serial mon:stdio -display gtk -s
)
