CPU + PCPI FFT：在 Vivado 界面中手动仿真
========================================

本目录只提供 tb_soc_fft.sv 测试台和本说明，不再提供或依赖 Tcl 运行脚本。
本次仅修改并人工审阅源文件，没有代你运行编译、展开、仿真或综合。

一、配置测试台
--------------
打开 D:/taosh/Documents/vivado/riscv-hetero-soc/sim/tb_soc_fft.sv。
文件开头有三个配置项：
  FIRMWARE_IMPL：先保持 "sw"；测试硬件版时改为 "hw"。
  PROJECT_ROOT：当前已设为 D:/taosh/Documents/vivado/riscv-hetero-soc。
                搬动仓库时才需修改，路径使用正斜杠。
  MAX_CYCLES：默认1000000，含程序完成后128周期观察窗口。

TB 根据所选模式自动读取 build/fft32/sw 或 build/fft32/hw 中的
firmware.hex 与 firmware.map。二者必须来自同一次软件构建。
MAP 用于寻找完成标志和结果缓冲区；HEX 用于初始化 SRAM。
TB 使用 $fgets 逐行读取 HEX，将十六进制字符转换为32位字，写入本地数组。
支持 LF/CRLF、首尾空格/TAB和空行；每个非空行必须只有1..8位十六进制数字。
这是当前 makehex.py 的逐字格式，不接受 Intel HEX、@地址、注释或X/Z。
字数必须恰好为16384，不能缺少或超出；检查通过后再复制到 SRAM 并回读比较。
本测试台不再调用 $readmemh，DUT 的 MEM_INIT_FILE 仍为空，避免重复加载。
ELF 保留用于软件调试，不需要添加为仿真源文件。
不需要设置 plusargs，也不需要设置 soc_top 的 MEM_INIT_FILE。

二、新建或使用 Vivado 工程
-------------------------
若已有合适的工程，可以继续使用；否则选择 Create Project，类型选 RTL Project。
建议工程名 soc_fft_sim，放在仓库的 vivado 目录，勾选 Create project subdirectory。
可以勾选 Do not specify sources at this time，之后按下列步骤添加源文件。
器件选择你计划使用的 FPGA；当前设计的行为仿真不依赖特定器件原语。
本阶段无需 XDC、Run Synthesis、Run Implementation 或 Generate Bitstream。

三、添加设计源文件
------------------
点击 Add Sources -> Add or Create Design Sources -> Add Files。
添加以下文件；已经添加的文件不用重复添加：
  D:/taosh/Documents/vivado/riscv-hetero-soc/rtl/picorv32_new.v
  D:/taosh/Documents/vivado/riscv-hetero-soc/rtl/pcpi_dispatch.v
  D:/taosh/Documents/vivado/riscv-hetero-soc/rtl/soc_sram_dp.v
  D:/taosh/Documents/vivado/riscv-hetero-soc/rtl/soc_top.v
  D:/taosh/Documents/vivado/riscv-hetero-soc/ip/fft/fft32_dit2.v
  D:/taosh/Documents/vivado/riscv-hetero-soc/ip/fft/fft16_dit2.v
  D:/taosh/Documents/vivado/riscv-hetero-soc/ip/fft/fft8_dit2.v
  D:/taosh/Documents/vivado/riscv-hetero-soc/ip/fft/fft4_dit4.v
  D:/taosh/Documents/vivado/riscv-hetero-soc/ip/fft/butterfly_radix2_dit.v
  D:/taosh/Documents/vivado/riscv-hetero-soc/ip/fft/common_func.vh

