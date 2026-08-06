# v0.1 Examples

`valid/` contains one complete instance for each v0.1 artifact type. Every file must pass its matching schema.

`invalid/` contains one focused contract violation per artifact:

| File | Expected failure |
| --- | --- |
| `task-missing-objective.json` | The required `objective` property is absent. |
| `run-empty-contract.json` | The required contract snapshot has none of its required fields. |
| `evidence-empty-checks.json` | `checks` violates `minItems: 1`. |
| `handoff-missing-required-reading.json` | The required `requiredReading` property is absent. |

Run all syntax and instance assertions from the repository root:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/validate.ps1
```
