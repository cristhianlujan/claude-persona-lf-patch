-- LF D1 -> D2 -> existing evidence planner -> D3: metadata-only preparation.
-- Does not dispatch an enterprise read or call an autonomous runtime.
-- Existing Supabase assets/policies and inventory remain authoritative.
CREATE OR REPLACE FUNCTION private.fn_lf_source_investigation_prepare_v1(
 p_objective text,p_candidate_budget integer DEFAULT 12
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path TO ''
AS $fn$
DECLARE
 v_qualification jsonb;
 v_discovery jsonb;
 v_checks jsonb:='[]'::jsonb;
 v_candidate jsonb;
 v_source_ref text;
 v_binding jsonb;
 v_binding_decision text;
 v_first_decision text:=NULL;
 v_structurally_ready integer:=0;
 v_plan jsonb;
 v_d3 jsonb;
 v_candidate_count integer:=0;
 v_checked integer:=0;
 v_stage text;
 v_observation jsonb;
BEGIN
 v_qualification:=private.fn_lf_d1_managed_inventory_qualification_v1();
 IF v_qualification->>'technical_readiness' IS DISTINCT FROM 'PASS' THEN
   RETURN pg_catalog.jsonb_build_object(
     'schema_version','LF_SOURCE_INVESTIGATION_PREPARATION_V1',
     'next_action','BLOCK_MANAGED_INVENTORY_NOT_CURRENT',
     'qualification',v_qualification,
     'discovery',pg_catalog.jsonb_build_object('discovery_state','ERROR_FAIL_CLOSED'),
     'binding_checks_count',0,
     'planner_stop_is_local_only',true,
     'global_discovery_exhausted',false,
     'business_data_read_authorized',false,
     'rows_accessed',false,
     'runtime_dispatched',false,
     'final_business_answer_allowed',false,
     'effects_executed',false);
 END IF;
 v_discovery:=private.fn_lf_d1_inventory_candidates_v1(p_objective,p_candidate_budget);
 IF v_discovery->>'discovery_state'='CANDIDATES_FOUND' THEN
   FOR v_candidate IN SELECT value FROM pg_catalog.jsonb_array_elements(
       coalesce(v_discovery->'candidate_sources','[]'::jsonb))
   LOOP
     v_source_ref:=v_candidate->>'source_ref';
     IF v_source_ref ~ '^db://[a-z_][a-z_0-9]*\.[a-z_][a-z_0-9]*$'
       AND v_candidate->>'source_kind' IN ('DB_TABLE','DB_VIEW') THEN
       v_binding:=private.fn_lf_d2_binding_readback_v1(v_source_ref);
       v_binding_decision:=v_binding->>'decision';
       v_checked:=v_checked+1;
       IF v_first_decision IS NULL THEN v_first_decision:=v_binding_decision; END IF;
       IF v_binding_decision='STRUCTURAL_MATCH_REQUIRES_REAL_ACTOR_FACADE_AUTHORIZATION'
        THEN v_structurally_ready:=v_structurally_ready+1; END IF;
       v_checks:=v_checks||pg_catalog.jsonb_build_array(
          pg_catalog.jsonb_build_object(
          'source_ref',v_source_ref,'binding_decision',v_binding_decision,
          'access_authorized',false,'rows_accessed',false));
     END IF;
   END LOOP;
 END IF;
 v_candidate_count:=coalesce((v_discovery->>'candidate_count')::integer,0);
 IF v_discovery->>'discovery_state'<>'CANDIDATES_FOUND' OR v_checked=0 THEN
   v_stage:='SOURCE_DISCOVERY';
   v_observation:=pg_catalog.jsonb_build_object(
       'discovery_state',v_discovery->>'discovery_state',
       'candidate_count',CASE WHEN v_checked=0 THEN 0 ELSE v_candidate_count END);
 ELSIF v_structurally_ready>0 THEN
   v_stage:='BINDING_READBACK';
   v_observation:=pg_catalog.jsonb_build_object('binding_decision',
     'STRUCTURAL_MATCH_REQUIRES_REAL_ACTOR_FACADE_AUTHORIZATION');
 ELSE
   v_stage:='BINDING_READBACK';
   v_observation:=pg_catalog.jsonb_build_object(
      'binding_decision',v_first_decision);
 END IF;
 v_d3:=private.fn_lf_d3_investigation_decision_v1(v_stage,v_observation);
 -- Planner is the existing engine. NO unadmitted candidates are passed as
 -- available. Its STOP is local to these supplied admissible candidates only.
 v_plan:=public.lf_targeted_evidence_acquisition_plan_v1(
   pg_catalog.jsonb_build_object(
    'consumer_ref','lf-d1d2-metadata-preparation',
    'unresolved_reasons',pg_catalog.jsonb_build_array('AUTHORIZED_BUSINESS_EVIDENCE_MISSING'),
    'current_evidence','[]'::jsonb,
    'candidates','[]'::jsonb));
 RETURN pg_catalog.jsonb_build_object(
   'schema_version','LF_SOURCE_INVESTIGATION_PREPARATION_V1',
   'discovery',v_discovery,
   'binding_checks',v_checks,
   'binding_checks_count',v_checked,
   'structurally_ready_bindings_count',v_structurally_ready,
   'planner_code',v_plan->>'code',
   'planner_stop_is_local_only',true,
   'd3',v_d3,'next_action',v_d3->>'next_action',
   'global_discovery_exhausted',false,
   'business_data_read_authorized',false,
   'rows_accessed',false,
   'runtime_dispatched',false,
   'final_business_answer_allowed',false,
   'effects_executed',false);
EXCEPTION WHEN insufficient_privilege THEN
 RETURN pg_catalog.jsonb_build_object(
   'schema_version','LF_SOURCE_INVESTIGATION_PREPARATION_V1',
   'next_action','BLOCK_CANONICAL_AUTHORITY_ACL_DENIED',
   'global_discovery_exhausted',false,
   'business_data_read_authorized',false,
   'rows_accessed',false,
   'runtime_dispatched',false,
   'final_business_answer_allowed',false,
   'effects_executed',false);
END $fn$;
COMMENT ON FUNCTION private.fn_lf_source_investigation_prepare_v1(text,integer)
 IS 'Metadata-only procedural composition of existing D1, D2, planner and D3; not an executor.';
REVOKE ALL ON FUNCTION private.fn_lf_source_investigation_prepare_v1(text,integer)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.fn_lf_source_investigation_prepare_v1(text,integer)
 TO service_role;
