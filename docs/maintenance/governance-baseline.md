# Repository Governance Baseline

本文件定义 `ccpanes-method-layer` 的自有评判标准。它只用于本仓库的维护决策，不替代用户指令、`AGENTS.md` 或已批准的任务授权。

## 适用范围

- 只评价本仓库当前状态与变更方向。
- 外部评论、评分、建议只作为输入，不作为唯一裁决。
- 当外部评价与本地事实冲突时，以本地文件、验证结果和授权边界为准。

## 我们如何判断是否在变好

1. **边界更清楚**
   - public schema、adapter、controller、文档和维护入口各自有明确职责。
   - v0.1 公共契约不在未授权情况下漂移。

2. **证据更强**
   - 完成性、兼容性和风险判断都要能被本地验证覆盖。
   - 改动后的结论要和实际检查结果一致。

3. **来源更可追**
   - 上游吸收记录 URL、版本 / commit、采用理由、改写点和舍弃点。
   - 许可状态和 provenance 缺口保持显式，不靠口头假设补齐。

4. **入口更清楚**
   - 新维护者能从 `README.md`、`HANDOFF.md` 和本文件快速找到当前基线。
   - 历史快照会被明确标注，不与当前权威状态混淆。

5. **变更更克制**
   - 只触达必要路径，不顺手扩范围。
   - 非授权情况下优先做文档、验证和边界收敛，不碰公共契约语义。

## 当前仓库基线

- Repository: `D:\ccpanes-method-layer`
- Branch: `codex/official-ccpanes-companion`
- HEAD: `704e6a090f1ba74869219b4318e559c927265711`
- Remote: `origin -> https://github.com/lihuabin1516-design/ccpanes-method-layer.git`
- License / provenance decision: [`docs/maintenance/license-provenance-decision.md`](docs/maintenance/license-provenance-decision.md)
- Public protocol: `task` / `run` / `evidence` / `handoff` v0.1 remains stable.
- Validation gate: `scripts/validate.ps1` covers schema syntax, examples, templates, Prompt Pack, Companion, adapter, controller, hash / byte rules, and `tests/.tmp` cleanup.

## 决策规则

- 若某个改动只让叙述更漂亮，但削弱边界、证据、来源或接手效率，则不算改进。
- 若外部评价给出高分，但本地事实、验证或授权不支持，按本地事实处理。
- 若一个改动会影响 v0.1 公共契约，先看是否有明确授权、验证和回滚说明。
