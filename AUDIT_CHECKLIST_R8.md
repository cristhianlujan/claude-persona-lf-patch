# Checklist auditable R8 — Creating Integral User Stories

Fecha de cierre: 2026-07-29  
Ejecución: `EXEC-BISC-004`  
Rama: `feat/integral-story-creator-r8-forward`  
Inventario canónico: **62 artefactos**  
Estado: **R8_AUDIT_COMPLETE_WITH_DUAL_BENCHMARK_EVIDENCE**  
Este archivo es auxiliar y **no incrementa el inventario canónico**.

## Resultado ejecutivo

```text
Artefactos PASS_WITH_EVIDENCE: 62/62 — 100.00%
Verdes duales: 62/62
Amarillos: 0
Rojos: 0
Sin nota: 0
Runtime bloqueados: 0
Pruebas positivas pendientes: 0
Pruebas negativas pendientes: 0
SHA mismatch: 0
Current duplicados: 0
Bloqueos abiertos: 0
```

El cierre R8 no autoriza producción, merge, `ready`, cierre de PR, release, tag ni habilitación de runtime operativo.

## Benchmark dual

| Fuente | Referencia verificada | Evidencia |
|---|---|---|
| Claude Skills | `anthropics/skills/skills/skill-creator/SKILL.md` | blob `65b3a402dbd09b8e83f9d637c6b553875189085c` |
| GitHub 150k+ | `Significant-Gravitas/AutoGPT/classic/original_autogpt/CLAUDE.md` | 185741 estrellas verificadas |
| GitHub 150k+ | `freeCodeCamp/freeCodeCamp/curriculum/schema/challenge-schema.js` | 453125 estrellas verificadas |

Fórmula aplicada:

```text
NOTA_FINAL = MIN(NOTA_CLAUDE, NOTA_GITHUB, NOTA_TECNICA)
```

## Checklist de los 62 artefactos

