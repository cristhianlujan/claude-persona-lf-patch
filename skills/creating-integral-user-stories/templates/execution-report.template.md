# Reporte de ejecución integral

Versión operativa: `v0.5`. Los porcentajes se calculan desde `schemas/execution-ledger.schema.json`; nunca se estiman manualmente.

## Identidad

```yaml
execution_id: EXEC-BISC-005-DEEP-AUDIT
operation_code: BUILD_INTEGRAL_STORY_CREATOR_LF
target_artifact: creating-integral-user-stories
repository: cristhianlujan/claude-persona-lf-patch
base_branch: feat/integral-story-creator-r8-forward
branch: fix/deep-audit-a01-a62
pr_number: 57
draft_pr: true
production_authorized: false
merge_authorized: false
runtime_enabled: false
```

## Estado por step

| Orden | step_id | Requerido | Aplicable | Crítico | Estado | Bit | Juez | Intento | Evidencia |
|---:|---|---|---|---|---|---:|---|---:|---|
| 1 | STEP-ID | sí | sí | sí | PASS_WITH_EVIDENCE | 1 | J01_SOURCE_INTEGRITY | 0 | ruta resoluble |

Cada fila corresponde a un objeto del ledger. Un step `PASS_WITH_EVIDENCE` exige bit 1, juez PASS, evidence refs no vacíos y hashes válidos.

## Estado por artefacto

| Código | Ruta | Tipo | Versión | Claude /10 | GitHub /10 | Técnica /10 | Final MIN /10 | Positivos | Negativos | BLOCKED/FAIL | Git blob | SHA-256 | GitHub–Supabase | Estado |
|---|---|---|---:|---:|---:|---:|---:|---|---|---|---|---|---|---|
| A01 | ruta | tipo | 1 | 10.0 | 10.0 | 10.0 | 10.0 | PASS | REJECTED | PASS | blob | sha256 | MATCH | PASS_WITH_EVIDENCE |

La nota final se calcula así:

```text
NOTA_FINAL = MIN(NOTA_CLAUDE, NOTA_GITHUB, NOTA_TECNICA)
```

No se declara verde por revisión editorial aislada.

## Evidencia de transporte

```yaml
expected_files:
written_files:
readback_files:
unexpected_written_files:
missing_written_files:
sha_mismatches:
canonical_sha256_map:
github_blob_sha1_map:
commit_sha:
pr_number: 57
draft_state: true
direct_main_write_detected: false
merged: false
released: false
tagged: false
```

## Evidencia de ejecución

```yaml
positive_cases_executed:
negative_cases_executed:
negative_cases_rejected:
blocked_cases_executed:
fail_cases_executed:
runtime_blockers:
assertions_missing:
assertions_orphan:
benchmark_snapshot_ref: tools/benchmark-snapshot.json
workflow_run_id:
evidence_artifact_id:
```

## Estado Supabase

```yaml
canonical_current_rows: 62
canonical_distinct_paths: 62
canonical_sha_mismatches:
canonical_pass_count:
canonical_not_validated_count:
latest_event_id:
versions_written:
readback_verified:
```

## Cierre

```yaml
required_steps:
passed_steps:
critical_steps_with_bit_zero:
steps_without_evidence:
applicable_judges:
judges_passed_with_evidence:
judges_failed:
judges_pending:
blocking_findings:
artifacts_required: 62
artifacts_deep_audited:
artifacts_github_confirmed:
artifacts_supabase_synced:
completion_percent:
final_result: IN_PROGRESS
```

El único cierre satisfactorio es `PASS_WITH_EVIDENCE` con 100%, 62/62 sincronizados, cero hallazgos bloqueantes y readback GitHub–Supabase completo. Mientras cualquier artefacto permanezca pendiente, el reporte conserva `IN_PROGRESS`.

## Restricciones preservadas

```text
direct_main_write = false
merge = false
production = false
runtime_enabled = false
release = false
tag = false
```

## Fuentes de diseño no normativas

- **anthropics/skills:** evals objetivas, evidencia y reparación iterativa.
- **microsoft/vscode:** workflows, outputs y stop conditions.
- **freeCodeCamp/freeCodeCamp:** constraints y rechazo determinista.
- **Significant-Gravitas/AutoGPT:** persistencia y límites operativos.

Los contratos LF prevalecen.
