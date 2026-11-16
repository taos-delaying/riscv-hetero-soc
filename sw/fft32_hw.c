#include "fft32_q15.h"

#if !defined(__riscv)
#error "The hardware FFT backend requires a RISC-V target."
#elif __riscv_xlen != 32
#error "The current PCPI FFT interface requires RV32 addresses."
#endif

#if defined(__BYTE_ORDER__) && (__BYTE_ORDER__ != __ORDER_LITTLE_ENDIAN__)
#error "The current FFT sample packing requires little-endian memory."
#endif

void fft32_q15(int16_t *buffer)
{
    /*
     * 对应现有 pcpi_dispatch 的 32 点编码：
     * opcode = 0x2b，funct3 = 0，funct7 = {010, 0101} = 0x25。
     * rs1、rs2 使用同一地址，进行原地计算；rd=x0，不写回通用寄存器。
     * 控制器先读完 32 个样本，再计算并写回，因此输出不会覆盖未读取的输入。
     *
     * PCPI 指令阻塞到写回结束。volatile 保留此操作，memory 告诉编译器
     * 本次指令会访问、修改缓冲区，禁止使用指令前缓存的内存值。
     * memory 是编译器约束，不是硬件 cache 刷新操作；当前 SoC 没有数据 cache。
     */
    __asm__ volatile (
        ".insn r 0x2b, 0, 0x25, x0, %0, %0"
        :
        : "r" (buffer)
        : "memory"
    );
}
