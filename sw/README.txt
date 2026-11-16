统一 FFT32 软件接口
==================

本目录提供一个接口、两份实现、同一份应用示例，以及适配当前 soc_top 的裸机启动和构建规则。
本次仅写入并审阅源码；没有运行编译、链接、镜像转换、仿真或测试，实际产物尚未生成。

接口
----
    void fft32_q15(int16_t *buffer);

两份实现都使用这一声明。应用包含本目录的 fft32_q15.h，然后调用同一个函数。
每次链接只选择一种实现。两个实现文件不能同时直接加入同一个程序。

数据约定
--------
- 固定 32 点正向复数 FFT，原地计算；返回后结果已写回 buffer。
- buffer 为 64 个 int16_t，排列为 re0, im0, re1, im1, ...，共 128 字节。
- 输入为 Q1.15；将输出按同样格式解释时，总体结果为 FFT(input)/32。
- 输出按正常频率顺序 k=0..31 排列。
- 缓冲区至少 4 字节对齐；当前 SoC 中必须完整位于 64 KiB 共享 RAM 内，
  起始字节地址不超过 0x0000ff80，并避开代码、栈和其他正在使用的数据。
- 函数不做参数检查；调用者负责提供有效缓冲区。
- NMSIS 与 RTL 的定点截断、饱和过程不同，不保证任意输入逐位相同。
  后续做软硬件数值对照时，需要明确允许的误差，或进一步对齐运算过程。

文件
----
fft32_q15.h    公共接口、数据约定和长度常量。
fft32_sw.c     软件实现，调用已有 NMSIS；使用固定只读的 32 点配置，免去运行时初始化。
fft32_hw.c     硬件实现，发出 32 点 PCPI 自定义指令。
example_main.c 相同的应用示例，填充输入后调用 fft32_q15，不含实现选择分支。
start.S        地址 0 的复位入口；初始化 gp/sp，清零 BSS，调用 main。
soc.ld         64 KiB RAM 的链接布局、4 KiB 栈预留和静态区域越界检查。
runtime.c      最小 memcpy/memset/memmove/memcmp，不依赖操作系统或外设。
Makefile       用 FFT_IMPL=sw 或 hw 选择实现，生成 ELF、BIN、HEX 和 MAP。

软件版与硬件版
--------------
软件版直接复用 ip/picorv32/third_party/nmsis 中已导入的源文件，不复制或修改库。
q15_t 与 int16_t 是相同类型，因此调用时不需要样本格式转换。
保留 NMSIS 的 Apache-2.0 许可证及源文件头；依赖版本见该目录的 SOURCE.txt。

硬件版使用 GNU 内联汇编：
    .insn r 0x2b, 0, 0x25, x0, 源地址寄存器, 目的地址寄存器

具体实现将同一指针同时作为 rs1 和 rs2，rd=x0。
funct7=0x25 对应现有 dispatcher 的 bits[31:29]=010、bits[28:25]=0101。
控制器先读取全部样本，再计算和写回，因而可按原地计算的接口组织。
PCPI ready 结束指令；返回后才继续执行调用者的后续指令，不需要软件轮询。
asm volatile 和 memory clobber 描述了指令副作用和对缓冲区的读写。
硬件版要求 RV32、小端、外部 PCPI 已启用且连接当前 FFT 控制器。
该实现不检查硬件是否存在，也不在缺少硬件时自动切换到软件版。

构建选择（供你后续自行执行）
----------------------------
在项目根目录执行，使用 GNU Make、Python 3 和提供 mkdir/mv 的 POSIX shell，适用于服务器或 WSL：

    make -C sw FFT_IMPL=sw TOOLCHAIN_PREFIX=/home/taoshuo/tools/picorv32-gcc-10.2.0-1.2/bin/riscv-none-embed-
    make -C sw FFT_IMPL=hw TOOLCHAIN_PREFIX=/home/taoshuo/tools/picorv32-gcc-10.2.0-1.2/bin/riscv-none-embed-

工具链前缀应按实际安装调整。前缀含 riscv64 也可以，但该工具链必须支持
-march=rv32i -mabi=ilp32，并提供标准头文件和匹配 RV32I/ILP32 的 libgcc。
不能用带 M/C 指令的运行库来代替 RV32I 运行库。构建还使用该前缀下的 ar 和 objcopy。
需要改变 Python 命令时可传 PYTHON=python3 或本机实际命令。
这里不使用原 ip/picorv32/Makefile，也不会启动其中的仿真目标。

软件版的预期产物：
    build/fft32/sw/firmware.elf
    build/fft32/sw/firmware.bin
    build/fft32/sw/firmware.hex
    build/fft32/sw/firmware.map

硬件版的预期产物：
    build/fft32/hw/firmware.elf
    build/fft32/hw/firmware.bin
    build/fft32/hw/firmware.hex
    build/fft32/hw/firmware.map

