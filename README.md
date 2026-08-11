# CC-Panes Method Layer

本仓库维护 CC-Panes 的本地方法层协议。v0.1 把 task intent、运行绑定、验证证据和主控交接定义为可审阅、可验证的本地 artifact；CC-Panes UI、Orchestrator 和目标项目仍保持各自边界。

## v0.1 协议边界

v0.1 包含四类 JSON artifact：

| Artifact | 责任 | Schema |
| --- | --- | --- |
| `task` | 目标、授权、基线、验收、证据要求、停止条件和 lineage | `schemas/task.schema.json` |
| `run` | task 引用、runner/session/profile、workspace/worktree 和 launch-time contract snapshot | `schemas/run.schema.json` |
| `evidence` | outcome、文件触达、检查结果、drift check、Git 状态和残余风险 | `schemas/evidence.schema.json` |
| `handoff` | 结构化九段式主控交接 | `schemas/handoff.schema.json` |

所有 v0.1 artifact 都必须包含：

- `protocolVersion: "0.1"`
- 与 schema 对应的 `artifactType`
- 统一规则的 `taskId`
- 关键字段非空约束
- 明确的 `additionalProperties: false` 对象边界

`riskMode` 在 v0.1 仅是 `simple` / `standard` / `deep` 的建议性工作深度。它不授予权限，也不自动选择 profile、启动 worker 或驱动 finish 行为。

## 本机验证

不需要安装依赖。仓库使用 Python 标准库检查 JSON 语法，使用 PowerShell 7 的 `Test-Json -SchemaFile` 检查实例。

从仓库根目录执行完整冻结验证：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\validate.ps1 -Mode Full
```

在 Windows PowerShell 缺少 `Test-Json` 时，脚本会使用本机现有的 `pwsh` 重新启动。也可以直接执行：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\validate.ps1 -Mode Full
```

`Full` 是默认模式，覆盖 schema、examples、templates、PowerShell parser、adapter、
controller planner 和 controller executor。当前冻结验收实测默认 Full 出现过
53.4 秒、67.3 秒、142.7 秒与 219.1 秒；此前同机观察到过约 294 秒的长耗时，后续冻结验收以
实际命令输出为准。

快速结构验证可执行：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\validate.ps1 -Mode Fast
```

`Fast` 只跳过 adapter/controller/executor 三个测试套件，仍检查 JSON syntax、
public examples、templates 和 PowerShell parser。发布、冻结、提交前必须运行
`Full`。

验证要求：

- `schemas/*.json` 和 `examples/**/*.json` 全部通过 JSON 语法检查。
- `examples/valid/*.json` 全部通过对应 schema。
- `examples/invalid/*.json` 全部被对应 schema 拒绝。
- `adapter/schemas/*.json` 与 adapter fixtures 通过 JSON 语法检查。
- `scripts/**/*.ps1|psm1` 与 `tests/**/*.ps1` 通过 PowerShell parser。
- 五类 adapter stdout 通过各自的 internal envelope schema。
- controller plan、execution journal/result 与 fixtures 通过 JSON 和 schema 验证。
- `tests/adapter/run.ps1` 全部通过。
- `tests/controller/run.ps1` 全部通过。
- `tests/controller-executor/run.ps1` 全部通过。
- `tests/prompt-pack/run.ps1` 验证 Prompt Pack manifest、技术栈 profile、Prompt 合同、来源锁、组合规则和确定性 eval。
- `.gitattributes` 将十个 source-locked artifact 标记为 `-text`，禁止 Git 行尾归一化改变其精确 bytes 和 SHA-256。
- 成功结束前 `scripts\validate.ps1` 会断言 `tests\.tmp` 为空；失败时保留现场供排查。

## Prompt Packs

Prompt Pack 是方法层的内部配置和知识输入，不是第五类 public artifact。当前首个 pack 为 `prompt-packs/java-enterprise/pack.json`。

其 canonical owner 是本仓库，包含五个本地化 Prompt、一个 Java/Spring 技术栈 profile、十三个确定性 eval fixtures，以及锁定 donor 的不可逆窗口哈希。具体框架版本必须来自项目事实；Prompt Pack 不扩大 task authorization。

设计、来源与仓库边界：

- `docs/specs/2026-08-10-prompt-pack-v0.1-design.md`
- `docs/upstreams/ai-coding-prompt-java.md`
- `docs/architecture/adr-2026-08-10-prompt-pack-repository-boundary.md`

Focused validation：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tests\prompt-pack\run.ps1
```

