# RETIREMENT_MANIFEST_SECURITY_GOVERNANCE_20260601

Estado: RETIRO_ARCHIVO_CONTROLADO
Proyecto: 00_GOBERNANZA_PORTAFOLIO_OPERATIVO_LF
Backlog: BACKLOG-GOV-RETIRAR-CANDIDATOS-CONTAMINADOS-SEGURIDAD-GOBERNANZA-20260601
Backlog ID: 48
Decisión: RETIRAR_CANDIDATO_CONTAMINADO_Y_RECREAR_DESDE_CERO
Fecha operativa: 2026-06-01

## 1. Motivo

Se retiran como candidatos contaminados los activos de seguridad de gobernanza creados/reparados el 2026-05-30 porque quedaron vinculados a ejecuciones con cierre bloqueado, steps no canónicos y paquete GitHub incompleto.

No se elimina evidencia histórica. Este manifest preserva el vínculo con los blobs originales y bloquea su uso operativo.

## 2. Activos retirados

| Activo | Ruta original | SHA original | Clasificación |
|---|---|---|---|
| CARD-MANEJO-SEGURO-IA-GOBERNANZA-LF-20260529 | cards/manejo_seguro_ia_gobernanza_lf/CARD.md | a312ba93869c95768e5f4c548a0327d9b09fba9a | CONTAMINATED_REQUIRES_RETIRE_OR_RECREATE |
| CARD-ZERO-TRUST-GOVERNANCE-SCOPE-CONTROL-LF-20260529 | cards/zero_trust_governance_scope_control_lf/CARD.md | 04b30c939bfd198ac0118fbff4d8b8be01f1ba1e | CONTAMINATED_REQUIRES_RETIRE_OR_RECREATE |
| PERFIL-SEGURIDAD-GOBERNANZA-LF-20260529 | perfiles/seguridad_gobernanza_lf/SKILL.md | af0bda09d0e8d84594003b2b607da1a359bb68f0 | CONTAMINATED_REQUIRES_RETIRE_OR_RECREATE |

## 3. Ejecuciones contaminadas relacionadas

| Execution | Operation | Motivos |
|---|---|---|
| EXEC-CARDS-SEGURIDAD-GOBERNANZA-LF-20260530-001 | CREACION_CARD_LF | closure_allowed=false; blocked_from_closure=true; PASS_WITH_RESTRICTIONS; approved_read_only=false; production_allowed=false; steps 30/31 no canónicos |
| EXEC-PERFIL-SEGURIDAD-GOBERNANZA-LF-20260530-001 | CREACION_PERFIL_LF | closure_allowed=false; blocked_from_closure=true; PASS_WITH_RESTRICTIONS; security_hold_continues=true; operational_approval_allowed=false; step_id 28/29 desalineados y 30/31 no canónicos |

## 4. Estado posterior al retiro

- Uso operativo: BLOQUEADO.
- Runtime: NO_HABILITADO.
- Impacto automático: BLOQUEADO.
- Producción general: NO VALIDADA.
- Protocolos: NO MODIFICADOS.
- lf_operation_steps: NO MODIFICADO.
- Evidencia histórica: PRESERVADA.

## 5. Regla de recreación

Estos activos no deben remendarse encima. La recreación debe hacerse desde cero con nuevos códigos/rutas y pasando por:

1. CREACION_CARD_LF completo para las cards nuevas.
2. CREACION_PERFIL_LF completo para el perfil nuevo.
3. Sin steps ad hoc.
4. Sin marcar VALIDATED.
5. Sin habilitar runtime ni impacto automático.

## 6. Cierre

Este manifest no cierra el backlog. Solo documenta el retiro/archivo controlado previo a la recreación desde cero.
