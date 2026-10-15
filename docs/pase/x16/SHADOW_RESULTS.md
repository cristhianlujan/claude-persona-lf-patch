# F09-X16 — resultados de shadow PASE

## Resultado de la ejecución fuera de CI

Se seleccionaron cinco PRs distintos mergeados entre el 13 y el 15/10/2026. Para cada uno fijé `base_sha` y `head_sha` exactos desde GitHub y ejecuté los evaluadores en worktrees. `main` live durante la comprobación era `6e84026f6bfb37b1ee2188efcf6574b2ff375e74`, posterior a todos esos merges.

| Tipo | PR, SHAs y Train | Checks históricos | PASE exact-head | `pase-merge-gate` exact-head | Paridad exact-head | Lectura |
|---|---|---|---|---|---|---|
| Sin migración | #2523; base `bbc8c307…`, head `89c73b32…`, merge `077ac889…`; Train run `38477329167` | PASE/paridad `38477007529` y gate `38477004494`: `skipped`; Train success | `FAIL_CI_PLAN_APPLICABILITY_UNRESOLVED:DEEP_SHARED_REGISTRY_INVALID` | `BLOCK_PASE_MERGE_GATE_PLAN_EMIT` al fallar el mismo emisor | `FAIL_MIGRATION_PARITY_FOCAL_REF_CURRENTNESS`; esperaba base `bbc8c307…`, live main era `6e84026…` | No hay veredicto de negocio. El bloqueo de paridad es stale al reevaluar un PR ya merged con el main actual, no prueba de falso bloqueo durante su evento. |
| Con migración | #2747; base `6e4f374e…`, head `d0f8def3…`, merge `16b9f1a2…`; Train `EXEC-DB-TRAIN-PR2747-20261015124000-R38735075375` | PASE workflow `38735397630`: `skipped`; el check PASE/paridad y gate no tienen evidencia independiente disponible | `FAIL_CI_PLAN_APPLICABILITY_UNRESOLVED:DEEP_SHARED_REGISTRY_INVALID` | `BLOCK_PASE_MERGE_GATE_PLAN_EMIT` por mismo emisor | `FAIL_MIGRATION_PARITY_FOCAL_REF_CURRENTNESS`; esperaba `6e4f374e…`, live `6e84026…` | Train receipt informa paridad PASS. PASE no fue ejecutado. Fallo de currentness es posterior al merge. |
| Runtime | #2732; base `d1ac7d96…`, head `3a55264c…`, merge `29ff3492…` | PASE/paridad workflow `38689320799` y gate `38689316532`: `skipped` | `FAIL_CI_PLAN_APPLICABILITY_UNRESOLVED:DEEP_SHARED_REGISTRY_INVALID` | `BLOCK_PASE_MERGE_GATE_PLAN_EMIT` por mismo emisor | `FAIL_MIGRATION_PARITY_FOCAL_REF_CURRENTNESS`; esperaba `d1ac7d96…`, live `6e84026…` | No hay veredicto de negocio; no declarar falso bloqueo. |
| Docs | #2629; base `6557eeb…`, head `437458ba…`, merge `b7e4cd13…` | PASE/paridad workflow `38603956139` y gate `38603950395`: `skipped` | `FAIL_CI_PLAN_APPLICABILITY_UNRESOLVED:DEEP_SHARED_REGISTRY_INVALID` | `BLOCK_PASE_MERGE_GATE_PLAN_EMIT` por mismo emisor | `FAIL_MIGRATION_PARITY_FOCAL_REF_CURRENTNESS`; esperaba `6557eeb…`, live `6e84026…` | No hay veredicto de negocio; no declarar falso bloqueo. |
| Fallo / stale | #2693; base `aa4dea84…`, head mergeado `19bbc5c0…`, merge `5d84fe7c…`; Train primero BLOCKED y luego COMPLETED | PASE/paridad workflow `38645667076` y gate `38645664335`: `skipped` | `FAIL_CI_PLAN_APPLICABILITY_UNRESOLVED:DEEP_SHARED_REGISTRY_INVALID` | `BLOCK_PASE_MERGE_GATE_PLAN_EMIT` por mismo emisor | `FAIL_MIGRATION_PARITY_FOCAL_REF_CURRENTNESS`; esperaba `aa4dea84…`, live `6e84026…` | El Train bloqueó por SQL real antes del efecto y completó tras retimestamp; no es un resultado PASE. Reevaluación histórica queda stale. |

