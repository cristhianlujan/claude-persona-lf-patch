# LF Input Governance N-4 / P10 — Handoff a revisión independiente
Fecha: 2026-10-28. Revisión técnica del proceso prospectivo, NO despliegue.
Repo: `cristhianlujan/claude-persona-lf-patch`.
PR de trabajo: #3269 (DRAFT), rama `dev/ig-n4-tremed-cascade-governed-20261028`.
Productor / ejecutor de prueba: esta sesión. Revisor: OTRO chat, solo lectura.

## Mandato y límites
Antes de evaluar, leer EKB vivo: `IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001`, `INPUT-GOV-CONSUMER-BINDING-001`, `CI-MIGRATION-SOURCE-PARITY-001`, `IG-M99-SANDBOX-LIVE-ADMISSION-CONFLATION-001`.
No modificar Supabase, GitHub ni EKB durante la revisión. No ejecutar DDL P10 sobre base compartida. No Router, merge a main, deploy, re-clasificación de pantallas históricas ni emisión de recibos simulados.
Congelar y reportar el **HEAD exacto** de PR #3269 al iniciar la revisión. El código P10 se revisa por SHA de blob, nunca por nombre de rama móvil.

## Evidencia del productor (NO sustituye verificación independiente)
- Run PG17.6 aislado: [GitHub Actions 40788761710](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/40788761710), job `123168438203`, conclusión `success`. Ejecutado sobre commit `869ade59767de69c3cb327eab52c9329b9c8f433` con workflow temporal limitado a PR #3269.
- Log propio del job muestra los 11 marcadores `P10_CASE|...|PASS`, uno por caso, y `PASS_P10_FORWARD_BOUNDARY_PG17_6_11_CASES_ROLLBACK`. El script comprueba retorno a preimagen en conexión posterior.
- Lista de casos: `SNAPSHOT_LOCKS_HELD`, `HISTORICAL_PARITY`, `PROMOTION_DENIED`, `NEW_VIGENTE_LINK_DENIED`, `NEW_ACTIVE_DENIED`, `SELECTOR_CHANGE_DENIED`, `CANDIDATE_AUTHORING_ALLOWED`, `CANDIDATE_LINK_REVIEW_ONLY`, `UNLINKED_NO_GLOBAL`, `NEW_SCREEN_NO_IMPLICIT_GLOBAL`, `REVOCATION_ALLOWED`.
- Regresión read-only independiente del DDL: 17/17 PASS, 0 diferencias en 15,028 vínculos históricos y 8,852 pares derivados; **es sombra, no prueba de triggers**.
- Workflow temporal `.github/workflows/ig-n4-p10-isolated-pg-pr3269.yml` retirado en commit `92307be33e0ddd244e0e0092675551efbce2ad3b`; su ausencia se verificó por 404.
- PASE posterior al retiro dio FAIL, específicamente `BLOCK_CI_AUTHORITY_CURRENTNESS:UNKNOWN_FAIL_CLOSED:COMPATIBILITY_ASSESSMENT_MISSING:STALE_BASE` en run `40788820391`, no por P10.
- Sincronización de main **solo hacia rama de desarrollo** mediante [PR #3293](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3293), merge `bfce9d1529dfb98f0af17a07755b0e1a8f9b7b97`. Sin conflicto; 31 archivos de main sin solapamiento con los 65 archivos P10/IG de la rama. Los blobs SQL y runner se preservaron.
- PASE exacto tras sincronización: [run 40790232446](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/40790232446), job `123173351320` SUCCESS. `PASE / MIGRATION_SOURCE_PARITY` permanece SKIPPED y NO está certificado.

## Fuentes del P10 que deben compararse por blob SHA
Todas bajo `sandbox/lf_contract_gate_test/input_governance/`:

| Archivo | Git blob SHA1 esperado |
|---|---|
| `ig_p10_forward_only_scope_boundary_candidate_20261028.sql` | `a4d1207c5010826ac98806aa05f1539479fd4de5` |
| `ig_p10_pg17_6_isolated_runner_20261028.sh` | `bbf42f4149354b2cc3df4e3bf9ece8db4a9a3ba8` |
| `ig_p10_pg17_6_process_fixture_20261028.sql` | `cb295f5527f5e850c9a9611b1d1438e07563648d` |
| `ig_p10_forward_only_scope_boundary_readonly_regression_20261028.sql` | `a6f82fe5fe979bceed6561a80ffebb34020ce251` |

## Checklist revisor
1. Leer EKB vivo, PR #3269 y los cuatro archivos por HEAD exacto. Comparar los blobs anteriores; si difieren: STALE, no adjudicar PASS.
2. Verificar que el candidato solo se permita en `lf_ig_n4_isolated_ci` PG17.6; preflight antes de LOCK; SHARE LOCK de cinco tablas; hashes de las cuatro funciones originales; un solo `BEGIN/ROLLBACK`.
3. Verificar que no haya hardcodes de códigos/IDs de reglas/pantallas, ampliación implícita de autoridad de `es_transversal` ni cambios al baseline de herencias históricas.
4. Leer el log de run `40788761710` y constatar los once marcadores, SQL real, rollback y salida 0. **Si solo se acredita por lectura histórica**, marcar `PRODUCER_EXECUTION_VERIFIED`, no `INDEPENDENT_RUNTIME_PASS`.
5. Repetir en entorno autorizado la prueba PG17.6 y mutación negativa si el revisor dispone de ejecución. Si no, `NO_VERIFICADO` para ejecución independiente, sin reabrir permisos ni tocar shared DB.
6. Verificar PASE del HEAD congelado. No equiparar PASE SUCCESS a `MIGRATION_SOURCE_PARITY` si el job está SKIPPED.
7. Dictaminar separadamente `P10_ISOLATED_RUNTIME`, `P10_INDEPENDENT_VERIFICATION`, `P10_INTEGRATION`, `G4_RULE_SCOPE_AUTHORITY`, `G5_RECLASSIFICATION`.

## Estado según evidencia del productor
`P10_ISOLATED_RUNTIME=PASS_11_OF_11` (PG17.6 + rollback).
`P10_READONLY_SHADOW=PASS_17_OF_17`.
`P10_INDEPENDENT_VERIFICATION=PENDING`.
`P10_INTEGRATION=NO_VERIFICADO`; `G4_RULE_SCOPE_AUTHORITY=NO_VERIFICADO`; `G5_RECLASSIFICATION=NO_RECLASSIFY`.
`PR3269= DRAFT/NO_MERGE`; ninguna escritura en Supabase ni despliegue.
