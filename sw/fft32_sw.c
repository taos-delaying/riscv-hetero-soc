#include "fft32_q15.h"
#include "dsp/transform_functions.h"
#include "riscv_const_structs.h"

/* 保持现有 PicoRV32 的标量整数配置，不选择 NMSIS DSP/RVV/FPU 路径。 */
#if defined(RISCV_MATH_DSP) || defined(RISCV_MATH_VECTOR) || \
    defined(RISCV_MATH_VECTOR_ZVE32X) || defined(__riscv_vector) || \
    defined(__riscv_flen)
#error "fft32_sw requires the scalar integer NMSIS implementation."
#endif

void fft32_q15(int16_t *buffer)
{
    /*
     * NMSIS 已提供只读的 32 点配置，无需每次构造或初始化实例。
     * q15_t 是 int16_t 的别名；直接使用调用者的缓冲区，无需格式复制。
     * ifftFlag = 0：正向变换；bitReverseFlag = 1：恢复正常频点顺序。
     * 算法源码和许可证沿用 ip/picorv32/third_party/nmsis。
     */
    riscv_cfft_q15(&riscv_cfft_sR_q15_len32, buffer, 0U, 1U);
}
