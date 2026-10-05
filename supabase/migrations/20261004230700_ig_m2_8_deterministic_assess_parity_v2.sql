create or replace function programacion.fn_input_deterministic_assess(p_subject jsonb,p_family text,p_graph jsonb,p_contract jsonb)
returns jsonb language plpgsql volatile as $f$
declare
  v_screen int; v_version bigint; v_family text:=upper(nullif(trim(p_family),''));
  v_policy jsonb; v_ref jsonb; v_resolved jsonb; v_stage jsonb; v_assessment jsonb; v_payload jsonb;
  v_graph_sha text; v_contract_sha text;
begin
  if jsonb_typeof(p_subject)<>'object' or jsonb_typeof(p_graph)<>'object' or jsonb_typeof(p_contract)<>'object' then raise exception 'DETERMINISTIC_ASSESS_INVALID_INPUT'; end if;
  if upper(coalesce(p_subject->>'source_class','DETERMINISTIC'))='SEMANTIC' then raise exception 'DETERMINISTIC_ASSESS_SEMANTIC_INPUT_FORBIDDEN'; end if;
  v_screen:=nullif(p_subject->>'pantalla_id','')::int;
  v_version:=coalesce(nullif(p_subject->>'version_id','')::bigint,nullif(p_graph->>'agent_contract_version_id','')::bigint);
  if v_screen is null or v_version is null or v_family is null then raise exception 'DETERMINISTIC_ASSESS_IDENTITY_REQUIRED'; end if;
  if p_contract->>'contract_revision'<>'5.13' then raise exception 'DETERMINISTIC_ASSESS_CONTRACT_REVISION'; end if;
  if p_graph->>'graph_contract' is distinct from p_contract->>'screen_graph_contract' then raise exception 'DETERMINISTIC_ASSESS_GRAPH_CONTRACT'; end if;
  if nullif(p_graph->>'agent_contract_version_id','')::bigint is distinct from v_version then raise exception 'DETERMINISTIC_ASSESS_VERSION_PIN'; end if;
  v_policy:=p_contract->'family_stage_requirements'->v_family;
  if v_policy is null then raise exception 'DETERMINISTIC_ASSESS_FAMILY'; end if;
  if coalesce(p_subject->>'applicability','')='' or coalesce(p_subject->>'coverage_status','')='' or coalesce(p_subject->>'well_defined_status','')='' then raise exception 'DETERMINISTIC_ASSESS_STATUS_REQUIRED'; end if;
  v_ref:=jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',v_screen);
  v_resolved:=programacion.fn_input_resolve_source_ref(v_ref,v_screen,v_version);
  v_graph_sha:=programacion.fn_v09_sha256_jsonb(p_graph);
  if v_resolved->>'observed_sha256' is distinct from v_graph_sha then raise exception 'DETERMINISTIC_ASSESS_GRAPH_DRIFT'; end if;
  v_contract_sha:=programacion.fn_v09_sha256_jsonb(p_contract);
  v_stage:=programacion.fn_input_stage_resolve_v2(v_family,v_screen,v_version,p_subject->>'coverage_status',p_subject->>'well_defined_status');
  v_assessment:=p_subject-'pantalla_id'-'version_id'-'source_class';
  if jsonb_typeof(v_assessment->'blockers') is distinct from 'array' then v_assessment:=jsonb_set(v_assessment,'{blockers}','[]'::jsonb,true); end if;
  v_assessment:=programacion.fn_input_apply_stage_authority_v2(v_assessment,v_screen,v_family,v_version);
  v_payload:=jsonb_build_object('contract','DETERMINISTIC_ASSESS_V1','subject_identity',jsonb_build_object('pantalla_id',v_screen,'version_id',v_version),'family_code',v_family,'contract_revision','5.13','contract_sha256',v_contract_sha,'graph_contract',p_graph->>'graph_contract','graph_sha256',v_graph_sha,'graph_resolution',jsonb_build_object('ref',v_ref,'observed_sha256',v_resolved->>'observed_sha256','matches_provided',true),'family_policy',v_policy,'stage_resolution',v_stage,'assessment',v_assessment,'semantic_boundary','EXCLUDED','semantic_calls','[]'::jsonb);
  return v_payload||jsonb_build_object('result_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;$f$;
comment on function programacion.fn_input_deterministic_assess(jsonb,text,jsonb,jsonb) is 'M2.8 deterministic facade; preserves deterministic readiness facts, rejects semantic inputs, and uses existing source/stage resolvers only.';
