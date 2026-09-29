-- Input Governance ANALYTICS semantic resolver v1.
-- Structural completeness is separated from provider/runtime readiness.

begin;

do $patch$
declare
  r record;
  v_def text;
begin
  for r in
    select *
    from (
      values
        (
          'programacion.fn_input_governance_semantic_probe_v3(integer,text,bigint)',
          $$  if p_family_code='FORCED_COLORS_CONTRAST' then$$,
          $$  if p_family_code='ANALYTICS' then
    with direct_rules as (
      select x.value as rule
      from jsonb_array_elements(
        coalesce(
          programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id)
            ->'canonical_contract'->'rules',
          '[]'::jsonb
        )
      ) x(value)
      where coalesce(x.value->>'status','')<>'DEPRECADO'
        and (
          upper(coalesce(x.value->>'category',''))='ANALYTICS'
          or jsonb_typeof(x.value->'config'->'providers')='array'
        )
    ), provider_refs as (
      select distinct p.value as provider_code
      from direct_rules d
      cross join lateral jsonb_array_elements_text(
        coalesce(d.rule->'config'->'providers','[]'::jsonb)
      ) p(value)
    ), provider_state as (
      select
        pr.provider_code,
        op.provider_id,
        op.status,
        op.enabled,
        op.integration_status
      from provider_refs pr
      left join lf_ops.observabilidad_proveedores op
        on op.provider_code=pr.provider_code
    ), rel as (
      select *
      from lf_ops.v_b2b_rel_screen_analytics
      where source_code=v_screen_code
    ), event_state as (
      select
        rel.target_code,
        c.event_code,
        c.status,
        c.allowed_parameters
      from rel
      left join lf_ops.v_b2b_analytics_contract c
        on c.event_code=rel.target_code
    )
    select
      (select count(*) from direct_rules),
      (select count(*) from direct_rules where coalesce(rule->>'status','')='CANDIDATO'),
      (select count(*) from rel),
      (select count(*) from event_state where event_code is null
          or jsonb_typeof(allowed_parameters)<>'array'
          or jsonb_array_length(allowed_parameters)=0),
      (select count(*) from provider_state where provider_id is null),
      (
        (select count(*) from provider_state where provider_id is not null)
        +
        (select count(*) from event_state where event_code is not null)
      ),
      exists(
        select 1
        from provider_state
        where provider_id is null
           or status not in ('VIGENTE','ACTIVO')
           or not enabled
           or integration_status not in (
             'ACTIVE','READY','CONFIGURED','IMPLEMENTED','READY_FOR_QA','QA_VERIFIED'
           )
      )
    into
      v_rule_count,
      v_candidate_count,
      v_story_source_count,
      v_broken_ref_count,
      v_missing_source_count,
      v_unresolved_count_b2b,
      v_implementation_pending;

    if v_rule_count>0
       and v_story_source_count>0
       and v_broken_ref_count=0
       and v_missing_source_count=0
       and v_unresolved_count_b2b>=2 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case
          when v_candidate_count>0 or v_implementation_pending then 'P1'
          else 'P4'
        end,
        'blocker_code',case
          when v_candidate_count>0 or v_implementation_pending
            then 'ANALYTICS_RUNTIME_PROVIDER_NOT_READY'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case
            when v_candidate_count>0 or v_implementation_pending then 'NOT_READY'
            else 'READY'
          end,
          'qa',case
            when v_candidate_count>0 or v_implementation_pending then 'BLOCKED'
            else 'READY'
          end,
          'production',case
            when v_candidate_count>0 or v_implementation_pending then 'BLOCKED'
            else 'READY'
          end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_implementation_pending then
            jsonb_build_array(jsonb_build_object(
              'code','ANALYTICS_RUNTIME_PROVIDER_NOT_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','ANALYTICS_SEMANTIC_RESOLUTION_V1',
          'analytics_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'screen_event_relation_count',v_story_source_count,
          'broken_or_incomplete_event_count',v_broken_ref_count,
          'missing_provider_reference_count',v_missing_source_count,
          'resolved_provider_plus_event_count',v_unresolved_count_b2b,
          'runtime_provider_pending',v_implementation_pending
        )
      );
    end if;

    if v_rule_count>0 or v_story_source_count>0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','PARTIAL',
        'severity','P1',
        'blocker_code','ANALYTICS_CANONICAL_SOURCE_INCOMPLETE',
        'stage_statuses',jsonb_build_object(
          'story','READY','implementation','NOT_READY','qa','BLOCKED','production','BLOCKED'
        ),
        'stage_blockers',jsonb_build_array(jsonb_build_object(
          'code','ANALYTICS_CANONICAL_SOURCE_INCOMPLETE',
          'earliest_blocking_stage','IMPLEMENTATION'
        )),
        'probe',jsonb_build_object(
          'resolution_contract','ANALYTICS_SEMANTIC_RESOLUTION_V1',
          'analytics_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'screen_event_relation_count',v_story_source_count,
          'broken_or_incomplete_event_count',v_broken_ref_count,
          'missing_provider_reference_count',v_missing_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='FORCED_COLORS_CONTRAST' then$$
        ),
        (
          'programacion.fn_input_governance_semantic_probe_v3_cached_v1(integer,text,bigint,jsonb)',
          $$  if p_family_code='FORCED_COLORS_CONTRAST' then$$,
          $$  if p_family_code='ANALYTICS' then
    with direct_rules as (
      select x.value as rule
      from jsonb_array_elements(
        coalesce(p_graph->'canonical_contract'->'rules','[]'::jsonb)
      ) x(value)
      where coalesce(x.value->>'status','')<>'DEPRECADO'
        and (
          upper(coalesce(x.value->>'category',''))='ANALYTICS'
          or jsonb_typeof(x.value->'config'->'providers')='array'
        )
    ), provider_refs as (
      select distinct p.value as provider_code
      from direct_rules d
      cross join lateral jsonb_array_elements_text(
        coalesce(d.rule->'config'->'providers','[]'::jsonb)
      ) p(value)
    ), provider_state as (
      select
        pr.provider_code,
        op.provider_id,
        op.status,
        op.enabled,
        op.integration_status
      from provider_refs pr
      left join lf_ops.observabilidad_proveedores op
        on op.provider_code=pr.provider_code
    ), rel as (
      select *
      from lf_ops.v_b2b_rel_screen_analytics
      where source_code=v_screen_code
    ), event_state as (
      select
        rel.target_code,
        c.event_code,
        c.status,
        c.allowed_parameters
      from rel
      left join lf_ops.v_b2b_analytics_contract c
        on c.event_code=rel.target_code
    )
    select
      (select count(*) from direct_rules),
      (select count(*) from direct_rules where coalesce(rule->>'status','')='CANDIDATO'),
      (select count(*) from rel),
      (select count(*) from event_state where event_code is null
          or jsonb_typeof(allowed_parameters)<>'array'
          or jsonb_array_length(allowed_parameters)=0),
      (select count(*) from provider_state where provider_id is null),
      (
        (select count(*) from provider_state where provider_id is not null)
        +
        (select count(*) from event_state where event_code is not null)
      ),
      exists(
        select 1
        from provider_state
        where provider_id is null
           or status not in ('VIGENTE','ACTIVO')
           or not enabled
           or integration_status not in (
             'ACTIVE','READY','CONFIGURED','IMPLEMENTED','READY_FOR_QA','QA_VERIFIED'
           )
      )
    into
      v_rule_count,
      v_candidate_count,
      v_story_source_count,
      v_broken_ref_count,
      v_missing_source_count,
      v_unresolved_count_b2b,
      v_implementation_pending;

    if v_rule_count>0
       and v_story_source_count>0
       and v_broken_ref_count=0
       and v_missing_source_count=0
       and v_unresolved_count_b2b>=2 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case
          when v_candidate_count>0 or v_implementation_pending then 'P1'
          else 'P4'
        end,
        'blocker_code',case
          when v_candidate_count>0 or v_implementation_pending
            then 'ANALYTICS_RUNTIME_PROVIDER_NOT_READY'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case
            when v_candidate_count>0 or v_implementation_pending then 'NOT_READY'
            else 'READY'
          end,
          'qa',case
            when v_candidate_count>0 or v_implementation_pending then 'BLOCKED'
            else 'READY'
          end,
          'production',case
            when v_candidate_count>0 or v_implementation_pending then 'BLOCKED'
            else 'READY'
          end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_implementation_pending then
            jsonb_build_array(jsonb_build_object(
              'code','ANALYTICS_RUNTIME_PROVIDER_NOT_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','ANALYTICS_SEMANTIC_RESOLUTION_V1',
          'analytics_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'screen_event_relation_count',v_story_source_count,
          'broken_or_incomplete_event_count',v_broken_ref_count,
          'missing_provider_reference_count',v_missing_source_count,
          'resolved_provider_plus_event_count',v_unresolved_count_b2b,
          'runtime_provider_pending',v_implementation_pending
        )
      );
    end if;

    if v_rule_count>0 or v_story_source_count>0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','PARTIAL',
        'severity','P1',
        'blocker_code','ANALYTICS_CANONICAL_SOURCE_INCOMPLETE',
        'stage_statuses',jsonb_build_object(
          'story','READY','implementation','NOT_READY','qa','BLOCKED','production','BLOCKED'
        ),
        'stage_blockers',jsonb_build_array(jsonb_build_object(
          'code','ANALYTICS_CANONICAL_SOURCE_INCOMPLETE',
          'earliest_blocking_stage','IMPLEMENTATION'
        )),
        'probe',jsonb_build_object(
          'resolution_contract','ANALYTICS_SEMANTIC_RESOLUTION_V1',
          'analytics_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'screen_event_relation_count',v_story_source_count,
          'broken_or_incomplete_event_count',v_broken_ref_count,
          'missing_provider_reference_count',v_missing_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='FORCED_COLORS_CONTRAST' then$$
        )
    ) x(sig,anchor_text,insert_text)
  loop
    select pg_get_functiondef(to_regprocedure(r.sig)) into v_def;
    if v_def is null then
      raise exception 'ANALYTICS_SEMANTIC_FUNCTION_MISSING:%',r.sig;
    end if;

    if position('ANALYTICS_SEMANTIC_RESOLUTION_V1' in v_def)=0 then
      if position(r.anchor_text in v_def)=0 then
        raise exception 'ANALYTICS_SEMANTIC_SOURCE_DRIFT:%',r.sig;
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
  v_probe:=programacion.fn_input_governance_semantic_probe_v3(51,'ANALYTICS',19);
  if v_probe->>'level'<>'COMPLETE'
     or v_probe->>'blocker_code'<>'ANALYTICS_RUNTIME_PROVIDER_NOT_READY'
     or v_probe#>>'{probe,resolution_contract}'<>'ANALYTICS_SEMANTIC_RESOLUTION_V1'
     or coalesce((v_probe#>>'{probe,screen_event_relation_count}')::integer,0)<>5
     or coalesce((v_probe#>>'{probe,missing_provider_reference_count}')::integer,0)<>0 then
    raise exception 'ANALYTICS_B2B_POSTCONDITION_FAILED:%',v_probe;
  end if;

  v_classifier:=programacion.fn_input_governance_bootstrap_classify_v2(51,'ANALYTICS',19);
  if v_classifier->>'coverage_status'<>'COMPLETE'
     or v_classifier->>'well_defined_status'<>'COMPLETE'
     or v_classifier->>'story_ready_status'<>'READY'
     or v_classifier->>'implementation_ready_status'<>'NOT_READY' then
    raise exception 'ANALYTICS_CLASSIFIER_POSTCONDITION_FAILED:%',v_classifier;
  end if;

  -- Negative synthetic graph with no analytics rule and no real screen relation.
  v_graph:=programacion.fn_input_screen_canonical_graph(51,19);
  v_graph:=jsonb_set(v_graph,'{screen_code}',to_jsonb('TEST-NO-ANALYTICS'::text),true);
  v_graph:=jsonb_set(v_graph,'{canonical_contract,rules}','[]'::jsonb,true);
  v_graph:=jsonb_set(v_graph,'{canonical_contract,analytics}','[]'::jsonb,true);

  v_negative:=programacion.fn_input_governance_semantic_probe_v3_cached_v1(
    51,'ANALYTICS',19,v_graph
  );
  if v_negative->>'level'='COMPLETE'
     or v_negative#>>'{probe,resolution_contract}'='ANALYTICS_SEMANTIC_RESOLUTION_V1' then
    raise exception 'ANALYTICS_NEGATIVE_FAIL_CLOSED_FAILED:%',v_negative;
  end if;
end;
$postconditions$;

commit;
