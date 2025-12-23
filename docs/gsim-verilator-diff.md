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

## 进一步定位（2025-02-15）
- 将 `SimTop.fir` 拷贝到 `tmp-out` 后直接运行 `gsim --dump`，查看 `SimTop_*dot`：在 `SimTop_3ExprOpt.dot` 仍能看到 CSR 信号连接 `module_6.io.bits.mstatus -> dpic.io.mstatus -> DiffExtCSRState`，但 `SimTop_4ConstantAnalysis.dot` 起这些边消失，最终 `SimTop_12Final.dot` 只剩 `enable -> DiffExtCSRState`。
- 生成的 `tmp-out/SimTop1.cpp:28057-28059` 因此把所有 CSR/整数/浮点状态参数都替换成字面量 `0x0`，对应 `tmp-out/SimTop.h:2248-2266` 等数据字段虽然声明但已不再驱动。
- 根因：GSIM 的 `constantAnalysis`/`removeConstant` 把 `DiffExt*` 视为无副作用的外设函数，常量折叠时仅保留 `enable`，将各 payload 端口折叠为常量 0，导致 DiffTest 初始状态全零。修复方向是为 `NODE_EXT`/`OP_EXT_FUNC` 或其子端口打上“保留 side-effect”标记，避免对 DiffTest 端口做常量折叠。
- 为何 EXT 会被折叠：`visitExtModule` 将 extmodule 的 `valTree` 构造成 `OP_EXT_FUNC`，输入端口仅作为参数，没有任何输出端口或副作用标记；`constantAnalysis`/`Node::computeConstant` 在这种“无用户、无输出”的模式下把 `OP_EXT_FUNC` 当作死逻辑，折叠为常量并清空 `assignTree`，后续 `removeDeadNodes` 只保留仍被引用的 `enable`，其它 payload 端口被裁剪，从而最终生成的 C++ 里参数全变成 0。

## 修复计划（草案）
1. **确认保护范围**：枚举 `DiffExt*` 外设（CSR/Int/Fp RegState、InstrCommit 等），决定是否用名字匹配或在 FIR -> AST 时为这类 extmodule 打标签。
2. **阻止常量折叠**：在 `constantAnalysis`/`removeConstant` 入口检查 `NODE_EXT` 或 `OP_EXT_FUNC`：
   - 方案 A：给 `Node` 增加 `noFold`/`hasSideEffect` 标志，在 `AST2Graph` 创建 extmodule 时根据 defname/params置位；`constantAnalysis` 跳过这些节点和其子端口的常量传播/删除。
   - 方案 B：在 `ExpTree::removeConstant` 等地方检测 `OP_EXT_FUNC`，保持原连接不替换成常量。
3. **保留信号连接**：确保 extmodule 内的 `NODE_EXT_IN` 输入不会被标记为 `CONSTANT_NODE`，同时不要清空 `assignTree`，以便 `instsGenerator` 生成带真实参数的调用。
4. **验证生成结果**：本地运行 `gsim --dump` 对比 `SimTop_3ExprOpt.dot` 与修复后的 `SimTop_4ConstantAnalysis.dot`，确认 `DiffExt*` 的 payload 边不再消失；检查生成的 `SimTop1.cpp` 中 `DiffExt*` 调用参数不再为零。
5. **运行回归**：`make run-gsim-emu` 与 verilator 对比，确认首条指令不再立即失配；若有进一步差异，再迭代修复。

## 修复尝试（2025-02-15）
- 实施：在 `Node::computeConstant`（`gsim/src/constantNode.cpp`）对 `isExt()` 节点直接返回 `VAL_INVALID`，避免被 `constantAnalysis` 视为可折叠的常量，保留 DiffExt 的输入依赖。重新 `make build-gsim` 编译。
- 结果：重新在 `tmp-out` 运行 `gsim --dump` 生成模型，`SimTop1.cpp:28133-28135` 中 `DiffExtCSRState`/`DiffExtArchIntRegState`/`DiffExtArchFpRegState` 的参数恢复为真实信号，不再是全 0 字面量；DOT 图 `SimTop_4ConstantAnalysis.dot` 之后仍保留 payload 边。
- 状态：初始 DiffTest 参数已恢复，但 `make run-gsim-emu` 仍存在问题（待进一步排查）。
