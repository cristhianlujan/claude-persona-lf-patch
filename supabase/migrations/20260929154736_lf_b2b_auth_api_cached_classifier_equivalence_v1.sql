-- B2B API_DATA_CONTRACT cached classifier equivalence v1
-- Curator uses classify_v2_cached_v1 while Validator uses classify_v2.
-- Keep API logical-schema / executable-binding semantics byte-equivalent.

begin;

do $patch$
declare
  r record;
  v_def text;
  v_start integer;
  v_end integer;
  v_block text :=
$$  if v->>'applicability'<>'NOT_APPLICABLE' and p_family_code='API_DATA_CONTRACT' then
    v_api:=programacion.fn_input_api_contract_resolution(p_pantalla_id);

    if coalesce((v_api->>'has_behavioral_contract')::boolean,false)
       and coalesce((v_api->>'broken_contract_ref_count')::integer,0)=0 then

      if coalesce((v_api->>'has_resolvable_operation_schema_authority')::boolean,false) then
        v:=jsonb_set(v,'{probe}',v_api,true);
        v:=jsonb_set(v,'{bootstrap_level}','"COMPLETE"'::jsonb,true);
        v:=jsonb_set(v,'{coverage_status}','"COMPLETE"'::jsonb,true);
        v:=jsonb_set(v,'{well_defined_status}','"COMPLETE"'::jsonb,true);
        v:=jsonb_set(v,'{story_ready_status}','"READY"'::jsonb,true);

        if coalesce((v_api->>'has_executable_binding_authority')::boolean,false) then
          v:=jsonb_set(v,'{severity}','"P4"'::jsonb,true);
          v:=jsonb_set(v,'{implementation_ready_status}','"READY"'::jsonb,true);
          v:=jsonb_set(v,'{qa_ready_status}','"READY"'::jsonb,true);
          v:=jsonb_set(v,'{production_ready_status}','"READY"'::jsonb,true);
          v:=jsonb_set(v,'{blockers}','[]'::jsonb,true);
        else
          v:=jsonb_set(v,'{severity}','"P1"'::jsonb,true);
          v:=jsonb_set(v,'{implementation_ready_status}','"NOT_READY"'::jsonb,true);
          v:=jsonb_set(v,'{qa_ready_status}','"BLOCKED"'::jsonb,true);
          v:=jsonb_set(v,'{production_ready_status}','"BLOCKED"'::jsonb,true);
          v:=jsonb_set(v,'{blockers}',jsonb_build_array(jsonb_build_object(
            'code','API_EXECUTABLE_IDENTITY_BINDING_PENDING',
            'family_code',p_family_code,
            'bootstrap_level','COMPLETE',
            'earliest_blocking_stage','IMPLEMENTATION'
          )),true);
        end if;

        v:=jsonb_set(v,'{rationale}',to_jsonb(
          'Provider-agnostic logical LF_AUTH_BOUNDARY request/response schema is canonical and fail-closed. Executable endpoint/grant/provider binding remains independently required for Implementation.'::text
        ),true);

      else
        v:=jsonb_set(v,'{probe}',v_api,true);
        v:=jsonb_set(v,'{bootstrap_level}','"PARTIAL"'::jsonb,true);
        v:=jsonb_set(v,'{severity}','"P1"'::jsonb,true);
        v:=jsonb_set(v,'{coverage_status}','"PARTIAL"'::jsonb,true);
        v:=jsonb_set(v,'{well_defined_status}','"COMPLETE"'::jsonb,true);
        v:=jsonb_set(v,'{story_ready_status}','"READY"'::jsonb,true);
        v:=jsonb_set(v,'{implementation_ready_status}','"NOT_READY"'::jsonb,true);
        v:=jsonb_set(v,'{qa_ready_status}','"BLOCKED"'::jsonb,true);
        v:=jsonb_set(v,'{production_ready_status}','"BLOCKED"'::jsonb,true);
        v:=jsonb_set(v,'{blockers}',jsonb_build_array(jsonb_build_object(
          'code','API_OPERATION_SCHEMA_SOURCE_INCOMPLETE',
          'family_code',p_family_code,
          'bootstrap_level','PARTIAL',
          'earliest_blocking_stage','IMPLEMENTATION'
        )),true);
      end if;
    end if;
  end if;

$$;
begin
  for r in
    select sig
    from (
      values
        ('programacion.fn_input_governance_bootstrap_classify_v2_cached_v1(integer,text,bigint,jsonb)'),
        ('programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(integer,text,bigint,jsonb)')
    ) x(sig)
  loop
    select pg_get_functiondef(to_regprocedure(r.sig)) into v_def;

    if v_def is null then
      raise exception 'API_CACHED_CLASSIFIER_FUNCTION_MISSING:%',r.sig;
    end if;

    v_start:=position(
      $$  if v->>'applicability'<>'NOT_APPLICABLE' and p_family_code='API_DATA_CONTRACT' then$$
      in v_def
    );
    v_end:=position(
      $$  if v->>'applicability'<>'NOT_APPLICABLE' and p_family_code='MFA_OTP_SSO' then$$
      in v_def
    );

    if v_start=0 or v_end=0 or v_end<=v_start then
      raise exception 'API_CACHED_CLASSIFIER_SOURCE_DRIFT:%',r.sig;
    end if;

    v_def:=substring(v_def from 1 for v_start-1)
           || v_block
           || substring(v_def from v_end);

    execute v_def;
  end loop;
end;
$patch$;

do $postconditions$
declare
  v_graph jsonb;
  v_normal jsonb;
  v_cached_v1 jsonb;
  v_cached_v2 jsonb;
begin
  v_graph:=programacion.fn_input_screen_canonical_graph(51,19);

  v_normal:=programacion.fn_input_governance_bootstrap_classify_v2(
    51,'API_DATA_CONTRACT',19
  );
  v_cached_v1:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v1(
    51,'API_DATA_CONTRACT',19,v_graph
  );
  v_cached_v2:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(
    51,'API_DATA_CONTRACT',19,v_graph
  );

  if v_normal->>'classifier_sha256' is distinct from v_cached_v1->>'classifier_sha256' then
    raise exception
      'API_CLASSIFIER_NORMAL_CACHED_V1_MISMATCH normal=% cached=% normal_payload=% cached_payload=%',
      v_normal->>'classifier_sha256',
      v_cached_v1->>'classifier_sha256',
      v_normal,
      v_cached_v1;
  end if;

  if v_normal->>'classifier_sha256' is distinct from v_cached_v2->>'classifier_sha256' then
    raise exception
      'API_CLASSIFIER_NORMAL_CACHED_V2_MISMATCH normal=% cached=% normal_payload=% cached_payload=%',
      v_normal->>'classifier_sha256',
      v_cached_v2->>'classifier_sha256',
      v_normal,
      v_cached_v2;
  end if;

  if v_normal->>'coverage_status'<>'COMPLETE'
     or v_normal->>'well_defined_status'<>'COMPLETE'
     or v_normal->>'implementation_ready_status'<>'NOT_READY'
     or v_normal->'blockers'->0->>'code'<>'API_EXECUTABLE_IDENTITY_BINDING_PENDING' then
    raise exception 'API_CLASSIFIER_EQUIVALENCE_STATE_INVALID:%',v_normal;
  end if;
end;
$postconditions$;

commit;
