/**
 * This is our linker script for the kernel. 
 * Something like this always exists for any normal target, but our kernel is
 * freestanding. So we have to say the linker how it should behave.
 */

/* We want the kernel to start at 1M (0x100000). */
KERNEL_PHYS_START = 1M;
/* This is how big our stack should be.  */
KERNEL_STACK_SIZE = 0x4000;

/* Our main function has the name "kmain", instead of the POSIX default
 * "_start". */
ENTRY(kmain)

/* Any executable has some so-called sections. The ".text" section, for
 * example, holds the code. */
SECTIONS {
    /* Previously, we set a *variable* where wee want our kernel to start. Now,
     * we use that variable and say the linker "start with everything at
     * 0x100000". */
    . = KERNEL_PHYS_START;

    /* Then, we include the text section. As said above, it holds the code we
     * will execute. The "ALIGN(4K)" ensures that everything is
     * 4KB-page-aligned, because in the bootloader we allocate pages for our
     * program. 
     */
    .text : ALIGN(4K) {
        *(.text*)
    }

    /* The rodata section contains data for the executable that already has
     * some value (often non-zero), but is read-only. */
    .rodata : ALIGN(4K) {
        *(.rodata*)
    }

    /* The data section contains data for the executable that already has some
     * value (often non-zero) and it's readable and writable. */
    .data : ALIGN(4K) {
        *(.data*)
    }

    /* The bss section contains data for the executable that does not have any
     * value (often zero) and it's readable and writable. */
    .bss : ALIGN(4K) {
        *(COMMON)
        *(.bss*)

        /* As you can see here, we inlude our 16KB kernel stack (where our
         * function-scoped variables and information about function calls are
         * stored). */
        . = ALIGN(16);
        . += KERNEL_STACK_SIZE;
    }
}
