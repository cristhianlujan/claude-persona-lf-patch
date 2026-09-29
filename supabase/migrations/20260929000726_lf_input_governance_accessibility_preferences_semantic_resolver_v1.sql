-- Input Governance semantic resolvers for forced-colors and reduced-motion.
-- Structural semantics decide coverage; lifecycle and implementation markers keep
-- Implementation fail-closed until the canonical source is actually implemented.

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
          $$  if p_family_code='AUDIT' then$$,
          $$  if p_family_code='FORCED_COLORS_CONTRAST' then
    select
      count(*) filter(
        where coalesce(x.value->'config'->>'forced_colors_support','')='REQUIRED'
          and coalesce(x.value->'config'->>'focus_visibility','')='REQUIRED'
          and coalesce(x.value->'config'->>'state_color_only','')='DENY'
          and coalesce(x.value->'config'->>'global_forced_color_adjust_none','')='DENY'
      ),
      count(*) filter(where coalesce(x.value->>'status','')='CANDIDATO'),
      count(*) filter(
        where coalesce(x.value->'config'->>'implementation_status','') ~* '(PENDING|NOT_READY|BLOCKED)'
      )
    into v_rule_count,v_candidate_count,v_missing_source_count
    from jsonb_array_elements(
      coalesce(
        programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id)
          ->'canonical_contract'->'rules',
        '[]'::jsonb
      )
    ) x(value)
    where coalesce(x.value->>'status','')<>'DEPRECADO'
      and (
        x.value->'config' ? 'forced_colors_support'
        or x.value->'config' ? 'state_color_only'
        or x.value->'config' ? 'global_forced_color_adjust_none'
      );

    if v_rule_count>0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case when v_candidate_count>0 or v_missing_source_count>0 then 'P1' else 'P4' end,
        'blocker_code',case
          when v_candidate_count>0 or v_missing_source_count>0
            then 'FORCED_COLORS_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case when v_candidate_count>0 or v_missing_source_count>0 then 'NOT_READY' else 'READY' end,
          'qa',case when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED' else 'READY' end,
          'production',case when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED' else 'READY' end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_missing_source_count>0 then
            jsonb_build_array(jsonb_build_object(
              'code','FORCED_COLORS_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','FORCED_COLORS_SEMANTIC_RESOLUTION_V1',
          'qualified_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'implementation_pending_count',v_missing_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='REDUCED_MOTION' then
    select
      count(*) filter(
        where coalesce(x.value->'config'->>'preference','')='prefers-reduced-motion'
          and coalesce(x.value->'config'->>'functional_dependency_on_motion','')='DENY'
          and coalesce(x.value->'config'->>'non_essential_motion_when_reduce','')='REDUCE_OR_REMOVE'
          and coalesce((x.value->'config'->>'status_requires_non_motion_cue')::boolean,false)
      ),
      count(*) filter(where coalesce(x.value->>'status','')='CANDIDATO'),
      count(*) filter(
        where coalesce(x.value->'config'->>'implementation_status','') ~* '(PENDING|NOT_READY|BLOCKED)'
      )
    into v_rule_count,v_candidate_count,v_missing_source_count
    from jsonb_array_elements(
      coalesce(
        programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id)
          ->'canonical_contract'->'rules',
        '[]'::jsonb
      )
    ) x(value)
    where coalesce(x.value->>'status','')<>'DEPRECADO'
      and (
        x.value->'config' ? 'preference'
        or x.value->'config' ? 'functional_dependency_on_motion'
        or x.value->'config' ? 'non_essential_motion_when_reduce'
      );

    if v_rule_count>0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case when v_candidate_count>0 or v_missing_source_count>0 then 'P1' else 'P4' end,
        'blocker_code',case
          when v_candidate_count>0 or v_missing_source_count>0
            then 'REDUCED_MOTION_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case when v_candidate_count>0 or v_missing_source_count>0 then 'NOT_READY' else 'READY' end,
          'qa',case when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED' else 'READY' end,
          'production',case when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED' else 'READY' end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_missing_source_count>0 then
            jsonb_build_array(jsonb_build_object(
              'code','REDUCED_MOTION_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','REDUCED_MOTION_SEMANTIC_RESOLUTION_V1',
          'qualified_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'implementation_pending_count',v_missing_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='AUDIT' then$$
        ),
        (
          'programacion.fn_input_governance_semantic_probe_v3_cached_v1(integer,text,bigint,jsonb)',
          $$  if p_family_code='AUDIT' then$$,
          $$  if p_family_code='FORCED_COLORS_CONTRAST' then
    select
      count(*) filter(
        where coalesce(x.value->'config'->>'forced_colors_support','')='REQUIRED'
          and coalesce(x.value->'config'->>'focus_visibility','')='REQUIRED'
          and coalesce(x.value->'config'->>'state_color_only','')='DENY'
          and coalesce(x.value->'config'->>'global_forced_color_adjust_none','')='DENY'
      ),
      count(*) filter(where coalesce(x.value->>'status','')='CANDIDATO'),
      count(*) filter(
        where coalesce(x.value->'config'->>'implementation_status','') ~* '(PENDING|NOT_READY|BLOCKED)'
      )
    into v_rule_count,v_candidate_count,v_missing_source_count
    from jsonb_array_elements(
      coalesce(p_graph->'canonical_contract'->'rules','[]'::jsonb)
    ) x(value)
    where coalesce(x.value->>'status','')<>'DEPRECADO'
      and (
        x.value->'config' ? 'forced_colors_support'
        or x.value->'config' ? 'state_color_only'
        or x.value->'config' ? 'global_forced_color_adjust_none'
      );

    if v_rule_count>0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case when v_candidate_count>0 or v_missing_source_count>0 then 'P1' else 'P4' end,
        'blocker_code',case
          when v_candidate_count>0 or v_missing_source_count>0
            then 'FORCED_COLORS_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case when v_candidate_count>0 or v_missing_source_count>0 then 'NOT_READY' else 'READY' end,
          'qa',case when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED' else 'READY' end,
          'production',case when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED' else 'READY' end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_missing_source_count>0 then
            jsonb_build_array(jsonb_build_object(
              'code','FORCED_COLORS_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','FORCED_COLORS_SEMANTIC_RESOLUTION_V1',
          'qualified_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'implementation_pending_count',v_missing_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='REDUCED_MOTION' then
    select
      count(*) filter(
        where coalesce(x.value->'config'->>'preference','')='prefers-reduced-motion'
          and coalesce(x.value->'config'->>'functional_dependency_on_motion','')='DENY'
          and coalesce(x.value->'config'->>'non_essential_motion_when_reduce','')='REDUCE_OR_REMOVE'
          and coalesce((x.value->'config'->>'status_requires_non_motion_cue')::boolean,false)
      ),
      count(*) filter(where coalesce(x.value->>'status','')='CANDIDATO'),
      count(*) filter(
        where coalesce(x.value->'config'->>'implementation_status','') ~* '(PENDING|NOT_READY|BLOCKED)'
      )
    into v_rule_count,v_candidate_count,v_missing_source_count
    from jsonb_array_elements(
      coalesce(p_graph->'canonical_contract'->'rules','[]'::jsonb)
    ) x(value)
    where coalesce(x.value->>'status','')<>'DEPRECADO'
      and (
        x.value->'config' ? 'preference'
        or x.value->'config' ? 'functional_dependency_on_motion'
        or x.value->'config' ? 'non_essential_motion_when_reduce'
      );

    if v_rule_count>0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case when v_candidate_count>0 or v_missing_source_count>0 then 'P1' else 'P4' end,
        'blocker_code',case
          when v_candidate_count>0 or v_missing_source_count>0
            then 'REDUCED_MOTION_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case when v_candidate_count>0 or v_missing_source_count>0 then 'NOT_READY' else 'READY' end,
          'qa',case when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED' else 'READY' end,
          'production',case when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED' else 'READY' end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_missing_source_count>0 then
            jsonb_build_array(jsonb_build_object(
              'code','REDUCED_MOTION_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','REDUCED_MOTION_SEMANTIC_RESOLUTION_V1',
          'qualified_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'implementation_pending_count',v_missing_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='AUDIT' then$$
        )
    ) x(sig,anchor_text,insert_text)
  loop
    select pg_get_functiondef(to_regprocedure(r.sig)) into v_def;
    if v_def is null then
      raise exception 'ACCESSIBILITY_PREFERENCE_SEMANTIC_FUNCTION_MISSING:%',r.sig;
    end if;
    if position('FORCED_COLORS_SEMANTIC_RESOLUTION_V1' in v_def)=0 then
      if position(r.anchor_text in v_def)=0 then
        raise exception 'ACCESSIBILITY_PREFERENCE_SEMANTIC_SOURCE_DRIFT:%',r.sig;
      end if;
      v_def:=replace(v_def,r.anchor_text,r.insert_text);
      execute v_def;
    end if;
  end loop;
end;
$patch$;

do $postconditions$
declare
  v_forced jsonb;
  v_motion jsonb;
  v_graph jsonb;
  v_positive jsonb;
  v_negative jsonb;
begin
  v_forced:=programacion.fn_input_governance_bootstrap_classify_v2(51,'FORCED_COLORS_CONTRAST',19);
  if v_forced->>'coverage_status'<>'COMPLETE'
     or v_forced->>'well_defined_status'<>'COMPLETE'
     or v_forced->>'implementation_ready_status'<>'NOT_READY'
     or v_forced#>>'{probe,resolution_contract}'<>'FORCED_COLORS_SEMANTIC_RESOLUTION_V1' then
    raise exception 'FORCED_COLORS_B2B_POSTCONDITION_FAILED:%',v_forced;
  end if;

  v_motion:=programacion.fn_input_governance_bootstrap_classify_v2(51,'REDUCED_MOTION',19);
  if v_motion->>'coverage_status'<>'COMPLETE'
     or v_motion->>'well_defined_status'<>'COMPLETE'
     or v_motion->>'implementation_ready_status'<>'NOT_READY'
     or v_motion#>>'{probe,resolution_contract}'<>'REDUCED_MOTION_SEMANTIC_RESOLUTION_V1' then
    raise exception 'REDUCED_MOTION_B2B_POSTCONDITION_FAILED:%',v_motion;
  end if;

  -- Synthetic VIGENTE positive: semantic completeness can become Implementation READY.
  v_graph:=programacion.fn_input_screen_canonical_graph(51,19);
  v_graph:=jsonb_set(
    v_graph,
    '{canonical_contract,rules}',
    jsonb_build_array(
      jsonb_build_object(
        'rule_code','TEST-FORCED-COLORS-VIGENTE',
        'status','VIGENTE',
        'config',jsonb_build_object(
          'forced_colors_support','REQUIRED',
          'focus_visibility','REQUIRED',
          'state_color_only','DENY',
          'global_forced_color_adjust_none','DENY',
          'implementation_status','IMPLEMENTED_QA_VERIFIED'
        )
      )
    ),
    true
  );
  v_positive:=programacion.fn_input_governance_semantic_probe_v3_cached_v1(
    51,'FORCED_COLORS_CONTRAST',19,v_graph
  );
  if v_positive#>>'{stage_statuses,implementation}'<>'READY'
     or v_positive->>'blocker_code' is not null then
    raise exception 'FORCED_COLORS_VIGENTE_POSITIVE_FAILED:%',v_positive;
  end if;

  v_graph:=jsonb_set(
    v_graph,
    '{canonical_contract,rules}',
    jsonb_build_array(
      jsonb_build_object(
        'rule_code','TEST-REDUCED-MOTION-VIGENTE',
        'status','VIGENTE',
        'config',jsonb_build_object(
          'preference','prefers-reduced-motion',
          'functional_dependency_on_motion','DENY',
          'non_essential_motion_when_reduce','REDUCE_OR_REMOVE',
          'status_requires_non_motion_cue',true,
          'implementation_status','IMPLEMENTED_QA_VERIFIED'
        )
      )
    ),
    true
  );
  v_positive:=programacion.fn_input_governance_semantic_probe_v3_cached_v1(
    51,'REDUCED_MOTION',19,v_graph
  );
  if v_positive#>>'{stage_statuses,implementation}'<>'READY'
     or v_positive->>'blocker_code' is not null then
    raise exception 'REDUCED_MOTION_VIGENTE_POSITIVE_FAILED:%',v_positive;
  end if;

  -- Negative unrelated evidence must remain fail-closed.
  v_graph:=jsonb_set(
    v_graph,
    '{canonical_contract,rules}',
    jsonb_build_array(jsonb_build_object(
      'rule_code','TEST-UNRELATED-A11Y',
      'status','VIGENTE',
      'config',jsonb_build_object('keyboard',true)
    )),
    true
  );
  v_negative:=programacion.fn_input_governance_semantic_probe_v3_cached_v1(
    51,'FORCED_COLORS_CONTRAST',19,v_graph
  );
  if v_negative->>'level'='COMPLETE' then
    raise exception 'FORCED_COLORS_NEGATIVE_FAIL_CLOSED_FAILED:%',v_negative;
  end if;

  v_negative:=programacion.fn_input_governance_semantic_probe_v3_cached_v1(
    51,'REDUCED_MOTION',19,v_graph
  );
  if v_negative->>'level'='COMPLETE' then
    raise exception 'REDUCED_MOTION_NEGATIVE_FAIL_CLOSED_FAILED:%',v_negative;
  end if;
end;
$postconditions$;

commit;
