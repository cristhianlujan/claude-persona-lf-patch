# IG M10.13 / CP3 — Clasificación exacta y limpieza segura de callers

Fecha de comprobación: 2026-10-22. Orígenes canónicos leídos: `pg_catalog.pg_proc` actual, M10.9 evento `public.lf_eventos#20161` (38 históricos), inventario M10.10 `#20193` (147/147, seis clases), EKB `IG-M1011-HISTORICAL-UNREFERENCED-LIVE-SQL-CALLER-001` y `GOV-ASSET-RETIREMENT-GOVERNANCE-V1-001`.

## Resultado de la lectura exacta

El patrón de **invocación SQL** `fn_input_governance_(semantic_probe_v[123]|bootstrap_classify_v[12]|field_reference_probe_v1)...(` encontró **21 funciones llamadoras con coincidencia real**. No son 21 consumidores legacy prohibidos. La lista se agrupa por clase histórica del *caller*, no por el sufijo de versión del *callee*.

| Clase de caller M10.10 (histórico) | Nº | Tratamiento |
|---|---:|---|
| ACTIVE_VNEXT | 10 | Conservar: rutas funcionales o bases compuestas necesarias para v2/v3 |
| LEGACY_REFERENCED | 3 | Examinar rehome con paridad; no DROP / REVOKE |
| LEGACY_UNREFERENCED | 2 | Candidatas a retiro, **no REMOVE_READY**: faltan pruebas independientes Edge/Router/ACL/contratos |
| SHADOW_TOOL | 1 | Conservar como no decisional mientras continúe el contrato shadow |
| OUTSIDE_CLASSIFIED_INVENTORY | 5 | Nuevos o auxiliares fuera de freeze 20193; clasificar ahora, nunca autorizar retiro por omisión |
| **TOTAL** | **21** | **0 autorizadas para eliminación** |

## Funciones que exigen atención

**LEGACY_REFERENCED**
- `programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(integer,text,bigint,jsonb)` — reutilizada desde recurate_v2, recurate_source_stale_v1 y otras rutas.
- `programacion.fn_input_governance_semantic_probe_v2_cached_v1(integer,text,bigint,jsonb)` — llamada desde probe_v3_cached_v1.
- `programacion.fn_input_governance_semantic_probe_v3_cached_v1(integer,text,bigint,jsonb)` — llamada desde clasificador cached_v2.

**LEGACY_UNREFERENCED / potencial retiro separado**
- `programacion.fn_input_governance_bootstrap_materialize_v1(integer,text,text)`: 0 menciones en prosrc ajeno, 0 triggers y 0 vistas, pero hay fuentes Git históricas, pruebas y restricción exacta de MD5 en fuente.
- `programacion.fn_input_run_semantic_revalidation_v1(bigint)`: 0 menciones en prosrc ajeno, 0 triggers y 0 vistas; la auditoría congelada de Profile Updater aún incluye esta identidad.

**No clasificados en el freeze M10.10, pero con invocaciones actuales**
- `fn_engineering_ig_validator_mismatch_probe_v1`, `fn_engineering_ig_validator_mutation_campaign_v1`, `fn_engineering_ig_validator_mutation_case_v2`: utilidades de prueba, invocan classifier_v2.
- `fn_input_governance_semantic_probe_v3_ctx`: contexto semántico v3 con base v2 y referencias de campo.
- `fn_t_remed_screen_status_v1`: consumidor T-REMED; invoca classifier cached_v2.

## Limpieza aprobada en este PR (solo gobernanza/medición)

1. Corregir la primera query del source-pack CP3: antes filtraba por una expresión amplia en `prosrc` y podía devolver caller con `callees=NULL`; ahora enumera solo coincidencias efectivas mediante `CROSS JOIN LATERAL regexp_matches`. El inventario literal de 21 se conserva como evidencia, no como constante de autorización.
2. Sustituir el segundo barrido de solo nombres por un inventario tipado `caller / callee / historical_class / cleanup_action` derivado de `pg_proc` **más** el evento histórico congelado `20193`; cualquier caller fuera de M10.10 es `REVIEW_NEW_CALLER` (no se confunde con `REMOVE_READY`).
3. No tocar funciones, Edge, ACL, triggers, contratos ejecutables ni rutas vigentes. Mantener `ZERO_LEGACY_CALLERS=PENDING` y el criterio de salida original. La mera clasificación **no es** prueba de cero legacy.
4. Exigir procedimiento `ASSET_RETIREMENT_GOVERNANCE` y readback multisuperficie para retirar las dos candidatas. Prohibidos `DROP`, `REVOKE`, falsas aserciones PASS o reencaminar consultas para ocultar llamadas.

El resultado útil es una medición limpia y reusable, con seguimiento exacto de candidatos y bloqueo explícito de acciones destructivas inseguras. Las migraciones históricas, fuentes Git y freezes no se reescriben.
