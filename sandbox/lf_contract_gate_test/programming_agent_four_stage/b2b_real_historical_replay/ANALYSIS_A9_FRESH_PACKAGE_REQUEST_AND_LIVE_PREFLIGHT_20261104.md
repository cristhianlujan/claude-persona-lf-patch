# LF — Solicitud de A9 moderno y preflight real (04-11-2026)

**Estado:** `BLOCKED_UPSTREAM_ANALYSIS_AND_PRODUCT_AUTHORITY`. Documento reutilizable para el dueño de Análisis. **No** es `ANALYSIS_IMPLEMENTATION_PACKAGE_V1`, no contiene un recibo `READY`, no ejecuta perfiles ni registra autorización.

## I. No repetir una solicitud ya existente

Existe `pg04_semantic_partition_candidate/A1_A9_FRESH_REQUEST_B2B_APP_SHELL_20261103.md`, que especifica la solicitud mínima correcta y se conserva como mandato técnico. Existe además `analysis_trial_b2b_app_shell_unadmitted_v1.json`, resultado candidato `NEED_MORE_EVIDENCE`, no A9 listo. No reescribir esos archivos ni promover el contexto v0.9.

Objetivo del ensayo: un cambio pequeño y **definido/autorizado** en el B2B shell. La etapa Análisis debe investigar una definición de producto vigente y el AS-IS real. Si no hay una modificación material autorizada y concreta, no inventar una.

## II. Evidencia actual de lectura

1. GitHub `cristhianlujan/claude-persona-lf-patch` PR #3529 (skill `PROGRAMMING_ANALYSIS_LF`) **MERGED**. El `skills/programming_analysis/SKILL.md` en main señala `CANDIDATE_SOURCE_ONLY_NOT_REGISTERED`, A1 implementado localmente y A2–A15 sin cableado operativo. El perfil `profiles/programming_analysis_lf/README.md` indica `CANDIDATE_NOT_RELEASED / SOURCE_ONLY / OPERATIONAL_QUALIFICATION_BLOCKED`, sin veredicto independiente ni ejecución autenticada.
2. SQL SELECT real: `lf_ops.app_shells` tiene `B2B_APP_SHELL` versión `v1.0`, **status=`CANDIDATO`**, `LF_DS_V1`, updated_at `2026-10-07 22:33:42+00`. No afirmar `VIGENTE` ni que exista un nuevo cambio aprobado.
3. SQL SELECT por códigos `%PROGRAMMING%ANALYSIS%`: **0 filas coincidentes** en `public.lf_profile_selection_registry_v1`, `private.lf_profile_capability_registry_v1`, `public.lf_skill_catalog_v1` al consultar. No supone que todas las demás rutas/fuentes de autoridad estén vacías.
4. SQL SELECT: `private.lf_programming_context_handoff_receipts_v1` 0 filas. Tres contextos históricos `private.lf_decision_context_asof_v1`; v0.9 (5/9 READY históricos), v1.0 (0/9 READY `NEED_MORE_EVIDENCE`), B2B-OFERTA (3/7 READY históricos), ninguno avalado como entrada CURRENT.
5. GitHub `profiles/programming_analysis_lf/contracts/runtime_binding.json` declara como fuentes obligatorias SKILL + binding. El validador `runtime_validate.py` evalúa forma de propuesta y mantiene `independent_semantic_judge=NOT_EXECUTED`, `pg01_consumer_verified=false`, `downstream_authorized=false`.

## III. Solicitud exacta al productor de Análisis — propietario externo del carril

**Mandato:** reutilizar perfil y única skill `PROGRAMMING_ANALYSIS_LF` + contratos A1–A9 existentes, sin crear otro engine ni bypass de Router.

**Entrada:** la petición descrita en `A1_A9_FRESH_REQUEST_B2B_APP_SHELL_20261103.md`; consultar en lectura fuentes actuales de `B2B_APP_SHELL`, reglas, rutas, LF_DS, implementaciones actuales y la fuente precisa del cambio elegido.

**Salida permitida:** `ANALYSIS_IMPLEMENTATION_PACKAGE_V1` candidato, `PROGRAMMING_CONTEXT_SNAPSHOT_V1` exacto, `stage_trace` A1–A9, requisitos con acceptance_signal/refs, frentes tipados, matriz bidireccional scope↔front, A6 implementability completo, A7 coverage, A8 stop, roles de autoridad vs implementación, `scope_readiness`, `package_readiness`, evidencia currentness y SHA de fuente. **No generar, omitir ni reinterpretar componentes por conveniencia**.

