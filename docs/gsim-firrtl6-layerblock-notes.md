# gsim 解析 XiangShan SimTop.fir 的问题与修复记录

## 现象
- 命令：`gsim --supernode-max-size=15 --cpp-max-size-KB=8192 --sep-mod=__DOT__ --sep-aggr=__DOT__ --dir XiangShan/build/gsim-compile/model XiangShan/build/rtl/SimTop.fir`
- 原日志：`Error at line 1447857: syntax error, unexpected ',', expecting ')' (unexpected token: ',').`
- 出错位置：`SimTop.fir:1447857`，语句为 `intrinsic(circt_chisel_ifelsefatal<format = "...", label = "chisel3_builtin">, clock, _exception_T_19, _exception_T_21, ...)`，处于 `layerblock Verification -> layerblock Assert` 中。
- 由于解析失败，`SimTop.h` 等生成物缺失，后续 C++ 编译报 `SimTop.h`/`sqlite3.h` not found。

## 根因
- FIRRTL 6 引入 `layerblock` 验证层与 `intrinsic(circt_chisel_ifelsefatal...)` 表达断言。旧版 gsim 语法不理解：
  - `layerblock`：被当作普通标识符，未展开内部语句。
  - `intrinsic(circt_chisel_ifelsefatal...)`：格式参数后出现逗号和额外实参，语法规则不接受，导致 `unexpected ','`。

## 修复方法
- 文件：`gsim/parser/syntax.y`
  - 为 `Intrinsic` 规则追加 `intrinsic_extra`，吞掉格式参数后的所有额外实参，避免逗号触发语法错误。
  - 仍然将 `circt_chisel_ifelsefatal` 直接降为 `P_ASSERT`，格式字符串作为断言消息。
  - `layerblock` 解析保持“无条件展开”行为（视为普通 `statements`，不阻断内部）。
- 新增辅助非终结符 `intrinsic_extra`：递归消费 `, expr ...`，仅返回尾部表达式或空。

## 验证
- 重建 gsim：`make gsim-build`（通过）。
- `make run-xs-gsim`：解析 `SimTop.fir` 成功，日志显示多线程解析完成并进入后续优化阶段；整体生成因耗时在 CLI 侧超时，未见再出现语法错误。后续可在本地延长超时时间继续完成生成。

## 影响面
- 消除了 FIRRTL 6 `layerblock`/`circt_chisel_ifelsefatal` 组合的解析报错。
- 其他 intrinsic 仍保持旧行为（不识别则返回空节点）。

## 后续建议
- 若需要完整生成，可在本地延长超时时间或拆分构建步骤继续执行 `make run-xs-gsim`。***
