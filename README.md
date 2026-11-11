# riscv-hetero-soc

基于 RISC-V 的可扩展异构计算与硬件任务调度平台。

当前通过 Git subtree 集成 FFT_DSE 和 PicoRV32 的已提交源码。后续沿用统一 PCPI 适配器连接多个计算核，逐步加入硬件任务调度。当前导入不代表 CPU 与 FFT 已完成硬件连接。

## 目录

- `ip/fft/`：FFT_DSE 原仓库，包括 FFT RTL、测试台和 OOC 约束。
- `ip/picorv32/`：PicoRV32 原仓库，包括 CPU RTL、示例与许可文件。

## 导入版本

| 子树 | 来源 | 分支 | 导入提交 |
| --- | --- | --- | --- |
| `ip/fft` | https://github.com/taos-delaying/FFT_DSE.git | `main` | `429ef1f7cb9eb7b0548291be95a826d3873debb2` |
| `ip/picorv32` | https://github.com/taos-delaying/picorv32.git | `main` | `f0c135aba637fa90c2dc361a91e17170122233d1` |

两次导入均使用 `--squash`。保留原仓库已经跟踪的内容和许可声明。

## 同步上游

在项目根目录、工作区干净时执行：

```powershell
git subtree pull --prefix=ip/fft fft-upstream main --squash
git subtree pull --prefix=ip/picorv32 picorv32-upstream main --squash
```

普通克隆已包含两个 IP 的源码，不需要额外初始化。新克隆若需要同步上游，先添加远程：

```powershell
git remote add fft-upstream https://github.com/taos-delaying/FFT_DSE.git
git remote add picorv32-upstream https://github.com/taos-delaying/picorv32.git
```

修改 FFT 子树后，将其与系统集成逻辑分开提交。需要回传时可推到 FFT 仓库的独立分支：

```powershell
git subtree push --prefix=ip/fft fft-upstream integration/fft-update
```

当前未设置总项目的 `origin`，也未推送到远程。

## 工程使用

FFT 源码引用 `common_func.vh`，编译时将 `ip/fft` 加入 include 搜索路径。按所需顶层显式选择源码，不要将所有测试台一起加入综合或仿真。`fft_ooc_100mhz.xdc` 用于 FFT 独立综合，不能直接作为未来 SoC 顶层约束。

原来的两个本地仓库（包括各自 `.git` 和被忽略的本地配置）保存在本机 `.git/subtree-backups/FFT_DSE` 和 `.git/subtree-backups/picorv32`，用于恢复；不进入提交，也不会随普通克隆传播。
