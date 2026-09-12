-- INPUT_GOVERNANCE_AGENT 5.12
-- Non-decisional shadow evaluator v1.
-- Purpose: expose evaluator-architecture gaps without changing readiness, Story Gate,
-- promotion, production authorization, canonical contracts, or persisted assessments.

create or replace function programacion.fn_input_governance_shadow_universe_preflight_v1(
  p_version_id bigint default 19
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','programacion','lf_ops'
as $function$
declare
  v_family_count integer:=0;
  v_explicit_stage_count integer:=0;
  v_active_screen_count integer:=0;
  v_graph_joinable_screen_count integer:=0;
  v_orphans jsonb:='[]'::jsonb;
  v_payload jsonb;
begin
  if not exists(
    select 1
    from programacion.contratos c
    where c.version_id=p_version_id
      and c.contrato_codigo='INPUT_READINESS_CONTRACT'
  ) then
    raise exception 'SHADOW_INPUT_READINESS_CONTRACT_NOT_FOUND:%',p_version_id;
  end if;

  select count(*)
    into v_family_count
  from lf_ops.reglas r
  cross join lateral jsonb_array_elements_text(coalesce(r.valor_config->'families','[]'::jsonb)) f(value)
  where r.codigo='B2B-RULE-STORY-READINESS-001';

  select count(*)
    into v_explicit_stage_count
  from programacion.contratos c
  cross join lateral jsonb_object_keys(coalesce(c.especificacion->'family_stage_requirements','{}'::jsonb)) k(key)
  where c.version_id=p_version_id
    and c.contrato_codigo='INPUT_READINESS_CONTRACT';

  select count(*)
    into v_active_screen_count
  from lf_ops.pantallas p
  where p.activa=true;

  select count(*)
    into v_graph_joinable_screen_count
  from lf_ops.pantallas p
  join lf_ops.modulos m on m.module_id=p.module_id
  join lf_ops.app_shells s on s.app_shell_id=m.app_shell_id
  where p.activa=true;

  select coalesce(jsonb_agg(jsonb_build_object(
      'pantalla_id',p.id,
      'screen_code',p.codigo,
      'name',p.nombre,
      'module_id',p.module_id,
      'module_code',p.module_code,
      'reason','MODULE_OR_SHELL_GRAPH_LINK_MISSING'
    ) order by p.id),'[]'::jsonb)
    into v_orphans
  from lf_ops.pantallas p
  left join lf_ops.modulos m on m.module_id=p.module_id
  left join lf_ops.app_shells s on s.app_shell_id=m.app_shell_id
  where p.activa=true
    and (m.module_id is null or s.app_shell_id is null);

  v_payload:=jsonb_build_object(
    'shadow_contract','INPUT_GOVERNANCE_SHADOW_UNIVERSE_PREFLIGHT_V1',
    'version_id',p_version_id,
    'decisional',false,
    'mutates_readiness',false,
    'promotion_authorized',false,
    'production_authorized',false,
    'family_count',v_family_count,
    'explicit_stage_count',v_explicit_stage_count,
    'implicit_default_stage_count',greatest(v_family_count-v_explicit_stage_count,0),
    'active_screen_count',v_active_screen_count,
    'graph_joinable_screen_count',v_graph_joinable_screen_count,
    'graph_orphan_screen_count',jsonb_array_length(v_orphans),
    'graph_orphan_screens',v_orphans
  );

  return v_payload||jsonb_build_object('shadow_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;

create or replace function programacion.fn_input_governance_shadow_evaluate_v1(
  p_pantalla_id integer,
  p_version_id bigint default 19
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','programacion','lf_ops'
as $function$
declare
  v_contract jsonb;
  v_family text;
  v_stage_cfg jsonb;
  v_stage_source text;
  v_explicit_stage text;
  v_current jsonb;
  v_sem jsonb;
  v_sem_handled boolean;
  v_resolution_contract text;
  v_source_kinds jsonb;
  v_source_ref_count integer;
  v_specific_ref_count integer;
  v_test_count integer;
  v_findings jsonb;
  v_rows jsonb:='[]'::jsonb;
  v_family_count integer:=0;
  v_stage_unspecified_count integer:=0;
  v_generic_source_only_count integer:=0;
  v_test_obligations_empty_count integer:=0;
  v_incomplete_without_semantic_resolver_count integer:=0;
  v_trace_contract_absent_count integer:=0;
  v_current_story_blocked_count integer:=0;
  v_meta_gap_family_count integer:=0;
  v_payload jsonb;
begin
  if not exists(select 1 from lf_ops.pantallas p where p.id=p_pantalla_id) then
    raise exception 'SHADOW_SCREEN_NOT_FOUND:%',p_pantalla_id;
  end if;

  select c.especificacion
    into v_contract
  from programacion.contratos c
  where c.version_id=p_version_id
    and c.contrato_codigo='INPUT_READINESS_CONTRACT';

  if v_contract is null then
    raise exception 'SHADOW_INPUT_READINESS_CONTRACT_NOT_FOUND:%',p_version_id;
  end if;

  -- Fail early if the screen cannot participate in the canonical graph.
  perform programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id);

  for v_family in
    select f.value
    from lf_ops.reglas r
    cross join lateral jsonb_array_elements_text(coalesce(r.valor_config->'families','[]'::jsonb)) f(value)
    where r.codigo='B2B-RULE-STORY-READINESS-001'
    order by f.value
  loop
    v_family_count:=v_family_count+1;
    v_current:=programacion.fn_input_governance_bootstrap_classify_v2(p_pantalla_id,v_family,p_version_id);
    v_sem:=programacion.fn_input_governance_semantic_probe_v3(p_pantalla_id,v_family,p_version_id);
    v_sem_handled:=coalesce((v_sem->>'handled')::boolean,false);

    v_stage_cfg:=coalesce(v_contract->'family_stage_requirements'->v_family,'{}'::jsonb);
    v_explicit_stage:=nullif(v_stage_cfg->>'coverage_required_by','');
    if v_explicit_stage is null then
      v_stage_source:='IMPLICIT_DEFAULT_STORY';
      v_stage_unspecified_count:=v_stage_unspecified_count+1;
    else
      v_stage_source:='EXPLICIT_CONTRACT';
    end if;

    select coalesce(jsonb_agg(q.kind order by q.kind),'[]'::jsonb)
      into v_source_kinds
    from (
      select distinct sr.value->>'kind' as kind
      from jsonb_array_elements(coalesce(v_current->'source_refs','[]'::jsonb)) sr(value)
      where nullif(sr.value->>'kind','') is not null
    ) q;

    v_source_ref_count:=jsonb_array_length(coalesce(v_current->'source_refs','[]'::jsonb));
    select count(*)
      into v_specific_ref_count
    from jsonb_array_elements(coalesce(v_current->'source_refs','[]'::jsonb)) sr(value)
    where sr.value->>'kind'<>'SCREEN_CANONICAL_GRAPH';

    v_test_count:=jsonb_array_length(coalesce(v_current->'test_obligations','[]'::jsonb));
    v_resolution_contract:=coalesce(
      nullif(v_sem->'probe'->>'resolution_contract',''),
      nullif(v_current->'probe'->>'resolution_contract','')
    );

    v_findings:='[]'::jsonb;

    if v_stage_source='IMPLICIT_DEFAULT_STORY' then
      v_findings:=v_findings||jsonb_build_array(jsonb_build_object(
        'code','SHADOW_STAGE_AUTHORITY_UNSPECIFIED',
        'observed_effective_stage',v_current->>'required_by_stage'
      ));
    end if;

    if v_current->>'coverage_status' in ('MISSING','PARTIAL') and not v_sem_handled then
      v_incomplete_without_semantic_resolver_count:=v_incomplete_without_semantic_resolver_count+1;
      v_findings:=v_findings||jsonb_build_array(jsonb_build_object(
        'code','SHADOW_CURRENT_INCOMPLETE_WITHOUT_SEMANTIC_RESOLVER'
      ));
    end if;

    if v_source_ref_count>0 and v_specific_ref_count=0 then
      v_generic_source_only_count:=v_generic_source_only_count+1;
      v_findings:=v_findings||jsonb_build_array(jsonb_build_object(
        'code','SHADOW_SOURCE_PROVENANCE_GENERIC_ONLY',
        'source_kinds',v_source_kinds
      ));
    end if;

    if v_test_count=0 then
      v_test_obligations_empty_count:=v_test_obligations_empty_count+1;
      v_findings:=v_findings||jsonb_build_array(jsonb_build_object(
        'code','SHADOW_TEST_OBLIGATIONS_EMPTY'
      ));
    end if;

    if v_current->>'coverage_status' in ('MISSING','PARTIAL') and v_resolution_contract is null then
      v_trace_contract_absent_count:=v_trace_contract_absent_count+1;
      v_findings:=v_findings||jsonb_build_array(jsonb_build_object(
        'code','SHADOW_RESOLUTION_TRACE_CONTRACT_ABSENT'
      ));
    end if;

    if v_current->>'story_ready_status'='BLOCKED' then
      v_current_story_blocked_count:=v_current_story_blocked_count+1;
    end if;

    if jsonb_array_length(v_findings)>0 then
      v_meta_gap_family_count:=v_meta_gap_family_count+1;
    end if;

    v_rows:=v_rows||jsonb_build_array(jsonb_build_object(
      'family_code',v_family,
      'shadow_decisional',false,
      'stage',jsonb_build_object(
        'source',v_stage_source,
        'explicit_coverage_required_by',v_explicit_stage,
        'current_effective_required_by_stage',v_current->>'required_by_stage'
      ),
      'resolver',jsonb_build_object(
        'semantic_handled',v_sem_handled,
        'resolution_contract',v_resolution_contract
      ),
      'provenance',jsonb_build_object(
        'source_ref_count',v_source_ref_count,
        'specific_source_ref_count',v_specific_ref_count,
        'source_kinds',v_source_kinds
      ),
      'tests',jsonb_build_object(
        'test_obligation_count',v_test_count
      ),
      'current_result',jsonb_build_object(
        'applicability',v_current->>'applicability',
        'coverage_status',v_current->>'coverage_status',
        'well_defined_status',v_current->>'well_defined_status',
        'story_ready_status',v_current->>'story_ready_status',
        'implementation_ready_status',v_current->>'implementation_ready_status',
        'qa_ready_status',v_current->>'qa_ready_status',
        'production_ready_status',v_current->>'production_ready_status',
        'severity',v_current->>'severity',
        'blockers',coalesce(v_current->'blockers','[]'::jsonb)
      ),
      'meta_findings',v_findings,
      'meta_status',case when jsonb_array_length(v_findings)=0 then 'META_CONTRACT_OK' else 'META_GAPS_PRESENT' end
    ));
  end loop;

  v_payload:=jsonb_build_object(
    'shadow_contract','INPUT_GOVERNANCE_SHADOW_EVALUATOR_V1',
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
      'stage_authority_unspecified_count',v_stage_unspecified_count,
      'generic_source_only_count',v_generic_source_only_count,
      'test_obligations_empty_count',v_test_obligations_empty_count,
      'current_incomplete_without_semantic_resolver_count',v_incomplete_without_semantic_resolver_count,
      'resolution_trace_contract_absent_count',v_trace_contract_absent_count,
      'current_story_blocked_count',v_current_story_blocked_count,
      'meta_gap_family_count',v_meta_gap_family_count
    ),
    'families',v_rows,
    'trace_contract_target',jsonb_build_object(
      'required_steps',jsonb_build_array(
        'CANDIDATE_DISCOVERY',
        'EXPLICIT_REFERENCE_EXPANSION',
        'AUTHORITY_RESOLUTION',
        'CANDIDATE_REJECTION',
        'SUFFICIENCY_EVALUATION',
        'FINAL_CLASSIFICATION'
      ),
      'v1_observation','CURRENT_EVALUATOR_EXPOSES_ONLY_PARTIAL_SUMMARY_PROBES; TARGET_TRACE_IS_NOT_YET_DECISIONAL'
    )
  );

  return v_payload||jsonb_build_object('shadow_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;

comment on function programacion.fn_input_governance_shadow_universe_preflight_v1(bigint)
is 'Non-decisional architecture preflight. Read-only; never authorizes readiness, promotion, or production.';

comment on function programacion.fn_input_governance_shadow_evaluate_v1(integer,bigint)
is 'Non-decisional shadow evaluator. Compares evaluator architecture metadata without mutating canonical readiness or gates.';

-- Reproducible invariants at introduction time. These validate the shadow contract,
-- not product readiness, and intentionally perform no DML.
do $do$
declare
  v_pre jsonb;
  v_rec jsonb;
begin
  v_pre:=programacion.fn_input_governance_shadow_universe_preflight_v1(19);
  if coalesce((v_pre->>'decisional')::boolean,true) then
    raise exception 'SHADOW_PREFLIGHT_MUST_BE_NON_DECISIONAL';
  end if;
  if (v_pre->>'family_count')::integer<>47 then
    raise exception 'SHADOW_FAMILY_UNIVERSE_MISMATCH:%',v_pre->>'family_count';
  end if;
  if (v_pre->>'explicit_stage_count')::integer<>8 then
    raise exception 'SHADOW_EXPLICIT_STAGE_BASELINE_MISMATCH:%',v_pre->>'explicit_stage_count';
  end if;
  if (v_pre->>'implicit_default_stage_count')::integer<>39 then
    raise exception 'SHADOW_IMPLICIT_STAGE_BASELINE_MISMATCH:%',v_pre->>'implicit_default_stage_count';
  end if;

  v_rec:=programacion.fn_input_governance_shadow_evaluate_v1(58,19);
  if coalesce((v_rec->>'decisional')::boolean,true) then
    raise exception 'SHADOW_EVALUATOR_MUST_BE_NON_DECISIONAL';
  end if;
  if coalesce((v_rec->>'promotion_authorized')::boolean,true)
     or coalesce((v_rec->>'production_authorized')::boolean,true) then
    raise exception 'SHADOW_EVALUATOR_CANNOT_AUTHORIZE_PROMOTION_OR_PRODUCTION';
  end if;
  if (v_rec->'summary'->>'family_count')::integer<>47 then
    raise exception 'SHADOW_REC001_FAMILY_COUNT_MISMATCH';
  end if;
  if (v_rec->'summary'->>'stage_authority_unspecified_count')::integer<>39 then
    raise exception 'SHADOW_REC001_STAGE_BASELINE_MISMATCH';
  end if;
  if (v_rec->'summary'->>'test_obligations_empty_count')::integer<>47 then
    raise exception 'SHADOW_REC001_TEST_OBLIGATION_BASELINE_MISMATCH';
  end if;
end;
$do$;
