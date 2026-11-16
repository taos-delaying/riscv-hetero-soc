#include "fft32_q15.h"

/* 两种实现共用这个应用；符号保留为全局，便于以后观察 RAM 中的结果。 */
int16_t fft_samples[FFT32_Q15_SCALAR_COUNT]
    __attribute__((aligned(FFT32_Q15_ALIGNMENT)));
volatile unsigned int fft_example_done;

int main(void)
{
    unsigned int n;

    fft_example_done = 0;
    for (n = 0; n < FFT32_Q15_POINTS; ++n) {
        fft_samples[2 * n] = 16384;     /* Q1.15 的 0.5 */
        fft_samples[2 * n + 1] = 0;
    }

    /* 此调用不随软件版 / 硬件版的构建选项改变。 */
    fft32_q15(fft_samples);
    fft_example_done = 1;

    /* 结果留在 RAM 中供观察；不使用旧平台的打印外设，也不触发 ebreak。 */
    for (;;) {
    }
}
