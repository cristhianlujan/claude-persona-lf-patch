-- LF Input Governance: ticket-bound, read-only Validator scope inspection.
-- Prevents CANDIDATE_ONLY from altering the normal SOURCE_INTEGRITY_ONLY run.
-- This is a native Validator helper, not a new route, writer or judge.
BEGIN;
CREATE OR REPLACE FUNCTION public.fn_input_governance_validator_semantic_scope_info_v1(
 p_run_id bigint,p_ticket uuid
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','programacion'
AS $body$
DECLARE v_run record; v_selected text[]; v_status text;
BEGIN
 IF p_run_id IS NULL OR p_run_id < 1 OR p_ticket IS NULL THEN
   RAISE EXCEPTION 'IG_SEMANTIC_SCOPE_INFO_INPUT_INVALID';
 END IF;
 PERFORM public.lf_profile_ig_ticket_verify_v1(p_ticket,NULL,p_run_id);
 SELECT r.status,r.scope->>'validator_semantic_mode' AS mode,
        r.scope->>'semantic_promotion_authorized' AS promo,
        r.invalidated_at INTO v_run
 FROM programacion.input_readiness_runs r WHERE r.id=p_run_id;
 IF NOT FOUND OR v_run.invalidated_at IS NOT NULL OR
    v_run.status NOT IN ('CURATING','VALIDATING','COMPLETED') THEN
   RAISE EXCEPTION 'IG_SEMANTIC_SCOPE_INFO_RUN_NOT_CURRENT:%',p_run_id;
 END IF;
 v_selected:=programacion.fn_input_validator_semantic_scope_v1(p_run_id);
 IF v_run.promo IS DISTINCT FROM 'false'
    OR v_run.mode NOT IN ('SOURCE_INTEGRITY_ONLY','SELECTED_SEMANTIC_COMPARISON') THEN
    RAISE EXCEPTION 'IG_SEMANTIC_SCOPE_INFO_UNAUTHORIZED:%',p_run_id;
 END IF;
 IF v_run.mode='SOURCE_INTEGRITY_ONLY' AND cardinality(v_selected)<>0 THEN
   RAISE EXCEPTION 'IG_SEMANTIC_SCOPE_INFO_SOURCE_ONLY_HAS_SELECTION:%',p_run_id;
 END IF;
 IF v_run.mode='SELECTED_SEMANTIC_COMPARISON' AND cardinality(v_selected)=0 THEN
   RAISE EXCEPTION 'IG_SEMANTIC_SCOPE_INFO_SELECTED_EMPTY:%',p_run_id;
 END IF;
 RETURN jsonb_build_object(
  'run_id',p_run_id,'run_status',v_run.status,
  'validator_semantic_mode',v_run.mode,
  'selected_families',to_jsonb(v_selected),
  'semantic_promotion_authorized',false,
  'official_write_authorized',false,
  'production_authorized',false);
END $body$;
REVOKE ALL ON FUNCTION
 public.fn_input_governance_validator_semantic_scope_info_v1(bigint,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.fn_input_governance_validator_semantic_scope_info_v1(bigint,uuid)
 TO service_role;
COMMIT;
