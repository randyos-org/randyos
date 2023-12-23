Simple Operating System in ZIG
==============================

This is a (very simple) example on how to write a bootloader that loads a kernel in the
programming language ZIG. 

Building and Running
--------------------

Linux: Just execute `run.sh`. Parameters for "zig build" can just be specified in the command, so
`./run.sh --help` produces `zig build --help`.  
Windows: Just execute `.\run.cmd`. Parameters for "zig build" are not supported right now
because I am a Linux guy and not a Windows one...  
Depends on zig (of course) and on QEMU. 

Comments
--------

  - exitBootServices may fail, then you just have to quit QEMU and restart it

Further Information
-------------------

Contact me at <samuel.fiedler@proton.me>.  
Licensed under GPLv3. Read it in the `LICENSE` file.  
Read the project history in the `history.md` file.  
The version scheme is MAJOR.MINOR.PATCH.  
Thanks a lot to the following two GitHub repos:

  - <https://github.com/ajxs/uefi-elf-bootloader>
  - <https://github.com/stakach/uefi-bootstrap>
