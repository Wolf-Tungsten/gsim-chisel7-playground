# GSIM DPI-C 关键断点（mstatus/privilege）

## 结论
- reg 源 `cpu$ldut$tile_prci_domain$element_reset_domain$rockettile$core$csr$reg_mstatus$$prv` 与 EXT 端 `endpoint$module_6$dpic$io$$mstatus` 始终存在，链路在中途被两次剪掉。
- 第一次：splitNodes 之后的 `removeDeadNodes` pass1 未保活 difftest 别名，删除 `csr$_io_difftest_privilegeMode_T`/`csr$io$$difftest$$privilegeMode`/`difftest_1$$privilegeMode`/`difftest_bundle_1$$privilegeMode`（`tmp-out/debug-dumps-pass1/gsim.log:119455-119458`，`gsim/src/deadNodes.cpp:85-93`）。此时 reg/EXT 仍在，但 difftest 段断链。
- 第二次：ConstantAnalysis 将剩余 gateway/endpoint 别名视为常量并删除（`tmp-out/debug-dumps-pass1/gsim.log:314350-314362`，`gsim/src/constantNode.cpp` 内部 `removeNodes(CONSTANT_NODE)`）。此后仅剩 reg 与 EXT 输入，链路彻底断开。
- pass1 删除原因：在 `AfterSplitNodes` 图中，这 4 个 difftest 别名只互相串联（reg_mstatus$$prv → csr$_io_difftest_privilegeMode_T → csr$io$$difftest$$privilegeMode → difftest_1$$privilegeMode → difftest_bundle_1$$privilegeMode），没有继续连接到 `difftest_packed_1/gatewayIn_packed_8_bore` 侧（无出边），导致从输出/EXT 种子回溯时不可达，故被 RemoveDeadNodes1 视为 dead。
- 下游缺失说明：`difftest_bundle_1$$privilegeMode` 在 `AfterSplitNodes` 就没有任何出边（仅有一条入边来自 `difftest_1$$privilegeMode`，无消费者），`RemoveDeadNodes1` 时入边也被剪掉，导致该节点及其上游被视作孤立链路。
- SplitNodes 对 `_difftest_packed_T_2` 的 OP_CAT 被折成单个 8bit `coreid`：`AfterSplitNodes` 中 `_difftest_packed_T_2`/`difftest_packed_1`/`gatewayIn_packed_8_bore` 的 assignTree 仅保留 8 位 coreid（其余 1152 位丢失）。这是因为 splitNodes 基于 usedBits/segment 判断该总线只有低 8 位被后续使用，自动裁剪掉其他 CAT 片段，导致 difftest 打包向下游只输出 8 位，也解释了下游链路被视为“无消费者”。需要复查 splitNodes 的 cut/segment 逻辑或 usedBits 种子，避免错误地认为 CAT 其他字段未被使用。



## 阶段存在性（tmp-out/debug-dumps-pass1）
- `AfterSplitNodes`：链路完整（reg → difftest → gatewayIn → endpoint → dpic）。
- `RemoveDeadNodes1`：difftest 四个别名缺失，其余仍在。
- `ConstantAnalysis`：gateway/endpoint 侧别名缺失，只余 reg 与 EXT 输入。

## 复现命令
`./gsim/build/gsim/gsim --dump-json --dump-assign-tree --dump-const-status --dump-stages=Init,TopoSort,AfterSplitNodes,RemoveDeadNodes1,ConstantAnalysis --dir tmp-out/debug-dumps-pass1 --log-level=2 tmp-out/SimTop.fir`

## JSON确证

cpu$ldut$tile_prci_domain$element_reset_domain$rockettile$core$_difftest_packed_T_2