El fallo PASE/Merge Gate sucede antes de emitir un plan y no significa que el código candidato se haya ejecutado. El resultado de paridad sí alcanza el control de head/currentness y rechaza correctamente el base histórico frente al main actual. Como son casos ya mergeados, ese bloqueo no permite inferir el veredicto que habrían recibido al tiempo del PR.

Las corridas históricas disponibles muestran checks `skipped`; por tanto no hay evidencia real de PASS/BLOCK PASE ni se puede contar un falso bloqueo. La excepción #2747 solo tiene un run `PASE` skipped; no atribuyo estados a checks separados que no pude recuperar.

Nota adicional: #2485 es la pista indicada para “main advanced”; PASE/paridad `38465636787` y gate `38465631267` estaban `skipped`, por lo que no demuestra ausencia de falso bloqueo. No había `EXEC-DB-TRAIN-*` asociado.

## Paridad de migraciones y deuda histórica

El carrier reutilizado es `run_migration_source_parity_pase_entry_v1.py` → `run_migration_source_parity_focal_v1.py`; el runner histórico `run_migration_source_parity_flow_v1.py` permanece separado. El focal exige `evaluation_scope=CHANGESET_SCOPED` y `historical_debt_disposition=RECONCILIATION_WORK_ITEM`. Calcula las rutas migratorias con `git diff --name-status base...head -- supabase/migrations` y falla cerrado ante cambios ambiguos o malformados dentro del diff. La deuda externa 66/17 no entra en ese conjunto y no debe bloquear un PR. Esta lectura estática es verificable; no sustituye una corrida live con el contexto de base autorizado.

## Qué falta para una decisión de shadow

1. Arreglar o resolver la fuente `DEEP_SHARED_REGISTRY_INVALID` dentro del proceso propietario, sin relajar el fail-closed ni alterar la clasificación de aplicabilidad.
2. Ejecutar los mismos cinco casos desde una revisión de confianza y con el currentness de `main`, evidencia/control-plane y lectura de cualificación que requieren los carriers.
3. Repetir con casos reales de no-migration, migration, runtime, docs y fallo/stale. Exigir que los siete canarios de `CANARIES_EVIDENCE.md` sean verdes antes de pedir cualquier cambio de ruleset.

No se ejecutaron simulaciones de PR ni pruebas con writes. No se modificaron workflows.

## Segunda vuelta: PRs abiertos tras corregir el registro (15/10/2026)

Después de que #2762 llegó a main (`13a23b0ecb55f3e68ac1d961918760968d3e0a74`), revisé cinco PRs abiertos en sus heads actuales. No se rebasaron ramas ni se evaluaron merges históricos. El control de currentness se conservó; por eso los PRs con base anterior a main quedan stale.

