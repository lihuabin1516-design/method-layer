# Upstream Evidence: Lattice

- Repository: `https://github.com/percena/lattice.git`
- Default branch: `main`
- Commit SHA: `855085ba501de90f33f0c9e34821ca291270ccce`
- Query date: `2026-08-05`
- Query command: `git ls-remote --symref https://github.com/percena/lattice.git HEAD`

## 本地采用点

- `spec` / `ticket` / `review` / PR 血缘映射到 `task.lineage`。
- worktree 绑定映射到 `run.workspace.worktreePath`。
- alignment check 映射到 `evidence.driftCheck`。
- finish ledger 思想由 `evidence` 和 `handoff` 组合承担。

## 本地改写点

- `.lattice/` 和 slash workflow 改写为普通 JSON artifact、Markdown 模板和未来 CC-Panes adapter。
- GitHub identifier 只作为可选 lineage，不是 task intake 的唯一入口。
- merge、push、cleanup 等动作不从上游继承，继续受本地授权门禁约束。
- v0.1 不建立独立 closure artifact。

## 舍弃点

- 不 vendor Lattice skill、plugin 或完整目录。
- 不默认要求 GitHub Issues / PR。
- 不启用远端写入、自动 merge 或 branch cleanup。

## 剩余不确定性

- 本轮通过远端 HEAD 查询确认了默认分支和 commit identity，没有把上游仓库 checkout 到本地，也没有对该 commit 的全部实现重新审计。
- 上游后续变更不会自动进入本地协议；再次吸收前必须重新记录 commit 和差异。
