CREATE OR REPLACE FUNCTION programacion.fn_ig_m98_independent_receipt_match_v6(p_producer jsonb,p_diff jsonb,p_decision jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path TO 'pg_catalog' AS $m$
SELECT coalesce(
p_producer->>'verification_state'='VERIFIED'
AND p_producer->>'receipt_kind'='IG_SHADOW_COMPARISON'
AND p_producer->>'gate_code'='IG_SHADOW_CANDIDATE_COMPARE'
AND p_producer#>>'{verification_payload,comparison_scope}'='PER_FIELD_CURRENT_CANDIDATE'
AND p_producer#>>'{verification_payload,provider_readback_verified}'='true'
AND p_producer#>>'{verification_payload,digest_recomputed}'='true'
AND p_decision#>>'{verification_payload,provider_readback_verified}'='true'
AND p_decision#>>'{verification_payload,digest_recomputed}'='true'
AND p_diff->>'level_code' IN ('D1','D2','D3','D5')
AND p_decision#>>'{receipt_payload,typed_evidence,adjudication,producer_receipt_id}'=p_producer->>'receipt_id'
AND p_decision->>'execution_id' IS DISTINCT FROM p_producer->>'execution_id'
AND p_decision->>'created_by_execution_id' IS DISTINCT FROM p_producer->>'created_by_execution_id'
AND programacion.fn_ig_m96_verified_field_decision_match_v1(p_decision,p_diff,p_producer->>'source_head_sha')
AND p_decision#>>'{receipt_payload,typed_evidence,adjudication,diff_ref}'=p_diff->>'diff_ref'
AND p_decision#>>'{receipt_payload,typed_evidence,adjudication,diff_sha256}'=p_diff->>'diff_sha256',false);
$m$;