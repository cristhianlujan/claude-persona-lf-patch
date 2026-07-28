# Reporte de ejecucion — <EXECUTION_ID>

## Por step

```text
STEP [n/total]
step_id:
status:
compliance_bit:
evidence:
judge:
failed_assertions:
next_step:
```

## Por fase

```text
PHASE:
steps_expected:
steps_passed:
steps_failed:
steps_blocked:
completion_percent:
files_created:
open_findings:
```

## Cierre

```yaml
execution_id:
required_steps:
passed_steps:
failed_steps:
blocked_steps:
missing_steps:
steps_without_evidence:
expected_files:
written_files:
readback_files:
unexpected_files:
sha_mismatches:
required_judges:
judges_passed:
judges_failed:
judges_pending:
required_evals:
evals_passed:
evals_failed:
critical_assertions_failed:
completion_percent:
final_result:
repository:
branch:
commit_sha:
draft_pr:
production_authorized: false
merge_authorized: false
runtime_enabled: false
```

El porcentaje se calcula desde el ledger con
`scripts/calculate_binary_completion.py`. Prohibido informar porcentajes
estimados. Unico cierre satisfactorio: `PASS_WITH_EVIDENCE`.
