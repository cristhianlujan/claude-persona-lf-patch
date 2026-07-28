# Reporte de ejecución integral

Versión operativa: `v0.3`. Los porcentajes se calculan desde
`schemas/execution-ledger.schema.json`; nunca se estiman manualmente.

## Identidad

```yaml
execution_id: EXECUTION-CODE
operation_code: BUILD_INTEGRAL_STORY_CREATOR_LF
target_artifact: creating-integral-user-stories
repository: repository-name
branch: feature-branch
draft_pr: true
production_authorized: false
merge_authorized: false
runtime_enabled: false
```

## Estado por step

| Orden | step_id | Requerido | Aplicable | Crítico | Estado | Bit | Juez | Intento | Evidencia |
|---:|---|---|---|---|---|---:|---|---:|---|
| 1 | STEP-ID | sí | sí | sí | PASS_WITH_EVIDENCE | 1 | J01_SOURCE_INTEGRITY | 0 | ruta resoluble |

Cada fila debe corresponder a un objeto del ledger. Un step con
`PASS_WITH_EVIDENCE` requiere bit 1, juez PASS y evidencia no vacía.

## Estado por artefacto

| Ruta | Tipo | Versión antes | Versión después | Bytes antes | Bytes después | Cambio % | Score antes | Score después | Mejora pp | Status | Fuentes principales |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| ruta | tipo | 1 | 2 | 1000 | 4000 | 300.0 | 35 | 92 | 57 | PASS_WITH_EVIDENCE | repo1; repo2; repo3 |

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
pr_number:
draft_state:
direct_main_write_detected: false
merged: false
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
completion_percent:
final_result:
```

El único cierre satisfactorio es `PASS_WITH_EVIDENCE` con 100%, cero hallazgos
bloqueantes y readback completo.

## Fuentes de diseño no normativas

- **microsoft/vscode** (~186,000 estrellas): `extensions/copilot/assets/prompts/skills/chronicle/SKILL.md`; patrones: prerrequisitos, workflows paso a paso, formatos de salida y stop conditions.
- **freeCodeCamp/freeCodeCamp** (~446,000 estrellas): `curriculum/schema/challenge-schema.js`; patrones: validación condicional, campos obligatorios, mensajes de error verificables.
- **huggingface/transformers** (~162,000 estrellas): `docs/source/en/testing.md`; patrones: arquitectura de pruebas reutilizable, casos rápidos y lentos, regresión y cobertura negativa.
