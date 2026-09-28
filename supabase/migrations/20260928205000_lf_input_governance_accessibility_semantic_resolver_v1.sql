-- Input Governance: semantic resolver for B2B ACCESSIBILITY core.
-- The validator already defines the four A11Y rules as the semantic core.
-- This migration makes the semantic probe/classifier use the same authority.
-- Candidate source state keeps implementation blocked; no production promotion is implied.

begin;

do $patch_uncached$
declare
  v_def text;
  v_anchor text;
  v_insert text;
begin
  select pg_get_functiondef(
    'programacion.fn_input_governance_semantic_probe_v3(integer,text,bigint)'::regprocedure
  ) into v_def;

  if position('B2B_ACCESSIBILITY_CORE_RESOLUTION_V1' in v_def)>0 then
    return;
  end if;

  v_anchor :=
$anchor$  v_screen_code:=nullif(programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id)->>'screen_code','');

$anchor$;

  v_insert :=
$insert$  v_screen_code:=nullif(programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id)->>'screen_code','');

  if p_family_code='ACCESSIBILITY' and v_screen_code like 'B2B-%' then
    select
      count(distinct r.value->>'rule_code'),
      count(*) filter(where coalesce(r.value->>'status','')='CANDIDATO')
    into v_rule_count,v_candidate_count
    from jsonb_array_elements(
      coalesce(
        programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id)
          ->'canonical_contract'->'rules',
        '[]'::jsonb
      )
    ) r(value)
    where r.value->>'rule_code' in (
      'B2B-RULE-A11Y-001',
      'B2B-RULE-A11Y-002',
      'B2B-RULE-A11Y-003',
      'B2B-RULE-A11Y-004'
    );

    if v_rule_count=4 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case when v_candidate_count>0 then 'P1' else 'P4' end,
        'blocker_code',case when v_candidate_count>0 then 'ACCESSIBILITY_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY' else null end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case when v_candidate_count>0 then 'NOT_READY' else 'READY' end,
          'qa',case when v_candidate_count>0 then 'BLOCKED' else 'READY' end,
          'production',case when v_candidate_count>0 then 'BLOCKED' else 'READY' end
        ),
        'stage_blockers',case
          when v_candidate_count>0 then jsonb_build_array(jsonb_build_object(
            'code','ACCESSIBILITY_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY',
            'earliest_blocking_stage','IMPLEMENTATION'
          ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','B2B_ACCESSIBILITY_CORE_RESOLUTION_V1',
          'core_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'required_rule_codes',jsonb_build_array(
            'B2B-RULE-A11Y-001',
            'B2B-RULE-A11Y-002',
            'B2B-RULE-A11Y-003',
            'B2B-RULE-A11Y-004'
          )
        )
      );
    end if;

    return v_base;
  end if;

$insert$;

  if position(v_anchor in v_def)=0 then
    raise exception 'ACCESSIBILITY_SEMANTIC_RESOLVER_UNCACHED_SOURCE_DRIFT';
  end if;

  v_def:=replace(v_def,v_anchor,v_insert);
  execute v_def;
end;
$patch_uncached$;

do $patch_cached$
declare
  v_def text;
  v_anchor text;
  v_insert text;
begin
  select pg_get_functiondef(
    'programacion.fn_input_governance_semantic_probe_v3_cached_v1(integer,text,bigint,jsonb)'::regprocedure
  ) into v_def;

  if position('B2B_ACCESSIBILITY_CORE_RESOLUTION_V1' in v_def)>0 then
    return;
  end if;

  v_anchor :=
$anchor$  v_screen_code:=nullif(p_graph->>'screen_code','');

$anchor$;

  v_insert :=
