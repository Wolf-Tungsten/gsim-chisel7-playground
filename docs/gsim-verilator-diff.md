# Verilator vs GSIM 仿真差异定位

## 问题描述
- `make run-gsim-emu` 与 `make run-verilator-emu` 均能跳转到 `0x80000000` 并跑到约 2529 条指令后在 `pc=0x2` ABORT，最后 trace 均为 `pc=0` 的异常（cause=1）。首条指令 diff 已消除。

## 定位结果
- gsim 在 `splitNodes` 阶段会将带符号常量零扩展成无符号，导致 `mem_npc` 屏蔽常量 `SInt<2>(-0h2)` 被翻译成 `0x2`。已通过为 `NodeElement` 记录 sign、按位宽做符号化等方式修复。
- 重新生成模型后，`SimTop1.cpp` 的计算变为 `& (int8_t)0xfe`，首跳与 Verilator 对齐，剩余 ABORT 为两边共同现象（需另行定位）。
