# B12_LEGACY · G08 — Recibo de regresión para el dueño

Estado documental: **PREPARADO, PENDIENTE DE EVIDENCIA DEL MERGE TRAIN Y CIERRE**.
Autoridad: Documento 12 del L28, rama `lf/issue-3779-lote28-blocker-closure-plan-v1`.

## Identificación y alcance
- Operación: `ACTUALIZACION_DB_LF`; ingreso por LF Migration Merge Train únicamente (sin invocar ACT-0001 manualmente).
- Cambios: una migración UP; restringir SOLO `EXECUTE` de `public.lf_rule_promotion_guard_v1()` para `PUBLIC`, `anon`, `authenticated`. `service_role` permanece habilitado.
- Preimagen: `audits/rule-quality-lote28/b12/01_preimagen_S21_04_live_20261113.json`, `as_of=2026-11-13T08:21:46.706817Z`.
- Evidencia de decisión: aprobación documental explícita del dueño en conversación; **sin firma física ni verificación de identidad humana**.
- Rollback: `audits/rule-quality-lote28/b12/02_guard_acl_hardening_rollback_v1.sql` (NO ejecutar manualmente en Supabase).

## G08 punto a punto — no completar sin evidencia real

| Control | Requisito | Evidencia inicial | Estado del recibo |
|---|---|---|---|
| G08-01 | Cuatro firmas S21_04, MD5, ACL/atributos preimagen | JSON congelado 2026-11-13 | OBSERVADO_PRE_UP; validar HEAD y SHA |
| G08-02 | Seis firmas V1 preservadas | Preflight #3803 y SELECT histórico 6/6 | PENDIENTE_READBACK_POST_TRAIN |
| G08-03 | Pruebas reales PG17.6 y PG18.7, rollback | CI de este PR y test B12 con SQL exacto | PENDIENTE_CI_EXACT_HEAD |
| G08-04 | Positivos, negativos, permisos, errores, idempotencia, no pérdida de reglas | Test con 4 funciones + dependencias, roles anon/auth/service | PENDIENTE_CI_EXACT_HEAD |
| G08-05 | Rollback seguro de ACL sin alterar cuerpo/MD5 | Rollback compare-and-swap documentado | PENDIENTE_TEST_REAL |
| G08-06 | Una sola migración, Train, ledger y RUN real | Se requiere Merge Train oficial | PENDIENTE_TRAIN |
| G08-07 | Readback live: 4/4 MD5 intactos, ACL sin EXECUTE a PUBLIC/anon/auth; service_role sí | SELECT post-Train obligatorio | PENDIENTE_LIVE |
| G08-08 | Regresión antes y después de #3803/#3804/#3806 y compatibilidad | Evidencia histórica en L28 y B12, nuevo readback | REQUIERE_CONCILIACION_ARQUITECTURA_DBA |
| G08-09 | Baseline B05, integración B08 e interfaces/consumidores | No cubierta por ACL aislada | PENDIENTE_PRODUCTO_QA_IG |
| G08-10 | Recibo oficial íntegro, validación independiente y decisión del dueño | No atribuir firma sin mecanismo real | PENDIENTE_ARQUITECTURA_DBA_DUENO |

## Campos de cierre (sin inventar)
- PR / HEAD exacto: PENDIENTE
- Run R17 / PASE / clasificación: PENDIENTE
- Train run / paso final / code: PENDIENTE
- Ledger versión/nombre: PENDIENTE
- RUN `execution_id`, `operation_code`, estado: PENDIENTE
- SQL readback timestamp + resultado/ACL/4 MD5 + SHA evidencia: PENDIENTE
- Firma verificable Arquitectura/DBA: PENDIENTE
- Decisión final dueño: **NO_EMITIDA**. Este consentimiento autoriza el REVOKE, no acredita automáticamente G08 completo.
- Estado B12: **ABIERTO_HASTA_EVIDENCIA_Y_RECIBOS**. Producción general: NO-GO.
