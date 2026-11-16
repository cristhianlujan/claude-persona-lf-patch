# LF Step70 — evaluación y promoción según decisión del dueño

## Modos de revisión y procedencia

`INDEPENDENT_EVAL_CONTEXT / PASS_INDEPENDENT_SEMANTIC` exige la cadena
inmutable de recibos `REQUEST → EXECUTOR → JUDGE`, SHA del RAW Step50,
alcance Step40, Step60 PASS, contexto limpio y los cinco controles GOV-037
aplicables. No declarar independencia cuando su procedencia no se verifica.

`CURRENT_CONTEXT_REVIEW / PASS_REVIEWED_CURRENT_CONTEXT` registra explícitamente
`reviewer_is_producer=true`, `producer_independence_proven=false`,
`model_call_count=0`, `judge_independence_status=NOT_PROVEN`.
Se admite el cierre técnico del RUN en el modo ya soportado por los
bridges; conservar controles V3 y hashes. El valor de `manifest.no_promotion`
no decide cierre, aprobación ni promoción (decisión del dueño, 2026-11-15
19:08 Lima).

## Ruta genérica CURRENT_CONTEXT

Step70 con `PASS_REVIEWED_CURRENT_CONTEXT`, Step80 y `COMPLETED` constituyen
una ejecución gobernada con evidencia técnica verificable. La ruta genérica
está en
[`20261101050034_lf_profile_current_context_semantic_review_v1.sql`](../../../supabase/migrations/20261101050034_lf_profile_current_context_semantic_review_v1.sql).
El modo actual no finge una segunda llamada ni un juicio independiente.

La **solicitud de promoción** es una decisión posterior y distinta que
se resuelve por `public.lf_rule_promotion_request_v1` y
`public.lf_rule_promotion_score_v1`: hashes Step40/50/60/70, referencias
de regla, `unsupported_claims=[]`, `behavior_tests` con pruebas PG17/18
ejecutables y CI verificado, nota A/B/C/D, `hard_block` y decisión
`AUTO / MANUAL / BLOCKED`. La aceptación del modo propio registra
`judge_independence=NOT_PROVEN_OWNER_ACCEPTED`, **no** `PROVEN`.

**AUTO no equivale a identidad humana.** La función actual
`lf_rule_promotion_decide_v1` requiere `decided_by=HUMAN:...` y rechaza
`AUTO_SCORE_V1`. El score se conserva con solicitud `PENDING_HUMAN_APPROVAL`
hasta que exista una decisión gobernada o una modificación explícita posterior
de ese contrato. No inventar aprobación del dueño.

## Evidencia Quality 497B6E82 (histórica, no reescribir)

El RUN `EXEC-PROFILE-GATE2-497B6E82FA5593B0F03CB10C` registró
`PASS_REVIEWED_CURRENT_CONTEXT`, independencia `NOT_PROVEN`, y Step50
`RETURN_TO_ORCHESTRATOR`, **19/25**, con hallazgos
`QUALITY_SEMANTIC_INDEPENDENCE_NOT_PROVEN` y
`QUALITY_GOV037_FULL_RESOLVER_GATE_NOT_EXECUTED`. No alterar sus
evidencias, identidad ni dictamen. El scoring posterior de reglas no
transforma retrospectivamente una evaluación Quality.

Para un dictamen Quality independiente cuando sea aplicable, usar las
**cinco compuertas GOV-037**, fuente congelada y evaluación limpia ejecutada
por el dueño. La política de solicitud de promoción usa el score y no el
valor `no_promotion`. Los controles de fuente y aprobaciones explícitas para
borrados/impactos irreversibles siguen vigentes.

## Verificación

- `20261114163200_lf_rule_promotion_independent_step70_existing_route_v1.sql`
  es la fuente histórica; el cambio nuevo se introduce por migración con
  versión posterior a `20261115222000`.
- PG17 / PG18: `BEGIN / ROLLBACK`, positivos de `CURRENT_CONTEXT`,
  negativos de hashes, Step70 ausente/FAIL, matriz score y hard_block.
- Leer `pg_get_functiondef` y resultados reales de CI/SELECT tras
  Merge Train. No dar por aplicada una fuente que siga en PR.
