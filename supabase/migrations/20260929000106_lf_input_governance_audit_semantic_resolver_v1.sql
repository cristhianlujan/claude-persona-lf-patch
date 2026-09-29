-- Input Governance AUDIT semantic resolver v1
-- Resolves audit evidence structurally (sink, actions, immutability, correlation)
-- instead of relying on localized category labels.

begin;

do $patch$
declare
  r record;
  v_def text;
  v_anchor text := $$  if p_family_code='ACCESSIBILITY' and v_screen_code like 'B2B-%' then$$;
  v_insert text :=
$insert$
  if p_family_code='AUDIT' then
    with direct_rules as (
      select x.value as rule
      from jsonb_array_elements(
        coalesce(
          case
            when to_regprocedure('programacion.fn_input_governance_semantic_probe_v3_cached_v1(integer,text,bigint,jsonb)') is not null
                 and p_family_code='AUDIT'
              then coalesce(
                case
                  when current_query() ilike '%semantic_probe_v3_cached_v1%' then null
                  else null
                end,
                '[]'::jsonb
              )
            else '[]'::jsonb
          end,
          '[]'::jsonb
        )
      ) x(value)
    )
    select 0 into v_rule_count;

    -- The function-specific source graph is injected below by migration replacement.
  end if;
$insert$;
begin
  -- placeholder replaced separately per function below
  null;
end;
$patch$;

do $rewrite$
declare
  r record;
  v_def text;
  v_anchor text;
  v_block text;
