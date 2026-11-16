#ifndef RISCV_HETERO_SOC_FFT32_Q15_H
#define RISCV_HETERO_SOC_FFT32_Q15_H

#include <stdint.h>

enum {
    FFT32_Q15_POINTS = 32,
    FFT32_Q15_SCALAR_COUNT = 64,
    FFT32_Q15_BYTES = 128,
    FFT32_Q15_ALIGNMENT = 4
};

/*
 * 统一接口：32 点正向复数 FFT，原地覆盖，返回时计算已经完成。
 *
 * buffer 包含 64 个 int16_t，依次为 re[0], im[0], re[1], im[1], ...。
 * 输入按 Q1.15 解释；输出按相同格式解释时为 FFT(input) / 32，
 * 频点顺序为 k = 0, 1, ..., 31。
 *
 * 调用者必须提供有效、可读写、至少 4 字节对齐的连续 128 字节缓冲区。
 * 在当前 SoC 上，整个缓冲区必须位于共享 RAM 内，起始字节地址不超过
 * 0x0000ff80，且不能覆盖代码或其他仍在使用的数据。函数不检查这些条件。
 * 当前小端存储中，每个 32 位字的低 16 位是实部，高 16 位是虚部。
 *
 * 每次构建只链接 fft32_sw.c 或 fft32_hw.c 中的一种实现。
 * 软件版和硬件版采用各自的定点截断/饱和过程，不承诺所有输入逐位相同。
 */
void fft32_q15(int16_t *buffer);

#endif
