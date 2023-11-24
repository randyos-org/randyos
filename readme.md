Simple Operating System in ZIG
==============================

This is a (very simple) example on how to write a bootloader that loads a kernel in the
programming language ZIG. 

Building and Running
--------------------

Just execute `run.sh`. Parameters for "zig build" can just be specified in the command, so
`./run.sh --help` produces `zig build --help`.  
Depends on zig (of course) and on QEMU. 

Further Information
-------------------

Contact me at <samuel.fiedler@proton.me>.  
Licensed under GPLv3. Read it in the `LICENSE` file.  
The version scheme is MAJOR.MINOR.PATCH.  
**Currently, the code does not work. It will have problems with physical addresses. I will add
the version tags after the first working version. Any help is appreciated. "**  
This is, as of the current version, basically <https://github.com/ajxs/uefi-elf-bootloader>
written in ZIG. 
