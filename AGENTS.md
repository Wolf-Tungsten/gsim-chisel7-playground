# 工作提醒
- 开始工作前在项目根目录执行 `source ./env.sh`。
- 创建的临时文件统一放在 `tmp-out/` 目录下。
- 不要到任何内层目录去运行make命令，用顶层目录的 makefile 即可。
- 定位问题是要通过打log、dump 图结构等手段给出充分的证据，不能凭感觉和猜测。
- 禁用 ccache：环境变量 CCACHE_DISABLE=1（已在 Makefile 对 rocket-chip 子构建设置）。