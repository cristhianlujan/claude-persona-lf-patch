# Checklist auditable R8 — Creating Integral User Stories

Fecha de corte: 2026-07-29  
Ejecución: `EXEC-BISC-004`  
Rama: `feat/integral-story-creator-r8-forward`  
Inventario canónico: **62 artefactos**  
Este archivo es auxiliar y **no incrementa el inventario canónico**.

## Reglas del semáforo

### Semáforo de nota benchmark

- 🟢 Verde: nota **mayor a 9.5**.
- 🟡 Amarillo: nota entre **8.5 y 9.5**, inclusive.
- 🔴 Rojo: nota menor a **8.5**.
- ⚪ Blanco: todavía no existe una nota benchmark verificable.

La nota compara calidad editorial y contractual con patrones de Claude Skills y repositorios GitHub de referencia. Los conteos de estrellas son contexto, no evidencia de aprobación.

### Semáforo técnico

- 🟢 Completo: contrato alineado, runtime PASS, prueba negativa PASS y evidencia GitHub–Supabase.
- 🟡 Evidencia incompleta: existe PASS canónico, pero falta demostrar uno o más gates del patrón nuevo.
- 🔴 Runtime bloqueado o falla material.
- ⚪ Pendiente: todavía no auditado con el patrón nuevo.

Un artefacto no se considera cerrado por la nota solamente.

## Checklist por artefacto

