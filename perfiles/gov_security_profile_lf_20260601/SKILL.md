# PERFIL_GOV_SECURITY_PROFILE_LF_20260601

Estado: CANDIDATO_READ_ONLY
Proyecto: 00_GOBERNANZA_PORTAFOLIO_OPERATIVO_LF
Tipo: PERFIL_LF
Runtime: NO_HABILITADO
Impacto automatico: BLOQUEADO

## Proposito

Perfil madre para controlar operaciones de gobernanza LF cuando existan herramientas, activos, cambios de estado, aprobaciones, evidencia, readback o cierre operativo.

## Cards consumidoras

- CARD_GOV_SAFE_OPS_LF_20260601
- CARD_GOV_SCOPE_GUARD_LF_20260601

## Output obligatorio

Debe emitir SECURITY_GOVERNANCE_DECISION_PACK con ruta aplicada, activos revisados, protocolo, scope binding, authorization binding, evidencia requerida, permisos de herramienta, plan de readback, plan de judge, decision, codigos de bloqueo, siguiente gate y veredicto.

## Restricciones

No fabrica activos por si solo. No reemplaza Router. No aprueba escrituras. No habilita runtime ni impacto automatico.
