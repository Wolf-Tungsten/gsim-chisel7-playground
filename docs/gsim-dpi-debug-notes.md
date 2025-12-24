# GSIM DPI-C 支持现状 & 定位打法（知识备份）

# GSIM DPI-C 支持现状 & 定位打法（知识备份）

## 现状梳理
- FIRRTL: `DiffExt*` 以 `extmodule` + `DummyDPICWrapper` 形式存在，`enable` 由 `io.valid && control.enable && !reset` 驱动（例如 `tmp-out/SimTop.fir:119954+`）。
- AST/Graph: GSIM 将 `extmodule` 解析为 `NODE_EXT`/`NODE_EXT_*`，在 `instsGenerator::computeExtMod` 中生成外部函数声明+调用（gsim/src/instsGenerator.cpp:1762-1814）。
- C++ 模型: DiffExt 调用被插在生成的 `SimTop*.cpp` 中，所属 `SuperNode` 被标记为 `SUPER_EXTMOD` 并总是 active（gsim/src/cppEmitter.cpp，调用示例 rocket-chip/build/gsim-compile/model/SimTop2.cpp:22090）。
- DPI 桥: `difftest-extmodule.cpp` 定义 `DiffExt*`，在 `enable` 为 1 时转调 `v_difftest_*`（rocket-chip/build/generated-src/difftest-extmodule.cpp:34-198）。`v_difftest_*` 写入 `diffstate_buffer`，在 `difftest_init` 中初始化（rocket-chip/build/generated-src/difftest-dpic.cpp:11-158；rocket-chip/difftest/src/test/csrc/difftest/difftest.cpp:36-59）。
- 常量折叠: `NODE_EXT` 被视为有副作用，常量传播会保留其输入（gsim/src/constantNode.cpp:986+），因此输入本不应被优化掉。

## 关键问题定位
- enable 侧：插桩日志显示部分 DiffExt（TrapEvent/CSRState/ArchEvent/RegState）复位后能拉高，enable 逻辑非全失效。
- 数据侧：TopoSort 阶段图中 mstatus 的实际链路存在——`gatewayIn_packed_8_bore -> gatewayIn$$8 -> endpoint$in$$8 -> ... -> endpoint$deltas$$6$$bits$$mstatus -> endpoint$module_6$io$$bits$$mstatus -> endpoint$module_6$dpic$io$$mstatus -> DiffExtCSRState`（边见 SimTop_1TopoSort.json）。
- ConstantAnalysis 后（SimTop_2ConstantAnalysis.json）上游边 `endpoint$module_6$io$$bits$$mstatus -> endpoint$module_6$dpic$io$$mstatus` 消失，仅剩 dpic 输入直连 DiffExt；graphPartition/Final 同样如此，说明在 ConstantAnalysis/RemoveDeadNodes 阶段上游被裁剪。
- 生成 C++ 中，`endpoint__DOT__module_6__DOT__dpic__DOT__io__DOT__mstatus` 每次激活都被置 0（SimTop2.cpp:19374-19381），无其他赋值，最终以 0 传给 DiffExtCSRState（22119 行）。其它 CSR 字段同理——上游被剪后 cppEmitter 清零悬空输入。
- 结论：关键差异在数据流；ConstantAnalysis/RemoveDeadNodes 把 dpic 上游（mstatus 等）判为无效/常量，导致 EXT 输入被清零，REF 端看到全 0。

## 调试/分析打法
- 阶段对比：使用 `--dump-stages=Init,TopoSort,ConstantAnalysis,...` 导出 JSON，对比关键信号边是否在 ConstantAnalysis 后被删除。
- C++ 验证：查 `SimTop*.cpp` 中 dpic 输入是否只有清零语句；如无上游赋值，则数据流已断。
- 保护措施思路：在 constantNode/removeDeadNodes 中特殊处理 EXT 输入，或确保 dpic enable/valid 不被推成常 0，避免上游被裁剪。
