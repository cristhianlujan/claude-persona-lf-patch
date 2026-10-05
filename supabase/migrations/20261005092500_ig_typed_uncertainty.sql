-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M3.6 / PAULO-045
-- Implement typed uncertainty at the final semantic classifier boundary.
-- Scope: only existing members of PROGRAMACION_FN_INPUT_GOVERNANCE_SEMANTIC_CLASSIFICATION_SET.
-- No new shared abstraction; no Curator/Validator/runtime deployment mutation.

begin;

do $m36$
declare
  r record;
  v_def text;
  v_needle constant text := $needle$  v:=programacion.fn_input_apply_stage_authority_v2(v,p_pantalla_id,p_family_code,p_version_id);
  v:=v-'classifier_sha256';
  return v||jsonb_build_object('classifier_sha256',programacion.fn_v09_sha256_jsonb(v));$needle$;
  v_replacement constant text := $inject$  v:=programacion.fn_input_apply_stage_authority_v2(v,p_pantalla_id,p_family_code,p_version_id);

  -- M3.6: every emitted semantic blocker is explicit and fail-closed.
  if jsonb_typeof(v->'blockers')='array' and jsonb_array_length(v->'blockers')>0 then
    select coalesce(jsonb_agg(
      b.value || jsonb_build_object(
        'state',typed.state,
        'uncertainty_type',typed.uncertainty_type,
        'blocking_stage',typed.blocking_stage,
        'evidence',jsonb_build_object(
          'assessment_id',null,
          'run_id',null,
          'family_code',p_family_code,
          'pantalla_id',p_pantalla_id,
          'version_id',p_version_id,
          'original_blocker_payload',b.value,
          'source_refs',coalesce(v->'source_refs','[]'::jsonb),
          'probe',coalesce(v->'probe','{}'::jsonb),
          'evidence_phase','SEMANTIC_PRE_PERSISTENCE',
          'persistence_identity_status','DEFERRED_TO_CURATOR'
        )
      ) order by b.ordinality
    ),'[]'::jsonb)
    into v_blockers
    from jsonb_array_elements(v->'blockers') with ordinality b(value,ordinality)
    cross join lateral (
      select case
        when upper(coalesce(b.value->>'code','')) in ('R3_SEMANTIC_FAIL_CLOSED_RECLASSIFICATION','V59_STAGE_SPECIFIC_RECLASSIFICATION')
          then 'POLICY_RECLASSIFICATION'
        when upper(coalesce(b.value->>'status',''))='HUMAN_DECISION_REQUIRED'
          or upper(coalesce(b.value->>'code','')) like '%DECISION_REQUIRED%'
          or coalesce((b.value->>'human_decision_required')::boolean,false)
          or b.value ? 'required_decision'
          then 'HUMAN_DECISION_REQUIRED'
        when upper(coalesce(b.value->>'code','')) ~ '(CONFLICT|RECONCILIATION)'
          then 'SOURCE_CONFLICT'
        when upper(coalesce(b.value->>'code',''))='PRODUCTION_NOT_AUTHORIZED'
          then 'PRODUCTION_AUTHORIZATION_MISSING'
        when upper(coalesce(b.value->>'code','')) ~ '(CANDIDATE|NOT_IMPLEMENTATION_READY)'
          then 'CANDIDATE_AUTHORITY'
        when upper(coalesce(b.value->>'code','')) ~ '(BINARY|VISUAL|ARTIFACT).*(UNRESOLVED|MISSING|PENDING|NOT_READY)'
          then 'EXTERNAL_ARTIFACT_UNRESOLVED'
        when upper(coalesce(b.value->>'code','')) ~ '(APPLICABILITY|SCOPE).*(UNRESOLVED|MISSING|PENDING|INCOMPLETE|NOT_READY)'
          then 'APPLICABILITY_AUTHORITY_MISSING'
        when upper(coalesce(b.value->>'code','')) ~ '(SEMANTIC|SUBJECT|THREAT|COMPONENT).*(UNRESOLVED|MISSING|PENDING|INCOMPLETE|NOT_READY)'
          then 'UNRESOLVED_SEMANTIC'
        when upper(coalesce(b.value->>'code','')) ~ '(BINDING|PROVIDER|RUNTIME|PLATFORM).*(UNRESOLVED|MISSING|PENDING|INCOMPLETE|NOT_READY|NOT_AUTHORIZED)'
          then 'IMPLEMENTATION_DEPENDENCY'
        when upper(coalesce(b.value->>'code','')) ~ '(QA|E2E|VALIDATION|TEST).*(REQUIRED|PENDING|MISSING|INCOMPLETE|NOT_READY)'
          then 'QA_EVIDENCE_PENDING'
        when upper(coalesce(b.value->>'code','')) ~ '(MISSING|NOT_LINKED|SOURCE.*INCOMPLETE|SOURCE_IDENTIFICATION|CANONICAL.*MISSING|REQUIREMENT.*MISSING|REFERENCE_UNRESOLVED)'
          then 'MISSING_SOURCE'
        when upper(coalesce(b.value->>'code','')) ~ '(PARTIAL|INCOMPLETE)'
          then 'INCOMPLETE_EVIDENCE'
        when upper(coalesce(b.value->>'code','')) ~ '(PENDING|NOT_READY|NOT_AUTHORIZED)'
          then 'DELIVERY_DEPENDENCY'
        else null
      end as uncertainty_type
    ) u
    cross join lateral (
      select
        case
          when u.uncertainty_type='POLICY_RECLASSIFICATION' then 'INFORMATIONAL'
          when u.uncertainty_type in ('IMPLEMENTATION_DEPENDENCY','QA_EVIDENCE_PENDING','DELIVERY_DEPENDENCY')
            and coalesce(nullif(b.value->>'dependency_ref',''),nullif(b.value->>'work_item_ref',''),nullif(b.value->>'platform_work_ref','')) is not null
            then 'READY_WITH_DEPENDENCY'
          when u.uncertainty_type is not null then 'BLOCKED'
          else null
        end as state,
        case
          when upper(coalesce(b.value->>'earliest_blocking_stage','')) in ('STORY','IMPLEMENTATION','QA','PRODUCTION','NONE')
            then upper(b.value->>'earliest_blocking_stage')
          when coalesce((b.value->>'blocks_story')::boolean,false) then 'STORY'
          when coalesce((b.value->>'blocks_implementation')::boolean,false) then 'IMPLEMENTATION'
          when coalesce((b.value->>'blocks_qa')::boolean,false) then 'QA'
          when coalesce((b.value->>'blocks_production')::boolean,false) then 'PRODUCTION'
          when u.uncertainty_type='POLICY_RECLASSIFICATION' then 'NONE'
          when u.uncertainty_type='PRODUCTION_AUTHORIZATION_MISSING' then 'PRODUCTION'
          when u.uncertainty_type='QA_EVIDENCE_PENDING' then 'QA'
          when u.uncertainty_type in ('CANDIDATE_AUTHORITY','IMPLEMENTATION_DEPENDENCY') then 'IMPLEMENTATION'
          when u.uncertainty_type='APPLICABILITY_AUTHORITY_MISSING' then 'STORY'
          when u.uncertainty_type='EXTERNAL_ARTIFACT_UNRESOLVED' then 'QA'
          when upper(coalesce(v->>'story_ready_status','')) in ('BLOCKED','NOT_READY') then 'STORY'
          when upper(coalesce(v->>'implementation_ready_status','')) in ('BLOCKED','NOT_READY') then 'IMPLEMENTATION'
          when upper(coalesce(v->>'qa_ready_status','')) in ('BLOCKED','NOT_READY') then 'QA'
          when upper(coalesce(v->>'production_ready_status','')) in ('BLOCKED','NOT_READY') then 'PRODUCTION'
          else null
        end as blocking_stage,
        u.uncertainty_type
    ) typed;

    v:=jsonb_set(v,'{blockers}',v_blockers,true);

    if exists (
      select 1 from jsonb_array_elements(v->'blockers') x(value)
      where nullif(x.value->>'uncertainty_type','') is null
         or nullif(x.value->>'state','') is null
         or nullif(x.value->>'blocking_stage','') is null
         or jsonb_typeof(x.value->'evidence')<>'object'
    ) then
      raise exception 'M36_UNTYPED_BLOCKER:%',p_family_code;
    end if;
  end if;

  if v->>'bootstrap_level'='PARTIAL'
     and jsonb_array_length(coalesce(v->'blockers','[]'::jsonb))=0 then
    raise exception 'M36_PARTIAL_WITHOUT_TYPED_BLOCKER:%',p_family_code;
  end if;

  v:=v-'classifier_sha256';
  return v||jsonb_build_object('classifier_sha256',programacion.fn_v09_sha256_jsonb(v));$inject$;
begin
  for r in
    select x.rp
    from (values
      ('programacion.fn_input_governance_bootstrap_classify_v2(integer,text,bigint)'::regprocedure),
      ('programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(integer,text,bigint,jsonb)'::regprocedure)
    ) x(rp)
  loop
    v_def:=pg_get_functiondef(r.rp);
    if position(v_needle in v_def)=0 then
      raise exception 'M36_DEFINITION_DRIFT:%',r.rp::text;
    end if;
    execute replace(v_def,v_needle,v_replacement);
  end loop;

  if position('M36_UNTYPED_BLOCKER' in pg_get_functiondef('programacion.fn_input_governance_bootstrap_classify_v2(integer,text,bigint)'::regprocedure))=0 then
    raise exception 'M36_LIVE_PATCH_MISSING:bootstrap_classify_v2';
  end if;
  if position('M36_UNTYPED_BLOCKER' in pg_get_functiondef('programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(integer,text,bigint,jsonb)'::regprocedure))=0 then
    raise exception 'M36_LIVE_PATCH_MISSING:bootstrap_classify_v2_cached_v2';
  end if;
end
$m36$;

commit;
