# Charter: CC-Panes Method Layer

## 一句话目标

为 CC-Panes 增加一个本地优先、可审计、可扩展的方法层，让多 agent 工作具备稳定 task identity、baseline、lineage、evidence、handoff 与 finish gate。

## 非目标

- 替换 CC-Panes UI / Orchestrator。
- 直接套用 Lattice 或 Aegis 的包装产物。
- 默认写入用户全局配置或目标项目。
- 默认执行 GitHub merge、push、cleanup 或远端操作。

## 核心原则

1. 本地优先：关键上下文落在本地 artifact，可 grep、可 review、可随项目管理。
2. 显层分离：CC-Panes 管 pane/session/profile；本仓库管方法协议。
3. 证据优先：完成性表述必须绑定 fresh verification evidence。
4. 取长补短：吸收上游概念，重写为 CC-Panes 原生 adapter。
5. 可插拔：后续可接入更多项目、方法包或远端源，不破坏当前 schema。
6. 自有评判：仓库是否变好，以本地治理基线为准；外部评价只作参考，不替代事实、证据和边界。

## 分层模型

```text
CC-Panes UI / Orchestrator
  -> Method Layer adapter
  -> Project rules / AGENTS.md
  -> Git / Worktree / Tests / GitHub optional
```