tmp-out/debug-dumps-pass1/SimTop_2RemoveDeadNodes.json
```
{"name": "cpu$ldut$tile_prci_domain$element_reset_domain$rockettile$core$_difftest_packed_T_2", "type": "NODE_OTHERS", "super": 17622, "assignTrees": [{"root": 0, "lvalue": 1, "nodes": [
      {"id": 0, "op": "OP_CAT", "width": 1160, "sign": 0, "isClock": 0, "reset": 0, "children": [2, 3]},
      {"id": 1, "op": "OP_EMPTY", "width": 1160, "sign": 0, "isClock": 0, "reset": 0, "node": "cpu$ldut$tile_prci_domain$element_reset_domain$rockettile$core$_difftest_packed_T_2", "children": []},
      {"id": 2, "op": "OP_CAT", "width": 1152, "sign": 0, "isClock": 0, "reset": 0, "children": [4, 5]},
      {"id": 3, "op": "OP_EMPTY", "width": 8, "sign": 0, "isClock": 0, "reset": 0, "node": "cpu$ldut$tile_prci_domain$element_reset_domain$rockettile$core$difftest_bundle_1$$coreid", "children": []},
      {"id": 4, "op": "OP_CAT", "width": 1088, "sign": 0, "isClock": 0, "reset": 0, "children": [6, 7]},
      {"id": 5, "op": "OP_EMPTY", "width": 64, "sign": 0, "isClock": 0, "reset": 0, "node": "cpu$ldut$tile_prci_domain$element_reset_domain$rockettile$core$difftest_bundle_1$$medeleg", "children": []},
      {"id": 6, "op": "OP_CAT", "width": 1024, "sign": 0, "isClock": 0, "reset": 0, "children": [8, 9]},
      {"id": 7, "op": "OP_EMPTY", "width": 64, "sign": 0, "isClock": 0, "reset": 0, "node": "cpu$ldut$tile_prci_domain$element_reset_domain$rockettile$core$difftest_bundle_1$$mideleg", "children": []},
      {"id": 8, "op": "OP_CAT", "width": 960, "sign": 0, "isClock": 0, "reset": 0, "children": [10, 11]},
      {"id": 9, "op": "OP_EMPTY", "width": 64, "sign": 0, "isClock": 0, "reset": 0, "node": "cpu$ldut$tile_prci_domain$element_reset_domain$rockettile$core$difftest_bundle_1$$sscratch", "children": []},
      {"id": 10, "op": "OP_CAT", "width": 896, "sign": 0, "isClock": 0, "reset": 0, "children": [12, 13]},
      {"id": 11, "op": "OP_EMPTY", "width": 64, "sign": 0, "isClock": 0, "reset": 0, "node": "cpu$ldut$tile_prci_domain$element_reset_domain$rockettile$core$difftest_bundle_1$$mscratch", "children": []},
      {"id": 12, "op": "OP_CAT", "width": 832, "sign": 0, "isClock": 0, "reset": 0, "children": [14, 15]},
      {"id": 13, "op": "OP_EMPTY", "width": 64, "sign": 0, "isClock": 0, "reset": 0, "node": "cpu$ldut$tile_prci_domain$element_reset_domain$rockettile$core$difftest_bundle_1$$mie", "children": []},
      {"id": 14, "op": "OP_CAT", "width": 768, "sign": 0, "isClock": 0, "reset": 0, "children": [16, 17]},
      {"id": 15, "op": "OP_EMPTY", "width": 64, "sign": 0, "isClock": 0, "reset": 0, "node": "cpu$ldut$tile_prci_domain$element_reset_domain$rockettile$core$difftest_bundle_1$$mip", "children": []},
      {"id": 16, "op": "OP_CAT", "width": 704, "sign": 0, "isClock": 0, "reset": 0, "children": [18, 19]},
      {"id": 17, "op": "OP_EMPTY", "width": 64, "sign": 0, "isClock": 0, "reset": 0, "node": "cpu$ldut$tile_prci_domain$element_reset_domain$rockettile$core$difftest_bundle_1$$satp", "children": []},
      {"id": 18, "op": "OP_CAT", "width": 640, "sign": 0, "isClock": 0, "reset": 0, "children": [20, 21]},
      {"id": 19, "op": "OP_EMPTY", "width": 64, "sign": 0, "isClock": 0, "reset": 0, "node": "cpu$ldut$tile_prci_domain$element_reset_domain$rockettile$core$difftest_bundle_1$$scause", "children": []},
      {"id": 20, "op": "OP_CAT", "width": 576, "sign": 0, "isClock": 0, "reset": 0, "children": [22, 23]},
      {"id": 21, "op": "OP_EMPTY", "width": 64, "sign": 0, "isClock": 0, "reset": 0, "node": "cpu$ldut$tile_prci_domain$element_reset_domain$rockettile$core$difftest_bundle_1$$mcause", "children": []},
      {"id": 22, "op": "OP_CAT", "width": 512, "sign": 0, "isClock": 0, "reset": 0, "children": [24, 25]},
      {"id": 23, "op": "OP_EMPTY", "width": 64, "sign": 0, "isClock": 0, "reset": 0, "node": "cpu$ldut$tile_prci_domain$element_reset_domain$rockettile$core$difftest_bundle_1$$stvec", "children": []},
      {"id": 24, "op": "OP_CAT", "width": 448, "sign": 0, "isClock": 0, "reset": 0, "children": [26, 27]},
      {"id": 25, "op": "OP_EMPTY", "width": 64, "sign": 0, "isClock": 0, "reset": 0, "node": "cpu$ldut$tile_prci_domain$element_reset_domain$rockettile$core$difftest_bundle_1$$mtvec", "children": []},
      {"id": 26, "op": "OP_CAT", "width": 384, "sign": 0, "isClock": 0, "reset": 0, "children": [28, 29]},
      {"id": 27, "op": "OP_EMPTY", "width": 64, "sign": 0, "isClock": 0, "reset": 0, "node": "cpu$ldut$tile_prci_domain$element_reset_domain$rockettile$core$difftest_bundle_1$$stval", "children": []},
      {"id": 28, "op": "OP_CAT", "width": 320, "sign": 0, "isClock": 0, "reset": 0, "children": [30, 31]},
      {"id": 29, "op": "OP_EMPTY", "width": 64, "sign": 0, "isClock": 0, "reset": 0, "node": "cpu$ldut$tile_prci_domain$element_reset_domain$rockettile$core$difftest_bundle_1$$mtval", "children": []},
      {"id": 30, "op": "OP_CAT", "width": 256, "sign": 0, "isClock": 0, "reset": 0, "children": [32, 33]},
      {"id": 31, "op": "OP_EMPTY", "width": 64, "sign": 0, "isClock": 0, "reset": 0, "node": "cpu$ldut$tile_prci_domain$element_reset_domain$rockettile$core$difftest_bundle_1$$sepc", "children": []},
      {"id": 32, "op": "OP_CAT", "width": 192, "sign": 0, "isClock": 0, "reset": 0, "children": [34, 35]},
      {"id": 33, "op": "OP_EMPTY", "width": 64, "sign": 0, "isClock": 0, "reset": 0, "node": "cpu$ldut$tile_prci_domain$element_reset_domain$rockettile$core$difftest_bundle_1$$mepc", "children": []},
      {"id": 34, "op": "OP_CAT", "width": 128, "sign": 0, "isClock": 0, "reset": 0, "children": [36, 37]},
      {"id": 35, "op": "OP_EMPTY", "width": 64, "sign": 0, "isClock": 0, "reset": 0, "node": "cpu$ldut$tile_prci_domain$element_reset_domain$rockettile$core$difftest_bundle_1$$sstatus", "children": []},
      {"id": 36, "op": "OP_EMPTY", "width": 64, "sign": 0, "isClock": 0, "reset": 0, "node": "cpu$ldut$tile_prci_domain$element_reset_domain$rockettile$core$difftest_bundle_1$$privilegeMode", "children": []},
      {"id": 37, "op": "OP_EMPTY", "width": 64, "sign": 0, "isClock": 0, "reset": 0, "node": "cpu$ldut$tile_prci_domain$element_reset_domain$rockettile$core$difftest_bundle_1$$mstatus", "children": []}
    ]}]},
```


