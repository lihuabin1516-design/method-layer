# CC-Panes MCP Transport Runbook v0.1

## 范围

本 runbook 定义 controller 如何消费 file-first adapter 的五类 stdout
envelope，并把其中的意图映射到 CC-Panes MCP。本仓库同时提供 planner 与需要
显式 `-Mode live` 的 journaled executor。

仓库内的 dry-run reference planner 位于：

- `scripts/controller/plan-transport.ps1`
- `controller/schemas/transport-plan.internal.schema.json`
- `controller/README.md`

planner 把本 runbook 的顺序生成为机器可验证 request plan，但不发送 request。
`scripts/controller/execute-transport.ps1` 复验 plan 后，可通过当前进程注入的
`CC_PANES_API_BASE_URL` / `CC_PANES_API_TOKEN` 执行 MCP Streamable HTTP。
token 不进入 journal 或 response artifact。

权威边界：

- `task` / `run` / `evidence` / `handoff` 文件仍是方法层事实源。
- `adapter/schemas/*-envelope.internal.schema.json` 是 controller 输入契约。
- controller 只传输 envelope 已声明的数据，不从 `riskMode` 推导权限或 profile。
- `launch_task.taskId` 是 launch-status identity，不是 TaskBinding ID。
- TaskBinding ID 必须通过 `sessionId` 查询或通过显式注册流程取得。

## Source pin

本映射按以下只读 Git object 复核：

```text
D:\cc-pane\.source\cc-pane
e63d0889c52b6f8dc1109266563327da59eb080e
```

相关路径：

- `src-tauri/src/services/orchestrator_service.rs`
- `cc-panes-core/src/models/task_binding.rs`
- `cc-panes-core/src/services/task_binding_service.rs`
- `web/types/orchestrator.ts`

复核时 source checkout 只有 `.git`，tracked 文件在工作树中呈删除状态；内容通过
`git show HEAD:<path>` 读取。本 runbook 不修复或写入该 checkout。

## Envelope gate

controller 在任何 MCP 调用前必须：

1. 将命令 stdout 作为一个完整 JSON document 解析。
2. 要求 `schemaVersion == "0.1-internal"`。
3. 按 `envelopeType` 使用对应 internal schema 复验。
4. 拒绝未知字段、未知 envelope 类型和 schema 失败。
5. 校验所有 artifact path 都是目标项目内的 `/` 分隔相对路径。
6. 保存本次 envelope、MCP request 摘要、响应和 correlation identity，供恢复使用。

五类契约：

| Command | `envelopeType` | Schema |
| --- | --- | --- |
| `prepare-launch.ps1` | `prepare-launch-envelope` | `adapter/schemas/prepare-launch-envelope.internal.schema.json` |
| `bind-launch.ps1` | `bind-launch-envelope` | `adapter/schemas/bind-launch-envelope.internal.schema.json` |
| `finish-run.ps1` | `finish-run-envelope` | `adapter/schemas/finish-run-envelope.internal.schema.json` |
| `new-handoff.ps1` | `handoff-envelope` | `adapter/schemas/handoff-envelope.internal.schema.json` |
| `recover-launch.ps1` | `recovery-envelope` | `adapter/schemas/recovery-envelope.internal.schema.json` |

adapter 命令在写 stdout 前再次执行同一 schema 校验，因此 schema 失败不会产生可消费
envelope。

## Metadata merge rule

MCP `update_task_binding` 接受 `metadata`，但该调用使用普通 update 语义；直接发送
`taskBindingPatch.metadata` 会覆盖 TaskBinding 现有 metadata。

controller 必须先取得当前 TaskBinding，然后本地合并：

```text
mergedMetadata = clone(binding.metadata || {})
mergedMetadata.methodLayer = envelope.taskBindingPatch.metadata.methodLayer
```

随后把 `mergedMetadata` 作为 `update_task_binding.metadata` 发送。不得丢弃
`binding.metadata` 中的 sibling keys。

