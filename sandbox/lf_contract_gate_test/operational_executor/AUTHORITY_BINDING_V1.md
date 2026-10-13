# Vinculación de autorización del carril operacional (candidato)

**Estado:** diseño/código en PR #2372; no aplicado, no activado. La conexión Supabase actual continúa READ_ONLY.

## Autoridad reutilizada

La función de admisión ya **no acepta un JSON que se declare aprobado como autoridad**. Consume y revalida los objetos existentes de LF:

- `private.lf_human_decision_requests_v1` y `private.lf_human_decision_receipts_v1`, mediante `fn_lf_human_decision_consume_v1`.
- `fn_lf_human_decision_current_for_subject_v1` para bloquear una decisión sustituida por una solicitud abierta o más reciente.
- `fn_lf_human_decision_resolve_policy_v1` para exigir clasificación, política de ruta y autoridad activas.
- `fn_lf_human_decision_assert_authority_receipt_v1` para verificar el recibo canónico en `programacion.provenance_receipts`, su digest, actor, objeto, autoridad y currentness.
- `fn_lf_operation_reserve_execution_v1` para registrar la ejecución una sola vez. Router sigue anclando su recibo.

La **clasificación de decisión ya existente** es `DATA_OPERATIONS`. La pareja de productor/sujeto genérica para este carril es `LF_OPERATION_EXECUTOR / OPERATIONAL_EXECUTION`, con decisión `APPROVE`. Es un contrato transversal, no un caso de IG, checkpoint o proyecto.

## Vinculación de sujeto exigida

La solicitud verificada debe tener `subject_key = execution_id` y `subject_ref` con estos atributos de contrato: `operation_code`, `execution_id`, `handler_code`, `handler_revision`, `payload_sha256`, `effect_scope`, `dispatch_key` e `idempotency_key`. Todos se cruzan con la reserva real.

La invocación `lf_operational_executor_admit_v1` recibe un **localizador**, no una autorización emitida por el caller, en `p_approval_receipt`: `schema_version=LF_OPERATIONAL_REQUEST_AUTHORIZATION_V1`, `decision=APPROVED`, `request_id`, `receipt_id`, `receipt_sha256`, `currentness_sha256`, `approval_ref=supabase://private/lf_human_decision_receipts_v1/<receipt_id>` y los bindings exactos de handler/payload/efecto. La base vuelve a leer todos los recibos, no confía en esas cadenas.

Admisión, BEGIN y FINISH verifican la vigencia y la ausencia de nuevas solicitudes superiores. No hay ejecución si la autoridad está desactivada, el recibo cambia, la solicitud expira o el sujeto no coincide.

## Dependencias que siguen bloqueadas

El readback de LF observa **cero políticas de autoridad activas y cero recibos de decisión humana**: no se ha habilitado ni inventado autoridad. La materialización de la clasificación, política de ruta y fuente verificable de decisión debe pasar por el gobierno existente; ninguna migración de este PR inserta una aprobación o credencial humana.

También faltan un sandbox del esquema LF completo con pruebas transaccionales, auditoría del propietario SECURITY DEFINER / privilegios efectivos, aplicación exclusivamente por Migration Train y EKB. El CI de PostgreSQL 17 comprueba gramática PL/pgSQL y RBAC real **en un contenedor desechable**, pero no equivale al E2E de Supabase.

**Veredicto vigente:** CODE CANDIDATE / BLOCK_APPLY / BLOCK_DEPLOY / PASE SKIPPED. No crear conexión nueva todavía.
