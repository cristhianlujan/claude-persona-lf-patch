# PG-03_C3 → EVIDENCE_LEDGER → PG-03_C9 — conexión gobernada

**Fecha:** 2026-11-03  
**Estado:** `REAL_READINESS_PROBE_EXECUTED / BLOCKED_UPSTREAM_PG01_C6 / NO_WRITE`  
**Plan real:** `PROGRAMMING_AGENT_PROGRAMMING_REMEDIATION_V1` (PG-01 work_item_id 934, PG-03 work_item_id 936).

## 1. Qué ya existe: no volver a construirlo

- **Productor candidato**: `pg03_strategy_candidate/pg03_strategy_v1.py::prepare_strategy` genera `PG03_STRATEGY_CANDIDATE_V1`, devuelve `CANDIDATE_NOT_ADMITTED`, `handoff_allowed=false` y un SHA Python de prueba. No publica material definitivo ni autentica repositorio/HEAD/PG01.
- **Libro de evidencias**: `private.lf_evidence_ledger_v1`; entrada gobernada `public.fn_lf_evidence_ledger_anchor_v1`. La función real exige ejecución `EVIDENCE_LEDGER` en curso, `orchestrator_execution_id`, `plan_digest` válido y `TRUSTED_PROVIDER_BOUND`.
- **Resolutores existentes**: `LF_GITHUB_SOURCE_READBACK_V1` (`GITHUB_API_READBACK_PLUS_OFFLINE_HASH`) y `LF_SUPABASE_READBACK_V1` (`SUPABASE_SQL_READBACK_PLUS_DB_DIGEST`).
- **Revisor existente**: `public.lf_independent_review_begin_v3`, operación `REVISION_INDEPENDIENTE_ESTRATEGIA_LF`, capacidad current `INDEPENDENT_ASSURANCE` v2.0.1, `CONTRACT_DRIVEN_ANY_SUBJECT`, sin whitelist de sujeto.
- **Precedente de integración productiva real** (para adaptar por el dueño, no copiar con constantes PE10): `supabase/migrations/20261013051000_lf_pe10_c3_verified_source_receipt_v3.sql` y `supabase/migrations/20261013053000_lf_pe10_c3_independent_review_begin_v1.sql`; alternativa más reciente `supabase/migrations/20261021163500_lf_pe10_c5_independent_review_init_v1.sql`. Estos precedentes ya usan dispatch/ledger/review con readback e idempotencia, sin segundo motor.

## 2. Sonda real ejecutada hoy

**SQL reutilizable:** `pg03_c9_real_runtime_readiness_v1.sql`. Es una sola SELECT con CTE, sin llamados a funciones de escritura ni cambios de estado. Fue ejecutada a través de Supabase_RO.

Resultado observado:
- PG-01_C6=PENDING; PG-03_C2=PENDING; PG-03_C3=PENDING; PG-03_C9=PENDING.
- `verified_subjects=0` para `subject_type='PG03_TECHNICAL_STRATEGY'` + `capability_code='EVIDENCE_LEDGER'` + `receipt_kind='SOURCE_SNAPSHOT'`.
- `assurance_current_count=1`, `generic_contract_current=true`, `operational_review_count=1`, `trusted_resolver_count=2`.
- `actual_pg03_review_runs=0`; `enabled_pg03_c3_c9_bindings=0`.
- `first_blocker=BLOCK_PG01_C6_NO_GOVERNED_REAL_HANDOFF`; `runtime_authorized_by_this_probe=false`.

**Precisión:** la ausencia de `lf_assurance_subject_bindings` no es precondición directa del `lf_independent_review_begin_v3`. En cambio, `programacion.programming_checkpoint_bindings` debe ser admitido para que el ejecutor simple cierre checkpoints requeridos. No confundir ambos tipos de binding.

## 3. Ruta de conexión exacta cuando exista autoridad