经过 SplitNodes 之后：


tmp-out/debug-dumps-pass1/SimTop_3AfterSplitNodes.json
```
    {"name": "cpu$ldut$tile_prci_domain$element_reset_domain$rockettile$core$_difftest_packed_T_2", "type": "NODE_OTHERS", "super": 17622, "assignTrees": [{"root": 0, "lvalue": 1, "nodes": [
      {"id": 0, "op": "OP_EMPTY", "width": 8, "sign": 0, "isClock": 0, "reset": 0, "node": "cpu$ldut$tile_prci_domain$element_reset_domain$rockettile$core$difftest_bundle_1$$coreid", "children": []},
      {"id": 1, "op": "OP_EMPTY", "width": 1160, "sign": 0, "isClock": 0, "reset": 0, "node": "cpu$ldut$tile_prci_domain$element_reset_domain$rockettile$core$_difftest_packed_T_2", "children": []}
    ]}]},
```
## 修复记录（gsim 更新）
- 2025-12-25 `2dcbc00 fix: DPI-C path lost`：`usedBits` 将 EXT/EXT_IN/EXT_OUT 也作为种子全宽保活，`splitNodes` 不再把 `_difftest_packed_T_2` 裁成 8bit；ConstantAnalysis 引入 `VAL_EXT`，对接 EXT 的节点不再被当成常量剪掉，同时 `removeDeadNodes` 也把 EXT_IN/OUT 纳入可达种子，difftest/gateway/endpoint 链路得到保留。新增 `--dump-const-status` 与 LogLevel=2 的详细日志，可在 `*_ConstStatus.json` 里确认常量判定。
- 2025-12-24 `1e16242 add assign tree dump into json`：`--dump-assign-tree` 支持在 JSON dump 中查看 assignTree，便于确认 CAT 切分后各段是否仍然完整。