$insert$  v_screen_code:=nullif(p_graph->>'screen_code','');

  if p_family_code='ACCESSIBILITY' and v_screen_code like 'B2B-%' then
    select
      count(distinct r.value->>'rule_code'),
      count(*) filter(where coalesce(r.value->>'status','')='CANDIDATO')
    into v_rule_count,v_candidate_count
    from jsonb_array_elements(
      coalesce(p_graph->'canonical_contract'->'rules','[]'::jsonb)
    ) r(value)
    where r.value->>'rule_code' in (
      'B2B-RULE-A11Y-001',
      'B2B-RULE-A11Y-002',
      'B2B-RULE-A11Y-003',
      'B2B-RULE-A11Y-004'
    );

    if v_rule_count=4 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case when v_candidate_count>0 then 'P1' else 'P4' end,
        'blocker_code',case when v_candidate_count>0 then 'ACCESSIBILITY_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY' else null end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case when v_candidate_count>0 then 'NOT_READY' else 'READY' end,
          'qa',case when v_candidate_count>0 then 'BLOCKED' else 'READY' end,
          'production',case when v_candidate_count>0 then 'BLOCKED' else 'READY' end
        ),
        'stage_blockers',case
          when v_candidate_count>0 then jsonb_build_array(jsonb_build_object(
            'code','ACCESSIBILITY_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY',
            'earliest_blocking_stage','IMPLEMENTATION'
          ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','B2B_ACCESSIBILITY_CORE_RESOLUTION_V1',
          'core_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'required_rule_codes',jsonb_build_array(
            'B2B-RULE-A11Y-001',
            'B2B-RULE-A11Y-002',
            'B2B-RULE-A11Y-003',
            'B2B-RULE-A11Y-004'
          )
        )
      );
    end if;

    return v_base;
  end if;

$insert$;

  if position(v_anchor in v_def)=0 then
    raise exception 'ACCESSIBILITY_SEMANTIC_RESOLVER_CACHED_SOURCE_DRIFT';
  end if;

  v_def:=replace(v_def,v_anchor,v_insert);
  execute v_def;
end;
$patch_cached$;

do $verify$
declare
  v_probe jsonb;
  v_class jsonb;
  v_cached jsonb;
  v_graph jsonb;
begin
  v_probe:=programacion.fn_input_governance_semantic_probe_v3(51,'ACCESSIBILITY',19);
  if v_probe->>'level'<>'COMPLETE'
     or v_probe#>>'{probe,resolution_contract}'<>'B2B_ACCESSIBILITY_CORE_RESOLUTION_V1'
     or coalesce((v_probe#>>'{probe,core_rule_count}')::integer,0)<>4
     or v_probe#>>'{stage_statuses,implementation}'<>'NOT_READY' then
    raise exception 'ACCESSIBILITY_SEMANTIC_RESOLVER_POSTCONDITION_FAILED:%',v_probe;
  end if;

  v_class:=programacion.fn_input_governance_bootstrap_classify_v2(51,'ACCESSIBILITY',19);
  if v_class->>'coverage_status'<>'COMPLETE'
     or v_class->>'well_defined_status'<>'COMPLETE'
     or v_class->>'implementation_ready_status'<>'NOT_READY'
     or v_class#>>'{probe,resolution_contract}'<>'B2B_ACCESSIBILITY_CORE_RESOLUTION_V1' then
    raise exception 'ACCESSIBILITY_CLASSIFIER_POSTCONDITION_FAILED:%',v_class;
  end if;

  v_graph:=programacion.fn_input_screen_canonical_graph(51,19);
  v_cached:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v1(51,'ACCESSIBILITY',19,v_graph);
  if v_cached->>'coverage_status'<>'COMPLETE'
     or v_cached->>'well_defined_status'<>'COMPLETE'
     or v_cached->>'implementation_ready_status'<>'NOT_READY'
     or v_cached#>>'{probe,resolution_contract}'<>'B2B_ACCESSIBILITY_CORE_RESOLUTION_V1' then
    raise exception 'ACCESSIBILITY_CACHED_CLASSIFIER_POSTCONDITION_FAILED:%',v_cached;
  end if;
end;
$verify$;

commit;
