-- LF D3: generic decision semantics for investigation procedure.
-- No source-specific routes, read access, user decisions, or data-plane operations.
-- An observation is UNTRUSTED until a separate canonical Supabase receipt readback.
-- This function only proposes the next procedure step, never a final answer.
CREATE OR REPLACE FUNCTION private.fn_lf_d3_investigation_decision_v1(
 p_stage text,p_observation jsonb
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path TO ''
AS $fn$
DECLARE
 v_action text:='BLOCK_UNRECOGNIZED_PROCEDURE_STATE';
 v_provisional text:=NULL;
 v_status text;
 v_count integer;
 v_read_count integer;
 v_scope_complete boolean;
 v_freshness text;
 v_error text:=NULL;
BEGIN
 IF jsonb_typeof(p_observation) IS DISTINCT FROM 'object' THEN
   v_error:='OBSERVATION_NOT_OBJECT';
 ELSIF p_stage='SOURCE_DISCOVERY' THEN
   v_status:=p_observation->>'discovery_state';
   IF p_observation->>'candidate_count' ~ '^[0-9]{1,4}$' THEN
     v_count:=(p_observation->>'candidate_count')::integer;
   ELSE v_count:=-1; END IF;
   IF v_status='ERROR_FAIL_CLOSED' THEN
     v_action:='BLOCK_DISCOVERY_POLICY_OR_TECHNICAL_ERROR';
   ELSIF v_status='NO_MATCH_IN_SCOPE' AND v_count=0 THEN
     v_action:='EXPAND_DISCOVERY_SCOPE_OR_OBTAIN_MORE_CONTEXT';
   ELSIF v_status='CANDIDATES_FOUND' AND v_count BETWEEN 1 AND 25 THEN
     v_action:='RESOLVE_CANONICAL_BINDING_FOR_CANDIDATES';
   ELSE
     v_error:='DISCOVERY_OBSERVATION_INCONSISTENT';
   END IF;
 ELSIF p_stage='BINDING_READBACK' THEN
   v_status:=p_observation->>'binding_decision';
   IF v_status='STRUCTURAL_MATCH_REQUIRES_REAL_ACTOR_FACADE_AUTHORIZATION' THEN
     v_action:='REQUEST_REAL_IDENTITY_AND_TENANT_FACADE_ADMISSION';
   ELSIF v_status='BLOCK_BINDING_ABSENT_OR_AMBIGUOUS' THEN
     v_action:='SEARCH_OTHER_CANDIDATES_OR_GOVERN_BINDING';
   ELSIF v_status='BLOCK_INVENTORY_SOURCE_NOT_UNIQUE_CURRENT' THEN
     v_action:='RETURN_TO_CANONICAL_SOURCE_DISCOVERY';
   ELSIF v_status LIKE 'BLOCK_%' THEN
     v_action:='BLOCK_UNVERIFIED_OR_UNAUTHORIZED_SOURCE';
   ELSE
     v_error:='BINDING_OBSERVATION_INCONSISTENT';
   END IF;
 ELSIF p_stage='FACADE_OBSERVATION' THEN
   -- No raw JSON receipt can prove actor, tenant, permissions or RLS.
   v_action:='VERIFY_AUTHORIZED_FACADE_RECEIPT_IN_SUPABASE';
   v_freshness:=p_observation->>'freshness_state';
   v_scope_complete:=p_observation->>'search_scope_complete'='true';
   IF p_observation->>'record_count' ~ '^[0-9]{1,7}$' THEN
     v_read_count:=(p_observation->>'record_count')::integer;
   ELSE v_read_count:=-1; END IF;
   IF v_read_count<0 OR v_freshness IS NULL
      OR v_freshness NOT IN ('CURRENT','STALE','UNKNOWN')
      OR pg_catalog.jsonb_typeof(p_observation->'search_scope_complete') IS DISTINCT FROM 'boolean' THEN
     v_error:='FACADE_OBSERVATION_INVALID';
   ELSIF v_freshness<>'CURRENT' THEN
     v_provisional:='REFRESH_FACADE_EVIDENCE';
   ELSIF NOT v_scope_complete THEN
     v_provisional:='CONTINUE_BOUNDED_SEARCH_OR_REQUEST_SCOPE';
   ELSIF v_read_count=0 THEN
     v_provisional:='NO_MATCH_WITHIN_CHECKED_SCOPE_ONLY';
   ELSIF v_read_count=1 THEN
     v_provisional:='INVESTIGATE_SINGLE_RECORD_STATUS_AND_RELATED_EVIDENCE';
   ELSE
     v_provisional:='REQUEST_MINIMUM_DISAMBIGUATOR_FOR_MULTIPLE_RECORDS';
   END IF;
 ELSIF p_stage='TECHNICAL_FAILURE' THEN
   v_action:='RETURN_TO_TARGETED_EVIDENCE_ACQUISITION';
 ELSE
   v_error:='PROCEDURE_STAGE_NOT_RECOGNIZED';
 END IF;
 IF v_error IS NOT NULL THEN
    v_action:='BLOCK_MALFORMED_PROCEDURE_INPUT';
    v_provisional:=NULL;
 END IF;
 RETURN pg_catalog.jsonb_build_object(
  'schema_version','LF_D3_INVESTIGATION_DECISION_V1',
  'stage',p_stage,'next_action',v_action,
  'provisional_after_verified_receipt',v_provisional,
  'validation_error',v_error,
  'final_business_answer_allowed',false,
  'canonical_actor_receipt_required',true,
  'global_discovery_exhausted',false,
  'business_data_read_authorized',false,
  'effects_executed',false);
END $fn$;
COMMENT ON FUNCTION private.fn_lf_d3_investigation_decision_v1(text,jsonb)
IS 'Generic D3 next-step planning only; untrusted raw observation never authorizes a business answer.';
REVOKE ALL ON FUNCTION private.fn_lf_d3_investigation_decision_v1(text,jsonb)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.fn_lf_d3_investigation_decision_v1(text,jsonb)
 TO service_role;
