/* Bare-metal reset entry for soc_top: RV32I, shared RAM, no IRQ or MMIO. */
    .section .text.start, "ax", @progbits
    .balign 4
    .globl _start
    .type _start, @function

_start:
    .option push
    .option norvc
    /* gp must not relax into a reference that assumes gp is already valid. */
    .option norelax
    la gp, __global_pointer$
    la sp, __stack_top

    /* soc.ld aligns both bounds to four bytes; clear all zero-initialized data. */
    la t0, __bss_start
    la t1, __bss_end
.Lclear_bss:
    bgeu t0, t1, .Lbss_ready
    sw zero, 0(t0)
    addi t0, t0, 4
    j .Lclear_bss

.Lbss_ready:
    /* .data is already at its execution address in the loaded RAM image. */
    li a0, 0
    li a1, 0
    call main

    /* No OS exit service, ebreak handler or interrupt support is assumed. */
.Lpark:
    j .Lpark
    .option pop
    .size _start, . - _start

    .section .note.GNU-stack, "", @progbits
