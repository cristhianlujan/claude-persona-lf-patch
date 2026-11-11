# LF Issue #3779 — Lote 2/C | Auditoría de promoción (solo lectura)

**Fuente:** `pg_get_functiondef`, `pg_proc.proacl`, `pg_trigger`, `public.lf_profile_write_authority_v1`, `public.lf_operation_contracts`, `lf_rule_promotion_v1`; consulta en Supabase, 2026-11-11. Ninguna función de mutación fue ejecutada.

## Identidad, control y estado

| Función | MD5 de source `pg_get_functiondef` | Invocación/efecto real |
|---|---|---|
| `public.lf_rule_promotion_request_v1(text,text,text)` | `2fcac9f18b1581985af93639e475cd1a` | SECURITY DEFINER; acceso `postgres` y `service_role`; verifica parent `EJECUCION_PERFIL_LF IN_PROGRESS`, operación `PROMOCION_REGLA_LF` en `lf_profile_write_authority_v1 ACTIVE`, regla `CANDIDATO`, no PENDING/APPROVED previa y razón no vacía. Congela SHA, inserta solicitud `PENDING`. |
| `public.lf_rule_promotion_decide_v1(text,text,text,text)` | `16e45f40dad5cecc215a2f978be47728` | SECURITY DEFINER; `postgres/service_role`; solo `APPROVE/REJECT`, estado `PENDING` y texto `p_decided_by ~ '^HUMAN:.+'`. En aprobación revalida SHA; escribe `APPROVED/REJECTED`, `decided_by`, `decided_at`, nota en `reason`. |
| `public.lf_rule_promotion_apply_v1(text)` | `d7fe763c999db6f6259b6b1e2bd69644` | SECURITY DEFINER; `postgres/service_role`; exige `APPROVED` y SHA actual igual; cambia `lf_ops.reglas.estado: CANDIDATO → VIGENTE`; promoción `APPLIED`, `applied_at`. |
| `public.lf_rule_promotion_guard_v1()` | `ee782e4bd0128c80ee13881899c0d74e` | Trigger `trg_lf_rule_promotion_guard_v1` BEFORE UPDATE OF estado en `lf_ops.reglas`; rechaza entrada a `VIGENTE` sin alguna solicitud `APPROVED` para código+SHA anterior exacto. |
| `public.lf_rule_promotion_report_v1(integer,integer)` | `e3e521aaa933604de88d697196f54564` | SECURITY DEFINER; `postgres/service_role`; solo lista solicitudes PENDING, título/contenido, duplicidad aproximada de título, SHA drift, pantallas y códigos de decisión. No aprueba. |

## Hallazgos del contrato vivo

- `public.lf_profile_write_authority_v1`: `PERFIL-PRODUCT-DIRECTOR-LF / PROMOCION_REGLA_LF` está `ACTIVE`; `self_update_allowed=false`.
- `public.lf_operation_contracts`: **0** filas de operación cuyo código contiene `PROMOCION`; no confundir existencia de funciones/RPC con operación gobernada completa.
- `public.lf_rule_promotion_v1`: **0 filas** actuales. No se hizo ninguna solicitud de promoción.
- ACL: los métodos request/decide/apply/report (y batch) conceden EXECUTE a `service_role` y `postgres`; `anon/authenticated` no. La autenticación efectiva de un usuario debe hacerse **fuera** del simple texto `p_decided_by`.
- `decide_v1` **NO** contiene evidencia criptográfica, ID autenticado por sesión, vínculo independiente al juez o verificación de un recibo humano. El regex `HUMAN:.+` es solo una declaración de texto. **No está autorizado afirmar que un juez/determinista puede decidir automáticamente**; la implementación actual obliga una etiqueta humana aunque quien tenga `service_role` pueda técnicamente escribir esa cadena.
- `request_v1` no exige evidencia limpia del paso 70 en su cuerpo; el binding de perfil existe pero no prueba ejecución semántica independiente. La cadena de gobierno de promoción requiere cierre específico.
- `apply_v1` no verifica `ROW_COUNT=1` tras `UPDATE lf_ops.reglas` antes de marcar `APPLIED`; registrar este riesgo de falso cierre. No se corrige bajo alcance de auditoría solo lectura.
- El trigger comprueba solicitud APPROVED y SHA; no valida directamente quién decidió ni la identidad del llamador.

## Qué falta para promover exactamente una regla CANDIDATO

1. Autoridad operativa y políticas específicas de `PROMOCION_REGLA_LF`, con parent RUN real de Product Director y evidencia/juez exigida por la gobernanza del sistema.
2. Solicitud única contra código `CANDIDATO`, snapshot SHA vigente y razón, por `request_v1` mediante el invocador autorizado; la función hoy no se invoca.
3. Aprobación de **persona verificada fuera del campo de texto** y recibo auditable ligado al `promotion_id`; la función actual solo exige `HUMAN:...` y no acredita identidad. No sustituir por respuesta del modelo ni por juez determinista sin rediseñar esa política.
4. Control previo a apply: `APPROVED`, SHA inalterado, estado `CANDIDATO`, guard/trigger, `UPDATE row_count=1`, historia pre/post y comparación de estado final.
5. Ejecución únicamente por ruta oficial autorizada, readback y cierre. **Sin solicitar, decidir, aplicar ni insertar en este Lote 2**.

**Estado:** `UNVERIFIED` la identidad humana real, un juez independiente y un piloto positivo; `NOT_TESTED` los efectos de request/decide/apply. Solo código, MD5, ACL, trigger y tablas fueron leídos.
