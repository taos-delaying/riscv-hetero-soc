/*
 * soc_top default memory map: 64 KiB RAM starting at zero.
 * The top 4 KiB is reserved for a downward-growing, 16-byte-aligned stack.
 * Text, constants and initialized data are loaded by the HEX image directly
 * at their execution addresses (LMA = VMA); there is no separate ROM copy.
 */
OUTPUT_ARCH(riscv)
OUTPUT_FORMAT("elf32-littleriscv")
ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 64K
}

__stack_size = 4K;
__stack_top = ORIGIN(RAM) + LENGTH(RAM);
__stack_bottom = __stack_top - __stack_size;

SECTIONS
{
    .text ORIGIN(RAM) :
    {
        KEEP(*(.text.start))
        *(.text .text.* .gnu.linkonce.t.*)
        . = ALIGN(4);
    } > RAM

    .rodata ALIGN(4) :
    {
        *(.rodata .rodata.* .srodata .srodata.* .gnu.linkonce.r.*)
        . = ALIGN(4);
    } > RAM

    .data ALIGN(4) :
    {
        __data_start = .;
        *(.data .data.* .gnu.linkonce.d.*)
        . = ALIGN(4);
        __global_pointer$ = . + 0x800;
        *(.sdata .sdata.* .sdata2 .sdata2.*)
        . = ALIGN(4);
        __data_end = .;
    } > RAM
    __image_end = .;

    .bss ALIGN(4) (NOLOAD) :
    {
        __bss_start = .;
        *(.sbss .sbss.* .sbss2 .sbss2.* .scommon)
        *(.bss .bss.* .gnu.linkonce.b.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > RAM
    __static_end = .;

    /* Reserve the stack without adding its bytes to the loadable binary. */
    .stack __stack_bottom (NOLOAD) :
    {
        . = . + __stack_size;
    } > RAM

    /* Retain ISA metadata in ELF, without allocating it in the RAM image. */
    .riscv.attributes 0 : { *(.riscv.attributes) }

    /* This C-only startup does not provide exception unwinding. */
    /DISCARD/ :
    {
        *(.comment .note.GNU-stack)
        *(.eh_frame .eh_frame.* .eh_frame_hdr .gcc_except_table .gcc_except_table.*)
    }
}

ASSERT(_start == ORIGIN(RAM), "Reset entry must be at address 0")
ASSERT(__static_end <= __stack_bottom, "Code/data/BSS exceed 60 KiB; stack would overlap")
ASSERT((__bss_start & 3) == 0 && (__bss_end & 3) == 0, "BSS must be word-aligned")
ASSERT((__image_end & 3) == 0, "Loadable image must end on a word boundary")
ASSERT((__stack_top & 15) == 0, "Stack top must satisfy the ILP32 ABI alignment")
