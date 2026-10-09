
create or replace function programacion.fn_input_governance_shadow_evaluate_v2(
  p_pantalla_id integer,
  p_version_id bigint default 19
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog'
as $$
declare
  v_family text;
  v_spec jsonb;
  v_current jsonb;
  v_sem_handled boolean;
  v_resolution_contract text;
  v_oracle jsonb;
  v_source_kinds jsonb;
  v_source_ref_count integer;
  v_specific_ref_count integer;
  v_test_fail_count integer;
  v_findings jsonb;
  v_rows jsonb:='[]'::jsonb;
  v_family_count integer:=0;
  v_stage_unresolved_count integer:=0;
  v_generic_source_only_count integer:=0;
  v_test_obligations_empty_count integer:=0;
  v_test_failure_family_count integer:=0;
  v_current_incomplete_without_semantic_resolver_count integer:=0;
  v_trace_contract_absent_count integer:=0;
  v_current_story_blocked_count integer:=0;
  v_oracle_implemented_family_count integer:=0;
  v_oracle_divergence_count integer:=0;
  v_meta_gap_family_count integer:=0;
  v_payload jsonb;
begin
  if not exists(select 1 from lf_ops.pantallas p where p.id=p_pantalla_id) then
    raise exception 'SHADOW_V2_SCREEN_NOT_FOUND:%',p_pantalla_id;
  end if;

  perform programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id);

  for v_family in
    select f.value
    from lf_ops.reglas r
    cross join lateral jsonb_array_elements_text(coalesce(r.valor_config->'families','[]'::jsonb)) f(value)
    where r.codigo='B2B-RULE-STORY-READINESS-001'
    order by f.value
  loop
    v_family_count:=v_family_count+1;
    v_spec:=programacion.fn_input_governance_shadow_family_spec_v2(v_family,p_version_id);
    v_current:=programacion.fn_input_governance_bootstrap_classify_v2(p_pantalla_id,v_family,p_version_id);

    -- bootstrap_classify_v2 already invokes semantic_probe_v3 and copies its
    -- handled result into the governed semantic rationale/probe. Reuse it.
    v_sem_handled:=coalesce(v_current->>'rationale','') like 'Governed semantic resolution %';
    v_resolution_contract:=nullif(v_current->'probe'->>'resolution_contract','');

    v_oracle:=programacion.fn_input_governance_shadow_priority_oracle_v2(p_pantalla_id,v_family,p_version_id);

    if v_spec->'stage_authority'->>'status'='UNRESOLVED' then
      v_stage_unresolved_count:=v_stage_unresolved_count+1;
    end if;

    select coalesce(jsonb_agg(q.kind order by q.kind),'[]'::jsonb)
      into v_source_kinds
    from (
      select distinct sr.value->>'kind' as kind
      from jsonb_array_elements(coalesce(v_current->'source_refs','[]'::jsonb)) sr(value)
      where nullif(sr.value->>'kind','') is not null
    ) q;

    v_source_ref_count:=jsonb_array_length(coalesce(v_current->'source_refs','[]'::jsonb));

    select count(*) into v_specific_ref_count
    from jsonb_array_elements(coalesce(v_current->'source_refs','[]'::jsonb)) sr(value)
    where sr.value->>'kind'<>'SCREEN_CANONICAL_GRAPH';

    if v_source_ref_count>0 and v_specific_ref_count=0 then
      v_generic_source_only_count:=v_generic_source_only_count+1;
    end if;

    if coalesce((v_spec->>'test_obligation_count')::integer,0)=0 then
      v_test_obligations_empty_count:=v_test_obligations_empty_count+1;
    end if;

    select count(*) into v_test_fail_count
    from jsonb_array_elements(coalesce(v_spec->'test_obligations','[]'::jsonb)) t(value)
    where t.value->>'status'='FAIL';

    if v_test_fail_count>0 then
      v_test_failure_family_count:=v_test_failure_family_count+1;
    end if;

    if v_current->>'coverage_status' in ('MISSING','PARTIAL')
       and not v_sem_handled then
      v_current_incomplete_without_semantic_resolver_count:=v_current_incomplete_without_semantic_resolver_count+1;
    end if;

    if v_current->>'coverage_status' in ('MISSING','PARTIAL')
       and v_resolution_contract is null
       and not coalesce((v_oracle->>'implemented')::boolean,false) then
      v_trace_contract_absent_count:=v_trace_contract_absent_count+1;
    end if;

    if v_current->>'story_ready_status'='BLOCKED' then
      v_current_story_blocked_count:=v_current_story_blocked_count+1;
    end if;

    if coalesce((v_oracle->>'implemented')::boolean,false) then
      v_oracle_implemented_family_count:=v_oracle_implemented_family_count+1;
      if v_oracle->>'classification' in ('MISSING','PARTIAL','COMPLETE')
         and v_current->>'coverage_status'<>v_oracle->>'classification' then
        v_oracle_divergence_count:=v_oracle_divergence_count+1;
      end if;
    end if;

    v_findings:='[]'::jsonb;

    if v_spec->'stage_authority'->>'status'='UNRESOLVED' then
      v_findings:=v_findings||jsonb_build_array(jsonb_build_object(
        'code','SHADOW_V2_STAGE_AUTHORITY_UNRESOLVED',
        'current_effective_required_by_stage',v_current->>'required_by_stage'
      ));
    end if;

    if v_source_ref_count>0 and v_specific_ref_count=0 then
      v_findings:=v_findings||jsonb_build_array(jsonb_build_object(
        'code','SHADOW_V2_TYPED_PROVENANCE_GENERIC_ONLY',
        'source_kinds',v_source_kinds
      ));
    end if;

    if v_test_fail_count>0 then
      v_findings:=v_findings||jsonb_build_array(jsonb_build_object(
        'code','SHADOW_V2_META_TEST_FAILURE',
        'failed_test_count',v_test_fail_count
      ));
    end if;

    if coalesce((v_oracle->>'implemented')::boolean,false)
       and v_oracle->>'classification' in ('MISSING','PARTIAL','COMPLETE')
       and v_current->>'coverage_status'<>v_oracle->>'classification' then
      v_findings:=v_findings||jsonb_build_array(jsonb_build_object(
        'code','SHADOW_V2_CURRENT_ORACLE_COVERAGE_DIVERGENCE',
        'current_coverage',v_current->>'coverage_status',
        'oracle_classification',v_oracle->>'classification'
      ));
    end if;

    if jsonb_array_length(v_findings)>0 then
      v_meta_gap_family_count:=v_meta_gap_family_count+1;
    end if;

    v_rows:=v_rows||jsonb_build_array(jsonb_build_object(
      'family_code',v_family,
      'shadow_decisional',false,
      'family_spec',v_spec,
      'typed_provenance',jsonb_build_object(
        'status',case
          when v_specific_ref_count>0 then 'TYPED_PRESENT'
          when v_source_ref_count>0 then 'GENERIC_ONLY'
          else 'MISSING'
        end,
        'source_ref_count',v_source_ref_count,
        'specific_source_ref_count',v_specific_ref_count,
        'source_kinds',v_source_kinds
      ),
      'current_resolver_observation',jsonb_build_object(
        'semantic_handled',v_sem_handled,
        'resolution_contract',v_resolution_contract
      ),
      'independent_oracle',v_oracle,
      'current_result',jsonb_build_object(
        'applicability',v_current->>'applicability',
        'coverage_status',v_current->>'coverage_status',
        'story_ready_status',v_current->>'story_ready_status',
        'severity',v_current->>'severity',
        'blockers',coalesce(v_current->'blockers','[]'::jsonb)
      ),
      'meta_findings',v_findings,
      'meta_status',case
        when jsonb_array_length(v_findings)=0 then 'META_CONTRACT_OK'
        else 'META_GAPS_PRESENT'
      end
    ));
  end loop;

  v_payload:=jsonb_build_object(
    'shadow_contract','INPUT_GOVERNANCE_SHADOW_EVALUATOR_V2',
    'version_id',p_version_id,
    'pantalla_id',p_pantalla_id,
    'decisional',false,
    'mutates_readiness',false,
    'changes_story_gate',false,
    'promotion_authorized',false,
    'production_authorized',false,
    'comparison_only',true,
    'summary',jsonb_build_object(
      'family_count',v_family_count,
      'stage_authority_unresolved_count',v_stage_unresolved_count,
      'generic_source_only_count',v_generic_source_only_count,
      'test_obligations_empty_count',v_test_obligations_empty_count,
      'test_failure_family_count',v_test_failure_family_count,
      'current_incomplete_without_semantic_resolver_count',v_current_incomplete_without_semantic_resolver_count,
      'resolution_trace_contract_absent_count',v_trace_contract_absent_count,
      'current_story_blocked_count',v_current_story_blocked_count,
      'oracle_implemented_family_count',v_oracle_implemented_family_count,
      'oracle_divergence_count',v_oracle_divergence_count,
      'meta_gap_family_count',v_meta_gap_family_count
    ),
    'families',v_rows,
    'trace_contract_target',jsonb_build_object(
      'required_steps',jsonb_build_array(
        'CANDIDATE_DISCOVERY','EXPLICIT_REFERENCE_EXPANSION','AUTHORITY_RESOLUTION',
        'CANDIDATE_REJECTION','SUFFICIENCY_EVALUATION','FINAL_CLASSIFICATION'
      ),
      'priority_oracle_mode','DIRECT_READBACK_INDEPENDENT_OF_CURRENT_CLASSIFIER_FOR_CLASSIFICATION',
      'non_priority_oracle_mode','UNRESOLVED_NO_INDEPENDENT_ORACLE'
    )
  );

  return v_payload||jsonb_build_object(
    'shadow_sha256',programacion.fn_v09_sha256_jsonb(v_payload)
  );
end;
$$;
