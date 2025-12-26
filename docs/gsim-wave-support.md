# GSIM 波形支持

为 GSIM 添加 FST 格式的波形支持。

## 参考资料

### FST 格式及 FST 库

- 参考项目 `zyj-gsim` 自带开源 `libfst`（`zyj-gsim/include/libfst/fstapi.h/.c`），通过 `fstWriterCreate(<name>.fst, 1)` 创建上下文，`fstWriterClose` 关闭；`gsim/` 目前尚未引入该库。
- 层次结构：用 `fstWriterSetScope(FST_ST_VCD_MODULE, "...")` 进入/退出 scope，信号句柄用 `fstWriterCreateVar` 创建并保存在 `fstHandleMap`，数组元素名字追加 `[idx]`。
- 写入内容：每个信号更新时调用 `fstWriterEmitValueChange32/64/Vec64`，只写当前值（变化检测由调用侧决定）；init 阶段 `emitAllSignalValues()` 先把全量初值写出，避免 x/z。
- 大位宽：`width<=32` 走 `ValueChange32`，`<=64` 走 `ValueChange64`，更大用 `ValueChangeVec64` 直接写 `uint64_t*`，都会先按位宽掩码。
- memory/数组：定义阶段逐维循环创建 handle，更新阶段同样嵌套循环，按元素名 `signal[i][j]` 分别写值。
- 时间信息：init 后先 `fstWriterEmitTimeChange(..., 0)`，每个 `step()` 末尾 `fstWriterEmitTimeChange(..., cycles)`，即以周期为单位推进时间轴。

### GSIM 插入波形的机会

- 层次保留：直接使用 FIRRTL 生成的节点名，按 `$` 拆成 scope，末级作为信号名；句柄变量名将 `$` 替换为 `_` 防止 C++ 命名冲突（`cppEmitter.cpp:1278-1346`）。
- 插入位置：`init()` 中创建 FST 文件并定义所有信号/数组句柄；`emitAllSignalValues()` 在 time=0 发一遍全量值；每个 super block 生成代码的 `SUPER_INFO_ASSIGN_END` 分支在信号被计算后调用 `updateFstSignal` 写波形；`step()` 末尾推进时间戳（`cppEmitter.cpp:900-951,1084-1104`）。
- clock/reset：被当作普通节点处理，init/emitAllSignalValues 会写初值，`step()` 开头的 `resetAll()`/内部对 `reg_reset` 的赋值后也会触发对应信号的 `updateFstSignal`。
- 不同信号类型：生成句柄时 reg/mem 用 `FST_VT_VCD_REG`，其他节点用 `FST_VT_VCD_WIRE`；数组/memory 逐元素生成；大宽度信号用 Vec64 写入。

## 实施目标

- 为 gsim 增加可选的 FST 波形输出能力，生成的 C++ 仅在用户显式开启时包含波形代码。
- 波形只覆盖优化后的、最终出现在生成 `top.h`（DUT 成员）的信号/存储体；内部临时节点不导出，保持性能。
- 运行时接口保持简单：`step(bool dumpWaveform=false)`，调用侧可按区间置 `true` 控制输出。
- 封装 libfst 为单头文件（如 `gsimFst.h`），避免额外链接步骤，便于生成代码直接 `#include`。
- 层次结构在优化完成后用变量名按 `$` 拆分重建，不影响优化流程。

## 实施方案

- 约束：当前实现细节基于 `zyj-gsim` 代码，用作参考。正式落地要改动的目录是 `gsim/`（编译器、生成器、Makefile 等），不要直接修改 `zyj-gsim/`。
- 现状缺口：`gsim/` 目录下目前没有 `libfst` 源码、也没有 `FST_WAVE` 编译开关或 `fstCtx` 字段/接口，`step(bool)` 也尚未存在。需引入 `zyj-gsim/include/libfst` 并封装成单头文件供生成代码使用，同时补齐编译开关与接口。
- `cppEmitter` 侧：在生成的 C++ 中（受 `FST_WAVE` 控制）注入 `fstCtx`/`fstHandleMap`、`fstWriterCreate`、timescale/version 填充，按 `$` 层次调用 `fstWriterSetScope` 创建 scope，并为所有节点/数组生成 `fstHandle`，最后 `fstWriterEmitTimeChange(...,0)`+`emitAllSignalValues()` 写初值。波形只覆盖最终出现在顶层生成的 `top.h`（即 DUT 类成员）的变量，内部临时/未导出节点无需写出，避免冗余；由于 gsim 会在生成前做优化/合并，导出集应基于优化后的节点集重建，层次结构也由优化后保留下来的变量名按 `$` 拆分恢复，而不是在优化前强行保留层次影响优化效果。信号写入沿用 super/block 调度，在 `SUPER_INFO_ASSIGN_END` 后调用 `updateFstSignal`，虽然增加一次调用/判断开销，但能避免无关写入；采用“激活就写”策略，不维护影子值，`dumpWaveform` 为假时不写。
- `step` 签名改为 `void step(bool dumpWaveform = false)`，将 `fstWriterEmitTimeChange` 和本周期的 `updateFstSignal`/`emitAllSignalValues` 包在 `if (dumpWaveform)` 中，用户可在指定周期范围内传 `true` 控制波形输出。
- 构建/开关：`gsim/` 需要引入 `libfst` 源，建议打包成单头文件（如 `gsimFst.h`）的 header-only 形式，供生成的 C++ 直接 `#include`，避免额外静态库/链接步骤，简化系统。提供类似 Verilator 的命令行开关（如 `--trace-fst`）在 FIR -> C++ 生成阶段决定是否内联波形代码；加了开关则在生成的 C++ 中包含 FST 字段/句柄/调用，未加则完全不带以避免性能开销。`FST_WAVE` 宏或同等编译开关待设计。
- 使用：接口形态为 `dut.step(bool dumpWaveform)`，调用时传 `true` 输出当前周期波形，`false` 则跳过；生成文件名/输出目录可沿用现有 gsim 约定，后续设计确定。

## 实施步骤

1) 封装 FST 依赖：将 `zyj-gsim/include/libfst` 整理为单头文件 `gsimFst.h`（含 writer API、必要的压缩实现），确保可直接 include，无外部链接依赖。
2) 编译开关与 CLI：在 gsim 编译入口增加 `--trace-fst`选项，配合编译宏控制是否在生成的 C++ 中注入波形代码。
3) Emitter 接入：在 `cppEmitter` 中受开关控制生成 `fstCtx`/`fstHandleMap` 字段、scope/handle 定义、`emitAllSignalValues`、`updateFstSignal` 等初始化/写值逻辑，层次按优化后节点名拆 `$` 重建。
4) 接口调整：将 DUT `step()` 改为 `step(bool dumpWaveform=false)`，在 `dumpWaveform` 为真时发 `fstWriterEmitTimeChange` 和本周期信号写入；其余路径保持零开销。
5) 选择导出集：只导出最终出现在生成 `top.h` 的字段（寄存器/线网/存储体），跳过内部临时节点，确保文件尺寸与性能可控。
6) 测试验证：复用现有 gsim 测试样例，添加新的 makefile 目标和测试脚本，验证波形文件生成正确，内容符合预期。
7) 文档更新：完善 gsim 用户文档，说明如何启用波形支持、使用 `step(bool)` 接口，以及生成文件的位置和格式。


