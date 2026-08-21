# Integration Map: Lattice + Aegis -> CC-Panes Method Layer v0.1

本表描述协议映射和已选定的方案 A adapter 边界，不表示已经接入 CC-Panes runtime。详细设计见 `docs/specs/2026-08-05-ccpanes-v0.1-file-first-adapter-design.md`。

## Lattice 映射

| Lattice 概念 | v0.1 映射 | 状态与边界 |
| --- | --- | --- |
| `spc-N` | `task.lineage.specId` | 当前字段；标识格式由 adapter 决定 |
| `tkt-N` | `task.lineage.ticketId` | 当前字段；GitHub 不是必需入口 |
| `rev-*` | `task.lineage.reviewId` | 当前字段 |
| PR reference | `task.lineage.pr` | 当前可选字段，不触发远端动作 |
| Spec -> ticket -> PR lineage | `task.lineage` | 当前字段，仅记录引用 |
| sibling worktree | `run.workspace.worktreePath` | 当前字段，由未来 launch adapter 填充 |
| alignment check | `evidence.driftCheck` | 当前字段，覆盖 scope/files/acceptance |
| finish ledger | `evidence` + `handoff` | 当前组合；没有独立 closure artifact |
| closure | 无 | future candidate；v0.1 不声明该字段 |

## Aegis 映射

| Aegis 概念 | v0.1 映射 | 状态与边界 |
| --- | --- | --- |
| baseline-first | `task.baseline`, `handoff.baseline` | 当前字段 |
| evidence-driven | `task.requiredEvidence`, `evidence.checks` | 当前字段 |
| long-task continuation | `handoff` | 当前九段式结构化 artifact |
| drift check | `evidence.driftCheck` | 当前字段 |
| proof bundle | `evidence` | 当前字段 |
| workflow depth | `task.riskMode` | 当前字段，v0.1 advisory-only |
| repair / retirement disposition | 无 | `changeDisposition` 是 future candidate |

## CC-Panes 原生能力映射

| CC-Panes 能力 | v0.1 接入点 | 当前状态 |
| --- | --- | --- |
| workspace/project 管理 | `task.baseline`, `run.workspace` | reference adapter 从 task baseline 显式映射 |
| `launch_task` | `run.taskRef`, `run.runner`, `run.workspace`, `run.contract` | `prepare-launch` 输出请求，`bind-launch` 消费响应；响应 `taskId` 保持 launch identity，TaskBinding 通过 `sessionId` 查询 |
| TaskBinding metadata | method identity 与 artifact 相对路径 | reference adapter 输出最小 patch；controller 必须读取并保留既存 metadata sibling keys，再调用 `update_task_binding` |
| leader/worker | worker 先产出 `evidence`，再更新 TaskBinding，最后通知 leader | `finish-run` 输出有序 patch/report envelope；readback 成功且 update 未自动发送终态通知时才手工 `report_to_leader` |
| profile routing | `run.runner.profile` 记录实际 profile | 由调用方显式选择；不由 `riskMode` 自动决定 |
| resume session | `run.runner.session.resumeSessionId` | 当前可选字段 |
| worker completion summary | `evidence.summary` 的输入之一 | 不单独证明 `evidence.outcome=completed` |
| `report_to_leader` / reconcile | TaskBinding 持久化并 readback 后通知；丢失时重新读取 | `finish-run` / `recover-launch` 已提供本地 envelope、command-specific schema 与恢复分类 |
| controller request planning / execution | 五类 envelope -> ordered MCP request plan -> journaled execution | dependency-free planner 与显式 live MCP executor 已实现；不自动接入 CC-Panes 主仓库、UI、profile 或 hook |
| UI/spec/todo | 可映射到 task lineage 或展示层 | future；不属于 v0.1 runtime |

## Prompt Pack 映射

| Prompt Pack 概念 | 本地 owner / artifact | 边界 |
| --- | --- | --- |
| Prompt identity、version、composition | `prompt-packs/<pack>/pack.json` | internal configuration，不改变 public artifact |
| Prompt metadata contract | `schemas/prompt-pack.internal.schema.json` | required inputs、output contract、acceptance、provenance |
| 技术栈假设 | `prompt-packs/<pack>/profiles/*.json` | 具体版本必须来自 project facts |
| Prompt 正文 | `prompt-packs/<pack>/prompts/*.md` | 独立重写；不继承 donor 权限或固定实现 |
| deterministic eval | `prompt-packs/<pack>/evals/*.json` + `tests/prompt-pack/run.ps1` | exact expected decisions、跨文件引用与 donor-window hashes；required gate 不使用 LLM judge |
| Task/project context | future composer input | 授权、事实、停止条件的 authority |
| `tool/skills` | generated projection | consumer，不是 source of truth |
| Official CC-Panes external Companion | caller-supplied context JSON -> metadata-only guidance JSON | 旁路协助官方 `cc-panes.exe`；不启动官方 exe、不改 profile/plugin/hook/MCP/user config、不执行/组合 Prompt |
| PaneForge PF-FUSION-007 | caller-supplied source-lock/catalog JSON -> sanitized metadata review | 默认关闭的只读 consumer；校验原始 bytes/hash、身份、顺序、覆盖与 host-path 边界，不读取 source path |
| launch/journal/evidence | Prompt identity/version/ref | 避免保存完整 Prompt 正文 |

## 稳定边界

- GitHub 是可选 surface，不是本地方法层的唯一事实源。
- 上游 skill 和 workflow 仅作为参考，不作为默认 runtime。
- task 是授权与验收的权威来源；run.contract 是 launch 时的不可变快照。
- evidence 记录事实，不自行授予 completion authority。
- handoff 表达下一轮控制契约，`nextOrder` 不扩大当前授权。
- adapter 可以增加映射逻辑，但不得静默改变 v0.1 artifact 语义。
- artifact 默认位于项目内 `.ccpanes-method/v0.1`，与 CC-Panes 宿主 `.ccpanes/` 分离。
- controller-mediated MCP transport contract 见 `docs/ccpanes-mcp-transport-runbook.md`；它不表示本仓库已执行 live runtime 接入。
- dry-run planner 输出 `controller-transport-plan` internal artifact；它不是新的方法层协议 artifact。
- Prompt Pack、technology profile 和 eval suite 使用 `0.1-internal` schema；它们不是新的方法层协议 artifact。
- Official Companion 是外部 sidecar；官方 CC-Panes 继续拥有 pane/session/PTY/runtime，Companion 只输出可人工复制或由单独批准 transport 消费的 metadata guidance。
- PaneForge 的 Prompt Pack review seam 只拥有 sanitized review projection；它不拥有 Prompt 语义、执行、组合、Skill 发布、方法层写入或 host 配置修改 authority。

## Future candidates

以下名称不属于 v0.1 当前 schema：

- `closure`
- `changeDisposition`
- UI-specific task/ticket projection
- 自动 profile selection
- 自动 merge/push/cleanup

加入这些能力需要新的协议评审、版本策略和明确授权。