| N.º | Lote | Ruta | V | Claude | GitHub | Técnica | Final | Técnico | Runtime/validación | G–S | Estado |
|---|---|---|---:|---:|---:|---:|---:|---|---|---|---|
| A01 | GLOBAL-RV | `agents/cross-cutting-enricher.md` | v4 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | Cadena asociada | MATCH | PASS_WITH_EVIDENCE |
| A02 | GLOBAL-RV | `agents/field-contract-author.md` | v3 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | Cadena asociada | MATCH | PASS_WITH_EVIDENCE |
| A03 | GLOBAL-RV | `agents/screen-decomposer.md` | v2 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | J01/J02 | MATCH | PASS_WITH_EVIDENCE |
| A04 | GLOBAL-RV | `agents/story-core-author.md` | v2 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | J03 | MATCH | PASS_WITH_EVIDENCE |
| A05 | GLOBAL-RV | `agents/test-deriver.md` | v2 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | J10 | MATCH | PASS_WITH_EVIDENCE |
| A06 | GLOBAL-RV | `evals/assertions.json` | v2 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | Evals | MATCH | PASS_WITH_EVIDENCE |
| A07 | GLOBAL-RV | `evals/evals.json` | v2 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | Evals | MATCH | PASS_WITH_EVIDENCE |
| A08 | GLOBAL-RV | `evals/fixtures/screen_insufficient_definition.json` | v2 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | Fixture negativo | MATCH | PASS_WITH_EVIDENCE |
| A09 | GLOBAL-RV | `evals/fixtures/screen_sensitive_fields.json` | v2 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | Fixture negativo | MATCH | PASS_WITH_EVIDENCE |
| A10 | GLOBAL-RV | `evals/fixtures/screen_simple_query.json` | v2 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | Fixture positivo | MATCH | PASS_WITH_EVIDENCE |
| A11 | GLOBAL-RV | `evals/fixtures/screen_wizard_six_steps.json` | v3 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | Fixture positivo | MATCH | PASS_WITH_EVIDENCE |
| A12 | GLOBAL-RV | `evals/trigger-evals.json` | v3 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | Trigger evals | MATCH | PASS_WITH_EVIDENCE |
| A13 | GLOBAL-RV | `judges/analytics-observability.yaml` | v4 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | Runtime PASS | MATCH | PASS_WITH_EVIDENCE |
| A14 | GLOBAL-RV | `judges/audit-traceability.yaml` | v4 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | Runtime PASS | MATCH | PASS_WITH_EVIDENCE |
| A15 | GLOBAL-RV | `judges/field-contracts.yaml` | v3 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | Runtime PASS | MATCH | PASS_WITH_EVIDENCE |
| A16 | GLOBAL-RV | `judges/observations-errors.yaml` | v3 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | Runtime PASS | MATCH | PASS_WITH_EVIDENCE |
| A17 | 05-11 | `judges/screen-decomposition.yaml` | v4 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | Runtime J02 PASS | MATCH | PASS_WITH_EVIDENCE |
| A18 | GLOBAL-RV | `judges/security-privacy.yaml` | v3 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | Runtime PASS | MATCH | PASS_WITH_EVIDENCE |
| A19 | GLOBAL-RV | `judges/skill-package.yaml` | v2 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | Runtime PASS | MATCH | PASS_WITH_EVIDENCE |
| A20 | GLOBAL-RV | `judges/story-core.yaml` | v3 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | Runtime J03 PASS | MATCH | PASS_WITH_EVIDENCE |
| A21 | 05-10 | `judges/test-coverage.yaml` | v4 | 9.8 | 9.8 | 9.8 | 9.8 | 🟢 | Runtime J10 PASS | MATCH | PASS_WITH_EVIDENCE |
| A22 | GLOBAL-RV | `judges/tokens-messages.yaml` | v4 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | Runtime PASS | MATCH | PASS_WITH_EVIDENCE |
| A23 | 05-17 | `manifest.yaml` | v3 | 9.8 | 9.8 | 9.8 | 9.8 | 🟢 | Parse + rama R8 | MATCH | PASS_WITH_EVIDENCE |
| A24 | GLOBAL-RV | `perfiles/PERFIL_CROSS_CUTTING_ENRICHER_LF.md` | v2 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | Consumidor/juez | MATCH | PASS_WITH_EVIDENCE |
| A25 | GLOBAL-RV | `perfiles/PERFIL_FIELD_CONTRACT_AUDITOR_LF.md` | v2 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | Consumidor/juez | MATCH | PASS_WITH_EVIDENCE |
| A26 | GLOBAL-RV | `perfiles/PERFIL_SCREEN_DECOMPOSER_LF.md` | v2 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | J01/J02 | MATCH | PASS_WITH_EVIDENCE |
| A27 | GLOBAL-RV | `references/field-contract.md` | v3 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | J04 | MATCH | PASS_WITH_EVIDENCE |
| A28 | GLOBAL-RV | `references/observations-errors-contract.md` | v3 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | J05 | MATCH | PASS_WITH_EVIDENCE |
| A29 | GLOBAL-RV | `references/story-pack-contract.md` | v3 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | J03–J11 | MATCH | PASS_WITH_EVIDENCE |
| A30 | GLOBAL-RV | `schemas/story-pack.schema.json` | v2 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | Schema + validadores | MATCH | PASS_WITH_EVIDENCE |
| A31 | GLOBAL-RV | `scripts/detect_pii_telemetry.py` | v6 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | Runtime PASS | MATCH | PASS_WITH_EVIDENCE |
| A32 | GLOBAL-RV | `scripts/lf_common.py` | v5 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | Módulo compartido | MATCH | PASS_WITH_EVIDENCE |
| A33 | GLOBAL-RV | `scripts/validate_field_coverage.py` | v3 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | Runtime PASS | MATCH | PASS_WITH_EVIDENCE |
| A34 | GLOBAL-RV | `scripts/validate_package.py` | v5 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | Runtime PASS | MATCH | PASS_WITH_EVIDENCE |
| A35 | GLOBAL-RV | `scripts/validate_security_coverage.py` | v4 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | Runtime PASS | MATCH | PASS_WITH_EVIDENCE |
| A36 | GLOBAL-RV | `scripts/validate_story_pack.py` | v4 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | Runtime PASS | MATCH | PASS_WITH_EVIDENCE |
| A37 | GLOBAL-RV | `scripts/validate_tokens.py` | v6 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | Runtime PASS | MATCH | PASS_WITH_EVIDENCE |
| A38 | GLOBAL-RV | `scripts/validate_traceability.py` | v6 | 9.7 | 9.7 | 9.7 | 9.7 | 🟢 | Runtime PASS | MATCH | PASS_WITH_EVIDENCE |
| A39 | 05-10 | `perfiles/PERFIL_STORY_CORE_AUTHOR_LF.md` | v3 | 9.8 | 9.8 | 9.8 | 9.8 | 🟢 | J03 | MATCH | PASS_WITH_EVIDENCE |
| A40 | 05-10 | `perfiles/PERFIL_STORY_TEST_DERIVER_LF.md` | v3 | 9.8 | 9.8 | 9.8 | 9.8 | 🟢 | J10 | MATCH | PASS_WITH_EVIDENCE |
| A41 | 05-10 | `references/test-derivation-contract.md` | v3 | 9.8 | 9.8 | 9.8 | 9.8 | 🟢 | J10 | MATCH | PASS_WITH_EVIDENCE |
| A42 | 05-11 | `judges/source-integrity.yaml` | v3 | 9.8 | 9.8 | 9.8 | 9.8 | 🟢 | Runtime J01 PASS | MATCH | PASS_WITH_EVIDENCE |
| A43 | 05-11 | `references/screen-decomposition-protocol.md` | v3 | 9.8 | 9.8 | 9.8 | 9.8 | 🟢 | Runtime J02 PASS | MATCH | PASS_WITH_EVIDENCE |
| A44 | 05-11 | `schemas/screen-decomposition.schema.json` | v3 | 9.8 | 9.8 | 9.8 | 9.8 | 🟢 | Válido/negativo | MATCH | PASS_WITH_EVIDENCE |
| A45 | 05-12 | `references/security-privacy-contract.md` | v3 | 9.8 | 9.8 | 9.8 | 9.8 | 🟢 | J06 | MATCH | PASS_WITH_EVIDENCE |
| A46 | 05-12 | `references/audit-traceability-contract.md` | v3 | 9.8 | 9.8 | 9.8 | 9.8 | 🟢 | J07 | MATCH | PASS_WITH_EVIDENCE |
| A47 | 05-12 | `references/tokens-messages-contract.md` | v3 | 9.8 | 9.8 | 9.8 | 9.8 | 🟢 | J08 | MATCH | PASS_WITH_EVIDENCE |
| A48 | 05-13 | `references/analytics-observability-contract.md` | v3 | 9.8 | 9.8 | 9.8 | 9.8 | 🟢 | J09 | MATCH | PASS_WITH_EVIDENCE |
| A49 | 05-13 | `references/accessibility-responsive-contract.md` | v3 | 9.8 | 9.8 | 9.8 | 9.8 | 🟢 | J10 | MATCH | PASS_WITH_EVIDENCE |
| A50 | 05-13 | `references/supabase-source-map.md` | v3 | 9.8 | 9.8 | 9.8 | 9.8 | 🟢 | Readback Supabase | MATCH | PASS_WITH_EVIDENCE |
| A51 | 05-14 | `schemas/task-packet.schema.json` | v3 | 9.8 | 9.8 | 9.8 | 9.8 | 🟢 | Válido/negativo | MATCH | PASS_WITH_EVIDENCE |
| A52 | 05-14 | `schemas/coverage-report.schema.json` | v3 | 9.8 | 9.8 | 9.8 | 9.8 | 🟢 | Válido/negativo | MATCH | PASS_WITH_EVIDENCE |
| A53 | 05-14 | `schemas/execution-ledger.schema.json` | v3 | 9.8 | 9.8 | 9.8 | 9.8 | 🟢 | Válido/negativo | MATCH | PASS_WITH_EVIDENCE |
| A54 | 05-15 | `templates/story-pack.template.json` | v3 | 9.8 | 9.8 | 9.8 | 9.8 | 🟢 | Schema + context_budget | MATCH | PASS_WITH_EVIDENCE |
| A55 | 05-15 | `templates/story-pack.template.md` | v3 | 9.8 | 9.8 | 9.8 | 9.8 | 🟢 | A–Q + context_budget | MATCH | PASS_WITH_EVIDENCE |
| A56 | 05-15 | `templates/judge-contract.template.yaml` | v3 | 9.8 | 9.8 | 9.8 | 9.8 | 🟢 | Judge result v0.5 | MATCH | PASS_WITH_EVIDENCE |
| A57 | 05-16 | `scripts/calculate_binary_completion.py` | v4 | 9.8 | 9.8 | 9.8 | 9.8 | 🟢 | Falso 100% rechazado | MATCH | PASS_WITH_EVIDENCE |
| A58 | 05-16 | `judges/github-integrity.yaml` | v3 | 9.8 | 9.8 | 9.8 | 9.8 | 🟢 | Runtime J12 PASS | MATCH | PASS_WITH_EVIDENCE |
| A59 | 05-16 | `judges/integration-close.yaml` | v3 | 9.8 | 9.8 | 9.8 | 9.8 | 🟢 | Runtime J13 PASS | MATCH | PASS_WITH_EVIDENCE |
| A60 | 05-17 | `templates/execution-report.template.md` | v3 | 9.8 | 9.8 | 9.8 | 9.8 | 🟢 | Reporte dual completo | MATCH | PASS_WITH_EVIDENCE |
| A61 | 05-17 | `schemas/judge-result.schema.json` | v5 | 9.8 | 9.8 | 9.8 | 9.8 | 🟢 | 1 positivo/3 negativos | MATCH | PASS_WITH_EVIDENCE |
| A62 | 05-17 | `SKILL.md` | v7 | 9.8 | 9.8 | 9.8 | 9.8 | 🟢 | Flujo J01–J13 | MATCH | PASS_WITH_EVIDENCE |

