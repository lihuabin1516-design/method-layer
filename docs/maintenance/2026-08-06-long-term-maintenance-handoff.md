# Long-Term Maintenance Handoff: CC-Panes Method Layer

## 1. 角色、任务标识与一句话结论

- 角色：下一任本项目长期维护主控。
- 任务标识：`ccpanes-method-layer-long-term-maintenance-20260806`
- 一句话结论：`D:\ccpanes-method-layer` 已从草案升级为可验证、可维护、可被后续 CC-Panes adapter 消费的 v0.1 方法层协议基线，并已推送到远端 `lihuabin1516-design/ccpanes-method-layer`。
- 状态：历史快照；当前权威基线请看 `README.md`、`HANDOFF.md` 和 `docs/maintenance/governance-baseline.md`。

## 2. 先决必读

按顺序读取：

1. `AGENTS.md`
2. `README.md`
3. `HANDOFF.md`
4. `docs/maintenance/2026-08-06-long-term-maintenance-handoff.md`
5. `docs/architecture/repository-structure.md`
6. `docs/charter.md`
7. `docs/workflow.md`
8. `docs/integration-map.md`
9. `docs/ccpanes-mcp-transport-runbook.md`
10. `controller/README.md`
11. `adapter/README.md`
12. `schemas/*.schema.json`
13. `adapter/schemas/*.json`
14. `controller/schemas/*.json`
15. `tests/adapter/run.ps1`
16. `tests/controller/run.ps1`
17. `tests/controller-executor/run.ps1`

## 3. 历史基线、事实和证据

### Git / remote

- 本地路径：`D:\ccpanes-method-layer`
- 分支：`main`
- 当前提交：`d75cf50be269009cc53f6e984fc70981c55cee31`
- 远端：`https://github.com/lihuabin1516-design/ccpanes-method-layer.git`
- 远端 `main` 已与本地 HEAD 对齐。
- 上一远端初始提交：`e70893f Initial commit`
- 当前基线提交标题：`Establish CC-Panes method-layer v0.1 protocol baseline`
- GitHub 仓库描述：

```text
CC-Panes v0.1 方法层协议基线：定义 task/run/evidence/handoff JSON Schema，提供 file-first adapter、controller planner、journaled executor 与本地 MCP transport 验证，用于后续 CC-Panes adapter 消费。
```

### 当前能力

本仓库已经包含：

- v0.1 public protocol：
  - `task`
  - `run`
  - `evidence`
  - `handoff`
- file-first adapter：
  - `prepare-launch`
  - `bind-launch`
  - `finish-run`
  - `new-handoff`
  - `recover-launch`
- controller planner：
  - adapter envelope -> ordered MCP transport plan
  - identity / metadata merge / readback plan
  - terminal auto-notify 与 manual report 分支
- journaled executor：
  - `dry-run`
  - explicit `live`
  - append-only JSONL journal
  - response artifact + SHA-256
  - replay gate
  - non-idempotent launch/report gate
  - TaskBinding precondition
- local MCP Streamable HTTP driver：
  - loopback endpoint gate
  - JSON 与 SSE response parser
  - JSON-RPC id matching
  - token 不落盘

### 已完成验证

