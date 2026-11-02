# PG-01 H1-C2 — handoff de activación de Operations (sin permiso de despliegue)

Fecha de observación: 2026-11-02. Fuente de verdad: Supabase readback y GitHub PR #3492 / Issue #2646. Este artefacto **no** habilita Operations ni concede una aprobación de Edge.

## Estado observado y código que se reutiliza
- Operación canónica: `DEPLOY_SUPABASE_EDGE_FUNCTION_LF`. `lf_operation_registry`: `status=CANDIDATO_READ_ONLY`, `lifecycle_state_code=OP_CANDIDATE`.
- `lf_operation_contracts`: `status=CANDIDATE_READ_ONLY`, `runtime_effect_enabled=false`, transporte declarado `GOVERNED_SUPABASE_EDGE_MANAGEMENT_API`.
- `lf_router_action_registry`: `EDGE_FUNCTION_DEPLOY` con `write_allowed=false`, `status=CANDIDATO_READ_ONLY`.
- Ocho pasos requeridos activos; ocho contratos, ocho jueces y ocho bindings `ACTIVE_ENFORCEMENT`. No crear registros paralelos.
- Cero ejecuciones `lf_operation_execution` para `lf-pg01-oidc-authority-v1`. Función todavía no desplegada; no existe rollback a versión anterior.
- Código canónico `edge_operation_authority_probe_v1.py` es solo lectura y siempre devuelve `can_deploy=false`. `edge_operation_step_judges_v1.py` exige `human_role=SUPER_ADMIN` y `human_decision=APPROVE_DEPLOY`.
- PR #3492 (Draft) prepara el transporte de GitHub para el slug exacto, pero su job `deploy-pg01-oidc` está **desactivado con `if: false && ...`**. No retirarlo hasta admisión real.

## Ruta crítica de decisión — sin reimplementación
1. **Decisión de gobernanza:** mantener firma humana por operación, o autorizar mediante acto independiente una delegación limitada y revocable. La preferencia del Owner por ausencia de aprobación recurrente no constituye por sí sola un recibo `SUPER_ADMIN`.
2. **Operación vigente y transportes:** calificar transporte autenticado de Operations, reserva/consumo del `lf_operation_effect_guard`, R17 canónico y bloqueo por ejecución; no aceptar check de GitHub como autorización del efecto.
3. **Bootstrap de función ausente:** readback autenticado de inexistencia; fuente exacta de main (incluidos imports); recuperación gobernada mediante deshabilitación/remoción y readback independiente. No inventar `rollback_sha` anterior.
4. **Activación mediante Train autorizado:** solo tras evidencia de 1–3, cambiar conjuntamente y de forma rastreable registry, contract y route. SQL directo o estado parcial no constituyen activación.
5. **Apertura del transporte:** PR separado y revisado para eliminar `if: false` únicamente cuando el ejecutor obtenga atestaciones externas verdaderas; pruebas adversariales de replay, cross-slug, cross-SHA, interrupción y doble ejecución.
6. **Cierre auténtico:** Deploy con permiso, postreadback de versión/JWT/bytes, recibos Supabase, GitHub OIDC positivo y negativos; después H1-C3/H1-C4.

## Criterios NO-GO verificables
- Cualquier `OP_CANDIDATE`, `runtime_effect_enabled=false`, `write_allowed=false`, falta de ejecución admitida, ausencia de firma/delegación conforme a política, o falta de reserva del effect guard.
- Evidencia que solo sea test local, JSON autofirmado, chequeo de nombre del bot, workflow completo, o recibo POST-PASE de otro alcance.
- Primera instalación tratada como actualización con rollback histórico inexistente.
- Ausencia de estrategia de recuperación real o despliegue que no coteje código y JWT de la función exacta.

**Responsabilidad siguiente:** gobernanza/Operations (#2646), con implementación acotada antes de habilitar #3492. No se solicita tocar otros 48 registros de operaciones.
