-- Input Governance RATE_LIMIT semantic resolver v1
-- Replaces category/regex sufficiency with explicit rate_limit_policy_id resolution.
-- Candidate lifecycle remains implementation-blocking; this does not promote any policy.

begin;

do $patch$
declare
  r record;
  v_def text;
  v_anchor text;
  v_insert text;
begin
  for r in
    select *
    from (
      values
        (
          'programacion.fn_input_governance_semantic_probe_v3(integer,text,bigint)',
          $$v_screen_code:=nullif(programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id)->>'screen_code','');$$,
          $$v_screen_code:=nullif(programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id)->>'screen_code','');

  if p_family_code='RATE_LIMIT' then
    with semantic_rules as (
      select
        x.value as rule,
        (x.value->'config'->>'rate_limit_policy_id')::bigint as policy_id
      from jsonb_array_elements(
        coalesce(
          programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id)
            ->'canonical_contract'->'rules',
          '[]'::jsonb
        )
      ) x(value)
      where coalesce(x.value->>'status','')<>'DEPRECADO'
        and coalesce(x.value->'config'->>'rate_limit_policy_id','') ~ '^[0-9]+$'
    ), resolved as (
      select
        s.rule,
        s.policy_id,
        ps.policy_code,
        ps.status as policy_status
      from semantic_rules s
      left join lf_ops.politicas_rate_limit ps
        on ps.rate_limit_policy_id=s.policy_id
    )
    select
      count(*),
      count(*) filter(where coalesce(rule->>'status','')='CANDIDATO'),
      count(*) filter(where policy_code is null),
      count(*) filter(where policy_status='CANDIDATO'),
      count(*) filter(
        where coalesce(rule->>'status','') in ('VIGENTE','ACTIVO')
          and policy_status='VIGENTE'
      )
    into
      v_rule_count,
      v_candidate_count,
      v_missing_source_count,
      v_unresolved_count_b2b,
      v_story_source_count
    from resolved;

    if v_rule_count>0 then
      if v_missing_source_count>0 then
        return jsonb_build_object(
          'handled',true,
          'family_code',p_family_code,
          'level','PARTIAL',
          'severity','P1',
          'blocker_code','RATE_LIMIT_POLICY_REFERENCE_UNRESOLVED',
          'stage_statuses',jsonb_build_object(
            'story','READY',
            'implementation','NOT_READY',
            'qa','BLOCKED',
            'production','BLOCKED'
          ),
          'stage_blockers',jsonb_build_array(jsonb_build_object(
            'code','RATE_LIMIT_POLICY_REFERENCE_UNRESOLVED',
            'earliest_blocking_stage','IMPLEMENTATION'
          )),
          'probe',jsonb_build_object(
            'resolution_contract','RATE_LIMIT_POLICY_RESOLUTION_V1',
            'direct_policy_reference_count',v_rule_count,
            'missing_policy_reference_count',v_missing_source_count,
            'candidate_rule_count',v_candidate_count,
            'candidate_policy_count',v_unresolved_count_b2b,
            'vigente_rule_policy_pair_count',v_story_source_count
          )
        );
      end if;

      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 then 'P1'
          else 'P4'
        end,
        'blocker_code',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0
            then 'RATE_LIMIT_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 then 'NOT_READY'
            else 'READY'
          end,
          'qa',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 then 'BLOCKED'
            else 'READY'
          end,
          'production',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 then 'BLOCKED'
            else 'READY'
          end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 then
            jsonb_build_array(jsonb_build_object(
              'code','RATE_LIMIT_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','RATE_LIMIT_POLICY_RESOLUTION_V1',
          'direct_policy_reference_count',v_rule_count,
          'resolved_policy_reference_count',v_rule_count-v_missing_source_count,
          'missing_policy_reference_count',v_missing_source_count,
          'candidate_rule_count',v_candidate_count,
          'candidate_policy_count',v_unresolved_count_b2b,
          'vigente_rule_policy_pair_count',v_story_source_count
        )
      );
    end if;

    return v_base;
  end if;$$
        ),
        (
          'programacion.fn_input_governance_semantic_probe_v3_cached_v1(integer,text,bigint,jsonb)',
          $$v_screen_code:=nullif(p_graph->>'screen_code','');$$,
          $$v_screen_code:=nullif(p_graph->>'screen_code','');

  if p_family_code='RATE_LIMIT' then
    with semantic_rules as (
      select
        x.value as rule,
        (x.value->'config'->>'rate_limit_policy_id')::bigint as policy_id
      from jsonb_array_elements(
        coalesce(p_graph->'canonical_contract'->'rules','[]'::jsonb)
      ) x(value)
      where coalesce(x.value->>'status','')<>'DEPRECADO'
        and coalesce(x.value->'config'->>'rate_limit_policy_id','') ~ '^[0-9]+$'
    ), resolved as (
      select
        s.rule,
        s.policy_id,
        ps.policy_code,
        ps.status as policy_status
      from semantic_rules s
      left join lf_ops.politicas_rate_limit ps
        on ps.rate_limit_policy_id=s.policy_id
    )
    select
      count(*),
      count(*) filter(where coalesce(rule->>'status','')='CANDIDATO'),
      count(*) filter(where policy_code is null),
      count(*) filter(where policy_status='CANDIDATO'),
      count(*) filter(
        where coalesce(rule->>'status','') in ('VIGENTE','ACTIVO')
          and policy_status='VIGENTE'
      )
    into
      v_rule_count,
      v_candidate_count,
      v_missing_source_count,
      v_unresolved_count_b2b,
      v_story_source_count
    from resolved;

    if v_rule_count>0 then
      if v_missing_source_count>0 then
        return jsonb_build_object(
          'handled',true,
          'family_code',p_family_code,
          'level','PARTIAL',
          'severity','P1',
          'blocker_code','RATE_LIMIT_POLICY_REFERENCE_UNRESOLVED',
          'stage_statuses',jsonb_build_object(
            'story','READY',
            'implementation','NOT_READY',
            'qa','BLOCKED',
            'production','BLOCKED'
          ),
          'stage_blockers',jsonb_build_array(jsonb_build_object(
            'code','RATE_LIMIT_POLICY_REFERENCE_UNRESOLVED',
            'earliest_blocking_stage','IMPLEMENTATION'
          )),
          'probe',jsonb_build_object(
            'resolution_contract','RATE_LIMIT_POLICY_RESOLUTION_V1',
            'direct_policy_reference_count',v_rule_count,
            'missing_policy_reference_count',v_missing_source_count,
            'candidate_rule_count',v_candidate_count,
            'candidate_policy_count',v_unresolved_count_b2b,
            'vigente_rule_policy_pair_count',v_story_source_count
          )
        );
      end if;

      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 then 'P1'
          else 'P4'
        end,
        'blocker_code',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0
            then 'RATE_LIMIT_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 then 'NOT_READY'
            else 'READY'
          end,
          'qa',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 then 'BLOCKED'
            else 'READY'
          end,
          'production',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 then 'BLOCKED'
            else 'READY'
          end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 then
            jsonb_build_array(jsonb_build_object(
              'code','RATE_LIMIT_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','RATE_LIMIT_POLICY_RESOLUTION_V1',
          'direct_policy_reference_count',v_rule_count,
          'resolved_policy_reference_count',v_rule_count-v_missing_source_count,
          'missing_policy_reference_count',v_missing_source_count,
          'candidate_rule_count',v_candidate_count,
          'candidate_policy_count',v_unresolved_count_b2b,
          'vigente_rule_policy_pair_count',v_story_source_count
        )
      );
    end if;

    return v_base;
  end if;$$
        )
    ) x(sig,anchor_text,insert_text)
  loop
    select pg_get_functiondef(to_regprocedure(r.sig)) into v_def;
    if v_def is null then
      raise exception 'RATE_LIMIT_SEMANTIC_FUNCTION_MISSING:%',r.sig;
    end if;

    if position('RATE_LIMIT_POLICY_RESOLUTION_V1' in v_def)=0 then
      if position(r.anchor_text in v_def)=0 then
        raise exception 'RATE_LIMIT_SEMANTIC_SOURCE_DRIFT:%',r.sig;
      end if;
      v_def:=replace(v_def,r.anchor_text,r.insert_text);
      execute v_def;
    end if;
  end loop;
