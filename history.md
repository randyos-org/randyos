History of my Zig OS
====================

Start (September 2023)
----------------------

Some months ago I searched for a faster JavaScript Runtime Environment than NodeJS and found
[Bun](https://bun.sh). Bun was written in [Zig](https://ziglang.org), which turned out to be an
awesome language for native stuff.  
I always liked challenges. I also needed them sometimes to get progress on learning something.
So I decided to start programming a little hobby operating system. I wanted to start with
programming my own bootloader and kernel.  
I started with almost zero "native" programming experience, I only programmed in JavaScript. But
I read many things about operating systems. So I searched for some projects for UEFI
bootloaders.  
I found mainly [one](https://github.com/ajxs/uefi-elf-bootloader). I started with this
bootloader as a small help and tried to write a bootloader for raw machine code completely
depending on myself. But there were some errors in my code, and a Zig panic was the cause to
exit unexpected. But I didn't saw that Zig panic, so I basically translated the code of the
GitHub Repository to Zig. Just while programming this part, it felt really awesome to be able
just to use Zig's *built-in* UEFI interface. Just while programming this part, it felt really
awesome to be able just to use Zig's *built-in* UEFI interface.  
Some small errors slowed my development down a bit: there were [incorrect
types](https://ziggit.dev/t/uefi-bootloader-correct-types/1870/1), [too small
buffers](https://ziggit.dev/t/uefi-bootloader-buffertoosmall-runtime-crash/1944/1),
[segfaults](https://ziggit.dev/t/uefi-read-file-strange-things-are-happening/1954/1), [string
formatting issues](https://ziggit.dev/t/uefi-string-formatting/2015/1), [type casting
issues](https://ziggit.dev/t/solved-cast-anyopaque-to-a-list-of-classes/2065/1), [C header
function
problems](https://ziggit.dev/t/solved-c-header-function-translated-to-zig-makes-errors/2083/1)
and [Zig panics](https://ziggit.dev/t/uefi-bootloader-err-integer-overflow/2212/1). But the
really awesome [Ziggit Forum](https://ziggit.dev) helped me a lot. 

First working version (December 2023)
-------------------------------------

Now, it's almost christmas. I tried to solve problems *three* months now, and many times I was
short before giving it up.  
But I continued. I did not give up. I searched for solutions. But I think that the thing that
brought my things to work was an awesome bootloader written in Zig. It's available on
<https://github.com/stakach/uefi-bootstrap>. This bootloader seemed not to be maintained, but it
supported virtual address mapping and anything other I could have needed. Finally I understood
the bootloading process completely (I needed some examples for that)!  
