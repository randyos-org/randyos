/**
 * This is our linker script for the kernel.
 * Something like this always exists for any normal target, but our kernel is
 * freestanding. So we have to say the linker how it should behave.
 *
 * STUB: copied from the x86_64 linker script as a roadmap placeholder.
 * KERNEL_PHYS_START is not yet chosen for real arm hardware (Raspberry Pi 3,
 * 32-bit mode) -- revisit once this arch has an actual boot story.
 */

/* We want the kernel to start at 1M (0x100000). */
KERNEL_PHYS_START = 1M;
/* This is how big our stack should be.  */
KERNEL_STACK_SIZE = 0x4000;
TRAP_STACK_SIZE = 16K;
TRAP_DATA = 1K;

/* Our main function has the name "kmain", instead of the POSIX default
 * "_start". */
/* ENTRY(kmain) */
ENTRY(_start)

/* Any executable has some so-called sections. The ".text" section, for
 * example, holds the code. */
SECTIONS {
    /* Previously, we set a *variable* where wee want our kernel to start. Now,
     * we use that variable and say the linker "start with everything at
     * 0x100000". */
    . = KERNEL_PHYS_START;
    __kernel_start = .;

    /* dedicated start section so we can ensure that everything related to startup always lies at the correct address */
    .start : ALIGN(4K) {
        __kernel_boot_info = .;
        . += 8;
        KEEP(*(.start*));
    }
    .start = KERNEL_PHYS_START;

    /* Then, we include the text section. As said above, it holds the code we
     * will execute. The "ALIGN(4K)" ensures that everything is
     * 4KB-page-aligned, because in the bootloader we allocate pages for our
     * program.
     */
    .text : ALIGN(4K) {
        __trap_handler_start = .;
        __trap_handler_end = .;
        __text_start = .;
        *(.text*)
        __text_end = .;
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

        /* As you can see here, we include our 16KB kernel stack (where our
         * function-scoped variables and information about function calls are
         * stored). */
        . = ALIGN(16);
        __stack_bottom = .;
        . += KERNEL_STACK_SIZE;
        __stack_top = .;
        __trap_stack_bottom = .;
        . += TRAP_STACK_SIZE;
        __trap_stack_top = .;
        __trap_data = .;
        . += TRAP_DATA;
    }

    /* DWARF debug info */
    .debug_info : ALIGN(4K) {
        __debug_info_start = .;
        KEEP(*(.debug_info*))
        __debug_info_end = .;
    }

    .debug_abbrev : ALIGN(4K) {
        __debug_abbrev_start = .;
        KEEP(*(.debug_abbrev*))
        __debug_abbrev_end = .;
    }

    .debug_str : ALIGN(4K) {
        __debug_str_start = .;
        KEEP(*(.debug_str*))
        __debug_str_end = .;
    }

    .debug_line : ALIGN(4K) {
        __debug_line_start = .;
        KEEP(*(.debug_line*))
        __debug_line_end = .;
    }

    .debug_ranges : ALIGN(4K) {
        __debug_ranges_start = .;
        KEEP(*(.debug_ranges*))
        __debug_ranges_end = .;
    }

    .debug_str_offsets : ALIGN(4K) {
        __debug_str_offsets_start = .;
        KEEP(*(.debug_str_offsets*))
        __debug_str_offsets_end = .;
    }

    .debug_line_str : ALIGN(4K) {
        __debug_line_str_start = .;
        KEEP(*(.debug_line_str*))
        __debug_line_str_end = .;
    }

    .debug_loclists : ALIGN(4K) {
        __debug_loclists_start = .;
        KEEP(*(.debug_loclists*))
        __debug_loclists_end = .;
    }

    .debug_rnglists : ALIGN(4K) {
        __debug_rnglists_start = .;
        KEEP(*(.debug_rnglists*))
        __debug_rnglists_end = .;
    }

    .debug_addr : ALIGN(4K) {
        __debug_addr_start = .;
        KEEP(*(.debug_addr*))
        __debug_addr_end = .;
    }

    .debug_names : ALIGN(4K) {
        __debug_names_start = .;
        KEEP(*(.debug_names*))
        __debug_names_end = .;
    }

    __kernel_end = .;
}