| Tipo | PR abierto (base → head) | PASE fuera de CI | `pase-merge-gate` | Paridad de migraciones | Falso bloqueo |
|---|---|---|---|---|---|
| Sin migración | #2753 `a8634eac…` → `9ca972f4…` | No llega a decisión: `FAIL_REPAIR_POLICY_UNIVERSE_DIGEST` al proyectar el plan | `BLOCK_PASE_MERGE_GATE_STALE_BASE` (base `a8634eac…`, main `13a23b0e…`) | `FAIL_MIGRATION_PARITY_FOCAL_REF_CURRENTNESS`, base esperada `a8634eac…`, main live `13a23b0e…` | PASE: bloqueo global por política/universo incoherente, no atribuible al changeset. Gate/paridad: no; stale real y esperado. |
| Con migración | #2755 `0497ead9…` → `62dfe29f…` | No llega a decisión: `FAIL_REPAIR_POLICY_UNIVERSE_DIGEST` | `BLOCK_PASE_MERGE_GATE_STALE_BASE` (base `0497ead9…`, main `13a23b0e…`) | Bloqueada por currentness: base `0497ead9…` distinta de main live `13a23b0e…`; no alcanzó consulta de ledger | PASE: bloqueo global no atribuible al changeset. Gate/paridad: no; stale real y esperado. |
| Runtime | #2706 `193c3828…` → `f64a53ef…` | No llega a decisión: `FAIL_REPAIR_POLICY_UNIVERSE_DIGEST` | `BLOCK_PASE_MERGE_GATE_STALE_BASE` (base `193c3828…`, main `13a23b0e…`) | `FAIL_MIGRATION_PARITY_FOCAL_REF_CURRENTNESS`, base esperada `193c3828…`, main live `13a23b0e…` | PASE: bloqueo global no atribuible al changeset. Gate/paridad: no; stale real y esperado. |
| Docs | #2752 `a8634eac…` → `85fe1e4e…` | No llega a decisión: `FAIL_REPAIR_POLICY_UNIVERSE_DIGEST` | `BLOCK_PASE_MERGE_GATE_STALE_BASE` (base `a8634eac…`, main `13a23b0e…`) | `FAIL_MIGRATION_PARITY_FOCAL_REF_CURRENTNESS`, base esperada `a8634eac…`, main live `13a23b0e…` | PASE: bloqueo global no atribuible al changeset. Gate/paridad: no; stale real y esperado. |
| Fallo / stale | #2676 `81428fb7…` → `9ce54051…` (DRAFT; evaluado como datos, sin aplicar) | No llega a decisión: `FAIL_REPAIR_POLICY_UNIVERSE_DIGEST` | `BLOCK_PASE_MERGE_GATE_STALE_BASE` (base `81428fb7…`, main `13a23b0e…`) | Bloqueada por currentness: base `81428fb7…` distinta de main live `13a23b0e…`; no alcanzó consulta de ledger | PASE: bloqueo global no atribuible al changeset. Gate/paridad: no; stale real y esperado. |

### Diagnóstico y límites de la segunda vuelta

El `lf_ci_control_impact_registry_v2.json` actual contiene 26 controles, mientras que `lf_pase_control_repair_quarantine_v1.json` conserva un digest distinto. Ejecuté `test_lf_pase_control_repair_quarantine_v1.py` en main y falla antes de evaluar los cambios: `FAIL_REPAIR_POLICY_UNIVERSE_DIGEST`. El test también espera 25 controles. #2762 corrigió el registro compartido S28; no modificó este registro de controles ni la política de cuarentena. Por tanto, esta segunda vuelta **no produce una decisión PASE por PR** y demuestra un bloqueo global de integridad que requiere diagnóstico gobernado aparte. No actualicé el digest ni relajé el fail-closed.

`pase-merge-gate` sí devuelve el bloqueo correcto para la identidad vieja del base. La paridad también termina en su guarda de currentness antes de consultar ledger; no se invocó una conexión de base. Así se evita confundir deuda histórica con el changeset, pero estos resultados no demuestran aceptación de la paridad sobre un base vigente. No había PR abierto por tipo con base `13a23b0e…` al tomar estos snapshots; no rebaseé ni abrí canarios porque las categorías sí tenían PRs abiertos y la instrucción pide evaluar sus heads exactos. El caso runtime usa #2706 (candidato UI Architect con helper asíncrono y pruebas locales), no #2748, que no era una muestra runtime tan directa.

**Estado shadow:** parcial / bloqueado. Queda volver a ejecutar cuando el universo/digest de la política PASE esté coherente y existan heads abiertos basados en main vigente, sin reinterpretar como falso bloqueo los rechazos correctos por stale. La inspección del código de paridad confirma que el análisis usa `git diff --name-status base...head -- supabase/migrations`; no se ejecutó el paso live de ledger en estas muestras.