| N.º | Lote | Artefacto | Tipo | Versión | Nota /10 | Semáforo nota | Semáforo técnico | Contrato | Runtime | Prueba negativa | GitHub–Supabase |
|---|---|---|---|---:|---:|---|---|---|---|---|---|
| A01 | BATCH-05-09 | `agents/cross-cutting-enricher.md` | AGENT | v4 | 9.7 | 🟢 | 🟡 Evidencia incompleta | PARTIAL | PASS | — | ✅ |
| A02 | PREVIO | `agents/field-contract-author.md` | AGENT | v3 | 9.7 | 🟢 | 🟡 Evidencia incompleta | PASS | — | — | ✅ |
| A03 | BATCH-05-04 | `agents/screen-decomposer.md` | AGENT | v2 | 9.7 | 🟢 | 🟡 Evidencia incompleta | PASS | — | — | ✅ |
| A04 | PREVIO | `agents/story-core-author.md` | AGENT | v2 | — | ⚪ | 🟡 Evidencia incompleta | PASS | — | — | ✅ |
| A05 | BATCH-05-04 | `agents/test-deriver.md` | AGENT | v2 | 9.7 | 🟢 | 🟡 Evidencia incompleta | PASS | — | — | ✅ |
| A06 | PREVIO | `evals/assertions.json` | EVAL | v2 | — | ⚪ | 🟡 Evidencia incompleta | PASS | — | — | ✅ |
| A07 | PREVIO | `evals/evals.json` | EVAL | v2 | — | ⚪ | 🟡 Evidencia incompleta | PASS | — | — | ✅ |
| A08 | PREVIO | `evals/fixtures/screen_insufficient_definition.json` | FIXTURE | v2 | — | ⚪ | 🟡 Evidencia incompleta | PASS | — | — | ✅ |
| A09 | PREVIO | `evals/fixtures/screen_sensitive_fields.json` | FIXTURE | v2 | — | ⚪ | 🟡 Evidencia incompleta | PASS | — | PASS | ✅ |
| A10 | PREVIO | `evals/fixtures/screen_simple_query.json` | FIXTURE | v2 | — | ⚪ | 🟡 Evidencia incompleta | PASS | — | — | ✅ |
| A11 | BATCH-05-05 | `evals/fixtures/screen_wizard_six_steps.json` | FIXTURE | v3 | 9.8 | 🟢 | 🟡 Evidencia incompleta | PASS | — | — | ✅ |
| A12 | BATCH-05-04 | `evals/trigger-evals.json` | EVAL | v3 | 9.8 | 🟢 | 🟡 Evidencia incompleta | PASS | — | — | ✅ |
| A13 | BATCH-05-09 | `judges/analytics-observability.yaml` | JUDGE | v4 | 9.8 | 🟢 | 🟢 Completo | PASS | PASS | PASS | ✅ |
| A14 | BATCH-05-08 | `judges/audit-traceability.yaml` | JUDGE | v4 | 9.8 | 🟢 | 🟢 Completo | PASS | PASS | PASS | ✅ |
| A15 | PREVIO | `judges/field-contracts.yaml` | JUDGE | v3 | 9.7 | 🟢 | 🟢 Completo | PASS | PASS | PASS | ✅ |
| A16 | PREVIO | `judges/observations-errors.yaml` | JUDGE | v3 | 9.7 | 🟢 | 🟢 Completo | PASS | PASS | PASS | ✅ |
| A17 | BATCH-05-05 | `judges/screen-decomposition.yaml` | JUDGE | v3 | 9.7 | 🟢 | 🔴 Runtime bloqueado | PASS | BLOCKED_DEDICATED_VALIDATOR_NOT_AVAILABLE | — | ✅ |
| A18 | BATCH-05-08 | `judges/security-privacy.yaml` | JUDGE | v3 | 9.8 | 🟢 | 🟢 Completo | PASS | PASS | PASS | ✅ |
| A19 | PREVIO | `judges/skill-package.yaml` | JUDGE | v2 | — | ⚪ | 🟡 Evidencia incompleta | PASS | — | — | ✅ |
| A20 | PREVIO | `judges/story-core.yaml` | JUDGE | v3 | — | ⚪ | 🟡 Evidencia incompleta | PASS | — | PASS | ✅ |
| A21 | BATCH-05-05 | `judges/test-coverage.yaml` | JUDGE | v3 | 9.7 | 🟢 | 🔴 Runtime bloqueado | PASS | BLOCKED_DEDICATED_VALIDATOR_NOT_AVAILABLE | — | ✅ |
| A22 | BATCH-05-09 | `judges/tokens-messages.yaml` | JUDGE | v4 | 9.8 | 🟢 | 🟢 Completo | PASS | PASS | PASS | ✅ |
| A23 | PREVIO | `manifest.yaml` | MANIFEST | v2 | — | ⚪ | 🟡 Evidencia incompleta | PASS | — | — | ✅ |
| A24 | BATCH-05-06 | `perfiles/PERFIL_CROSS_CUTTING_ENRICHER_LF.md` | PROFILE | v2 | 9.7 | 🟢 | 🟡 Evidencia incompleta | PASS | — | — | ✅ |
| A25 | BATCH-05-06 | `perfiles/PERFIL_FIELD_CONTRACT_AUDITOR_LF.md` | PROFILE | v2 | 9.7 | 🟢 | 🟡 Evidencia incompleta | PASS | — | — | ✅ |
| A26 | BATCH-05-06 | `perfiles/PERFIL_SCREEN_DECOMPOSER_LF.md` | PROFILE | v2 | 9.7 | 🟢 | 🟡 Evidencia incompleta | PASS | — | — | ✅ |
| A27 | PREVIO | `references/field-contract.md` | REFERENCE | v3 | — | ⚪ | 🟡 Evidencia incompleta | PASS | — | PASS | ✅ |
| A28 | PREVIO | `references/observations-errors-contract.md` | REFERENCE | v3 | — | ⚪ | 🟡 Evidencia incompleta | PASS | — | PASS | ✅ |
| A29 | PREVIO | `references/story-pack-contract.md` | REFERENCE | v3 | — | ⚪ | 🟡 Evidencia incompleta | PASS | — | — | ✅ |
| A30 | PREVIO | `schemas/story-pack.schema.json` | SCHEMA | v2 | — | ⚪ | 🟡 Evidencia incompleta | PASS | — | — | ✅ |
| A31 | BATCH-05-09 | `scripts/detect_pii_telemetry.py` | SCRIPT | v6 | 9.8 | 🟢 | 🟢 Completo | PASS | PASS | PASS | ✅ |
| A32 | PREVIO | `scripts/lf_common.py` | SHARED_MODULE | v5 | 9.7 | 🟢 | 🟡 Evidencia incompleta | PASS | — | — | ✅ |
| A33 | PREVIO | `scripts/validate_field_coverage.py` | SCRIPT | v3 | — | ⚪ | 🟡 Evidencia incompleta | PASS | — | PASS | ✅ |
| A34 | PREVIO | `scripts/validate_package.py` | SCRIPT | v5 | — | ⚪ | 🟢 Completo | PASS | PASS | PASS | ✅ |
| A35 | BATCH-05-08 | `scripts/validate_security_coverage.py` | SCRIPT | v4 | 9.8 | 🟢 | 🟢 Completo | PASS | PASS | PASS | ✅ |
| A36 | PREVIO | `scripts/validate_story_pack.py` | SCRIPT | v4 | — | ⚪ | 🟡 Evidencia incompleta | PASS | PASS | — | ✅ |
| A37 | BATCH-05-09 | `scripts/validate_tokens.py` | SCRIPT | v6 | 9.8 | 🟢 | 🟢 Completo | PASS | PASS | PASS | ✅ |
| A38 | BATCH-05-01 | `scripts/validate_traceability.py` | SCRIPT | v6 | 9.8 | 🟢 | 🟡 Evidencia incompleta | PASS | — | — | ✅ |
| A39 | 05-10 | `perfiles/PERFIL_STORY_CORE_AUTHOR_LF.md` | PROFILE | v2 | — | ⚪ | ⚪ Pendiente | — | — | — | ✅ |
| A40 | 05-10 | `perfiles/PERFIL_STORY_TEST_DERIVER_LF.md` | PROFILE | v2 | — | ⚪ | ⚪ Pendiente | — | — | — | ✅ |
| A41 | 05-10 | `references/test-derivation-contract.md` | REFERENCE | v2 | — | ⚪ | ⚪ Pendiente | — | — | — | ✅ |
| A42 | 05-11 | `judges/source-integrity.yaml` | JUDGE | v2 | — | ⚪ | ⚪ Pendiente | — | — | — | ✅ |
| A43 | 05-11 | `references/screen-decomposition-protocol.md` | REFERENCE | v2 | — | ⚪ | ⚪ Pendiente | — | — | — | ✅ |
| A44 | 05-11 | `schemas/screen-decomposition.schema.json` | SCHEMA | v2 | — | ⚪ | ⚪ Pendiente | — | — | — | ✅ |
| A45 | 05-12 | `references/security-privacy-contract.md` | REFERENCE | v2 | — | ⚪ | ⚪ Pendiente | — | — | — | ✅ |
| A46 | 05-12 | `references/audit-traceability-contract.md` | REFERENCE | v2 | — | ⚪ | ⚪ Pendiente | — | — | — | ✅ |
| A47 | 05-12 | `references/tokens-messages-contract.md` | REFERENCE | v2 | — | ⚪ | ⚪ Pendiente | — | — | — | ✅ |
| A48 | 05-13 | `references/analytics-observability-contract.md` | REFERENCE | v2 | — | ⚪ | ⚪ Pendiente | — | — | — | ✅ |
| A49 | 05-13 | `references/accessibility-responsive-contract.md` | REFERENCE | v2 | — | ⚪ | ⚪ Pendiente | — | — | — | ✅ |
| A50 | 05-13 | `references/supabase-source-map.md` | REFERENCE | v2 | — | ⚪ | ⚪ Pendiente | — | — | — | ✅ |
| A51 | 05-14 | `schemas/task-packet.schema.json` | SCHEMA | v2 | — | ⚪ | ⚪ Pendiente | — | — | — | ✅ |
| A52 | 05-14 | `schemas/coverage-report.schema.json` | SCHEMA | v2 | — | ⚪ | ⚪ Pendiente | — | — | — | ✅ |
| A53 | 05-14 | `schemas/execution-ledger.schema.json` | SCHEMA | v2 | — | ⚪ | ⚪ Pendiente | — | — | — | ✅ |
| A54 | 05-15 | `templates/story-pack.template.json` | TEMPLATE | v2 | — | ⚪ | ⚪ Pendiente | — | — | — | ✅ |
| A55 | 05-15 | `templates/story-pack.template.md` | TEMPLATE | v2 | — | ⚪ | ⚪ Pendiente | — | — | — | ✅ |
| A56 | 05-15 | `templates/judge-contract.template.yaml` | TEMPLATE | v2 | — | ⚪ | ⚪ Pendiente | — | — | — | ✅ |
| A57 | 05-16 | `scripts/calculate_binary_completion.py` | SCRIPT | v3 | — | ⚪ | ⚪ Pendiente | — | — | — | ✅ |
| A58 | 05-16 | `judges/github-integrity.yaml` | JUDGE | v2 | — | ⚪ | ⚪ Pendiente | — | — | — | ✅ |
| A59 | 05-16 | `judges/integration-close.yaml` | JUDGE | v2 | — | ⚪ | ⚪ Pendiente | — | — | — | ✅ |
| A60 | 05-17 | `templates/execution-report.template.md` | TEMPLATE | v2 | — | ⚪ | ⚪ Pendiente | — | — | — | ✅ |
| A61 | 05-17 | `schemas/judge-result.schema.json` | SCHEMA | v5 | — | ⚪ | ⚪ Pendiente | — | — | — | ✅ |
| A62 | 05-17 | `SKILL.md` | SKILL_MD | v6 | — | ⚪ | ⚪ Pendiente | — | — | — | ✅ |

