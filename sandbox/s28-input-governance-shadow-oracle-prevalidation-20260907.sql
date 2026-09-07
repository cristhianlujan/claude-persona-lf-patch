-- INPUT_GOVERNANCE_AGENT / Strategy 28 / IG-C prevalidation
-- Rollback-only source candidate. No live runtime switch, no promotion, no production mutation.
-- Frozen holdout source: runs 213 ONB_003 and 214 ONB_004, contract revision 5.12.
-- Demonstrated authority patterns only:
--   1) APPLICABILITY_READINESS <- ADR-EKB-033 + PRV-AUD-019
--   2) ROLLOUT_PRODUCTION_GATES <- INPUT_GOVERNANCE_EXECUTION_CONTRACT
-- Remaining holdout families are intentionally NOT given an oracle while family_spec source authority is UNRESOLVED_NOT_DECLARED.

begin;

do $guard$
declare
  v_sha text;
begin
  select encode(digest(pg_get_functiondef(p.oid),'sha256'),'hex')
    into v_sha
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion'
    and p.proname='fn_input_governance_shadow_priority_oracle_v2';

  if v_sha is distinct from '10c4154eb5f71a169a531c223e982e1a1fac0ddc4968005ea000bd8d51c70d7d' then
    raise exception 'S28_IGC_ORACLE_BASELINE_SHA_MISMATCH:%',coalesce(v_sha,'NULL');
  end if;
end
$guard$;

