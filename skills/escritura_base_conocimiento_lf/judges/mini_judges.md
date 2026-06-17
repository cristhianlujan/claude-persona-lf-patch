# Mini Judges -- SKILL_ESCRITURA_BASE_CONOCIMIENTO_LF

## MINI_JUDGE_KBWRITE_S1A_ROUTER_V1
**PASS si:** router_read=true AND operation_scope_verified=true
**BLOCK si:** router_bypassed OR scope_not_verified
**Codigo:** BLOCKED_ROUTER_BYPASS

## MINI_JUDGE_KBWRITE_S2A_UPSTREAM_V1
**PASS si:** decision_id presente AND decision_upstream=ALLOW_PROD_GATE AND source verificada
**BLOCK si:** decision_missing OR decision_not_allow OR decision_unverified
**Codigo:** BLOCKED_UPSTREAM_DECISION_NOT_ALLOW

## MINI_JUDGE_KBWRITE_S3A_CONTENT_V1
**PASS si:** topic presente AND source_url presente AND visible_text suficiente
**BLOCK si:** topic_missing OR source_url_missing OR visible_text_empty
**Codigo:** BLOCKED_CONTENT_VALIDATION_FAIL

## MINI_JUDGE_KBWRITE_S4A_KB_CLASS_V1
**PASS si:** kb_category presente AND kb_subcategory presente AND classification_reason presente
**BLOCK si:** generic_classification OR kb_category_missing OR no_classification_reason
**Codigo:** BLOCKED_KB_CLASSIFICATION_FAIL

## MINI_JUDGE_KBWRITE_S5A_SUMMARY_V1
**PASS si:** summary presente AND key_insights no vacio AND quality_score presente
**BLOCK si:** summary_empty OR key_insights_empty OR summary_inventado sin fuente
**Codigo:** BLOCKED_SUMMARY_GENERATION_FAIL

## MINI_JUDGE_KBWRITE_S6A_DEDUP_V1
**PASS si:** dedup_checked AND (no_duplicate OR update_autorizado)
**BLOCK si:** duplicate_detectado sin autorizacion OR dedup_not_run
**Codigo:** BLOCKED_DEDUP_CHECK_FAIL

## MINI_JUDGE_KBWRITE_S7A_WRITE_V1
**PASS si:** kb_id retornado AND write_status=WRITTEN AND execution_mode_autorizado
**BLOCK si:** write_sin_autorizacion OR kb_id_missing OR execution_mode_no_autorizado
**Codigo:** BLOCKED_KB_WRITE_NOT_AUTHORIZED

## MINI_JUDGE_KBWRITE_S8A_READBACK_V1
**PASS si:** record_found_in_kb AND fields_match_input AND no_data_corruption
**BLOCK si:** record_not_found OR fields_mismatch OR data_corruption_detected
**Codigo:** BLOCKED_READBACK_FAIL

## MINI_JUDGE_KBWRITE_S9A_EVIDENCE_V1
**PASS si:** evidence_pack completo AND event_registered AND kb_id en evidence
**BLOCK si:** evidence_pack_incompleto OR event_not_registered OR evidencia inventada
**Codigo:** BLOCKED_EVIDENCE_CLOSE_FAIL
