# Handoff: ACT-0056 -> ACT-0057

**Skill origen:** SKILL_ANALISIS_RIESGO_CONTENIDO_LF (ACT-0056)
**Skill destino:** SKILL_ESCRITURA_BASE_CONOCIMIENTO_LF (ACT-0057)
**Tabla de transferencia:** lf_content_decisions -> lf_knowledge_base
**Version:** v0.2 — soporte KB multidimensional + ALERT_CAPTURE

## Condiciones de handoff

| decision | Pasa a ACT-0057 | kb_polarity | kb_dimension |
|---|---|---|---|
| ALLOW_PROD_GATE | SI | POSITIVO o NEUTRAL | EDUCATIVO, REGULATORIO o SEÑAL_MERCADO |
| ALERT_CAPTURE | SI | NEGATIVO | ALERTA o SEÑAL_MERCADO |
| ALLOW_CANDIDATE_READ_ONLY | NO — solo sandbox | — | — |
| RESEARCH_OR_HITL | NO | — | — |
| HITL_REQUIRED | NO — espera decision humana | — | — |
| BLOCK_OR_HITL | NO | — | — |

- evidence_pack completo en registro upstream
- consumer_gate_passed = false (ACT-0057 lo activara tras readback)
- Para ALERT_CAPTURE: alert_actor y alert_evidence_url deben venir en evidence_pack

## Campos que recibe ACT-0057 desde lf_content_decisions

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
| kb_polarity_suggested | lf_content_decisions.evidence_pack.kb_polarity_suggested |
| kb_dimension_suggested | lf_content_decisions.evidence_pack.kb_dimension_suggested |
| alert_actor | lf_content_decisions.evidence_pack.alert_actor (si ALERT_CAPTURE) |
| alert_evidence_url | lf_content_decisions.evidence_pack.alert_evidence_url (si ALERT_CAPTURE) |

## Pipeline siguiente

Desde lf_knowledge_base el contenido puede alimentar segun kb_polarity:

- POSITIVO/EDUCATIVO → Generacion de contenido LF, SEO, conversion
- POSITIVO/SEÑAL_MERCADO → Social Listening, dashboards demanda
- NEUTRAL/REGULATORIO → Contexto legal para contenido, disclaimers
- NEGATIVO/ALERTA → Contenido de proteccion usuario, diferenciacion LF vs competidores fraudulentos
- NEGATIVO/SEÑAL_MERCADO → Alertas de mercado, monitoreo reputacional
