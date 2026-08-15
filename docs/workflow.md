# Workflow v0.1

## 标准路径

```text
1. task intake
2. baseline readback
3. risk advisory classification
4. task artifact validation
5. run artifact creation with contract snapshot
6. worker execution / investigation
7. evidence artifact validation
8. drift and finish gate
9. handoff or local completion decision
```

v0.1 定义 artifact 和门禁输入。本仓库 reference adapter 已实现本地文件与
JSON envelope 转换；controller 可在显式 live 模式执行 MCP plan，UI、远端动作和
CC-Panes 主仓库接入仍保持独立。

辅助派生图形 brief 见
[`docs/architecture/diagram-v0.1-lifecycle.md`](architecture/diagram-v0.1-lifecycle.md)。
该 brief 是 `derived: true` / `authoritative: false` 的 renderer-neutral 视图，不替代
本文件、public schema、adapter/controller 合同或运行状态证据。

## Reference adapter 路径

```text
prepare-launch
  -> caller invokes launch_task
  -> bind-launch
  -> caller resolves TaskBinding by sessionId
  -> caller applies taskBindingPatch
  -> worker execution
  -> finish-run
  -> caller applies taskBindingPatch
  -> caller sends leaderReport
  -> new-handoff
  -> caller applies latestHandoffPath patch
```

adapter command 在 stdout 返回单个 JSON envelope。文件 artifact 先落盘，transport 动作随后执行。
每类 stdout 在输出前通过 command-specific internal schema。controller 的 MCP
字段映射、metadata merge/readback 门禁与恢复动作见
`docs/ccpanes-mcp-transport-runbook.md`。

本仓库提供 `scripts/controller/plan-transport.ps1`，把 envelope 与可选
TaskBinding snapshot 转成 `controller-transport-plan`；随后
`scripts/controller/execute-transport.ps1` 在 `dry-run` 或显式 `live` 模式消费
该计划。live 模式将 journal 和 response 写入项目内 artifact root。

## 1. Task

主控创建 `task` artifact，至少固定：

- 唯一目标和 `taskId`
- allowed paths、forbidden actions、conditional actions
- project/repository/Git baseline
- acceptance assertions
- required evidence
- stop conditions
- lineage
- task status
- advisory-only `riskMode`

`riskMode` 只提示工作深度：

- `simple`：局部、低耦合、验证面小。
- `standard`：多文件或需要完整证据闭环。
- `deep`：高影响、跨层或需要额外审查。

它不等同于授权，也不要求 adapter 自动选择某个 profile。

## 2. Run

`prepare-launch` 与 `bind-launch` 两阶段创建 `run` artifact：

- `taskRef` 指向 task identity 和协议版本。
- `runner` 记录实际 cliTool、profile、runtime 和 session。
- `workspace` 记录 projectPath、worktreePath 和 branch。
- `contract` 复制 task 中直接约束本次运行的目标、授权、验收、证据和停止条件。

`run.contract` 是 launch-time snapshot。task 后续发生变化时，既有 run 不应被静默重写。

## 3. Evidence

worker evidence 或 `finish-run` 创建 `evidence` artifact：

- `outcome`
- created/modified/deleted/inspected 文件
- 必要和可选检查及其 pass/fail/blocked/not-run 状态
- scope/files/acceptance drift check
- 完成时 Git 状态
- residual risk
- recommended next action

检查结果必须来自实际执行。`evidence` 是事实记录，不是 merge、push 或 completion 的自动许可。

## 4. Finish Gate

主控至少检查：

- task objective 与 run.contract 是否一致
- 是否存在越权或未解释文件
- required checks 是否满足
- drift check 是否 aligned
- Git 状态是否符合任务授权
- 是否仍需要用户批准 integration、commit、merge、push 或 cleanup

MCP transport 还必须先读取当前 TaskBinding 并保留既存 metadata sibling keys，
只替换 `metadata.methodLayer`；`update_task_binding` 后 readback 成功，才允许发送
`report_to_leader`。若 update 已触发 worker 终态自动通知，则按
`leaderReport.dispatchPolicy=if-not-auto-notified` 跳过手工补报。

v0.1 没有独立 `closure` 字段或 artifact。后续 transport 可以在不改变 evidence 事实的前提下实现 closure 行为。

## 5. Handoff

需要继续任务时生成结构化 `handoff`，覆盖：

1. role / taskId / currentResult
2. requiredReading
3. baseline / facts / evidence
4. objective
5. authorization / forbidden / conditionalAuthorization
6. executionOrder / agentDispatchBoundary
7. requiredChecks / acceptanceAssertions
8. audit / fuse / stopConditions
9. artifacts / delivery / nextOrder

`nextOrder` 只描述门禁依赖；完成当前 objective 后停止，不自动执行下一项。