最近一次完整验证：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\validate.ps1
```

结果：

- JSON syntax：pass
- valid examples：pass
- invalid examples：pass
- templates：pass
- PowerShell parser：pass
- adapter tests：23/23 pass
- controller planner tests：16/16 pass
- controller executor tests：16/16 pass
- overall validation：pass

额外验证：

- `python -m json.tool schemas/task.schema.json`
- `python -m json.tool schemas/run.schema.json`
- `python -m json.tool schemas/evidence.schema.json`
- `python -m json.tool schemas/handoff.schema.json`
- 本机 MCP 只读 probe：`find_task_binding_by_session` through `/mcp` pass
- token scan：pass
- `tests/.tmp`：空
- dependency dirs：`node_modules/vendor/.venv/__pycache__` 均为 0

环境噪声：

- Python 运行期间出现 Anaconda `RequestsDependencyWarning`，不影响 JSON syntax validation。

## 4. 本轮唯一目标

长期维护本仓库作为 CC-Panes 方法层协议基线，优先保证：

1. 四类 public artifact 的 v0.1 兼容性；
2. 本机验证稳定；
3. adapter/controller 的边界清晰；
4. 后续吸收其它项目方法层时可追溯、可比较、可回滚；
5. 后续 CC-Panes adapter 消费时不把 runtime 细节反向污染协议层。

## 5. 精确授权、禁止项和条件授权

### 默认可做

- 修改本仓库文档、schema、adapter、controller、tests、templates。
- 运行本仓库验证命令。
- 读取上游项目公开代码、文档和 release 信息。
- 新增 `docs/upstreams/<source>.md` 记录外部方法层调研。
- 新增 `docs/plans/*.md` 记录协议变更计划。
- 新增 focused examples / fixtures / tests 支撑协议演进。

### 默认保持边界

- `D:\cc-pane` 作为外部项目读取参考。
- 用户全局配置保持外部状态。
- CC-Panes UI、hook、plugin、profile、主仓库接入保持独立任务。
- GitHub 只作为同步与协作 surface，不作为方法层事实源。
- Lattice / Aegis / 其它项目只吸收方法与契约，不 vendor 成品目录。

### 条件动作

以下动作需要在新任务中明确写出目标、路径和预期影响：

- 改 v0.1 public schema 的 required 字段、语义或 artifact 名称。
- 引入 v0.2 / experimental schema。
- 修改 `D:\cc-pane` 或任何 CC-Panes 主仓库文件。
- 写用户级配置。
- 安装依赖。
- 增加 UI、hook、plugin、profile。
- 运行 live mutation transport。
- merge、push、tag、release。

## 6. 执行顺序与 Agent 分派边界

### 新对话启动顺序

1. 读取 `HANDOFF.md` 与本文件。
2. 运行：

```powershell
git status --branch --short
powershell -ExecutionPolicy Bypass -File scripts\validate.ps1
```

3. 确认当前 HEAD 与远端状态。
4. 明确本轮目标属于：
   - protocol maintenance
   - upstream absorption
   - adapter maintenance
   - controller maintenance
   - documentation maintenance
   - CC-Panes integration preparation
5. 为本轮目标新增或更新 `docs/plans/*.md`。
6. 先写失败或聚焦测试，再改 schema / adapter / controller。
7. 验证并报告。

### Agent 分派建议

适合分派的只读任务：

- 某个外部项目方法层调研。
- 某个 schema 的 backward compatibility review。
- 某个 adapter envelope 与 controller plan 的映射审查。
- 某个文档与测试覆盖对齐审查。

适合分派的写入任务：

- 新增单个 upstream note。
- 新增单个 focused invalid/valid example。
- 新增单个 controller planner 或 executor fixture。
- 更新单个文档章节。

主控保留职责：

- 版本语义裁决。
- public schema 变更裁决。
- 最终 diff review。
- 最终 `scripts\validate.ps1`。
- Git commit / push 的最后执行。

## 7. 必要检查与验收断言

### 每轮必跑

```powershell
powershell -ExecutionPolicy Bypass -File scripts\validate.ps1
git status --branch --short
```

### public schema 变更额外检查

```powershell
python -m json.tool schemas/task.schema.json > $null
python -m json.tool schemas/run.schema.json > $null
python -m json.tool schemas/evidence.schema.json > $null
python -m json.tool schemas/handoff.schema.json > $null
pwsh -NoProfile -ExecutionPolicy Bypass -File tests\adapter\run.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tests\controller\run.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tests\controller-executor\run.ps1
```

### Upstream absorption 验收断言

吸收其它项目方法层时，每个来源至少记录：

- 来源名称与 URL；
- 读取日期；
- 版本、tag、commit 或 release；
- 可吸收能力；
- 与当前 v0.1 的映射；
- 不吸收项与理由；
- 对 schema 的影响；
- 对 adapter/controller 的影响；
- 新增测试；
- backward compatibility 结论；
- rollback 方案。

### 交付断言

- 文档入口能指向新增内容。
- `docs/architecture/repository-structure.md` 与实际目录一致。
- 新增 schema 或 fixture 进入 `scripts\validate.ps1` 覆盖范围。
- 没有真实 token、PII、生产数据落入仓库。
- `.ccpanes/`、`.ccpanes-method/`、`artifacts/local/` 继续忽略。

## 8. 审计、熔断和停止条件

### 审计

- 写入前记录 `git status --branch --short`。
- 写入后检查 `git diff --stat` 和 `git diff --check`。
- 完成前运行全量验证。
- push 前确认本地 HEAD、远端 HEAD 和工作区状态。

### 熔断

以下情况先停在计划或报告：

- public schema 变化会破坏现有 valid examples。
- adapter envelope 与 controller plan 语义不一致。
- executor 需要绕过 journal / response hash / precondition。
- live transport 需要接触非 synthetic TaskBinding。
- upstream 方法层要求引入大体量成品目录。
- 同一根因修复三轮后仍失败。

### 停止条件

- 需要跨仓库写入。
- 需要用户级配置写入。
- 需要安装依赖。
- 需要远端破坏性操作。
- 需要改变 CC-Panes 主仓库 runtime 行为。
- 验证失败且根因尚未说明。

## 9. Artifact、交付要求和后续顺序

### 当前核心 artifacts

- `schemas/*.schema.json`
- `examples/**`
- `templates/**`
- `adapter/**`
- `controller/**`
- `scripts/adapter/**`
- `scripts/controller/**`
- `tests/adapter/**`
- `tests/controller/**`
- `tests/controller-executor/**`
- `docs/**`
- `README.md`
- `HANDOFF.md`
- `AGENTS.md`

### 交付报告格式

普通维护任务报告使用：

```text
完成状态：
变更：
验证：
风险：
下一步：
```

涉及 schema / upstream / runtime / Git remote 的任务补充：

```text
兼容性：
回滚：
远端状态：
```

### 推荐后续顺序

1. 建立 upstream absorption 模板。
2. 为 Lattice / Aegis 现有 upstream notes 补齐对比矩阵。
3. 为未来 v0.2 建立 `docs/plans/*` 草案，不直接改 v0.1 public schema。
4. 设计 CC-Panes adapter consumption plan，但保持主仓库接入为独立任务。
5. 增加 release checklist 与 tag 策略。

## 10. 新对话启动提示词

新开对话时可直接粘贴：

```text
请在 D:\ccpanes-method-layer 继续担任 CC-Panes Method Layer 长期维护主控。

先读：
- AGENTS.md
- README.md
- HANDOFF.md
- docs/maintenance/2026-08-06-long-term-maintenance-handoff.md
- docs/architecture/repository-structure.md
- docs/integration-map.md
- docs/workflow.md
- docs/ccpanes-mcp-transport-runbook.md

先执行：
- git status --branch --short
- powershell -ExecutionPolicy Bypass -File scripts\validate.ps1

本仓库目标：
维护 v0.1 方法层协议基线，后续按计划吸收其它项目的方法层能力。保持 public schema 兼容、adapter/controller 边界清晰、本机验证稳定。

默认边界：
- 只改 D:\ccpanes-method-layer。
- 不改 D:\cc-pane。
- 不写用户全局配置。
- 不安装依赖。
- 不自动做 UI/hook/plugin/profile/主仓库接入。
- 不 vendor 外部项目成品目录。

开始后先给当前状态、验证结果和建议本轮维护计划。
```