create or replace function programacion.fn_input_governance_shadow_rollout_oracle_candidate_v1(
  p_version_id bigint,
  p_contract_override jsonb default null
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
as $function$
declare
  v_contract jsonb;
  v_source text;
  v_defined boolean:=false;
  v_fail_closed boolean:=false;
  v_has_promotion boolean:=false;
  v_has_production boolean:=false;
  v_promotion boolean;
  v_production boolean;
  v_classification text;
  v_reason text;
begin
  if p_contract_override is null then
    select jsonb_build_object(
      'id',c.id,'version_id',c.version_id,'contrato_codigo',c.contrato_codigo,
      'estado',c.estado,'fail_closed',c.fail_closed,'especificacion',c.especificacion
    ) into v_contract
    from programacion.contratos c
    where c.version_id=p_version_id
      and c.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT';
    v_source:='DIRECT_PROGRAMACION_CONTRATOS_READBACK';
  else
    v_contract:=p_contract_override;
    v_source:='SYNTHETIC_MUTATION_TEST_ONLY';
  end if;

  v_defined:=coalesce(v_contract->>'estado','')='defined';
  v_fail_closed:=coalesce((v_contract->>'fail_closed')::boolean,false);
  v_has_promotion:=jsonb_typeof(v_contract->'especificacion'->'promotion_authorized')='boolean';
  v_has_production:=jsonb_typeof(v_contract->'especificacion'->'production_authorized')='boolean';
  if v_has_promotion then v_promotion:=(v_contract->'especificacion'->>'promotion_authorized')::boolean; end if;
  if v_has_production then v_production:=(v_contract->'especificacion'->>'production_authorized')::boolean; end if;

  if v_defined and v_fail_closed and v_has_promotion and v_has_production then
    v_classification:='COMPLETE';
    v_reason:=case when v_production
      then 'EXECUTION_CONTRACT_COMPLETE_PRODUCTION_AUTHORIZED'
      else 'EXECUTION_CONTRACT_COMPLETE_PRODUCTION_NOT_AUTHORIZED' end;
  elsif v_contract is null then
    v_classification:='MISSING';
    v_reason:='EXECUTION_CONTRACT_MISSING';
  else
    v_classification:='MISSING';
    v_reason:='EXECUTION_CONTRACT_AUTHORITY_INCOMPLETE_OR_NOT_FAIL_CLOSED';
  end if;

  return jsonb_build_object(
    'shadow_contract','INPUT_GOVERNANCE_SHADOW_ROLLOUT_ORACLE_CANDIDATE_V1',
    'version_id',p_version_id,'family_code','ROLLOUT_PRODUCTION_GATES',
    'implemented',true,'decisional',false,'comparison_only',true,'mutates_readiness',false,
    'promotion_authorized',false,'production_authorized',false,
    'classification',v_classification,'reason',v_reason,'direct_source_mode',v_source,
    'observed_authority',jsonb_build_object(
      'contract_defined',v_defined,'fail_closed',v_fail_closed,
      'promotion_authority_explicit',v_has_promotion,'production_authority_explicit',v_has_production,
      'promotion_authorized_value',v_promotion,'production_authorized_value',v_production
    ),
    'source_refs',case when v_contract is null then '[]'::jsonb else jsonb_build_array(
      jsonb_build_object('kind','CONTRACT','ref','INPUT_GOVERNANCE_EXECUTION_CONTRACT','version_id',p_version_id,'id',v_contract->>'id')
    ) end
  );
end
$function$;

create or replace function programacion.fn_input_governance_shadow_applicability_oracle_candidate_v1(
  p_decision_override jsonb default null,
  p_prevention_override jsonb default null
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
as $function$
declare
  v_decision jsonb;
  v_prevention jsonb;
  v_decision_ok boolean:=false;
  v_prevention_ok boolean:=false;
  v_classification text;
  v_reason text;
begin
  if p_decision_override is null then
    select to_jsonb(d) into v_decision from transversal.decision_log d where d.adr='ADR-EKB-033';
  else
    v_decision:=p_decision_override;
  end if;

  if p_prevention_override is null then
    select to_jsonb(p) into v_prevention from transversal.prevention_rules p where p.regla_codigo='PRV-AUD-019';
  else
    v_prevention:=p_prevention_override;
  end if;

  v_decision_ok:=coalesce(lower(v_decision->>'estado'),'')='vigente'
    and coalesce(v_decision->>'decision','') ilike '%source authority independiente%'
    and coalesce(v_decision->>'decision','') ilike '%source_ref%';
  v_prevention_ok:=coalesce((v_prevention->>'activa')::boolean,false)
    and v_prevention->>'error_codigo'='AUD-019'
    and coalesce(v_prevention->>'regla','') ilike '%autoridad de fuente independiente%'
    and coalesce(v_prevention->>'regla','') ilike '%semánticas explícitas%';

  if v_decision_ok and v_prevention_ok then
    v_classification:='COMPLETE';
    v_reason:='INDEPENDENT_SOURCE_AUTHORITY_AND_SEMANTIC_VALIDATION_POLICY_RESOLVED';
  else
    v_classification:='MISSING';
    v_reason:='APPLICABILITY_READINESS_AUTHORITY_INCOMPLETE';
  end if;

  return jsonb_build_object(
    'shadow_contract','INPUT_GOVERNANCE_SHADOW_APPLICABILITY_ORACLE_CANDIDATE_V1',
    'family_code','APPLICABILITY_READINESS','implemented',true,'decisional',false,'comparison_only',true,
    'classification',v_classification,'reason',v_reason,
    'authority_checks',jsonb_build_object('ADR-EKB-033',v_decision_ok,'PRV-AUD-019',v_prevention_ok),
    'source_refs',jsonb_build_array(
      jsonb_build_object('kind','EKB_DECISION','ref','ADR-EKB-033','row_sha256',programacion.fn_v09_sha256_jsonb(v_decision)),
      jsonb_build_object('kind','EKB_PREVENTION','ref','PRV-AUD-019','row_sha256',programacion.fn_v09_sha256_jsonb(v_prevention))
    )
  );
end
$function$;

do $tests$
declare
  v_contract jsonb;
  v_decision jsonb;
  v_prevention jsonb;
  v_result jsonb;
begin
  select jsonb_build_object('id',c.id,'version_id',c.version_id,'contrato_codigo',c.contrato_codigo,'estado',c.estado,'fail_closed',c.fail_closed,'especificacion',c.especificacion)
    into v_contract
  from programacion.contratos c where c.version_id=19 and c.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT';
  select to_jsonb(d) into v_decision from transversal.decision_log d where d.adr='ADR-EKB-033';
  select to_jsonb(p) into v_prevention from transversal.prevention_rules p where p.regla_codigo='PRV-AUD-019';

  v_result:=programacion.fn_input_governance_shadow_rollout_oracle_candidate_v1(19,null);
  if v_result->>'classification'<>'COMPLETE' then raise exception 'S28_ROLLOUT_POSITIVE_FAIL:%',v_result; end if;
  if (select coverage_status from programacion.input_family_assessments where run_id=214 and family_code='ROLLOUT_PRODUCTION_GATES')<>v_result->>'classification' then raise exception 'S28_ROLLOUT_COVERAGE_DIVERGENCE'; end if;
  if programacion.fn_input_governance_shadow_rollout_oracle_candidate_v1(19,v_contract #- '{especificacion,production_authorized}')->>'classification'<>'MISSING' then raise exception 'S28_ROLLOUT_DROP_AUTHORITY_NOT_DETECTED'; end if;
  if programacion.fn_input_governance_shadow_rollout_oracle_candidate_v1(19,jsonb_set(v_contract,'{fail_closed}','false'::jsonb,true))->>'classification'<>'MISSING' then raise exception 'S28_ROLLOUT_FAIL_OPEN_NOT_DETECTED'; end if;
  if programacion.fn_input_governance_shadow_rollout_oracle_candidate_v1(19,jsonb_set(v_contract,'{especificacion,production_authorized}','true'::jsonb,true))->>'classification'<>'COMPLETE' then raise exception 'S28_ROLLOUT_AUTHORIZED_METAMORPHIC_FAIL'; end if;

  v_result:=programacion.fn_input_governance_shadow_applicability_oracle_candidate_v1(null,null);
  if v_result->>'classification'<>'COMPLETE' then raise exception 'S28_APPLICABILITY_POSITIVE_FAIL:%',v_result; end if;
  if (select coverage_status from programacion.input_family_assessments where run_id=213 and family_code='APPLICABILITY_READINESS')<>v_result->>'classification' then raise exception 'S28_APPLICABILITY_COVERAGE_DIVERGENCE'; end if;
  if programacion.fn_input_governance_shadow_applicability_oracle_candidate_v1(jsonb_set(v_decision,'{estado}','"deprecated"'::jsonb,true),v_prevention)->>'classification'<>'MISSING' then raise exception 'S28_APPLICABILITY_DECISION_STATE_MUTATION_NOT_DETECTED'; end if;
  if programacion.fn_input_governance_shadow_applicability_oracle_candidate_v1(v_decision,jsonb_set(v_prevention,'{activa}','false'::jsonb,true))->>'classification'<>'MISSING' then raise exception 'S28_APPLICABILITY_PREVENTION_STATE_MUTATION_NOT_DETECTED'; end if;
  if programacion.fn_input_governance_shadow_applicability_oracle_candidate_v1(jsonb_set(v_decision,'{decision}','"No independent authority semantics"'::jsonb,true),v_prevention)->>'classification'<>'MISSING' then raise exception 'S28_APPLICABILITY_SEMANTIC_MUTATION_NOT_DETECTED'; end if;
end
$tests$;

select jsonb_build_object(
  'status','PASS_ROLLBACK_ONLY',
  'holdout_pairs_total',6,
  'oracle_architecture_demonstrated_pairs',2,
  'remaining_source_authority_blocked_pairs',4,
  'baseline_priority_oracle_v2_sha256','10c4154eb5f71a169a531c223e982e1a1fac0ddc4968005ea000bd8d51c70d7d',
  'live_runtime_changed',false,
  'claim_ceiling','PREVALIDATION_ONLY_NO_IGC_CLOSURE_NO_LIVE_ORACLE'
) as receipt;

rollback;