planner 还必须把用于 merge 的 binding id、session id、role、status 和 metadata
SHA-256 写入 update step preconditions。executor 在 update 前使用 live lookup
重新核对；不一致时进入 `manual-review`，避免覆盖并发 metadata 变化。
当前 MCP update 没有 server-side CAS；因此 executor 默认阻止 metadata replacement，
只有显式 `-AllowNonAtomicTaskBindingUpdate` 才继续，并在 update 后核对完整计划字段。

`taskBindingPatch` 只包含 MCP 当前允许更新的字段：

- bind / handoff：`metadata`
- finish：`status`、`progress`、`completionSummary`、可选 `exitCode`、`metadata`

## Prepare -> launch_task

1. 执行 `prepare-launch.ps1`。
2. 验证 `prepare-launch-envelope`。
3. 原样映射 `launchTaskRequest` 到 MCP `launch_task`。
4. 将响应保存为项目内 JSON staging file。
5. 响应必须通过 `launch-response.internal.schema.json`。
6. 把 staging file 传给 `bind-launch.ps1`。

映射：

```text
launch_task(
  projectPath       = launchTaskRequest.projectPath,
  prompt            = launchTaskRequest.prompt,      # 与 resumeId 二选一
  resumeId          = launchTaskRequest.resumeId,
  cliTool           = launchTaskRequest.cliTool,
  profileId         = launchTaskRequest.profileId,
  runtimeKind       = launchTaskRequest.runtimeKind,
  providerId        = launchTaskRequest.providerId,
  providerSelection = launchTaskRequest.providerSelection,
  workspaceName     = launchTaskRequest.workspaceName,
  paneId            = launchTaskRequest.paneId,
  layoutId          = launchTaskRequest.layoutId,
  layoutName        = launchTaskRequest.layoutName,
  placement         = launchTaskRequest.placement
)
```

controller 必须分别记录：

- `response.taskId` -> launch status identity
- `response.sessionId` -> PTY/session identity
- method `taskId` -> task artifact identity

三者不得互相代用。

## Bind -> find -> update

1. 执行 `bind-launch.ps1` 并验证 `bind-launch-envelope`。
2. 调用：

```text
find_task_binding_by_session(
  sessionId = envelope.taskBindingLookup.sessionId
)
```

3. 返回 TaskBinding 时，读取其 `id` 和现有 `metadata`。
4. 按 metadata merge rule 合并。
5. 调用：

```text
update_task_binding(
  id       = binding.id,
  metadata = mergedMetadata
)
```

6. 再次按 `sessionId` 读取，断言：

```text
metadata.methodLayer.taskId  == envelope.taskBindingPatch.metadata.methodLayer.taskId
metadata.methodLayer.runId   == envelope.taskBindingPatch.metadata.methodLayer.runId
metadata.methodLayer.runPath == envelope.runPath
```

`find_task_binding_by_session` 返回 `null` 时：

- 已存在 leader/worker 注册上下文：走显式 `register_plan_worker` 或既定注册策略，
  再重新查询。
- 没有注册上下文：停止为 `manual-review`。
- 不使用 `launchTaskId` 伪造 TaskBinding ID。

## Finish -> update -> report

`finish-run.ps1` 已先发布 evidence，再 CAS 更新 run，最后才生成 envelope。

controller 顺序固定为：

1. 验证 `finish-run-envelope`。
2. 调用 `find_task_binding_by_session(sessionId =
   taskBindingLookup.sessionId)` 取得当前 TaskBinding。
3. 断言 `binding.id == leaderReport.workerId`；缺失或不一致时进入
   `manual-review`。
4. 合并 metadata。
5. 调用 `update_task_binding`：

```text
update_task_binding(
  id                = leaderReport.workerId,
  status            = taskBindingPatch.status,
  progress          = taskBindingPatch.progress,
  completionSummary = taskBindingPatch.completionSummary,
  exitCode          = taskBindingPatch.exitCode,
  metadata          = mergedMetadata
)
```

