# Handoff: ACT-0056 → Generación de Contenido LF

**Skill origen:** SKILL_ANALISIS_RIESGO_CONTENIDO_LF (ACT-0056)  
**Destino:** Skill de generación de contenido LF (pendiente de crear)  
**Tabla de transferencia:** lf_content_decisions

## Condiciones para handoff

- decision = ALLOW_CANDIDATE_READ_ONLY o ALLOW_PRODUCTION
- consumer_gate_passed = true
- evidence_pack completo
- hitl_required = false
- p0_p1_flags = []

## Campos que pasan al siguiente step

| Campo | Descripción |
|---|---|
| decision_id | Referencia trazable de la decisión |
| topic | Tema clasificado |
| risk_family | Familia de riesgo evaluada |
| claim_type | Tipo de claim procesado |
| funnel_stage | Etapa del funnel |
| source_url | URL fuente verificada |
| visible_text | Texto visible procesado |
| decision | Decisión autorizada |
| evidence_pack | Pack de evidencia completo |

## Bloqueadores de handoff

- decision = RESEARCH_OR_HITL → No handoff, requiere investigación
- decision = HITL_REQUIRED → No handoff, escalar a humano
- decision = BLOCK_OR_HITL → No handoff, bloquear pipeline
- consumer_gate_passed = false → No handoff, falta gate formal

## Nota operativa

Este handoff es candidato. La skill de generación de contenido LF aún no existe como activo formal en el portafolio. Registrar backlog si se requiere priorizar su creación.