end;
$patch$;

do $postconditions$
declare
  v_probe jsonb;
  v_classifier jsonb;
  v_graph jsonb;
  v_negative jsonb;
begin
  -- Real B2B case: canonical reference exists, but rule/policy remain candidate.
  v_probe:=programacion.fn_input_governance_semantic_probe_v3(51,'RATE_LIMIT',19);
  if v_probe->>'level'<>'COMPLETE'
     or v_probe->>'blocker_code'<>'RATE_LIMIT_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY'
     or v_probe#>>'{probe,resolution_contract}'<>'RATE_LIMIT_POLICY_RESOLUTION_V1'
     or coalesce((v_probe#>>'{probe,direct_policy_reference_count}')::integer,0)<1
     or coalesce((v_probe#>>'{probe,candidate_policy_count}')::integer,0)<1 then
    raise exception 'RATE_LIMIT_B2B_CANDIDATE_POSTCONDITION_FAILED:%',v_probe;
  end if;

  v_classifier:=programacion.fn_input_governance_bootstrap_classify_v2(51,'RATE_LIMIT',19);
  if v_classifier->>'coverage_status'<>'COMPLETE'
     or v_classifier->>'well_defined_status'<>'COMPLETE'
     or v_classifier->>'story_ready_status'<>'READY'
     or v_classifier->>'implementation_ready_status'<>'NOT_READY' then
    raise exception 'RATE_LIMIT_B2B_CLASSIFIER_POSTCONDITION_FAILED:%',v_classifier;
  end if;

  -- Synthetic positive case using an existing VIGENTE policy, without persisting data.
  v_graph:=programacion.fn_input_screen_canonical_graph(51,19);
  v_graph:=jsonb_set(
    v_graph,
    '{canonical_contract,rules}',
    jsonb_build_array(
      jsonb_build_object(
        'rule_code','TEST-RATE-LIMIT-VIGENTE',
        'status','VIGENTE',
        'category','SECURITY',
        'pending_decision',false,
        'config',jsonb_build_object('rate_limit_policy_id',9)
      )
    ),
    true
  );
  v_probe:=programacion.fn_input_governance_semantic_probe_v3_cached_v1(
    51,'RATE_LIMIT',19,v_graph
  );
  if v_probe->>'level'<>'COMPLETE'
     or v_probe->>'blocker_code' is not null
     or v_probe#>>'{stage_statuses,implementation}'<>'READY'
     or coalesce((v_probe#>>'{probe,vigente_rule_policy_pair_count}')::integer,0)<>1 then
    raise exception 'RATE_LIMIT_VIGENTE_POSITIVE_POSTCONDITION_FAILED:%',v_probe;
  end if;

  -- Negative case: no explicit policy reference must not become semantically COMPLETE.
  v_graph:=jsonb_set(
    v_graph,
    '{canonical_contract,rules}',
    jsonb_build_array(
      jsonb_build_object(
        'rule_code','TEST-NO-RATE-LIMIT-REFERENCE',
        'status','VIGENTE',
        'category','SECURITY',
        'pending_decision',false,
        'config',jsonb_build_object('unrelated','value')
      )
    ),
    true
  );
  v_negative:=programacion.fn_input_governance_semantic_probe_v3_cached_v1(
    51,'RATE_LIMIT',19,v_graph
  );
  if v_negative#>>'{probe,resolution_contract}'='RATE_LIMIT_POLICY_RESOLUTION_V1'
     or v_negative->>'level'='COMPLETE' then
    raise exception 'RATE_LIMIT_NEGATIVE_FAIL_CLOSED_POSTCONDITION_FAILED:%',v_negative;
  end if;
end;
$postconditions$;

commit;