**Si fuente no VIGENTE, la modificación no existe o falta evidencia:** respuesta `NEED_MORE_EVIDENCE` / `REQUIRES_DECISION` / `BLOCKED`, incluyendo cada motivo y la referencia verificable. `STOP` no es `READY`. Una salida `READY_CANDIDATE` solo puede pasar a PG01 tras juez independiente, recibos, currentness, identidad de perfil y operación gobernada.

**Probar el runtime real** únicamente mediante Router → perfil/skill, con su autorización. El rol de Programación no registra la skill, no modifica Producto y no suplanta un perfil sin autoridad.

## IV. Frontera y verificación de salida por Programación

Al recibir una respuesta de Análisis, verificar en este orden:

1. Identidad A9 + validador/schema existentes del perfil; resultado discriminado `CANDIDATE` vs `BLOCKED` vs `READY`. Nunca equiparar coherencia estructural con autenticidad.
2. Evidencias exactas de fuentes: `source_snapshot_sha256`, `snapshot_schema_digest_sha256`, `authority_fingerprint_sha256`, revisión Git de target, scope_front_matrix coherente y A6 tipado.
3. Recibo de contexto as-of de mismo `context_id`, re-cálculo SHA PostgreSQL, paridad A9→PG01, juez independiente actual y currentness. Si falta algo: `PG01_BLOCKED`.
4. Para solo *diagnóstico offline*, separar la prueba de contenido de los gates de autoridad con `SKIPPED_FOR_DIAGNOSTICS`; el material faltante no se fabrica. A ningún resultado sintético se le asigna `PG01_ADMITTED`.
5. Si y solo si el productor PG03 genera estrategia con requisitos/aceptaciones, el `PG03_C8_PG04_HANDOFF_CANDIDATE_V1` y obligaciones/outcome_registry tipadas **con provenance verificable**, reutilizar `pg03_pg04_exact_handoff_bridge_v1.py`. No duplicarlo.
6. Registrar en informe por paso `input_source`, `producer_invoked`, `result_code`, `evidence_ref`, `output_sha256`, `authority=false` hasta admisión real.

## V. Gate resumido

| Gate | Readback observado | Resultado |
|---|---|---|
| Definición B2B shell vigente para nueva modificación | `v1.0 CANDIDATO` | `BLOCK_SOURCE_AUTHORITY_NOT_VIGENTE` |
| Perfil/skill Análisis registrable y operativo | skill fuente merged; registros 0 bajo código previsto | `BLOCK_ANALYSIS_RUNTIME_NOT_RELEASED` |
| Paquete A9 fresh completo y calificado | no se localizó | `NOT_AVAILABLE` |
| Recibo A9→PG01 real | 0 en Supabase | `BLOCK_HANDOFF_RECEIPT_MISSING` |
| Programación PG03/PG04 con fresh A9 | no ejecutado | `NOT_REACHED` |

Estos son **diagnósticos de lectura**, no códigos de error afirmados como retorno literal de las funciones productivas. No se ejecutó el perfil ni la skill.

## VI. Decisión de continuidad

La ruta B2B actual no puede producir legítimamente un `READY` hasta resolver autoridad de definición de Producto y conectar el runtime de Análisis. **No seguir buscando paquetes históricos indistintamente**; este bloqueo es del producto/producer actual.

**Ruta paralela válida:** continuar verificando componentes PG03/PG04 con fixtures existentes y sus propios tests (resultado `CANDIDATE`), pero registrarlos por separado del ensayo sobre el paquete real. El siguiente positivo auténtico exige un productor A9 habilitado, con entrada autorizada, resultados y recibos.

## VII. SQL de reproducción RO

```sql
SELECT app_shell_code,version,status,design_system_code,updated_at
FROM lf_ops.app_shells WHERE app_shell_code='B2B_APP_SHELL';

SELECT 'profile_selection' AS kind,profile_code AS code,descriptor_status AS status
FROM public.lf_profile_selection_registry_v1 WHERE profile_code ILIKE '%PROGRAMMING%ANALYSIS%'
UNION ALL
SELECT 'profile_capability',profile_code,status FROM private.lf_profile_capability_registry_v1
WHERE profile_code ILIKE '%PROGRAMMING%ANALYSIS%'
UNION ALL
SELECT 'skill_catalog',skill_code,required_operation FROM public.lf_skill_catalog_v1
WHERE skill_code ILIKE '%PROGRAMMING%ANALYSIS%';

SELECT count(*) FROM private.lf_programming_context_handoff_receipts_v1;
```

**No-op realizado:** sin INSERT/UPDATE/DDL, sin PR merge, sin cambio a Análisis, Producto, Router, Testing, Worker, `main` o permisos.
