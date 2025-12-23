# Verilator vs GSIM 仿真差异定位

## 运行结果
- `make run-verilator-emu`：执行到若干指令后在 1000 周期未提交告警后终止（见终端日志）。
- `make run-gsim-emu`：首条指令即与 REF 不一致，`t0`、`mstatus`、`sstatus` 等全为 0，立即 ABORT。

## 关键发现
- GSIM 生成的模型把若干 DiffTest 状态端口裁剪掉，只保留了 `enable`。在生成的 `rocket-chip/build/gsim-compile/model/SimTop.h` 中，`DiffExtCSRState`/`DiffExtArchIntRegState`/`DiffExtArchFpRegState` 仅有 `enable` 成员（如 `SimTop.h:3293-3295`），没有任何寄存器/CSR 数据字段。
- 相应地，GSIM 运行时调用 DiffTest 导出函数时把所有状态参数都传成 0（`rocket-chip/build/gsim-compile/model/SimTop1.cpp:27996-27998`）。因此 REF 看到的初始寄存器和 CSR 状态全是零，导致首条指令就与 Spike 差异。
- Verilator 版本保留了完整的 DPI 模块和状态信号，所以能继续执行到后续阶段（虽然后面仍有独立问题），差异源于 GSIM 侧 DiffTest 信号被优化掉。

## 结论
GSIM 前端在处理仅用于 DiffTest 的外设模块（`DiffExt*`）时，把其输入信号视为无用逻辑并在生成 C++ 模型时裁剪为常量 0，导致 DiffTest 初始状态错误，从而与 Spike 立即失配。

