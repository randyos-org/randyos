Simple Operating System in ZIG
==============================

This is a (very simple) example on how to write a bootloader that loads a kernel in the
programming language ZIG. 

It is designed to help starters understand how an operating system works, so sources are
explained well (TODO).  

Building and Running
--------------------

Linux: Just execute `run.sh`. Parameters for "zig build" can just be specified in the command, so
`./run.sh --help` produces `zig build --help`.  
Windows: Just execute `.\run.cmd`. Parameters for "zig build" are not supported right now
because I am a Linux guy and not a Windows one...  
Depends on zig (of course) and on QEMU. 

Further Information
-------------------

Licensed under GPLv3. Read it in the `LICENSE` file.  
This repository was previously the place of development for the so-called "Loup OS", for which I
have now created a separate organisation: <https://codeberg.org/loup-os>. 