### 启用 PaneForge 只读审查后的实际收益

这项能力不是“自动写代码”，而是 Prompt Pack 进入工作流前的体检层：

1. 方法层继续维护 Prompt、schema、profile、eval 和来源哈希。
2. PaneForge 只接收调用方粘贴的 source-lock JSON 与 sanitized catalog JSON。
3. 它核对 source-lock 原始 UTF-8 bytes、manifest/profile/eval 和五个 Prompt 的哈希、身份、顺序与覆盖范围。
4. 一致时展示安全的 metadata；哈希不一致时隔离为 `quarantined`，提示重新提供匹配的两段 JSON。

对现有工作流的直接优化：

- **少用错版本**：Prompt 或 manifest 被改过，哈希会立刻暴露，不再靠人工猜。
- **少做重复核对**：五个 Prompt、profile、十三个 eval 的基础审查一次完成。
- **减少脏输入进入后续步骤**：本机绝对路径、`file://`、Prompt 正文、donor 文本和未批准 authority 会被挡住。
- **问题更容易定位**：结构错误直接拒绝；仅哈希过期则进入隔离并给出明确恢复动作。
- **试用风险低**：该 seam 不执行或组合 Prompt，不生成/安装 Skill，不写方法层，也不修改 host 配置。

当前 PaneForge 预览实现位于 `codex/pf-fusion-007-readonly-review-seam`，默认关闭：

```powershell
$env:PANEFORGE_PROMPT_PACK_REVIEW_ENABLED = '1'
```

启用后可从 PaneForge 的 **Settings → AI → Prompt Pack Review** 使用。当前它仍是下游任务 worktree 中的开发预览，不代表已经进入正式 PaneForge 发布构建。

## 当前本地任务状态

本轮 donor intake 在 linked worktree 中进行：

- Worktree：`D:\ccpanes-method-layer-worktrees\prompt-pack-java-intake`
- Branch：`codex/prompt-pack-java-intake`
- Baseline HEAD：`d9abbb8b0f5cfa68448a3d7bf673bbd00ab72d47`
- Main worktree：`D:\ccpanes-method-layer`，不承载本轮 tracked 变更
- Remote：`origin -> https://github.com/lihuabin1516-design/ccpanes-method-layer.git`
- Git commit / push：用户已在 `2026-08-11` 明确授权本任务同步到上述 remote；merge 到 `main` 和 worktree cleanup 不在该授权内

实际 dirty summary 始终由以下命令复核：

```powershell
git status --short --branch
```

本轮允许的变更类别是 donor 来源记录、Prompt Pack 内部 schema、manifest、profile、Prompt、eval、测试、验证脚本、架构文档和当前 `HANDOFF.md`。

## 阅读顺序

1. `HANDOFF.md`：当前权威基线、授权和下一步。
2. `docs/maintenance/2026-08-06-long-term-maintenance-handoff.md`：长期维护交接与新对话启动提示词。
3. `docs/architecture/repository-structure.md`：仓库目录架构、职责边界和维护检查表。
4. `docs/charter.md`：方法层定位与非目标。
5. `docs/integration-map.md`：上游概念、v0.1 字段和 future 边界。
6. `docs/specs/2026-08-10-prompt-pack-v0.1-design.md`：Prompt Pack 内部架构。
7. `prompt-packs/java-enterprise/README.md`：首个 pack 的组合和验证入口。
8. `docs/workflow.md`：artifact 生命周期和 finish gate。
9. `schemas/*.schema.json`：机器可验证契约。
10. `examples/README.md` 与 `examples/**`：正反实例。
11. `templates/*`：人工任务和交接输出模板。

## 长期维护入口

后续新对话维护本项目时，优先读取：

- `HANDOFF.md`
- `docs/maintenance/2026-08-06-long-term-maintenance-handoff.md`
- `docs/maintenance/long-term-maintenance-agent-prompt.md`
- `docs/architecture/repository-structure.md`

