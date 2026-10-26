/*
 * MicroBlaze V co-processor memory: 128 KB of local memory at 0 (the same
 * block RAM the A53 sees at 0x8010_0000).
 *   0x0_0000 .. 0x0_FFFF  program, data, bss
 *   0x1_0000 .. 0x1_BFFF  shared buffer: the A53 puts work data here
 *   0x1_F000 .. 0x1_FFFF  stack (4 KB)
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    PROG  (rwx) : ORIGIN = 0x00000000, LENGTH = 64K
    STACK (rw)  : ORIGIN = 0x0001F000, LENGTH = 4K
}

SECTIONS
{
    .text : {
        KEEP(*(.text.start))
        *(.text .text.*)
    } > PROG
    .rodata : { *(.rodata .rodata.* .srodata .srodata.*) } > PROG
    .data   : { *(.data .data.* .sdata .sdata.*) } > PROG
    .bss (NOLOAD) : {
        __bss_start = .;
        *(.bss .bss.* .sbss .sbss.* COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > PROG
    __global_pointer$ = ADDR(.data) + 0x800;
    __stack_top = ORIGIN(STACK) + LENGTH(STACK);
    /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.note*) }
}