1. **PG-01_C6**: obtener un handoff A9 auténtico desde `EJECUCION_PERFIL_LF`, con snapshot current y recibo `ACCEPT` persistido por writer gobernado. El estado del checkpoint debe acreditarse en la ruta vigente; no sustituir por PR, test o `DONE` manual.
2. **PG-02 y PG-03_C2**: completar clasificadores/reglas/skills/calificación y binding de validador con recibos del **mismo run**. C3 de catálogo y L3 actuales deben ser autorizados.
3. **PG-03_C3 productor**: resolver estrategia material real del pedido y fuentes; fijar `subject_type='PG03_TECHNICAL_STRATEGY'`, `subject_ref` estable, commit Git del producto y digest canónico con readback de fuente, no el SHA autodeclarado de Python. Registrar ejecución de productor auténtica.
4. **EVIDENCE_LEDGER**: desde un orquestador `ORQUESTACION_PIPELINE_LF` en ejecución, generar dispatch real para `EVIDENCE_LEDGER`, enlazar capability current con `fn_lf_capability_bind_from_orchestrator_v1`, invocar `fn_lf_evidence_ledger_anchor_v1` con evidencia verificada por `LF_GITHUB_SOURCE_READBACK_V1` o `LF_SUPABASE_READBACK_V1`. Exigir `verification_state='VERIFIED'`, `receipt_kind='SOURCE_SNAPSHOT'`, identidad repo/HEAD, digest, provider y readback estable.
5. **Readback independiente** de `private.lf_evidence_ledger_v1` por `receipt_id` (único). Verificar `subject_type/ref/sha/head`, `capability_code`, `verification_state`, `receipt_sha256` y origen/ejecución. No admitir simplemente UUID suministrado por el caller.
6. **Revisión C9**: despacho real `fn_lf_orchestrator_dispatch_receipt_v1` hacia `INDEPENDENT_ASSURANCE`; abrir por `lf_independent_review_begin_v3` con recibo exacto, manifest SHA current, plan digest, identidad distinta productor/revisor. Releer `lf_capability_binding` `BOUND` y los seis pasos existentes: `route_bind`, `target_currentness`, `semantic_review`, `judge_record`, `reviewer_readback`, `report_output`.
7. **Solo al final**: recibir y releer veredicto independiente atestado, comprobar pertinencia de reglas y ausencia de defeaters. Entonces la autoridad del plan podrá marcar C9 por validador actual del checkpoint. No hacerlo con un script aislado.

## 4. Guardas de seguridad y límites

- Ninguno de estos pasos se ejecuta desde Supabase_RO. Se requiere orquestador autorizado, contexto de ejecución real y permiso de `service_role` por la ruta definida, **no** ampliar GRANTs.
- No llamar `fn_lf_evidence_ledger_anchor_v1` con `p_verification_state='VERIFIED'` por afirmación del productor; solamente si un lector confiable revalidó la fuente y el run.
- El `pg03_c9_subject_binding_v1.py` del PR #3523 es **preflight candidato**, no puede reemplazar verificaciones EVIDENCE_LEDGER/CURRENTNESS.
- No añadir otra operación, segundo juez ni writer de recibos; adaptar los precedentes PE10 en la ruta real del propietario `ORQUESTACION_PIPELINE_LF`.
- No producir SQL de mutación para una estrategia todavía inexistente, ni convertir `PENDING` en `DONE` por evidencia sintética.

## 5. Dictamen

`PG03_C3_C9_RUNTIME_CONNECTIVITY_ROUTE_IDENTIFIED / READINESS_PROBE_REAL_PASS / OPERATIONAL_BLOCKED_UPSTREAM`.

**Causa primaria:** PG-01_C6 no tiene recibo real admitido; la ruta de estrategia real C3 y los bindings de los checkpoints tampoco están establecidos. El proveedor/orquestador debe producir primero esos artefactos con autoridad. La infraestructura genérica de ledger/revisión **sí está presente**.

**Este PR no contiene integración ejecutada en producción**: el producto aún no suministra fuente elegible. No se modificaron main, grants, Supabase ni PRs existentes.
