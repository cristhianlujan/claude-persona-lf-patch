# LF Lote 5 — contrato candidato: veredicto ciego, propietario, retorno
Estado: **DRAFT / NO-GO / NO LIVE APPLY**. Ruta: **IG propone → perfil propietario aprueba → no resuelto: humano**.

## Fuente y autoridad

1. IG conserva su API existente #3682: `fn_input_governance_semantic_packet_v1` y `fn_input_governance_semantic_external_receipt_readback_v1`. No se crea un segundo IG ni un segundo juez.
2. El veredicto de las 5 pasadas **no está adjunto como lista RAW** a este lote. La afirmación «130/130, 0/24, N=5» fue reportada por el auditor, pero ningún id/cita concretos están acreditados aquí. No reemplazar esta ausencia por citas inventadas.
3. El adaptador lee exclusivamente `ig_semantic_external_receipt.l5_blind_case_verdict` ya obtenido por la API existente; no admite un veredicto proporcionado al llamar a la función de pin.
4. Estructura de cada caso: `id` (opaco K...), `verdict` (`ALLOW`, `BLOCK`, `INCONCLUSIVE`), `exact_excerpt` (literal de la regla), `source_code`, `source_sha256`, `rule_snapshot_sha256`, `packet_sha256`, `candidate_sha256`. El snapshot de la regla y la cita se revalidan en base de datos.
5. `lf_rule_promotion_blind_verdict_pin_v1` genera hash del caso + hash del vínculo que incluye promoción, IG RUN, snapshot de regla, packet, candidato, hash del recibo #3682 y binding IG; `lf_rule_promotion_blind_verdict_verify_v1` valida cada elemento al decidir y al aplicar.
6. `BLOCK` o `INCONCLUSIVE` → `HUMAN_DECISION_REQUIRED`, sin aprobación automática. Un `ALLOW` no es autoridad: únicamente habilita la revisión del **perfil propietario** con su recibo Step70 bajo los contratos existentes. Si el recibo real de caso no existe → `RETRY_REQUIRED`.
7. **Pendiente upstream**: el readback #3682 desplegado no está acreditado como emisor de `l5_blind_case_verdict` ni como emisor de un recibo real de esas pasadas; se requiere una operación gobernada del mismo IG, sin otra instancia o juez. La suite PG18 usa un mock declarado y no lo acredita.

## Registro de propietarios — sin autoasignación

- Tabla candidata: `public.lf_rule_promotion_profile_owner_v1` de L4D. **No hay INSERT/seed en las migraciones L4D/L5**.
- **Quién escribe:** custodio de la **gerencia de reglas/decisiones gobernadas**, mediante una migración autorizada basada en una entrada `public.lf_decisiones_gov` `VIGENTE/APROBADA`. No se añade endpoint de escritura interactivo; la operación de registro queda pendiente de su autorización oficial.
- **Quién lee:** `lf_rule_promotion_profile_owner_verify_v1`, `lf_rule_promotion_profile_approve_v1` y la continuación del perfil por funciones `SECURITY DEFINER`. El servicio solo tiene SELECT directo sobre la tabla de mapeo.
- **Vínculo exigido:** `raw_payload.rule_code` y `raw_payload.owner_profile_code` de la decisión canónica deben coincidir con `rule_code`/perfil propietario mapeados. Se valida el SHA256 de esa misma decisión por el quality judge. Además, el perfil debe tener la autoridad vigente `PROMOCION_REGLA_LF`.
- **Sin autoasignación:** tabla con DML revocado a `PUBLIC/anon/authenticated/service_role`; proponente `requested_by_profile`, identidad IG y `HUMAN:` no pueden ser propietarios. Los perfiles no tienen permiso de escritura en el registro. El ID de usuario no se infiere del prompt.

## Retorno al perfil y readback

- `lf_rule_promotion_apply_v1`: **misma ruta existente**, ahora con verificación semántica/propietario/receipts; actualiza `lf_ops.reglas` dentro de un bloque transaccional, calcula hash del snapshot esperado con `estado=VIGENTE`, ejecuta `lf_rule_promotion_rule_readback_v1` y compara estado/hash.
- Si falla el readback o la actualización, la subtransacción revierte `VIGENTE`; queda `APPROVED + rule_return_status=RETRY_REQUIRED` (estado de promoción reintentable) y la regla continúa `CANDIDATO`.
- Si pasa: `APPLIED + rule_return_status=READY`, recibo de retorno con SHA256 de regla, binding propietario, recibo IG, binding ciego y hash de la salida.
- El perfil propietario hace **lectura** por `lf_rule_promotion_profile_return_readback_v1(promotion_id,owner_execution_id)` en la continuación gobernada de su RUN. Rechaza cualquier otro execution_id y revalida regla VIGENTE y hashes de retorno/IG/caso. **No es transporte nuevo, PUSH ni escritor Step80**.
- `report_output` / paso 80 debe usar su bridge oficial y acreditar recibo terminal conforme EKB. No se han emitido pasos, reportes ni RUN históricos.

## Evidencias, límites y aceptación

- El PG18 local/CI usa mocks **marcados** como `PG18_MOCK_NOT_USER_REVIEW`, siempre con ROLLBACK; ningún PASS estructural sirve como recibo semántico real.
- Un caso real necesita el archivo RAW de cinco pasadas (no la clave) y una vinculación que demuestre cuál regla/promoción revisa. No permitir que se seleccione a conveniencia un ALLOW de otro caso.
- PASE/paridad global, revisión en banco del usuario, fuente oficial del registro, delivery real del readback #3682, independencia y cierre del perfil → **UNVERIFIED / NO-GO**.
- IG y perfil son el **mismo modelo**: la doble intervención mide **consistencia**, no independencia.
