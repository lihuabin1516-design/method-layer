# Upstream Evidence: Aegis

- Repository: `https://github.com/GanyuanRan/Aegis.git`
- Default branch: `main`
- Commit SHA: `a1f15466d33b215fadd94a2dc14c78372d5df1a4`
- Query date: `2026-08-05`
- Query command: `git ls-remote --symref https://github.com/GanyuanRan/Aegis.git HEAD`

## 本地采用点

- baseline-first 映射到 `task.baseline` 和 `handoff.baseline`。
- evidence-before-completion 映射到 `task.requiredEvidence` 和 `evidence.checks`。
- drift check、proof bundle 和 long-task continuation 映射到 `evidence` 与 `handoff`。
- workflow depth 映射到 advisory-only `task.riskMode`。

## 本地改写点

- `docs/aegis/` ceremony 改写为四类轻量、独立验证的 JSON artifact。
- method-pack 自动触发改写为未来 CC-Panes adapter 显式生成 run/evidence/handoff。
- completion authority 继续属于项目规则、实际证据和当前用户授权。
- repair/retirement track 不在 v0.1 定义 `changeDisposition`。

## 舍弃点

- 不直接覆盖项目 `AGENTS.md`。
- 不启用全量自动触发。
- 不让方法包自行授予 completion、merge 或远端权限。
- 不 vendor Aegis 成品目录。

## 剩余不确定性

- 本轮通过远端 HEAD 查询确认了默认分支和 commit identity，没有把上游仓库 checkout 到本地，也没有对该 commit 的全部实现重新审计。
- `changeDisposition` 是否进入后续版本，需由实际 adapter 和 retirement 用例驱动。
