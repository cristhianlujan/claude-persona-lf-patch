# Handoff: ACT-0056 -> ACT-0057

**Skill origen:** SKILL_ANALISIS_RIESGO_CONTENIDO_LF (ACT-0056)
**Skill destino:** SKILL_ESCRITURA_BASE_CONOCIMIENTO_LF (ACT-0057)
**Tabla de transferencia:** lf_content_decisions -> lf_knowledge_base

## Condiciones de handoff

- decision = ALLOW_PROD_GATE en lf_content_decisions
- evidence_pack completo en registro upstream
- consumer_gate_passed = false (ACT-0057 lo activara tras readback)

## Campos que recibe ACT-0057

| Campo | Fuente |
|---|---|
| decision_id | lf_content_decisions.decision_id |
| run_id | Nuevo UUID generado por ACT-0057 |
| topic | lf_content_decisions.topic |
| source_url | lf_content_decisions.source_url |
| visible_text | lf_content_decisions.visible_text |
| claim_type | lf_content_decisions.claim_type |
| funnel_stage | lf_content_decisions.funnel_stage |
| grounding_status | lf_content_decisions.grounding_status |

## Pipeline siguiente

Desde lf_knowledge_base el contenido puede alimentar:
- Generacion de contenido LF
- Social Listening
- Dashboards de inteligencia competitiva