## Checklist obligatorio para cambiar una fila a verde técnico

- [ ] Nota benchmark mayor a 9.5.
- [ ] Contrato del artefacto alineado con el worker, juez, validador y schema aplicables.
- [ ] Caso positivo ejecutado con resultado esperado.
- [ ] Caso negativo ejecutado y rechazado correctamente.
- [ ] Casos `BLOCKED` y `FAIL` cubiertos cuando apliquen.
- [ ] Cero assertions huérfanas o renombradas.
- [ ] Git blob registrado.
- [ ] SHA-256 GitHub igual a SHA-256 Supabase.
- [ ] Sin bloqueos abiertos.
- [ ] Evidencia y limitaciones visibles.

## Instrucción de auditoría para Claude

Audita cada fila sin confiar en el semáforo declarado. Para cada artefacto:

1. abre el contenido actual en GitHub;
2. verifica el blob y calcula SHA-256;
3. compara con la fila actual de Supabase;
4. confirma la nota benchmark y su evidencia;
5. verifica contrato, runtime y prueba negativa;
6. identifica PASS antiguos incompatibles con el patrón nuevo;
7. devuelve `CONFIRMED`, `RETURN_TO_WORKER` o `BLOCKED_WITH_EVIDENCE`;
8. no cambies el porcentaje hasta cerrar todos los gates de la fila.

Hallazgos visibles al crear esta matriz:

- `A17 judges/screen-decomposition.yaml`: nota 9.7, pero runtime dedicado no disponible.
- `A21 judges/test-coverage.yaml`: nota 9.7, pero runtime dedicado no disponible.
- Varias filas con PASS histórico siguen amarillas porque su evidencia no contiene todos los campos del patrón nuevo.
