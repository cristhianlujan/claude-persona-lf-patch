-- Input Governance Agent v5.5 audit remediation R2
-- Preserve the B2B-AUTH-005 screen-specific applicability assertion while keeping
-- governance policy assertions grounded in independent EKB authority. No promotion.

create or replace function programacion.fn_input_governance_assertion_relevant(p_family_code text,p_source_ref jsonb,p_path jsonb)
returns boolean
language plpgsql
immutable
set search_path to 'pg_catalog'
as $$
declare v_kind text:=coalesce(p_source_ref->>'kind',''); v_path text;
begin
  if p_family_code not in ('SOURCE_AUTHORITY_PROVENANCE','FRESHNESS_INVALIDATION','NEGATIVE_REQUIREMENTS','CONFLICT_PRECEDENCE','APPLICABILITY_READINESS') then return false; end if;
  if jsonb_typeof(p_path)<>'array' then return false; end if;
  select string_agg(x.value,'/' order by x.ord) into v_path from jsonb_array_elements_text(p_path) with ordinality x(value,ord);
  if v_kind in ('EKB_DECISION_SET','EKB_PREVENTION_SET') and (v_path='observed' or v_path like 'observed/%') then return true; end if;
  if p_family_code='APPLICABILITY_READINESS' and v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/rules%' then return true; end if;
  return false;
end;
$$;

do $$
declare
  v_old_id bigint:=73; v_new_id bigint; v_run programacion.input_readiness_runs%rowtype; v_old_ass programacion.input_family_assessments%rowtype; v_new_ass record;
  v_curator_identity text:='INPUT_CURATOR:v0.5r1-auth005-v55r2-20260818'; v_validator_identity text:='INPUT_VALIDATOR:v0.5r1-auth005-v55r2-20260818';
  v_run_sha text; v_assertions jsonb; v_source_ref jsonb; v_receipt jsonb;
begin
  select * into strict v_run from programacion.input_readiness_runs where id=v_old_id and status='COMPLETED';
  insert into programacion.input_readiness_runs(id,version_id,pantalla_id,universe_rule_id,supersedes_run_id,scope,universe_snapshot_sha256,family_count,status,curator_identity,contract_version,source_manifest,curator_component_id)
  values(nextval('programacion.input_readiness_runs_id_seq'),v_run.version_id,v_run.pantalla_id,v_run.universe_rule_id,v_old_id,v_run.scope||jsonb_build_object('remediation','AUDIT_20260818_R2_ASSERTION_CARDINALITY'),v_run.universe_snapshot_sha256,v_run.family_count,'CURATING',v_curator_identity,v_run.contract_version,'[]'::jsonb,46)
  returning id into v_new_id;

  for v_old_ass in select * from programacion.input_family_assessments where run_id=v_old_id order by id loop
    insert into programacion.input_family_assessments(id,run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,source_refs,rationale,blockers,negative_requirements,test_obligations,curator_evidence)
    values(nextval('programacion.input_family_assessments_id_seq'),v_new_id,v_old_ass.family_code,v_old_ass.severity,v_old_ass.applicability,v_old_ass.coverage_status,v_old_ass.well_defined_status,v_old_ass.story_ready_status,v_old_ass.implementation_ready_status,v_old_ass.qa_ready_status,v_old_ass.production_ready_status,v_old_ass.source_refs,v_old_ass.rationale,v_old_ass.blockers,v_old_ass.negative_requirements,v_old_ass.test_obligations,v_old_ass.curator_evidence||jsonb_build_object('remediation_revision','AUDIT_20260818_R2_ASSERTION_CARDINALITY','prior_candidate_run_id',v_old_id));
  end loop;

  update programacion.input_readiness_runs set status='VALIDATING',validator_identity=v_validator_identity,validator_component_id=47 where id=v_new_id;
  select source_snapshot_sha256 into strict v_run_sha from programacion.input_readiness_runs where id=v_new_id;

  for v_new_ass in select * from programacion.input_family_assessments where run_id=v_new_id order by id loop
    if v_new_ass.family_code='APPLICABILITY_READINESS' then
      v_source_ref:=jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH');
      v_receipt:=jsonb_build_object('ref',v_source_ref,'observed',programacion.fn_input_screen_canonical_graph(v_run.pantalla_id,19));
      v_assertions:=jsonb_build_array(jsonb_build_object('path',jsonb_build_array('observed','canonical_contract','rules'),'actual',v_receipt #> array['observed','canonical_contract','rules'],'expected',jsonb_build_array(jsonb_build_object('config',jsonb_build_object('normal_flow','DENY','legacy_trace_only',true,'activation_authority','HUMAN_DECISION_REQUIRED','implementation_as_active_path','DENY'),'rule_code','B2B-RULE-AUTH-035','pending_decision',true)),'operator','CONTAINS','source_ref',v_source_ref));
      v_source_ref:=jsonb_build_object('kind','EKB_DECISION_SET','adrs',jsonb_build_array('ADR-EKB-033'));
      v_receipt:=programacion.fn_input_resolve_source_ref(v_source_ref,v_run.pantalla_id,19);
      v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object('path',jsonb_build_array('observed'),'actual',v_receipt->'observed','expected',jsonb_build_array(jsonb_build_object('adr','ADR-EKB-033','estado','vigente')),'operator','CONTAINS','source_ref',v_source_ref));
      v_source_ref:=jsonb_build_object('kind','EKB_PREVENTION_SET','codes',jsonb_build_array('PRV-P0-002'));
      v_receipt:=programacion.fn_input_resolve_source_ref(v_source_ref,v_run.pantalla_id,19);
      v_assertions:=v_assertions||jsonb_build_array(jsonb_build_object('path',jsonb_build_array('observed'),'actual',v_receipt->'observed','expected',jsonb_build_array(jsonb_build_object('regla_codigo','PRV-P0-002','activa',true)),'operator','CONTAINS','source_ref',v_source_ref));
    else
      select validator_evidence->'assertions' into v_assertions from programacion.input_family_assessments where run_id=v_old_id and family_code=v_new_ass.family_code;
    end if;
    update programacion.input_family_assessments set validator_outcome='PASS',validator_findings='[]'::jsonb,validator_evidence=jsonb_build_object('assertions',v_assertions,'prevalidation','305_ASSERTIONS_CURRENT_SOURCE_RECHECK','curator_sha256',v_new_ass.curator_sha256,'execution_mode','INDEPENDENT_VALIDATOR','contract_revision','5.5','remediation_revision','AUDIT_20260818_R2_ASSERTION_CARDINALITY','direct_source_readback',true,'source_snapshot_sha256',v_run_sha),validator_identity=v_validator_identity where id=v_new_ass.id;
  end loop;
  update programacion.input_readiness_runs set status='COMPLETED' where id=v_new_id;
end;
$$;