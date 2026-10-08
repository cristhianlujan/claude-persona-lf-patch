-- IG M8.2 exact live composer body, timing leaves NEW and all semantic hashes unchanged.
CREATE OR REPLACE FUNCTION programacion.fn_input_curator_compose_before_insert_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'public'
AS $function$
declare
  v_ctx jsonb;
  v_strategy text;
  v_run record;
  v_core_contract jsonb;
  v_core_result jsonb;
  v_semantic_registry jsonb;
  v_semantic_registry_sha text;
  v_semantic_policy jsonb;
  v_semantic_resolver text;
  v_resolver_oid oid;
  v_probe jsonb;
  v_selector_version text;
  v_selector_sha text;
  v_eligibility text;
  v_execution_state text;
  v_m82_start timestamptz;
  v_m82_deterministic_ms bigint;
  v_m82_semantic_ms bigint;
  v_m82_spans jsonb;
begin
  v_ctx:=nullif(current_setting('lf.input_request_context_v1',true),'')::jsonb;
  if v_ctx is null or v_ctx->>'schema_version'<>'INPUT_GOVERNANCE_REQUEST_CONTEXT_V1' then
    return new; -- other internal test/producer routes do not enter this wrapper
  end if;
  v_strategy:=v_ctx->>'strategy';
  if v_strategy not in ('BOOTSTRAP','REBIND','SOURCE_STALE_RECURATE','FULL_RECURATE') then
    return new;
  end if;
  select r.version_id,r.pantalla_id,r.curator_identity,r.status into v_run
    from programacion.input_readiness_runs r where r.id=new.run_id;
  if v_run.status<>'CURATING'
     or v_run.pantalla_id is distinct from (v_ctx->>'pantalla_id')::integer
     or v_run.version_id is distinct from (v_ctx->>'version_id')::bigint
     or v_run.curator_identity is distinct from v_ctx->>'request_identity'
     or jsonb_typeof(v_ctx->'graph')<>'object' then
    raise exception 'IG_PREINSERT_CONTEXT_AUTHORITY_MISMATCH:%',new.family_code;
  end if;
  select c.especificacion into v_core_contract
    from programacion.contratos c
    where c.version_id=v_run.version_id
      and c.contrato_codigo='INPUT_READINESS_CONTRACT' and c.estado='defined' and c.fail_closed
    order by c.id desc limit 1;
  if v_core_contract is null then raise exception 'IG_PREINSERT_CORE_CONTRACT_MISSING'; end if;
  -- Trust boundary: verify the writer's ORIGINAL evidence hash before enrichment.
  if new.curator_sha256 is distinct from programacion.fn_v09_sha256_jsonb(jsonb_build_object(
    'run_id',new.run_id,'family_code',new.family_code,
    'severity',new.severity,'applicability',new.applicability,
    'coverage_status',new.coverage_status,'well_defined_status',new.well_defined_status,
    'story_ready_status',new.story_ready_status,'implementation_ready_status',new.implementation_ready_status,
    'qa_ready_status',new.qa_ready_status,'production_ready_status',new.production_ready_status,
    'source_refs',new.source_refs,'rationale',new.rationale,'blockers',new.blockers,
    'negative_requirements',new.negative_requirements,'test_obligations',new.test_obligations,
    'freshness',new.freshness,'curator_evidence',new.curator_evidence,
    'subject_coverage',new.subject_coverage,'threat_coverage',new.threat_coverage,
    'semantic_depth_sha256',new.semantic_depth_sha256)) then
    raise exception 'IG_PREINSERT_ORIGINAL_CURATOR_SHA_MISMATCH:%',new.family_code;
  end if;
  v_m82_start:=clock_timestamp();
  v_core_result:=programacion.fn_input_deterministic_assess(
    (to_jsonb(new)-'id'-'run_id'-'family_code') ||
      jsonb_build_object('pantalla_id',v_run.pantalla_id,'version_id',v_run.version_id,'source_class','DETERMINISTIC'),
    new.family_code,v_ctx->'graph',v_core_contract);
  v_m82_deterministic_ms:=greatest(0,round(extract(epoch from (clock_timestamp()-v_m82_start))*1000)::bigint);
  if coalesce(v_core_result->>'result_sha256','')='' then
    raise exception 'IG_PREINSERT_CORE_RECEIPT_MISSING:%',new.family_code;
  end if;
  new.severity:=coalesce(v_core_result#>>'{assessment,severity}',new.severity);
  new.applicability:=coalesce(v_core_result#>>'{assessment,applicability}',new.applicability);
  new.coverage_status:=coalesce(v_core_result#>>'{assessment,coverage_status}',new.coverage_status);
  new.well_defined_status:=coalesce(v_core_result#>>'{assessment,well_defined_status}',new.well_defined_status);
  new.story_ready_status:=coalesce(v_core_result#>>'{assessment,story_ready_status}',new.story_ready_status);
  new.implementation_ready_status:=coalesce(v_core_result#>>'{assessment,implementation_ready_status}',new.implementation_ready_status);
  new.qa_ready_status:=coalesce(v_core_result#>>'{assessment,qa_ready_status}',new.qa_ready_status);
  new.production_ready_status:=coalesce(v_core_result#>>'{assessment,production_ready_status}',new.production_ready_status);
  new.blockers:=coalesce(v_core_result#>'{assessment,blockers}',new.blockers);
  new.curator_evidence:=coalesce(new.curator_evidence,'{}'::jsonb)||jsonb_build_object(
    'core_invocation',jsonb_build_object(
      'contract','M5_4_DETERMINISTIC_ASSESS_BRIDGE_V1',
      'facade','programacion.fn_input_deterministic_assess',
      'result_sha256',v_core_result->>'result_sha256',
      'contract_sha256',v_core_result->>'contract_sha256',
      'legacy_seed_removal_checkpoint','NEGATIVE_NO_CLASSIFY'
    )
  );
  select c.especificacion,c.especificacion->>'registry_sha256'
    into v_semantic_registry,v_semantic_registry_sha
    from programacion.contratos c
    where c.version_id=public.fn_lf_version_compatibility_current_version_id_v1(
      'PROGRAMACION_CONTRACT','INPUT_FAMILY_POLICY_REGISTRY',null)
      and c.contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY'
      and c.estado='defined' and c.fail_closed
    order by c.id desc limit 1;
  if v_semantic_registry is null or v_semantic_registry->>'registry_sha256'
       is distinct from v_semantic_registry_sha then
     raise exception 'IG_PREINSERT_FAMILY_POLICY_REGISTRY_SHA_DRIFT';
  end if;
  v_semantic_policy:=v_semantic_registry->'families'->new.family_code;
  if v_semantic_policy is null then
    raise exception 'IG_PREINSERT_FAMILY_POLICY_MISSING:%',new.family_code;
  end if;
  v_semantic_resolver:=v_semantic_policy#>>'{semantic_resolvers,0,function}';
  v_resolver_oid:=to_regprocedure(v_semantic_resolver);
  if v_resolver_oid is null
    or not exists(select 1 from pg_proc p where p.oid=v_resolver_oid and p.pronargs=3 and p.prorettype='jsonb'::regtype) then
    raise exception 'IG_PREINSERT_SEMANTIC_RESOLVER_UNSUPPORTED:%:%',
      new.family_code,coalesce(v_semantic_resolver,'NULL');
  end if;
  v_m82_start:=clock_timestamp();
  execute format('select %s($1,$2,$3)',v_resolver_oid::regproc)
    using v_run.pantalla_id,new.family_code,v_run.version_id into v_probe;
  v_m82_semantic_ms:=greatest(0,round(extract(epoch from (clock_timestamp()-v_m82_start))*1000)::bigint);
  select c.version,c.manifest_sha256
    into v_selector_version,v_selector_sha
    from public.lf_capability_current c
    join public.lf_capability_version_registry v
      on v.capability_code=c.capability_code and v.version=c.version
    where c.capability_code='CAPABILITY_SELECTOR' and v.release_state='RELEASED';
  if v_selector_version is null or v_selector_sha is null then
    raise exception 'IG_PREINSERT_SELECTOR_NOT_RELEASED';
  end if;
  v_eligibility:=case
    when new.applicability='NOT_APPLICABLE' then 'NOT_REQUIRED'
    when upper(coalesce(v_semantic_policy#>>'{stage_policy,coverage_required_by}',''))='STORY'
      then 'REQUIRED'
    else 'CONDITIONAL' end;
  v_execution_state:=case
    when v_eligibility='NOT_REQUIRED' then 'NOT_REQUIRED'
    when new.coverage_status='COMPLETE' then 'DONE'
    when v_eligibility='REQUIRED' then 'BLOCKED'
    else 'PENDING' end;
  new.curator_evidence:=new.curator_evidence||jsonb_build_object(
    'semantic_plan',jsonb_build_object(
      'contract','M5_4_SEMANTIC_PLAN_V1',
      'family_registry',jsonb_build_object(
        'contract_code','INPUT_FAMILY_POLICY_REGISTRY',
        'registry_sha256',v_semantic_registry_sha),
      'deterministic_resolver',v_semantic_policy->'deterministic_resolver',
      'semantic_resolvers',v_semantic_policy->'semantic_resolvers',
      'resolver_result',v_probe,'eligibility',v_eligibility,
      'execution_state',v_execution_state,'stage_policy',v_semantic_policy->'stage_policy',
      'selector_binding',jsonb_build_object(
        'capability_code','CAPABILITY_SELECTOR','version',v_selector_version,
        'manifest_sha256',v_selector_sha,'selection_only',true,
        'fallback_capabilities',jsonb_build_array('FULL_SAFE_MIX_V1_CANDIDATE'),
        'runtime_selection_claim',false)
    )
  );
  new.curator_sha256:=programacion.fn_v09_sha256_jsonb(jsonb_build_object(
    'run_id',new.run_id,'family_code',new.family_code,
    'severity',new.severity,'applicability',new.applicability,
    'coverage_status',new.coverage_status,
    'well_defined_status',new.well_defined_status,
    'story_ready_status',new.story_ready_status,
    'implementation_ready_status',new.implementation_ready_status,
    'qa_ready_status',new.qa_ready_status,
    'production_ready_status',new.production_ready_status,
    'source_refs',new.source_refs,'rationale',new.rationale,
    'blockers',new.blockers,'negative_requirements',new.negative_requirements,
    'test_obligations',new.test_obligations,'freshness',new.freshness,
    'curator_evidence',new.curator_evidence,
    'subject_coverage',new.subject_coverage,'threat_coverage',new.threat_coverage,
    'semantic_depth_sha256',new.semantic_depth_sha256));
  -- M8.2: measured by each actual family/resolver invocation, outside assessment SHA.
  -- Transaction-local only. The façade returns spans and resets this context.
  v_m82_spans:=coalesce(nullif(current_setting('lf.input_curator_family_timings_v1',true),'')::jsonb,'[]'::jsonb);
  if jsonb_typeof(v_m82_spans)<>'array' then raise exception 'IG_M82_SPANS_INVALID'; end if;
  perform set_config('lf.input_curator_family_timings_v1',(
    v_m82_spans||jsonb_build_array(jsonb_build_object(
      'family_code',new.family_code,
      'deterministic_resolver','programacion.fn_input_deterministic_assess(jsonb,text,jsonb,jsonb)',
      'deterministic_elapsed_ms',v_m82_deterministic_ms,
      'semantic_resolver',v_resolver_oid::regprocedure::text,
      'semantic_elapsed_ms',v_m82_semantic_ms,
      'measurement_method','CLOCK_TIMESTAMP_OBSERVED',
      'semantic_sha_excluded',true
    ))
  )::text,true);
  return new;
end
$function$;
