## gsim 常量符号缺失问题排查记录（截至当前进展）

目标：修复 gsim 将 FIRRTL 中的 `SInt<2>(-0h2)` 错误翻译成无符号 `0x2`，导致 `mem_npc` 只保留 bit1（&0x2）而不是清零 LSB（&(-2)）。

### 已尝试修改
- **常量节点符号保持（前序修补）**
  - `ExpTree/allocIntEnode` 支持显式 sign 并从 `-` 前缀推断。
  - `constantNode`、`consInt`、`instsInt` 在负数字面量时保持 sign 并按二补码折叠/生成。
- **根因定位 & 修复**
  - 发现符号在 `splitNodes` 阶段被抹掉：`NodeElement::updateWidth` 对负数直接做掩码，组件值被零扩展成正数，重建表达式时常量变成 `0x2`。
  - 为 `NodeElement` 增加 `sign` 标记；构造/合并时保留符号，并在 `updateWidth` 里按指定位宽做符号化（调用 `s_asSInt`）。`inferComponent(OP_INT)` 创建常量组件时传入 ENODE 的 sign。

### 当前反馈/现象
- 重新生成 gsim 模型后，`SimTop1.cpp` 中 `mem_npc` 计算已变为与 RTL 一致的 `((int64_t)... & (int8_t)0xfe)`，FIRRTL 里的 `SInt<2>(-0h2)` 保持为带符号常量 `-2`。
- gsim 首跳现在落到 `0x80000000`，与 Verilator 行为一致；二者都能跑到约 2529 条指令后在 `pc=0x2` 共同 ABORT，首条指令 diff 已消除，后续失败需另行排查。

### 后续建议
1) 针对两边共同的 ABORT（pc=0x2，cause=1）继续定位：对比 gsim/verilator trace，检查异常向量、入口指令与参考 spike 的差异。  
2) 若需要可精简 `tmp-out/gsim-debug-dumps*` 调试产物，避免后续跑分受干扰。  