其中长期维护交接文件包含：

- 当前 Git / remote / commit 基线；
- 本轮会话沉淀的事实和验证证据；
- 维护授权边界；
- upstream absorption 流程；
- 新对话启动提示词。

如果需要给另一个 Agent 开启维护会话，可直接复制：

- `docs/maintenance/long-term-maintenance-agent-prompt.md`

目录架构文件说明每个目录的职责、测试入口、release/push checklist，以及后续吸收其它项目方法层时应落文档和测试的位置。

## File-first reference adapter

仓库内已提供 PowerShell 7 reference adapter，以独立层消费 v0.1：

1. `prepare-launch.ps1` 验证 task、基线和授权，写入 launch attempt 并输出 `launch_task` envelope。
2. transport 调用 CC-Panes `launch_task`。
3. `bind-launch.ps1` 消费真实响应，发布 `run` 并输出 TaskBinding metadata patch。
4. `finish-run.ps1` 发布 evidence、更新 run，并输出 TaskBinding patch 与 leader report。
5. `new-handoff.ps1` 生成九段式 handoff。
6. `recover-launch.ps1` 对 prepared/launched/bound 状态给出恢复动作。

完整命令说明见 `adapter/README.md`。reference adapter 生成 JSON envelope，CC-Panes runtime transport 仍保持独立边界。

controller 如何将五类 envelope 映射到 `launch_task`、
`find_task_binding_by_session`、`update_task_binding` 和
`report_to_leader`，见：

- `docs/ccpanes-mcp-transport-runbook.md`

该 runbook 固定 metadata merge/readback、identity 分离、journal 和 recovery
action 映射。live transport 只能通过显式 `-Mode live` 启动。

## Controller planner 与 executor

`scripts/controller/plan-transport.ps1` 消费 adapter envelope、可选 TaskBinding
snapshot 和 recovery journal envelope，输出 schema-valid 的 MCP request plan：

- `launch_task`
- `find_task_binding_by_session`
- `update_task_binding`
- 条件性 `report_to_leader`

planner 保留 metadata sibling keys、计划 update 后 readback、识别 terminal
auto-notify，并对 identity 冲突、缺失 binding/journal 和超过 64 KiB 的合并请求
执行 fail-closed decision。完整说明见 `controller/README.md`。

`scripts/controller/execute-transport.ps1` 对 plan 做第二次 schema 校验，并提供：

- 默认 `dry-run`；
- 显式 `live` MCP Streamable HTTP transport；
- append-only JSONL journal 和独立 response artifacts；
- TaskBinding snapshot hash precondition；
- read/update 最多三次 transient retry；
- ambiguous `launch_task` / `report_to_leader` 单次后进入 `manual-review`；
- crash/replay 时只跳过 request hash 相同的成功 mutation。

方案 A“文件优先薄 Adapter”的设计基线位于：

- `docs/specs/2026-08-05-ccpanes-v0.1-file-first-adapter-design.md`

该设计固定 artifact 存储布局、TaskBinding 最小 metadata、launch attempt 恢复、finish/evidence 顺序与 handoff 门禁，当前已由本地 reference adapter 实现。

已确认设计对应的实施计划：

- `docs/plans/2026-08-05-v0.1-file-first-adapter.md`

计划采用 PowerShell 7 的依赖零安装 reference adapter，通过 `prepare-launch` / `bind-launch`、`finish-run`、`new-handoff` 和 `recover-launch` 生成可供 CC-Panes transport 消费的 JSON envelope；实现和测试文件已落在本仓库。

## 当前明确不做

- 不接入 `D:\cc-pane` 或 CC-Panes 主仓库。
- 不实现 UI、hook、plugin、profile 或 MCP 写入。
- 不写用户全局配置。
- 不自动 merge、push、cleanup 或执行其它远端操作。
- 不把 Lattice/Aegis 成品目录复制进本仓库。
- 不把 GitHub 设为唯一事实源。

## 本地宿主文件

`.ccpanes/` 和根目录 `CLAUDE.md` 是 CC-Panes 工作空间宿主生成状态，不属于 v0.1 协议内容，已由 `.gitignore` 排除。