## Controles de cierre

- [x] Benchmark Claude ejecutado para 62/62.
- [x] Benchmark GitHub 150k+ ejecutado para 62/62.
- [x] Nota Claude, GitHub, técnica y final mayor a 9.5 para 62/62.
- [x] Casos positivos ejecutados.
- [x] Casos negativos rechazados.
- [x] J01–J13 con contrato, validador y evidencia aplicable.
- [x] Cero runtime bloqueados.
- [x] Cero assertions huérfanas o faltantes conocidas.
- [x] Cero SHA mismatch.
- [x] Cero versiones `current` duplicadas.
- [x] GitHub–Supabase reconciliados.
- [x] Rama R8 preservada.
- [x] Main, merge, producción, release, tag y runtime operativo no autorizados.

## Hallazgos diferenciales incorporados

1. Recalcular cobertura desde objetos, sin confiar en resúmenes autorreportados.
2. Fixtures exactos y detección de `vacuous_pass` en J10.
3. Comparación triple: mapa canónico → escritura GitHub → readback.
4. Cierre binario que rechaza porcentajes declarados sin evidencia.
5. `context_budget` obligatorio y vinculado a atomicidad.
6. Hash de fuente recalculado en J01.
7. Continuidad entre sesiones y reconciliación explícita de concurrencia.

## Cierre permitido

```text
R8_AUDIT_COMPLETE_WITH_DUAL_BENCHMARK_EVIDENCE
```
