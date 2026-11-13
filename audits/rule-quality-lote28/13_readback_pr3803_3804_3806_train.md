# L28 — Readback de GitHub: PR #3803, #3804, #3806 y Merge Train

**Fuente:** PR, rutas de migración, workflows/logs consultados en GitHub el 13-nov-2026. Snapshot sin hora UTC exacta de consulta. **Esta evidencia no demuestra cambios en Supabase vivo**. Todo estado puede variar con commits futuros.

## PR #3803 — procedencia de PROMOCION_REGLA_LF
- URL: https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3803
- HEAD observado `655822a9bdbd1af3796b2ffd7346cc273fa31028`; PR abierto, campo GitHub `draft=false` aunque título conserva «[DRAFT]», no merge confirmado.
- **Train fallido:** [run 43373800126](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43373800126), job `131715479069`, paso `Apply exact version and ledger readback`. Error literal `LF_OPERATION_PROVENANCE_CREATED_EXECUTION_MISSING:EXEC-MIGRATION-LF-IG-LIFECYCLE-V2` por FK de procedencia de operación `PROMOCION_REGLA_LF`. Comentario automático `PRE-APPLY STOP. No DB apply or merge executed`. No afirmar aplicación exitosa ni efecto parcial fuera de transacción.
- Código del último HEAD contiene bootstrap candidato `VULNERABILITY_COVERAGE_REPAIR_LF` con `fn_lf_operation_reserve_execution_v1` y `created_by_execution_id` de ejecución real del Train. Exige `router_authority_receipt` y RUN `ACTUALIZACION_DB_LF`. No fue verificado con Train SUCCESS.
- Exact HEAD CI: PASE run `43376438227` SUCCESS; clasificación run `43376438189` SUCCESS; R17 [run 43376438216](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43376438216) **FAILURE**, job `131723914671`. Log: `operator does not exist: text ->> unknown` en un SELECT del test de procedencia; replay de rollback PG17.6/PG18 arroja `LF_IG_PROMOTION_EXACT_LIVE_TRAIN_RUN_REQUIRED:0`. Es CI de código, no incidente live.
- El SQL también declara decisión humana documental `Cristhian Luján`, `identity_verified=false`, UUID interno placeholder, y `public.lf_ig_g15_motor_temporary_v1` que devuelve `NO_GO_MOTOR` incluso para siete entradas autodeclaradas.

## PR #3804 — owner único, guard
- URL: https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3804
- HEAD `68a922e9597375a1a4a6603efcba032c8916355c`, open/DRAFT, mergeable=false en lectura; base `acd16ef314536f9c992147a8c6ccaa3e098c1e9d`, anterior al nuevo HEAD de #3803.
- SQL `supabase/migrations/20261113233000_lf_asset_owner_one_name_guard_v1.sql` blob `cc0de74a5c3ae033d37c2142fd570c17f40f157f`. DEFAULT `LF_GOVERNANCE`, triggers INSERT/UPDATE y writer documental; **no modifica los 155 históricos por sí solo**. Aún sin despliegue registrado.
- Fuente README: 238 activos, 83 canónicos, 155 a normalizar (144 no archivados, 11 archivados), 13 archivados en total; preimage por fila y SHA plan. PR necesita actualizar ancestry/readback respecto del #3803 finalmente aplicado.

## PR #3806 — backfill DATA 155
- URL: https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3806
- HEAD `7a8e516724f5b722e8bc71856766691cce79c8b5`, open/DRAFT; base PR #3804. SQL `supabase/migrations/20261113235900_lf_asset_owner_one_name_backfill_v1.sql` blob `590a73d8d57a9ee5670e4b063edf359c4d0cb6b4`.
- Fuente de PR: antes de aplicar comprueba 238 SHA reales y archived_at; posterior espera 155 receipts APPLIED/238 LF_GOVERNANCE. CI PG18 en [run 43372966623](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43372966623) y PASE/clasificación en 43372966637/43372966617 reportados SUCCESS para ese HEAD; **prueba del fixture reemplaza en memoria los 238 hashes por hashes de filas sintéticas** (`PG18_FIXTURE_SHA_ADAPTATION_238_TEST_ONLY`): no significa que las 155 filas fueron escritas en Supabase real.
- Fuente actual todavía menciona ACT-0001, B13/B14 como gates temporales; ese texto es anterior al alcance 7/5/2 y a la decisión de Train directo, pendiente de reconciliar.

## Contradicción de migración vs EKB
**Dueño, pendiente de firma:** migraciones se envían directamente al Merge Train sin Router previo/manual. **Runtime/PR actual:** Train mantiene una operación `ACTUALIZACION_DB_LF`, contrato `router_authority_receipt` y control de procedencia. No se borró ni saltó esa seguridad. Si “sin Router” significa incluso quitar el receipt interno, hay **cambio de contrato/ruta** pendiente de revisión y prueba; no se puede dar por implementado solo por escribirlo en L28. Para ejecuciones de perfiles, el EKB V1.4 sigue diciendo ACT-0001→Perfil→RUN→IG.

## Estado de los 7 Motor
B02/B03 sin reconciliación real; B06 guard+backfill no aplicados; B08 sin readback documental live; B07 sin lifecycle LF4/SALY5 completo verificado; B09 sin Step70 genuino/terminal READY; B12 CI último HEAD #3803 fallido y sin readback de legacy post-Train. **0/7 cerrados**. Sin cambios en RUN históricos, fuentes oficiales, SQL ni producción desde L28.