begin
  for r in
    select *
    from (
      values
        (
          'programacion.fn_input_governance_semantic_probe_v3(integer,text,bigint)',
          $$  if p_family_code='ACCESSIBILITY' and v_screen_code like 'B2B-%' then$$,
          $$  if p_family_code='AUDIT' then
    with semantic_rules as (
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
          x.value->'config' ? 'audit_sink'
          or x.value->'config' ? 'required_audit_actions'
          or x.value->'config' ? 'append_only'
          or x.value->'config' ? 'mutation_blocked'
        )
    ), normalized as (
      select
        rule,
        nullif(coalesce(rule->'config'->>'audit_sink',rule->'config'->>'table'),'') as sink_name,
        case
          when jsonb_typeof(rule->'config'->'required_audit_actions')='array'
            then jsonb_array_length(rule->'config'->'required_audit_actions')
          else 0
        end as action_count,
        (
          coalesce((rule->'config'->>'append_only')::boolean,false)
          or coalesce((rule->'config'->>'mutation_blocked')::boolean,false)
          or coalesce(rule->'config'->>'update_delete','')='DENY'
        ) as immutable_contract,
        (
          coalesce((rule->'config'->>'correlation_id_required')::boolean,false)
          or coalesce((rule->'config'->>'correlation_required')::boolean,false)
        ) as correlation_contract
      from semantic_rules
    )
    select
      count(*),
      count(*) filter(where coalesce(rule->>'status','')='CANDIDATO'),
      count(*) filter(where sink_name is not null and to_regclass(sink_name) is not null),
      count(*) filter(where action_count>0),
      count(*) filter(where immutable_contract),
      count(*) filter(where correlation_contract)
    into
      v_rule_count,
      v_candidate_count,
      v_story_source_count,
      v_unresolved_count_b2b,
      v_broken_ref_count,
      v_missing_source_count
    from normalized;

    if v_rule_count>0 then
      if v_story_source_count>0
         and v_unresolved_count_b2b>0
         and v_broken_ref_count>0
         and v_missing_source_count>0 then
        return jsonb_build_object(
          'handled',true,
          'family_code',p_family_code,
          'level','COMPLETE',
          'severity',case when v_candidate_count>0 then 'P1' else 'P4' end,
          'blocker_code',case
            when v_candidate_count>0 then 'AUDIT_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY'
            else null
          end,
          'stage_statuses',jsonb_build_object(
            'story','READY',
            'implementation',case when v_candidate_count>0 then 'NOT_READY' else 'READY' end,
            'qa',case when v_candidate_count>0 then 'BLOCKED' else 'READY' end,
            'production',case when v_candidate_count>0 then 'BLOCKED' else 'READY' end
          ),
          'stage_blockers',case
            when v_candidate_count>0 then jsonb_build_array(jsonb_build_object(
              'code','AUDIT_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
            else '[]'::jsonb
          end,
          'probe',jsonb_build_object(
            'resolution_contract','AUDIT_SEMANTIC_RESOLUTION_V1',
            'semantic_rule_count',v_rule_count,
            'candidate_rule_count',v_candidate_count,
            'resolved_sink_rule_count',v_story_source_count,
            'required_action_contract_count',v_unresolved_count_b2b,
            'immutability_contract_count',v_broken_ref_count,
            'correlation_contract_count',v_missing_source_count
          )
        );
      end if;

      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','PARTIAL',
        'severity','P1',
        'blocker_code','AUDIT_CANONICAL_SOURCE_INCOMPLETE',
        'stage_statuses',jsonb_build_object(
          'story','READY','implementation','NOT_READY','qa','BLOCKED','production','BLOCKED'
        ),
        'stage_blockers',jsonb_build_array(jsonb_build_object(
          'code','AUDIT_CANONICAL_SOURCE_INCOMPLETE',
          'earliest_blocking_stage','IMPLEMENTATION'
        )),
        'probe',jsonb_build_object(
          'resolution_contract','AUDIT_SEMANTIC_RESOLUTION_V1',
          'semantic_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'resolved_sink_rule_count',v_story_source_count,
          'required_action_contract_count',v_unresolved_count_b2b,
          'immutability_contract_count',v_broken_ref_count,
          'correlation_contract_count',v_missing_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='ACCESSIBILITY' and v_screen_code like 'B2B-%' then$$
        ),
        (
          'programacion.fn_input_governance_semantic_probe_v3_cached_v1(integer,text,bigint,jsonb)',
          $$  if p_family_code='ACCESSIBILITY' and v_screen_code like 'B2B-%' then$$,
          $$  if p_family_code='AUDIT' then
    with semantic_rules as (
      select x.value as rule
      from jsonb_array_elements(
        coalesce(p_graph->'canonical_contract'->'rules','[]'::jsonb)
      ) x(value)
      where coalesce(x.value->>'status','')<>'DEPRECADO'
        and (
          x.value->'config' ? 'audit_sink'
          or x.value->'config' ? 'required_audit_actions'
          or x.value->'config' ? 'append_only'
          or x.value->'config' ? 'mutation_blocked'
        )
    ), normalized as (
      select
        rule,
        nullif(coalesce(rule->'config'->>'audit_sink',rule->'config'->>'table'),'') as sink_name,
        case
          when jsonb_typeof(rule->'config'->'required_audit_actions')='array'
            then jsonb_array_length(rule->'config'->'required_audit_actions')
          else 0
        end as action_count,
        (
          coalesce((rule->'config'->>'append_only')::boolean,false)
          or coalesce((rule->'config'->>'mutation_blocked')::boolean,false)
          or coalesce(rule->'config'->>'update_delete','')='DENY'
        ) as immutable_contract,
        (
          coalesce((rule->'config'->>'correlation_id_required')::boolean,false)
          or coalesce((rule->'config'->>'correlation_required')::boolean,false)
        ) as correlation_contract
      from semantic_rules
    )
    select
      count(*),
      count(*) filter(where coalesce(rule->>'status','')='CANDIDATO'),
      count(*) filter(where sink_name is not null and to_regclass(sink_name) is not null),
      count(*) filter(where action_count>0),
      count(*) filter(where immutable_contract),
      count(*) filter(where correlation_contract)
    into
      v_rule_count,
      v_candidate_count,
      v_story_source_count,
      v_unresolved_count_b2b,
      v_broken_ref_count,
      v_missing_source_count
    from normalized;

    if v_rule_count>0 then
      if v_story_source_count>0
         and v_unresolved_count_b2b>0
         and v_broken_ref_count>0
         and v_missing_source_count>0 then
        return jsonb_build_object(
          'handled',true,
          'family_code',p_family_code,
          'level','COMPLETE',
          'severity',case when v_candidate_count>0 then 'P1' else 'P4' end,
          'blocker_code',case
            when v_candidate_count>0 then 'AUDIT_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY'
            else null
          end,
          'stage_statuses',jsonb_build_object(
            'story','READY',
            'implementation',case when v_candidate_count>0 then 'NOT_READY' else 'READY' end,
            'qa',case when v_candidate_count>0 then 'BLOCKED' else 'READY' end,
            'production',case when v_candidate_count>0 then 'BLOCKED' else 'READY' end
          ),
          'stage_blockers',case
            when v_candidate_count>0 then jsonb_build_array(jsonb_build_object(
              'code','AUDIT_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
            else '[]'::jsonb
          end,
          'probe',jsonb_build_object(
            'resolution_contract','AUDIT_SEMANTIC_RESOLUTION_V1',
            'semantic_rule_count',v_rule_count,
            'candidate_rule_count',v_candidate_count,
            'resolved_sink_rule_count',v_story_source_count,
            'required_action_contract_count',v_unresolved_count_b2b,
            'immutability_contract_count',v_broken_ref_count,
            'correlation_contract_count',v_missing_source_count
          )
        );
      end if;

      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','PARTIAL',
        'severity','P1',
        'blocker_code','AUDIT_CANONICAL_SOURCE_INCOMPLETE',
        'stage_statuses',jsonb_build_object(
          'story','READY','implementation','NOT_READY','qa','BLOCKED','production','BLOCKED'
        ),
        'stage_blockers',jsonb_build_array(jsonb_build_object(
          'code','AUDIT_CANONICAL_SOURCE_INCOMPLETE',
          'earliest_blocking_stage','IMPLEMENTATION'
        )),
        'probe',jsonb_build_object(
          'resolution_contract','AUDIT_SEMANTIC_RESOLUTION_V1',
          'semantic_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'resolved_sink_rule_count',v_story_source_count,
          'required_action_contract_count',v_unresolved_count_b2b,
          'immutability_contract_count',v_broken_ref_count,
          'correlation_contract_count',v_missing_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='ACCESSIBILITY' and v_screen_code like 'B2B-%' then$$
        )
    ) x(sig,anchor_text,insert_text)
  loop
    select pg_get_functiondef(to_regprocedure(r.sig)) into v_def;
    if v_def is null then
      raise exception 'AUDIT_SEMANTIC_FUNCTION_MISSING:%',r.sig;
    end if;

    if position('AUDIT_SEMANTIC_RESOLUTION_V1' in v_def)=0 then
      if position(r.anchor_text in v_def)=0 then
        raise exception 'AUDIT_SEMANTIC_SOURCE_DRIFT:%',r.sig;
      end if;
      v_def:=replace(v_def,r.anchor_text,r.insert_text);
      execute v_def;
    end if;
  end loop;
end;
$rewrite$;

do $postconditions$
declare
  v_probe jsonb;
  v_classifier jsonb;
  v_graph jsonb;
  v_negative jsonb;
begin
  v_probe:=programacion.fn_input_governance_semantic_probe_v3(51,'AUDIT',19);
  if v_probe->>'level'<>'COMPLETE'
     or v_probe->>'blocker_code'<>'AUDIT_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY'
     or v_probe#>>'{probe,resolution_contract}'<>'AUDIT_SEMANTIC_RESOLUTION_V1'
     or coalesce((v_probe#>>'{probe,resolved_sink_rule_count}')::integer,0)<1
     or coalesce((v_probe#>>'{probe,required_action_contract_count}')::integer,0)<1
     or coalesce((v_probe#>>'{probe,immutability_contract_count}')::integer,0)<1
     or coalesce((v_probe#>>'{probe,correlation_contract_count}')::integer,0)<1 then
    raise exception 'AUDIT_B2B_CANDIDATE_POSTCONDITION_FAILED:%',v_probe;
  end if;

  v_classifier:=programacion.fn_input_governance_bootstrap_classify_v2(51,'AUDIT',19);
  if v_classifier->>'coverage_status'<>'COMPLETE'
     or v_classifier->>'well_defined_status'<>'COMPLETE'
     or v_classifier->>'story_ready_status'<>'READY'
     or v_classifier->>'implementation_ready_status'<>'NOT_READY' then
    raise exception 'AUDIT_B2B_CLASSIFIER_POSTCONDITION_FAILED:%',v_classifier;
  end if;

  v_graph:=programacion.fn_input_screen_canonical_graph(51,19);
  v_graph:=jsonb_set(
    v_graph,
    '{canonical_contract,rules}',
    jsonb_build_array(
      jsonb_build_object(
        'rule_code','TEST-AUDIT-VIGENTE',
        'status','VIGENTE',
        'category','AUDIT',
        'pending_decision',false,
        'config',jsonb_build_object(
          'audit_sink','lf_ops.auditoria_eventos',
          'required_audit_actions',jsonb_build_array('TEST_EVENT'),
          'append_only',true,
          'correlation_id_required',true
        )
      )
    ),
    true
  );

  v_probe:=programacion.fn_input_governance_semantic_probe_v3_cached_v1(
    51,'AUDIT',19,v_graph
  );
  if v_probe->>'level'<>'COMPLETE'
     or v_probe->>'blocker_code' is not null
     or v_probe#>>'{stage_statuses,implementation}'<>'READY' then
    raise exception 'AUDIT_VIGENTE_POSITIVE_POSTCONDITION_FAILED:%',v_probe;
  end if;

  v_graph:=jsonb_set(
    v_graph,
    '{canonical_contract,rules}',
    jsonb_build_array(
      jsonb_build_object(
        'rule_code','TEST-AUDIT-INCOMPLETE',
        'status','VIGENTE',
        'category','AUDIT',
        'pending_decision',false,
        'config',jsonb_build_object(
          'audit_sink','lf_ops.auditoria_eventos'
        )
      )
    ),
    true
  );

  v_negative:=programacion.fn_input_governance_semantic_probe_v3_cached_v1(
    51,'AUDIT',19,v_graph
  );
  if v_negative->>'level'='COMPLETE'
     or v_negative->>'blocker_code'<>'AUDIT_CANONICAL_SOURCE_INCOMPLETE' then
    raise exception 'AUDIT_NEGATIVE_FAIL_CLOSED_POSTCONDITION_FAILED:%',v_negative;
  end if;
end;
$postconditions$;

commit;
