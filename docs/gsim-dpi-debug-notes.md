# GSIM DPI-C 支持现状 & 定位打法（知识备份）

## 现状梳理
- FIRRTL: `DiffExt*` 以 `extmodule` + `DummyDPICWrapper` 形式存在，`enable` 由 `io.valid && control.enable && !reset` 驱动（例如 `tmp-out/SimTop.fir:119954+`）。
- AST/Graph: GSIM 将 `extmodule` 解析为 `NODE_EXT`/`NODE_EXT_*`，在 `instsGenerator::computeExtMod` 中生成外部函数声明+调用（gsim/src/instsGenerator.cpp:1762-1814）。
- C++ 模型: DiffExt 调用被插在生成的 `SimTop*.cpp` 中，所属 `SuperNode` 被标记为 `SUPER_EXTMOD` 并总是 active（gsim/src/cppEmitter.cpp，调用示例 rocket-chip/build/gsim-compile/model/SimTop2.cpp:22090）。
- DPI 桥: `difftest-extmodule.cpp` 定义 `DiffExt*`，在 `enable` 为 1 时转调 `v_difftest_*`（rocket-chip/build/generated-src/difftest-extmodule.cpp:34-198）。`v_difftest_*` 写入 `diffstate_buffer`，在 `difftest_init` 中初始化（rocket-chip/build/generated-src/difftest-dpic.cpp:11-158；rocket-chip/difftest/src/test/csrc/difftest/difftest.cpp:36-59）。
- 常量折叠: `NODE_EXT` 被视为有副作用，常量传播会保留其输入（gsim/src/constantNode.cpp:986+），因此输入不会被优化掉。

## 关键问题
- GSIM 运行时 REF 端状态为 0，说明 `DiffExt*` 调用链可能未被触发（`enable` 不高或未进入 `v_difftest_*`）。Verilator 正常说明 DIF 流程/REF 端本身可用。

## 调试/分析打法
- 开关与日志：
  - `--log-level=1` 打印各阶段 begin/done；`--dump`/`--dump-stages=Init,TopoSort,...` 控制 graph dump。
  - `--dump-json`/`--dump-dot` 选择输出格式，默认两者。
- 验证 `enable`：
  - 在 `difftest-extmodule.cpp` 里临时插入打印/计数（或用新的 `--log-level` 加阶段日志）确认 `enable` 何时为 1。
  - 如 `enable` 始终 0，需回溯 `DummyDPICWrapper` 输入来源及 `control.enable`。
- 结构检查：
  - 通过 graph dump（dot/json）确认 `SUPER_EXTMOD` 存在且未被裁剪。
  - 若 graph 中缺少 EXT 节点，检查 FIR 解析（AST2Graph.extmodule 分支）或常量优化阶段。
- 数据流确认：
  - 核对生成的 `SimTop*.cpp` 中 `DiffExt*` 调用参数是否与 FIR 端口顺序一致。
  - 若 REF 侧 buffer 未初始化，检查 `difftest_init` 是否被调用（emu 主循环 args/路径差异）。

## 待验证方向
- 在 GSIM 仿真启动后插桩统计 DiffExt 调用次数/enable 状态，定位“首条指令就不一致”原因。
- 若 enable 低，进一步查 `control.enable` 来源（FIR 中 `io.valid`/reset 逻辑），排查 Chisel7 升级带来的差异。
