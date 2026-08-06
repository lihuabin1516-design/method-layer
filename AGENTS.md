# CC-Panes Method Layer 仓库规则

## 范围

本仓库只维护 CC-Panes 方法层协议、schema、模板、映射文档和本地实验脚本。不要把 Lattice 或 Aegis 的完整成品复制进来。

## 上游处理

- 上游仓库作为参考源：`percena/lattice`、`GanyuanRan/Aegis`。
- 每次吸收上游能力时，记录来源、版本或 commit、采用理由、改写点和舍弃点。
- 保留 CC-Panes 原生术语和 artifact 边界，避免上游默认行为直接覆盖本地授权模型。

## 安全与授权

- 默认只改本仓库文件。
- 任何接入 CC-Panes 主仓库、用户全局配置、远端 GitHub、hook、plugin、profile 的动作，需要单独授权。
- merge、push、清理 worktree、删除远端分支、写入用户配置，都需要明确授权。

## 验收

文档/schema 变更至少执行：

```powershell
git status --short
Get-ChildItem -Recurse -File | Select-Object FullName
python -m json.tool schemas/task.schema.json > $null
python -m json.tool schemas/run.schema.json > $null
python -m json.tool schemas/evidence.schema.json > $null
python -m json.tool schemas/handoff.schema.json > $null
```

完成报告要包含：变更、验证、风险、下一步。
