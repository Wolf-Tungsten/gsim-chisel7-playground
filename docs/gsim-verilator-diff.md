# Verilator vs GSIM 仿真差异定位

## 问题描述
- `make run-verilator-emu`：执行到若干指令后在 1000 周期未提交告警后终止（见终端日志）。
- `make run-gsim-emu`：首条指令即与 REF 不一致，`t0`、`mstatus`、`sstatus` 等全为 0，立即 ABORT。

## 定位思路
- DiffTest 框架依托 DPI-C 接口实现 DUT 与 REF 之间的状态对比，目前问题在于 GSIM 对于 DPI-C 没有妥善支持，导致 REF 端状态无法正确传递到 DUT 端。
- 当前，GSIM 刚刚升级了对 Chisel 7 的支持，很可能是该升级过程导致了问题。
- 请你从 GSIM 对 DPI-C 的支持入手，定位该问题的根因并给出解决方案。
- 在开始工作前，请你为 gsim 添加可配置的详细日志打印、graph dump json等功能，便于后续定位问题。
- 在开始工作前，请你先结合 gsim 代码 和 tmp-out/SimTop.fir 案例，分析 gsim 目前对 DPI-C 的支持情况，给出分析报告。

## 追加定位发现（2025-12-23）
- 已在 GSIM 构建生成的 `difftest-extmodule.cpp` 加入 enable 日志，确认多数 DiffExt（InstrCommit/StoreEvent 等）始终 `enable=0`，但部分如 TrapEvent/CSRState/ArchEvent/RegState 在复位后能被拉高，说明 enable 逻辑本身不是全局失效。
- Graph dump（SimTop_1TopoSort.json）显示 `mstatus` 从 core CSR 经 `gatewayIn_packed_8_bore -> gatewayIn$$8 -> endpoint$in$$8 -> … -> endpoint$module_6$dpic$io$$mstatus -> DiffExtCSRState` 的连接是存在的。
- 生成的 GSIM C++ 模型中，这些 EXT 输入被每周期清零而未赋值：例如 `SimTop2.cpp:19374-19381` 将 `endpoint__DOT__module_6__DOT__dpic__DOT__io__DOT__mstatus` 置 0，文件内无其他赋值，最终以 0 传入 `DiffExtCSRState`（SimTop2.cpp:22119）。类似清零行为覆盖了 sstatus/mepc 等其他 CSR。
- 推断：EXT 输入赋值在 instsGenerator/cppEmitter 中被裁剪或优化掉，导致 DiffExt 侧只看到常 0 数据，是 GSIM 与 Verilator 差异的关键原因。下一步需修复 EXT 输入的生成/保留逻辑。 

