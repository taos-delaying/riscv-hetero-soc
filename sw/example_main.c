#include "fft32_q15.h"

/* 两种实现共用这个应用；符号保留为全局，便于以后观察 RAM 中的结果。 */
int16_t fft_samples[FFT32_Q15_SCALAR_COUNT]
    __attribute__((aligned(FFT32_Q15_ALIGNMENT)));
volatile unsigned int fft_example_done;
volatile uint32_t fft_cycles;

static inline __attribute__((always_inline)) uint32_t read_cycle32(void)
{
    uint32_t value;

    /*
     * 编码等价于 rdcycle，即 csrrs rd, 0xc00, x0。
     * .insn i 的立即数为有符号12位，-1024 对应位模式0xc00。
     * 使用原始格式以兼容当前 -march=rv32i 的构建选项；CPU 必须开启
     * ENABLE_COUNTERS。volatile 保留读取，memory 约束计时边界两侧的访存。
     */
    __asm__ volatile (
        ".insn i 0x73, 0x2, %0, x0, -1024"
        : "=r" (value)
        :
        : "memory"
    );
    return value;
}

int main(void)
{
    unsigned int n;
    uint32_t start_cycle;
    uint32_t end_cycle;

    fft_example_done = 0;
    fft_cycles = 0;
    for (n = 0; n < FFT32_Q15_POINTS; ++n) {
        fft_samples[2 * n] = 16384;     /* Q1.15 的 0.5 */
        fft_samples[2 * n + 1] = 0;
    }

    /* 输入准备在计时区间之外；两版在相同的统一接口前后读取计数器。 */
    start_cycle = read_cycle32();
    fft32_q15(fft_samples);
    end_cycle = read_cycle32();

    /*
     * 先结束计时，再保存结果并通知 TB。无符号减法允许计数器低32位回绕，
     * 前提是测量区间少于2^32周期。该原始测量值含调用/返回和计时开销，
     * 没有扣除空区间基线；硬件版还包括PCPI及SRAM读取/写回。
     */
    fft_cycles = end_cycle - start_cycle;
    fft_example_done = 1;

    /* 结果留在 RAM 中供观察；不使用旧平台的打印外设，也不触发 ebreak。 */
    for (;;) {
    }
}