各自目录中还保留 .o、.d 和 libfft32_q15.a 作为中间文件。
默认目标 all 生成完整 ELF 和 HEX；也可指定 elf、hex 或 library 单独构建相应阶段。
两份程序由相同的 start.S、example_main.c 和 soc.ld 构建，差别是所链接的 FFT 实现。
软件库包含所需 NMSIS 目标文件，硬件库仅包含自定义指令封装。
两版都使用基础 RV32I/ILP32，与当前 soc_top 默认 CPU 配置一致；本例不使用 rdcycle。
硬件版可用 .insn 显式编码自定义指令，不需要给 -march 添加一个虚构的 FFT 扩展。
切换 sw/hw 使用不同目录；如果更换工具链或其他编译参数，需要重新构建对应目标文件。

启动和内存布局
--------------
链接脚本对应 soc_top 的默认 PROGADDR_RESET=0x00000000、STACKADDR=0x00010000。
若以后更改硬件的地址范围或启动地址，应同时调整此脚本和启动约定。

    0x00000000              _start，随后是程序代码
    代码之后                常量表、初始化全局数据、零初始化全局数据/FFT 缓冲区
    静态区域末尾～0x0000efff 未使用空间，无堆分配器
    0x0000f000～0x0000ffff   保留 4 KiB，供栈向低地址增长
    0x00010000              初始 sp，位于 RAM 末尾后一字节

启动代码先初始化 gp/sp，再按字清零 .bss（包括 .sbss 和 COMMON），然后调用 main。
gp 的初始化禁止链接松弛，以免使用尚未初始化的 gp。代码只使用 RV32I 指令。
如果 main 返回，启动代码会停在循环中，不执行 ebreak、退出系统调用或 IRQ 操作。

代码、常量和 .data 的加载地址就是运行地址（LMA=VMA），已包含在 HEX 中，
无需从 ROM 再复制 .data。.bss 和栈是 NOLOAD，不占 BIN 的有效载入内容。
链接脚本检查入口、对齐和静态区域边界；静态区域超过 0xF000 时链接失败。
4 KiB 栈仅为预留值，链接断言不能检查运行中的栈深度；本次未验证实际峰值。

硬件复位不会重载 RAM。启动代码会重新清零 .bss，但不会把已经改写的 .data
恢复为镜像中的初始值；需要恢复完整初始内容时，应重新加载 HEX 或重新配置 FPGA。
当前示例的样本和完成标志属于 .bss，因此每次进入 main 都会重新填充输入。

链接与镜像格式
--------------
    start.o + example_main.o + runtime.o + 所选 FFT 库 + RV32I libgcc -> ELF
    ELF -> objcopy 原始 BIN -> makehex.py 转换和填充 -> HEX

构建使用 -nostdlib 和自有启动文件，同时显式链接 -lgcc 提供软件乘法等支持函数。
runtime.c 提供可能出现的内存操作，并单独禁止将循环优化成对同名函数的递归调用。
构建使用函数/数据分节及 --gc-sections，仅保留实际使用的 NMSIS 函数与表格。
这里没有 C 标准库的完整平台支持，也没有堆、TLS、构造函数或 C++ 异常运行时。

复用 ip/picorv32/firmware/makehex.py，填充参数是 16384 个 32 位字，即 64 KiB。
HEX 每行是一个字，按小端顺序把 BIN 中连续四个字节组成八位十六进制数。
例如 BIN 中的 13 00 00 00 对应 HEX 行 00000013；第 0 行装入 RAM 字地址 0。
这是 $readmemh 的字格式，不是 Intel HEX 格式，不能将 ELF 文件直接交给 $readmemh。
未占用的 RAM 字填零；生成 HEX 时先写临时文件，转换成功后才替换目标文件。

在 soc_top 中加载
----------------
将 soc_top 的 MEM_INIT_FILE 参数设为所选 firmware.hex 的实际路径。
Vivado 中建议使用带正斜杠的绝对路径，避免工具运行目录变化导致找不到文件。
例如，硬件版在本地项目中的预期位置为：
    D:/taosh/Documents/vivado/riscv-hetero-soc/build/fft32/hw/firmware.hex
软件版则将路径中的 hw 换成 sw；如果在服务器构建，需要先将产物放到实际加载路径。

本次没有更改 soc_top 的 MEM_INIT_FILE 默认值，它仍为空；生成文件后需选择要加载的版本。
硬件版要求当前 FFT PCPI 已连接；软件版也可在同一套带 FFT 的电路上运行。
使用 RAM 配置初始化时，更新 HEX 后还需让 FPGA 配置中的 RAM 初值同步更新，单纯复位
CPU 不会重新读取电脑上的 HEX 文件。外部 resetn 至少覆盖一个时钟上升沿。

调用示例说明
------------
example_main.c 将 32 个样本填成 0.5+j0，调用统一接口，然后停留在循环中。
fft_samples 保留计算结果，fft_example_done 从 0 变为 1 表示函数已返回。
可从对应 firmware.map 找到这两个符号的地址，供以后观察 RAM 内容使用。
完成标志只表示函数返回，不表示数值校验已通过。示例没有打印、计时或数值断言。
生成规则已补齐，但因本次未执行构建或运行，尚不声称固件已经编译通过或在硬件上验证。

汇编语法参考
------------
https://sourceware.org/binutils/docs/as/RISC_002dV_002dFormats.html
https://sourceware.org/binutils/docs/as/RISC_002dV_002dDirectives.html
https://gcc.gnu.org/onlinedocs/gcc/Extended-Asm.html
https://gcc.gnu.org/onlinedocs/gcc/Link-Options.html
