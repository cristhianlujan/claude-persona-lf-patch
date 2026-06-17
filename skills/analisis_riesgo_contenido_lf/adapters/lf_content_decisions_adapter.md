# ADAPTER: lf_content_decisions

**Skill owner:** SKILL_ANALISIS_RIESGO_CONTENIDO_LF (ACT-0056)  
**Tabla destino:** public.lf_content_decisions  
**Estado:** CANDIDATO_READ_ONLY  
**Operación:** WRITE (solo en DRY_RUN/SANDBOX con go explícito)

## Mapeo de campos

| Campo skill output | Columna BD | Tipo | Notas |
|---|---|---|---|
| run_id | run_id | UUID | Generado por la skill |
| operation_code | operation_code | TEXT | Siempre ANALISIS_RIESGO_CONTENIDO_LF |
| execution_mode | execution_mode | TEXT | DRY_RUN / SANDBOX / PRODUCTION_CONTROLLED |
| topic | topic | TEXT | Nullable |
| risk_family | risk_family | TEXT | Nullable |
| claim_type | claim_type | TEXT | Nullable |
| funnel_stage | funnel_stage | TEXT | Nullable |
| grounding_status | grounding_status | TEXT | Nullable |
| source_url | source_url | TEXT | Nullable |
| visible_text | visible_text | TEXT | Nullable |
| risk_level | risk_level | TEXT | LOW/MEDIUM/HIGH/CRITICAL |
| risk_reasons | risk_reasons | JSONB | Array de strings |
| p0_p1_flags | p0_p1_flags | JSONB | Array de strings |
| pii_detected | pii_detected | BOOLEAN | Default false |
| hitl_required | hitl_required | BOOLEAN | Default false |
| hitl_reason | hitl_reason | TEXT | Nullable |
| severity | severity | TEXT | Nullable |
| decision | decision | TEXT | NOT NULL — 5 valores permitidos |
| decision_reason | decision_reason | TEXT | Nullable |
| evidence_pack | evidence_pack | JSONB | Default {} |
| consumer_gate_passed | consumer_gate_passed | BOOLEAN | Default false |
| evidence_event_id | evidence_event_id | BIGINT | ID evento lf_eventos |

## Restricciones del adapter

- NO escribir sin run_id válido
- NO escribir sin execution_mode explícito
- NO escribir en producción sin consumer_gate_passed=true
- decision debe ser uno de los 5 valores del schema