取消 Copy sources into project，以便 VS Code 中修改的仓库源文件直接生效。
不需要添加旧的 picorv32.v、FFT64/128 等模块或独立 FFT 的旧测试台。
FFT32 内部使用 FFT16/8/4，因此上述较小点数模块仍需要添加。
common_func.vh 的 File Type 保持 Verilog Header，不要勾选 Global Include：
它包含放在模块内部的函数定义，由相关 RTL 的 `include 引入。
在 Sources 的 Design Sources 中，将 soc_top 设为顶层（右键 Set as Top）。

四、添加仿真源文件和 include 路径
---------------------------------
再次点击 Add Sources -> Add or Create Simulation Sources -> Add Files。
选择 D:/taosh/Documents/vivado/riscv-hetero-soc/sim/tb_soc_fft.sv。
取消 Copy sources into project，保留 Include all design sources for simulation。
文件类型应是 SystemVerilog，不要把 .sv 改为 .v。
在 Sources -> Simulation Sources 下右键 tb_soc_fft，选择 Set as Top。

打开 Settings -> Simulation -> Compilation，在 Verilog 的 include 搜索路径中添加：
  D:/taosh/Documents/vivado/riscv-hetero-soc/ip/fft
具体标签随 Vivado 版本略有不同，一般为 Verilog Include Files Search Paths。
Target Simulator 选择 Vivado Simulator，保存设置。
HEX/MAP 使用 TB 中的绝对路径读取，不需要另外导入为 HDL 源文件。

五、运行软件版
--------------
确认 FIRMWARE_IMPL 为 "sw"，保存测试台。
点击 Flow Navigator -> Simulation -> Run Simulation -> Run Behavioral Simulation。
Vivado 会根据工程中的文件执行语法检查、展开并打开仿真界面。
如果只运行了默认的一小段时间，没有 PASS/FAIL，点击仿真工具栏的 Run All。
时钟周期为10ns，默认最多约10ms仿真时间；这不是实际等待的墙钟时间。

测试台自行检查完成标志、trap、访存错误、FFT 完成脉冲和全部32个结果。
在 Tcl Console 或仿真日志中查看输出，预期通过格式为：
  [SOC FFT PASS] mode=sw program_cycles=实际周期数 fft_done_count=0
这是预期格式，不是已经运行得到的结果。检查完成后 TB 调用 $finish。
本版本不再生成脚本专用的 result.txt；以当前仿真中的 PASS/FAIL 输出为准。
旧 build/soc_sim 目录中的日志是历史结果，不代表这次 GUI 运行。

六、查看波形
------------
在 Scope 选择 tb_soc_fft，在 Objects 选择信号，右键 Add to Wave Window：
  clk、resetn、completion_value、sample0_value、fft_cycles_value、fft_done_count、cycles。
在 dut 层可添加 pcpi_valid/pcpi_wait/pcpi_ready、pcpi_insn、pcpi_rs1，
以及 fft_sram_en/we/addr/wdata/rdata、trap、mem_fault。
cpu 层的 reg_pc 表示 CPU 当前程序计数器；fft 层有 FFT_STATE 和 fft_counter。
若信号是运行后才加入的，要看从零时刻开始的波形，点击 Restart，再点击 Run All。
Restart 仅重新运行当前已展开的设计；它不会把新修改的源文件重新编译进去。

七、切换硬件版
--------------
关闭当前仿真（Close Simulation），在 VS Code 中把 FIRMWARE_IMPL 改为 "hw" 并保存。
再次点击 Run Simulation -> Run Behavioral Simulation，打开后按需点击 Run All。
不要只点击 Restart，否则可能仍运行上一次编译的软件版 TB。
硬件版预期通过格式为：
  [SOC FFT PASS] mode=hw program_cycles=实际周期数 fft_done_count=1

八、结果含义与报错
------------------
当前程序的32个输入均为0.5+j0，正向 FFT，固定总缩放1/32。
预期 k=0 的实部原始整数为16384、虚部为0，其余31个频点都为0。
这一次通过验证当前测试向量的完整执行通路，不代表全部输入和连续任务已验证。
program_cycles 包括启动、输入填充、调用等，不能当作 FFT 硬件核本身的延迟。

解析/展开失败：查看 Messages 或相应日志中的第一条 ERROR。
运行出现 [SOC FFT FAIL]：保留该行及前后输出。
Cannot open MAP/HEX：核对 PROJECT_ROOT、模式，以及两个文件是否存在。
HEX read failed / invalid character / word count mismatch 等：文件读取或格式检查失败，
错误会报告行号、列号或实际字数；此时尚未写入 SRAM。
Parsed HEX buffer is unknown：解析计数已通过，但本地数组仍有未知值。
RAM copy failed：本地镜像已经通过检查，但写入 SRAM 后回读不一致。
本版本启动时会打印 HEX loader=line-by-line (LF/CRLF accepted)。
解析成功会打印 HEX parsed: words=16384 以及第0、1和最后一个字。
加载成功会打印 Loaded and verified 16384 RAM words。
若仍在初始化阶段失败，请保留 HEX loader、HEX parsed（如有）、此前警告和完整 FAIL 行。
超时：查看完成标志和 reg_pc，不要只靠增加 MAX_CYCLES 绕过。
若 common_func.vh 找不到：检查 Compilation 中的 include 搜索路径。

此前脚本运行的已有日志显示：语法检查和展开已完成，但 XSim 报
“Expected a switch but found s”，说明当次在解析启动参数时退出，测试尚未执行。
当前手动流程已取消脚本和 plusargs 依赖；仍需你实际启动仿真确认运行结果。

九、分解硬件FFT调用的周期
-------------------------
沿用已经打印 fft_cycles 的两版固件；本次只更新测试台及本说明，无需重新编译C程序。
测试台仍需MAP中的fft_cycles符号。分析硬件版时把 FIRMWARE_IMPL 设为 "hw"，
关闭当前仿真，再次 Run Behavioral Simulation -> Run All。
本监测器针对当前“读取计数器、调用一次FFT、再次读取计数器”的例程。

计时方式：在时钟上升沿、RTL非阻塞赋值更新之前读取CPU的count_cycle。
当CPU处于cpu_state_ld_rs1并执行instr_rdcycle时，捕获计数器实际取值，
随后于上升沿后1ns核对CPU的reg_out。两次取值之差必须等于RAM中的fft_cycles。
这不会改变CPU、FFT或SRAM的任何输入和状态，不会给被测硬件增加运行周期。

硬件模式记录8个时刻，按相邻时刻差打印7项，单位均为周期：

输出字段                      开始 -> 结束
cpu_before_request            第一次计数器取值 -> 控制器首次采样到FFT32请求
request_to_first_read         首次FFT32请求 -> SRAM采样首个读请求
input_read_and_capture        首个读请求 -> 控制器捕获第32个有效输入
controller_compute_window     第32个输入捕获 -> 控制器进入COMPUTE_END并设置写使能
result_writeback              设置写使能 -> SRAM采样第32次结果写入
writeback_to_ack              第32次写入 -> CPU在上升沿采样valid&&ready完成握手
ack_to_end_counter            完成握手 -> 第二次计数器实际取值

这些区间覆盖两次计数器取值之间的时间，不重叠，不留空隙；相邻时间戳作差，
不要为每个区间额外加1。result_writeback包含写使能设置后等待首个写入沿的时间。
controller_compute_window是控制器安排的计算等待窗口；当前FFT核没有独立的
输出有效握手，不能仅凭这个数字证明纯蝶形电路的最短计算延迟。

成功时先打印 [SOC FFT TIMING]，然后打印7行 [SOC FFT PHASE]，最后打印：
  [SOC FFT PHASE] total=实际总和 fft_cycles=固件测量值 match=YES
这两个值必须完全相等。对之前测得104周期的同一硬件固件，预期两者仍为104；
本次未代你运行，具体各阶段数字以你重新仿真的输出为准。
原来的 [SOC FFT PERF] 与 [SOC FFT PASS] 输出也保留。
软件版只做两次计数器差值的核对，不打印硬件阶段分解。

另外输出 [SOC FFT TRAFFIC]：
  sram_read_requests       两次计数器取值之间的物理SRAM读请求数
  input_captures           由read_valid使能的有效输入捕获数，当前例程应为32
  sram_write_requests      实际SRAM全字写入数，当前例程应为32
  reads_after_inputs_ready 最后一次有效输入捕获之后，后续上升沿上的读请求数

TRAFFIC是事务次数，不是额外时间，不能叠加到7个阶段的周期总和中。
读请求和有效输入捕获未必一一对应：当前状态机在最后输入捕获沿仍可能发出
未使用的下一地址读请求，写回后回到IDLE时译码信号也可能尚未清零而继续发读。
因此测试台检查捕获32个输入、写入32个结果，但不强制物理读请求只能是32次。
最后输入捕获同一沿的读请求不计入reads_after_inputs_ready，它属于之前的取数阶段。

原有“FFT completion pulse at cycle ...”在上升沿后1ns观察完成电平出现；
新ACK边界记录CPU在上升沿真正采样该电平的时刻，物理上通常相隔一拍。
新时间戳使用CPU计数器，原日志使用TB的cycles，两者复位释放基准也不同，
不应直接相减；阶段计算全部统一使用CPU计数器。

波形中可以添加 phase_cycle、phase_seen、counter_read_count、sram_read_requests、
input_captures、sram_write_requests、reads_after_inputs。phase_cycle[0..7]按上表
从第一次计数器取值到第二次取值排列。若以后改动CPU或控制器内部状态机，
需要同步检查测试台的观察条件；当前监测仅面向现有RTL。

官方操作参考
------------
https://docs.amd.com/r/2021.1-English/ug900-vivado-logic-simulation/Adding-or-Creating-Simulation-Source-Files
