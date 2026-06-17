# Mini Judges — SKILL_ANALISIS_RIESGO_CONTENIDO_LF

## MINI_JUDGE_JIEANA_S1A_ROUTER_V1
**Step:** router  
**PASS si:** router_read=true AND operation_scope_verified=true  
**BLOCK si:** router_bypassed OR operation_scope_not_verified  
**Código bloqueo:** BLOCKED_ROUTER_BYPASS

## MINI_JUDGE_JIEANA_S2A_CASE_READ_V1
**Step:** case_read  
**PASS si:** case_id presente AND source_ref verificado AND texto presente o gap declarado  
**BLOCK si:** case_missing OR source_unverified OR raw_text_absent sin declaración de gap  
**Código bloqueo:** BLOCKED_CASE_READ_NOT_CLEAN

## MINI_JUDGE_JIEANA_S3A_VISIBLE_EVIDENCE_V1
**Step:** visible_evidence_check  
**PASS si:** source_url presente AND (visible_text suficiente OR research_required declarado)  
**BLOCK si:** claim inferido sin evidencia visible OR source_url ausente OR gap no declarado  
**Código bloqueo:** BLOCKED_VISIBLE_EVIDENCE_INSUFFICIENT

## MINI_JUDGE_JIEANA_S4A_CLASSIFICATION_V1
**Step:** claim_classification  
**PASS si:** classification_reason presente AND claim_type en valores permitidos  
**BLOCK si:** clasificación genérica OR sin evidencia OR risk_family no soportada  
**Código bloqueo:** BLOCKED_CLAIM_CLASSIFICATION_NOT_CLEAN

## MINI_JUDGE_JIEANA_S5A_GROUNDING_V1
**Step:** grounding_check  
**PASS si:** grounding_status en valores permitidos AND grounding insuficiente → research o block  
**BLOCK si:** decisión sin grounding OR grounding insuficiente no marcado  
**Código bloqueo:** BLOCKED_GROUNDING_INSUFFICIENT

## MINI_JUDGE_JIEANA_S6A_RISK_JUDGE_V1
**Step:** risk_judge  
**PASS si:** risk_level presente AND p0_p1_flags evaluados AND pii_detected declarado  
**BLOCK si:** P0/P1 no evaluado OR claim alto riesgo permitido sin razón OR PII sin redactar  
**Código bloqueo:** BLOCKED_RISK_JUDGE_NOT_CLEAN

## MINI_JUDGE_JIEANA_S7A_HITL_V1
**Step:** hitl_judge  
**PASS si:** P0/P1 rutea a HITL o BLOCK AND hitl_reason presente cuando requerido  
**BLOCK si:** P0/P1 sin HITL OR hitl_required sin razón OR override sin autoridad  
**Código bloqueo:** BLOCKED_HITL_JUDGE_NOT_CLEAN

## MINI_JUDGE_JIEANA_S8A_DECISION_V1
**Step:** decision_matrix  
**PASS si:** decision en [ALLOW_CANDIDATE_READ_ONLY, ALLOW_PROD_GATE, RESEARCH_OR_HITL, HITL_REQUIRED, BLOCK_OR_HITL] AND decision_reason presente  
**BLOCK si:** decisión fuera de schema OR decisión productiva no autorizada OR alto riesgo sin HITL  
**Código bloqueo:** BLOCKED_DECISION_MATRIX_NOT_CLEAN

## MINI_JUDGE_JIEANA_S9A_EVIDENCE_CLOSE_V1
**Step:** evidence_close  
**PASS si:** evidence_pack completo AND decisión escrita en lf_content_decisions AND evento registrado  
**BLOCK si:** decisión sin evidencia OR source_refs faltantes OR evidencia inventada  
**Código bloqueo:** BLOCKED_EVIDENCE_PACK_NOT_CLEAN