6. 按同一 `sessionId` readback，并核对 `latestEvidencePath`、状态、进度和摘要。
7. 判断本次 `update_task_binding` 是否已触发 CC-Panes 的 worker 终态自动通知：
   - fresh binding 是非终态且 patch status 是 `completed` / `failed`：视为自动通知已触发，
     不再手工补报。
   - 其它情况按 `leaderReport.dispatchPolicy == "if-not-auto-notified"` 进入手工补报。
8. 需要补报时调用：

```text
report_to_leader(
  workerId = leaderReport.workerId,
  status   = leaderReport.status,
  summary  = leaderReport.summary
)
```

9. 记录 `sent`、`queued` 或 `skipReason`。`skipReason` 不是方法层 evidence
   的改写理由；它是 transport 结果。

TaskBinding execution status 与 `methodOutcome` 保持分离。controller 不把
`methodOutcome=completed` 自动转换成 TaskBinding 状态。

## Handoff -> update

1. 执行 `new-handoff.ps1` 并验证 `handoff-envelope`。
2. 调用 `find_task_binding_by_session(sessionId =
   taskBindingLookup.sessionId)` 取得当前 TaskBinding；缺失时进入
   `manual-review`。
3. 合并 metadata。
4. 调用：

```text
update_task_binding(
  id       = binding.id,
  metadata = mergedMetadata
)
```

5. readback 并断言 `metadata.methodLayer.latestHandoffPath == envelope.handoffPath`。

handoff transport 不调用 `launch_task`，`nextOrder` 也不触发下一任务。

## Recovery action mapping

| `recoveryAction` | Controller action |
| --- | --- |
| `retry-launch` | 使用 controller journal 中原始、已验证的 `prepare-launch-envelope` 重试 `launch_task`；attempt 不保存 prompt body，缺少原始 envelope 时进入人工复核。 |
| `bind-response` | 按嵌套 `bindResult` 执行 Bind -> find -> update；不得再次 launch。 |
| `repair-metadata` | 通过 envelope 的 `sessionId` 查询 TaskBinding，合并并应用 `taskBindingPatch`，然后 readback。 |
| `already-bound` | 只做 run 与 TaskBinding metadata readback；不重复写入。 |
| `manual-review` | 停止自动 transport，保存 attempt、run、binding 和响应摘要；已有 methodLayer 的 task/run/path/session 身份冲突不得自动覆盖。 |

## Retry and failure rules

- adapter 文件写入使用 create-once/CAS；controller 不绕过 conflict。
- MCP 返回非 JSON 错误文本时，本次 transport 记为失败，不把它写成成功响应。
- `update_task_binding` 成功后 readback 失败，不发送 `report_to_leader`。
- `report_to_leader` 失败时不回滚 evidence/run/TaskBinding；由于它是非幂等通知，
  ambiguous delivery 不自动重试，进入 `manual-review`。
- `report_to_leader` 绕过自动去重；controller 必须执行 `dispatchPolicy`，避免在
  `update_task_binding` 已触发终态通知后重复发送。
- 合并后的 `update_task_binding` request 超过 65,536 UTF-8 bytes 时进入
  `manual-review`。
- 同一 transport 根因最多自主重试三轮。
- `launch_task` 与 `report_to_leader` 的 ambiguous delivery 最多一次；read 和
  `update_task_binding` 的 transient failure 才进入最多三次 retry。
- journal 使用 JSONL append-only sequence；response 单独 create-once 保存并记录
  SHA-256。重放只跳过 request hash 相同且已有成功 journal entry 的 mutation。
- 任一动作要求写入本仓库外的未授权路径、用户配置或 CC-Panes 主仓库时停止。

## 本仓库验证

本 runbook 对应的本地 contract tests：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tests\adapter\run.ps1 -Group envelope
pwsh -NoProfile -ExecutionPolicy Bypass -File tests\controller\run.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tests\controller-executor\run.ps1
powershell -ExecutionPolicy Bypass -File scripts\validate.ps1
```

自动检查使用注入式 fixture transport，不发起 live MCP 调用。生产 driver 的交付
验收另做只读 `find_task_binding_by_session` probe。
