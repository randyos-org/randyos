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
Thanks a lot to the two following GitHub repos:

  - <https://github.com/ajxs/uefi-elf-bootloader>
  - <https://github.com/stakach/uefi-bootstrap>
