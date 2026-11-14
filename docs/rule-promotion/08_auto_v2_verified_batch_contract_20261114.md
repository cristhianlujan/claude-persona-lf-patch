# LF — Promoción automática V2 condicionada a juez independiente y dueño verificado

**Solo sandbox. Sin fuentes simuladas en vivo.** Estado por SELECT: 166 CANDIDATO, 412 VIGENTE; 64 PASS directo, 7 SCOPE_REVIEW, 95 HOLD. Cero solicitudes de promoción y cero aplicaciones. Las 6 reglas con identity_verified=false (235,438,439,440,532,577) no están entre las 64 PASS. Dos de las 6 son ya VIGENTE. Las otras cuatro fallan calidad.

Fuentes: [64 IDs y 190 diagnósticos por SELECT](07_rule_promotion_preview_64_and_190_findings_20261114.json), [190 filas completas de causas y mecanismos](07_manual_findings_190_rules_v2_20261114.csv). Las 190 son 102 CANDIDATO restantes + 77 VIGENTE con calidad HOLD + 11 VIGENTE con SCOPE_REVIEW. Incluyen el path exacto del marcador pendiente y prueba propuesta.

## Contrato propuesto

| Etapa | Escritor/lector | Gate |
|---|---|---|
| PLAN | lf_rule_promotion_v2_auto_plan_v1() | V2, cuatro condiciones de calidad, SCOPE_EVIDENCE PASS, estado CANDIDATO, sin decisión ni identidad false, sha256 de cada fuente |
| OWNER | private.fn_lf_rule_promotion_v2_owner_receipt_check_v1 | Recibo humano canónico, hash de lote, IDs exactos, rol LF_OWNER y autoridad vigente verificada en provenance_receipts; declaración de chat no vale |
| JUEZ | EJECUCION_PERFIL_LF Product Director | Run IN_PROGRESS real con Step40→50→60→70; PASS_INDEPENDENT_SEMANTIC NUEVO y referencia a cada fuente |
| SOLICITUD | lf_rule_promotion_request_v1 por cada regla | Hash exacto y juez 70 realmente ligado |
| DECIDIR | lf_rule_promotion_decide_batch_v1 | Solo después de recibo humano auténtico; no aceptar una cadena HUMAN: improvisada |
| APLICAR | lf_rule_promotion_apply_batch_v1 | Todo el lote o rollback atómico ante error |
| AUDITAR | lf_rule_promotion_auto_audit_v1 | Antes/después SHA, promoción, run, humano, bitácora persistente |
| REVERTIR | lf_rule_promotion_v2_auto_reverse_v1 | Recibo humano nuevo, hash post-imagen intacto y actualización reversible VIGENTE→CANDIDATO |

Los errores de contenido y de falta de autoridad se reportan como FINDING_NO_WRITE con continuation_allowed=true: prosigue el run del perfil, pero ninguna regla recibe PASS o se promueve artificialmente. Funciones ejecutables solo por service_role, no anon/authenticated; no se transportan secretos al modelo.

## Estado de autoridad por SELECT

El registro LF del owner tiene identity_mode=UNVERIFIED_CHAT_DECLARATION y owner_sub placeholder. private.lf_human_decision_receipts_v1 registra 0, lf_ig_owner_decision_v2 registra 0 y políticas canónicas de autoridad humana ACTIVAS consultadas: 0. Existen Step70 históricos independientes, pero ningún recibo actual de los 64 en un Product Director run activo. Por lo tanto 0 promociones reales son autorizables hoy. No inventar identidad ni juez. El registro del recibo requiere la ruta humana oficial para RULE_PROMOTION / LF_RULE_PROMOTION_BATCH_V2 / LF_OWNER, ligada a un hash de los 64.

## Procedimiento reversible

SELECT audit_id,rule_id,rule_code,promotion_id,execution_id,owner_request_id,source_plan_sha256,original_rule_snapshot_sha256,applied_rule_snapshot_sha256,status,reverted_at FROM public.lf_rule_promotion_auto_audit_v1 ORDER BY audit_id;

Para revertir solicitar otro recibo humano legítimo con sujeto ROLLBACK:<audit_id>, acción APPROVE_ROLLBACK, mismo rule_id y sha256 de la post-imagen. Ejecutar vía RPC gobernado; ante drift retornar RULE_CHANGED_AFTER_PROMOTION sin tocar el estado. La promoción original sigue históricamente APPLIED y el audit específico se marca REVERTED. Nunca UPDATE directo.

## Test PG17/18

Test con exactamente 64 IDs de la simulación, pero con registros, juez independiente y autoridad humana **sintéticos de fixture**: falta owner → sin escritura; identidad falsificada → rechaza; juez no independiente → rechaza; dueño/juez sintéticos verificados → request/decide_batch/apply_batch reales en PG fixture, log de 64 y reversión autorizada de 1. Luego BEGIN/ROLLBACK deja 0 modificaciones. No atribuir el fixture a una ejecución humana real.

## Riesgos

El escritor legacy lf_rule_promotion_decide_v1 acepta solo el patrón HUMAN: sin autenticar la identidad por sí mismo. El nuevo adaptador sí exige recibo canónico y fuente; un acceso privilegiado directo al legacy permanece como riesgo a revisar antes de producción. No se baja calidad, no se toca V1 ni históricos 262+8, y no se promueve ninguna regla sin revisión del owner.
