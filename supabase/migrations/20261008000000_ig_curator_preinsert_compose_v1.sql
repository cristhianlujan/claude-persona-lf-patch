-- IG M7.10 EKB IG-CURATOR-POSTINSERT-IMMUTABLE-COLLISION-001.
-- Core + semantic before immutable INSERT; no bypass of 5.13.
do $guard$
begin
 if md5((select prosrc from pg_proc where oid='programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)'::regprocedure))
   <> 'a8a242158d6b6b9647ae3468a16bed0f' then
   raise exception 'IG_M710_CURATOR_SOURCE_DRIFT';
 end if;
end $guard$;

create or replace function programacion.fn_input_curator_compose_before_insert_v1()
returns trigger language plpgsql security definer
set search_path='pg_catalog','programacion','public'
as $fn$
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
  v_core_result:=programacion.fn_input_deterministic_assess(
    (to_jsonb(new)-'id'-'run_id'-'family_code') ||
      jsonb_build_object('pantalla_id',v_run.pantalla_id,'version_id',v_run.version_id,'source_class','DETERMINISTIC'),
    new.family_code,v_ctx->'graph',v_core_contract);
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
  execute format('select %s($1,$2,$3)',v_resolver_oid::regproc)
    using v_run.pantalla_id,new.family_code,v_run.version_id into v_probe;
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
  return new;
end
$fn$;
revoke all on function programacion.fn_input_curator_compose_before_insert_v1() from public,anon,authenticated,service_role;
drop trigger if exists trg_input_family_assessment_00a_preinsert_composition
  on programacion.input_family_assessments;
create trigger trg_input_family_assessment_00a_preinsert_composition
before insert on programacion.input_family_assessments
for each row execute function programacion.fn_input_curator_compose_before_insert_v1();

do $delta_guard$
begin
 if md5((select prosrc from pg_proc where oid='programacion.fn_input_governance_curator_plan_v1(integer,boolean,bigint)'::regprocedure))
     <> '2cfa1bcb2e35b6290bd0f83be040ea82'
 or md5((select prosrc from pg_proc where oid='programacion.fn_input_governance_recurate_source_stale_v1(integer,text,text,bigint)'::regprocedure))
     <> '9f289a5611e471f7e77fe7fa5dc7c546' then
   raise exception 'IG_M710_FRESHNESS_PLAN_WRITER_SOURCE_DRIFT';
 end if;
end $delta_guard$;
CREATE OR REPLACE FUNCTION programacion.fn_input_governance_curator_plan_v1(p_pantalla_id integer, p_force_selftest boolean DEFAULT false, p_completed_run_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'public'
AS $function$
declare
  v_completed bigint;
  v_scope jsonb;
  v_mode text;
  v_delta jsonb;
  v_changed_sources integer:=0;
  v_affected_families integer:=0;
  v_successor_required boolean:=false;
  v_resolution_errors integer:=0;
  v_run_state text;
  v_current boolean:=false;
  v_strategy text;
  v_reason text;
begin
  if p_completed_run_id is not null then
    select id,scope
      into v_completed,v_scope
    from programacion.input_readiness_runs
    where id=p_completed_run_id
      and pantalla_id=p_pantalla_id
      and status='COMPLETED'
      and version_id=public.fn_lf_version_compatibility_current_version_id_v1(
        'PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT'
      );
  else
    select id,scope
      into v_completed,v_scope
    from programacion.input_readiness_runs
    where version_id=public.fn_lf_version_compatibility_current_version_id_v1(
            'PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT'
          )
      and pantalla_id=p_pantalla_id
      and status='COMPLETED'
    order by id desc
    limit 1;
  end if;

  if v_completed is null then
    return jsonb_build_object(
      'schema_version','INPUT_GOVERNANCE_CURATOR_STRATEGY_PLAN_V1',
      'strategy','BOOTSTRAP',
      'reason','NO_COMPLETED_RUN',
      'completed_run_id',null,
      'write_performed',false
    );
  end if;

  if p_force_selftest then
    return jsonb_build_object(
      'schema_version','INPUT_GOVERNANCE_CURATOR_STRATEGY_PLAN_V1',
      'strategy','REBIND',
      'reason','FORCE_SELFTEST',
      'completed_run_id',v_completed,
      'write_performed',false
    );
  end if;

  v_mode:=coalesce(v_scope->>'mode','');
  if v_mode not in (
    'GOVERNED_CANONICAL_BOOTSTRAP_V1',
    'RUNTIME_GOVERNED_RECURATION_V2',
    'RUNTIME_ASSERTION_REBIND_SAFE_SUCCESSOR_V1'
  ) then
    return jsonb_build_object(
      'schema_version','INPUT_GOVERNANCE_CURATOR_STRATEGY_PLAN_V1',
      'strategy','BLOCK',
      'reason','AMBIGUOUS_OR_UNSUPPORTED_SCOPE_MODE',
      'completed_run_id',v_completed,
      'scope_mode',v_mode,
      'write_performed',false
    );
  end if;

  v_delta:=programacion.fn_input_freshness_delta(v_completed);
  -- Reuse exact plan delta for the selected writer; the request identity is checked downstream.
  if nullif(current_setting('lf.input_request_context_v1',true),'') is not null then
    perform set_config('lf.input_request_freshness_delta_cached_v1',
      jsonb_build_object('run_id',v_completed,'pantalla_id',p_pantalla_id,'delta',v_delta)::text,true);
  end if;
  v_run_state:=coalesce(v_delta->>'run_state','');
  v_changed_sources:=coalesce((v_delta#>>'{summary,changed_source_count}')::integer,0);
  v_affected_families:=coalesce((v_delta#>>'{summary,affected_family_count}')::integer,0);
  v_successor_required:=coalesce((v_delta#>>'{summary,use_successor_required}')::boolean,false);

  select count(*)
    into v_resolution_errors
  from jsonb_array_elements(coalesce(v_delta->'source_changes','[]'::jsonb)) x(value)
  where x.value->>'state'='RESOLUTION_ERROR';

  if v_resolution_errors>0 then
    v_strategy:='BLOCK';
    v_reason:='SOURCE_RESOLUTION_ERROR';
  elsif v_run_state='STALE' then
    if v_changed_sources<=0 then
      v_strategy:='BLOCK';
      v_reason:='AMBIGUOUS_STALE_WITHOUT_CHANGED_SOURCE';
    elsif v_successor_required then
      v_strategy:='FULL_RECURATE';
      v_reason:='STALE_SUCCESSOR_REQUIRED';
    elsif v_affected_families=0 then
      v_strategy:='REBIND';
      v_reason:='STALE_NON_SEMANTIC_SOURCE_CHANGE';
    else
      v_strategy:='SOURCE_STALE_RECURATE';
      v_reason:='STALE_AFFECTED_FAMILIES';
    end if;
  elsif v_run_state='CURRENT' then
    v_current:=programacion.fn_input_readiness_run_is_current_cached_v1(v_completed);
    if v_current then
      v_strategy:='NOOP';
      v_reason:='COMPLETED_RUN_CURRENT';
    else
      v_strategy:='FULL_RECURATE';
      v_reason:='CURRENT_FRESHNESS_BUT_AUTHORITY_NOT_CURRENT';
    end if;
  else
    v_strategy:='BLOCK';
    v_reason:='AMBIGUOUS_RUN_STATE';
  end if;

  return jsonb_build_object(
    'schema_version','INPUT_GOVERNANCE_CURATOR_STRATEGY_PLAN_V1',
    'strategy',v_strategy,
    'reason',v_reason,
    'completed_run_id',v_completed,
    'scope_mode',v_mode,
    'run_state',v_run_state,
    'changed_source_count',v_changed_sources,
    'affected_family_count',v_affected_families,
    'successor_required',v_successor_required,
    'resolution_error_count',v_resolution_errors,
    'run_current',v_current,
    'write_performed',false
  );
end;
$function$;

CREATE OR REPLACE FUNCTION programacion.fn_input_governance_recurate_source_stale_v1(p_pantalla_id integer, p_consumer text, p_curator_identity text, p_parent_run_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'programacion', 'lf_ops', 'transversal'
AS $function$
declare
  v_version bigint:=public.fn_lf_version_compatibility_current_version_id_v1('PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT');
  v_parent programacion.input_readiness_runs%rowtype; v_contract_schema integer; v_contract_revision text; v_curator_component bigint; v_new bigint; v_family text; v_class jsonb; v_count integer; v_exec_id text:=gen_random_uuid()::text; v_prop jsonb; v_payload jsonb; v_delta jsonb; v_changed integer:=0; v_affected integer:=0; v_successor_required boolean:=false; v_resolution_errors integer:=0; v_graph jsonb;
  v_freshness jsonb; v_evidence jsonb; v_subject jsonb; v_threat jsonb; v_semantic_sha text; v_curator_sha text;
begin
  perform pg_advisory_xact_lock(hashtextextended('LF_INPUT_GOVERNANCE_RUN_PAIR:'||v_version::text||':'||p_pantalla_id::text,0));
  if p_curator_identity !~ '^INPUT_CURATOR:EDGE:input-governance-curator-v1:[A-Za-z0-9_-]{6,128}$' then raise exception 'INPUT_GOVERNANCE_CURATOR_RUNTIME_IDENTITY_INVALID'; end if;
  if not exists(select 1 from jsonb_array_elements_text((select especificacion->'allowed_consumers' from programacion.contratos where version_id=v_version and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT')) x(v) where x.v=p_consumer) then raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>'); end if;
  select * into v_parent from programacion.input_readiness_runs where id=p_parent_run_id and version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED' and invalidated_at is null;
  if not found then raise exception 'INPUT_SOURCE_STALE_RECURATION_PARENT_INVALID:%',p_parent_run_id; end if;
  if p_parent_run_id is distinct from (select id from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED' order by id desc limit 1) then raise exception 'INPUT_SOURCE_STALE_RECURATION_PARENT_NOT_LATEST:%',p_parent_run_id; end if;
  v_delta:=case
    when (nullif(current_setting('lf.input_request_freshness_delta_cached_v1',true),'')::jsonb->>'run_id')::bigint
         is not distinct from p_parent_run_id
     and (nullif(current_setting('lf.input_request_freshness_delta_cached_v1',true),'')::jsonb->>'pantalla_id')::integer
         is not distinct from p_pantalla_id
    then nullif(current_setting('lf.input_request_freshness_delta_cached_v1',true),'')::jsonb->'delta'
    else programacion.fn_input_freshness_delta(p_parent_run_id) end; v_changed:=coalesce((v_delta#>>'{summary,changed_source_count}')::integer,0); v_affected:=coalesce((v_delta#>>'{summary,affected_family_count}')::integer,0); v_successor_required:=coalesce((v_delta#>>'{summary,use_successor_required}')::boolean,false);
  select count(*) into v_resolution_errors from jsonb_array_elements(coalesce(v_delta->'source_changes','[]'::jsonb)) x(value) where x.value->>'state'='RESOLUTION_ERROR';
  if v_delta->>'run_state'<>'STALE' or v_changed<=0 or v_affected<=0 or v_successor_required or v_resolution_errors<>0 then raise exception 'INPUT_SOURCE_STALE_RECURATION_PROOF_INVALID:run=% summary=%',p_parent_run_id,v_delta->'summary'; end if;
  select (especificacion->>'schema_version')::integer,especificacion->>'contract_revision' into v_contract_schema,v_contract_revision from programacion.contratos where version_id=v_version and contrato_codigo='INPUT_READINESS_CONTRACT' and estado='defined' and fail_closed;
  if v_contract_revision is null then raise exception 'INPUT_RECURATION_CONTRACT_REVISION_UNSUPPORTED:%',v_contract_revision; end if;
  select id into v_curator_component from programacion.componentes where version_id=v_version and componente_codigo='INPUT_CURATOR'; if v_curator_component is null then raise exception 'INPUT_CURATOR_COMPONENT_UNRESOLVED'; end if;
  v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,v_version);
  insert into programacion.input_readiness_runs(version_id,pantalla_id,universe_rule_id,supersedes_run_id,status,scope,universe_snapshot_sha256,family_count,contract_version,curator_identity,curator_component_id)
  values(v_parent.version_id,v_parent.pantalla_id,v_parent.universe_rule_id,v_parent.id,'CURATING',v_parent.scope || jsonb_build_object('mode','RUNTIME_GOVERNED_RECURATION_V2','parent_run_id',v_parent.id,'reason','SOURCE_STALE_RECURATION','successor_strategy','REBUILD_CHANGED_SOURCES','analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','remediation_decision','DEC-INPUT-GOV-SELF-REMEDIATE-001','remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','runtime','input-governance-curator-v1','source_stale_proof','INPUT_FRESHNESS_DELTA_V1','source_stale_affected_family_count',v_affected,'classifier_mode','CACHED_CANONICAL_GRAPH_EQUIVALENT','promotion_authorized',false,'production_authorized',false),v_parent.universe_snapshot_sha256,v_parent.family_count,v_contract_schema,p_curator_identity,v_curator_component) returning id into v_new;
  for v_family in select value from jsonb_array_elements_text((select valor_config->'families' from lf_ops.reglas where codigo='B2B-RULE-STORY-READINESS-001')) loop
    v_class:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(p_pantalla_id,v_family,v_version,v_graph);
    v_freshness:=jsonb_build_object('mode','DB_MANIFEST_V'||v_contract_schema::text,'status','PENDING_RUN_SNAPSHOT');
    v_subject:=case when v_family in ('DESIGN_SYSTEM','SECURITY') then programacion.fn_input_subject_depth_expected(p_pantalla_id,v_family) else '[]'::jsonb end;
    v_threat:=case when v_family='SECURITY' then programacion.fn_input_security_threat_expected(p_pantalla_id) else '[]'::jsonb end;
    v_semantic_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object('family_code',v_family,'subject_coverage',v_subject,'threat_coverage',v_threat));
    v_evidence:=jsonb_build_object('component_id',v_curator_component,'execution_id',v_exec_id,'execution_mode','INDEPENDENT_CURATOR','runtime','SUPABASE_EDGE_FUNCTION:input-governance-curator-v1','contract_revision',v_contract_revision,'parent_run_id',v_parent.id,'direct_source_readback',true,'semantic_policy','GOVERNED_RECURATION_FROM_CANONICAL_SOURCES','remediation_decision','DEC-INPUT-GOV-SELF-REMEDIATE-001','analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','bootstrap_classifier_sha256',v_class->>'classifier_sha256','bootstrap_probe',v_class->'probe','source_stale_proof','INPUT_FRESHNESS_DELTA_V1','classifier_mode','CACHED_CANONICAL_GRAPH_EQUIVALENT','semantic_depth_sha256',v_semantic_sha);
    v_curator_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object('run_id',v_new,'family_code',v_family,'severity',v_class->>'severity','applicability',v_class->>'applicability','coverage_status',v_class->>'coverage_status','well_defined_status',v_class->>'well_defined_status','story_ready_status',v_class->>'story_ready_status','implementation_ready_status',v_class->>'implementation_ready_status','qa_ready_status',v_class->>'qa_ready_status','production_ready_status',v_class->>'production_ready_status','source_refs',v_class->'source_refs','rationale',v_class->>'rationale','blockers',v_class->'blockers','negative_requirements',v_class->'negative_requirements','test_obligations',v_class->'test_obligations','freshness',v_freshness,'curator_evidence',v_evidence,'subject_coverage',v_subject,'threat_coverage',v_threat,'semantic_depth_sha256',v_semantic_sha));
    insert into programacion.input_family_assessments(run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,source_refs,rationale,blockers,negative_requirements,test_obligations,freshness,curator_evidence,curator_sha256,validator_outcome,validator_findings,validator_evidence,validator_identity,validator_sha256,validator_assessed_at,subject_coverage,threat_coverage,semantic_depth_sha256)
    values(v_new,v_family,v_class->>'severity',v_class->>'applicability',v_class->>'coverage_status',v_class->>'well_defined_status',v_class->>'story_ready_status',v_class->>'implementation_ready_status',v_class->>'qa_ready_status',v_class->>'production_ready_status',v_class->'source_refs',v_class->>'rationale',v_class->'blockers',v_class->'negative_requirements',v_class->'test_obligations',v_freshness,v_evidence,v_curator_sha,'PENDING','[]'::jsonb,'{}'::jsonb,null,null,null,v_subject,v_threat,v_semantic_sha);
  end loop;
  select count(*) into v_count from programacion.input_family_assessments where run_id=v_new; if v_count<>47 then raise exception 'INPUT_RECURATION_UNIVERSE_INCOMPLETE expected=47 actual=%',v_count; end if;
  v_prop:=programacion.fn_input_governance_materialize_gap_proposals_v1(v_new);
  v_payload:=jsonb_build_object('status','VALIDATOR_RUNTIME_REQUIRED','run_id',v_new,'parent_run_id',v_parent.id,'pantalla_id',p_pantalla_id,'family_count',47,'required_role','INPUT_VALIDATOR','analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','proposal_materialization',v_prop,'source_stale_proof','INPUT_FRESHNESS_DELTA_V1','affected_family_count',v_affected,'promotion_authorized',false,'production_authorized',false);
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;

CREATE OR REPLACE FUNCTION programacion.fn_input_governance_curator_materialize_v1(p_pantalla_id integer, p_consumer text, p_curator_identity text, p_force_selftest boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'public'
AS $function$
declare
  v_plan jsonb;
  v_strategy text;
  v_completed bigint;
  v_version bigint;
  v_source_snapshot_sha256 text;
  v_source_manifest jsonb:='[]'::jsonb;
  v_contract_registry jsonb:='[]'::jsonb;
  v_graph jsonb;
  v_context jsonb;
  v_result jsonb;
  v_graph_build_count integer;
  v_core_contract jsonb;
  v_core_run_id bigint;
  v_core_assessment record;
  v_core_result jsonb;
  v_core_invocation_count integer:=0;
  v_semantic_registry jsonb;
  v_semantic_registry_sha text;
  v_semantic_policy jsonb;
  v_semantic_resolver text;
  v_m54_semantic_resolver_oid oid;
  v_semantic_probe jsonb;
  v_semantic_eligibility text;
  v_semantic_execution_state text;
  v_semantic_plan_count integer:=0;
  v_selector_version text;
  v_selector_manifest_sha text;
  v_freshness_count integer;
begin
  perform set_config('lf.input_request_freshness_delta_cached_v1','',true);
  perform set_config('lf.input_request_graph_build_count_v1','0',true);
  perform set_config('lf.input_request_freshness_count_v1','0',true);
  select c.version_id into v_version
  from programacion.contratos c
  join programacion.versiones_agente v on v.id=c.version_id
  join programacion.agentes a on a.id=v.agente_id
  where a.agente_codigo='INPUT_GOVERNANCE_AGENT'
    and c.contrato_codigo='INPUT_READINESS_CONTRACT'
    and c.estado='defined' and c.fail_closed
  order by c.version_id desc,c.id desc limit 1;
  if v_version is null then
    raise exception 'INPUT_REQUEST_CONTEXT_VERSION_UNRESOLVED:%',p_pantalla_id;
  end if;
  v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,v_version);
  v_context:=jsonb_build_object(
    'schema_version','INPUT_GOVERNANCE_REQUEST_CONTEXT_V1',
    'pantalla_id',p_pantalla_id,
    'version_id',v_version,
    'consumer',p_consumer,
    'request_identity',p_curator_identity,
    'strategy',null,
    'completed_run_id',null,
    'graph',v_graph,
    'graph_sha256',programacion.fn_v09_sha256_jsonb(v_graph),
    'contract_registry','[]'::jsonb,
    'source_snapshot_sha256',null,
    'source_manifest','[]'::jsonb
  );
  perform set_config('lf.input_request_context_v1',v_context::text,true);
  v_plan:=programacion.fn_input_governance_curator_plan_v1(
    p_pantalla_id,p_force_selftest,null
  );
  v_strategy:=v_plan->>'strategy';
  v_completed:=nullif(v_plan->>'completed_run_id','')::bigint;

  if v_completed is not null then
    select r.source_snapshot_sha256,coalesce(r.source_manifest,'[]'::jsonb)
      into v_source_snapshot_sha256,v_source_manifest
    from programacion.input_readiness_runs r
    where r.id=v_completed and r.pantalla_id=p_pantalla_id and r.version_id=v_version;
    if not found then
      raise exception 'INPUT_REQUEST_CONTEXT_RUN_IDENTITY_MISMATCH:%:%',p_pantalla_id,v_completed;
    end if;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
      'id',c.id,
      'contract_code',c.contrato_codigo,
      'status',c.estado,
      'fail_closed',c.fail_closed
    ) order by c.contrato_codigo,c.id),'[]'::jsonb)
    into v_contract_registry
  from programacion.contratos c
  where c.version_id=v_version
    and c.contrato_codigo in (
      'INPUT_READINESS_CONTRACT',
      'INPUT_GOVERNANCE_EXECUTION_CONTRACT',
      'INPUT_CONTEXT_MANIFEST_CONTRACT',
      'INPUT_FRESHNESS_DELTA_CONTRACT',
      'INPUT_RETRIEVAL_HANDLE_CONTRACT',
      'INPUT_FAMILY_POLICY_REGISTRY'
    );

  v_context:=v_context || jsonb_build_object(
    'strategy',v_strategy,
    'completed_run_id',v_completed,
    'contract_registry',v_contract_registry,
    'source_snapshot_sha256',v_source_snapshot_sha256,
    'source_manifest',v_source_manifest
  );
  perform set_config('lf.input_request_context_v1',v_context::text,true);

  case v_strategy
    when 'BOOTSTRAP' then
      v_result:=programacion.fn_input_governance_bootstrap_materialize_v2(
        p_pantalla_id,p_consumer,p_curator_identity
      );
    when 'REBIND' then
      v_result:=programacion.fn_input_governance_curator_rebind_v1(
        p_pantalla_id,p_consumer,p_curator_identity,p_force_selftest
      );
    when 'SOURCE_STALE_RECURATE' then
      v_result:=programacion.fn_input_governance_recurate_source_stale_v1(
        p_pantalla_id,p_consumer,p_curator_identity,v_completed
      );
    when 'FULL_RECURATE' then
      v_result:=programacion.fn_input_governance_recurate_v2(
        p_pantalla_id,p_consumer,p_curator_identity
      );
    when 'NOOP' then
      v_result:=jsonb_build_object(
        'schema_version','INPUT_GOVERNANCE_CURATOR_EXECUTION_V1',
        'status','NOOP_CURRENT_RUN',
        'strategy','NOOP',
        'run_id',v_completed,
        'pantalla_id',p_pantalla_id,
        'consumer',p_consumer,
        'write_performed',false,
        'strategy_plan',v_plan,
        'promotion_authorized',false,
        'production_authorized',false
      );
    when 'BLOCK' then
      v_result:=jsonb_build_object(
        'schema_version','INPUT_GOVERNANCE_CURATOR_EXECUTION_V1',
        'status','BLOCKED',
        'strategy','BLOCK',
        'blocker','CURATOR_STRATEGY_PLAN_BLOCKED',
        'pantalla_id',p_pantalla_id,
        'consumer',p_consumer,
        'write_performed',false,
        'strategy_plan',v_plan,
        'promotion_authorized',false,
        'production_authorized',false
      );
    else
      raise exception 'INPUT_GOVERNANCE_CURATOR_STRATEGY_UNSUPPORTED:%',coalesce(v_strategy,'<NULL>');
  end case;
  v_core_run_id:=nullif(v_result->>'run_id','')::bigint;
  if v_strategy in ('BOOTSTRAP','REBIND','SOURCE_STALE_RECURATE','FULL_RECURATE') then
    if v_core_run_id is null then
      raise exception 'M5_6_PERSISTENCE_PIPELINE_RUN_ID_MISSING:%',v_strategy;
    end if;
    if not exists (select 1 from programacion.input_readiness_runs r where r.id=v_core_run_id and r.pantalla_id=p_pantalla_id) then
      raise exception 'M5_6_PERSISTENCE_PIPELINE_RUN_READBACK_MISSING:%:%',v_strategy,v_core_run_id;
    end if;
    if (select count(*) from programacion.input_family_assessments a where a.run_id=v_core_run_id)=0 then
      raise exception 'M5_6_PERSISTENCE_PIPELINE_ASSESSMENTS_MISSING:%:%',v_strategy,v_core_run_id;
    end if;
    v_result:=v_result || jsonb_build_object(
      'persistence_pipeline_receipt',jsonb_build_object(
        'schema_version','INPUT_GOVERNANCE_PERSISTENCE_PIPELINE_RECEIPT_V1',
        'entrypoint','programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)',
        'strategy',v_strategy,
        'strategy_writer',case v_strategy
          when 'BOOTSTRAP' then 'programacion.fn_input_governance_bootstrap_materialize_v2(integer,text,text)'
          when 'REBIND' then 'programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)'
          when 'SOURCE_STALE_RECURATE' then 'programacion.fn_input_governance_recurate_source_stale_v1(integer,text,text,bigint)'
          when 'FULL_RECURATE' then 'programacion.fn_input_governance_recurate_v2(integer,text,text)' end,
        'run_id',v_core_run_id,
        'run_count',(select count(*) from programacion.input_readiness_runs r where r.id=v_core_run_id),
        'assessment_count',(select count(*) from programacion.input_family_assessments a where a.run_id=v_core_run_id),
        'gap_proposal_count',(select count(*) from programacion.input_gap_proposals g where g.run_id=v_core_run_id),
        'receipt_mode','RETURN_ENVELOPE_READBACK',
        'strategy_functions_fused',false,
        'promotion_authorized',false,
        'production_authorized',false
      )
    );
  end if;
  -- M7.10/EKB: the actual Core and semantic plan are now composed and SHA-bound
  -- in BEFORE INSERT. Contract 5.13 forbids post-INSERT Curator-owned mutations.
  -- NOOP reuses the previously completed run without a write.
  if v_strategy in ('BOOTSTRAP','REBIND','SOURCE_STALE_RECURATE','FULL_RECURATE') then
    select count(*),
           count(*) filter (where a.curator_evidence->'core_invocation'->>'contract'='M5_4_DETERMINISTIC_ASSESS_BRIDGE_V1'),
           count(*) filter (where a.curator_evidence->'semantic_plan'->>'contract'='M5_4_SEMANTIC_PLAN_V1')
      into v_core_invocation_count, v_semantic_plan_count, v_graph_build_count
    from programacion.input_family_assessments a
    where a.run_id=v_core_run_id;
    if v_core_invocation_count=0 or v_semantic_plan_count<>v_core_invocation_count
       or v_graph_build_count<>v_core_invocation_count then
      raise exception 'IG_PREINSERT_CORE_SEMANTIC_COMPOSITION_MISSING:run=% total=% core=% semantic=%',
        v_core_run_id,v_core_invocation_count,v_semantic_plan_count,v_graph_build_count;
    end if;
    v_result:=v_result || jsonb_build_object(
      'core_invocation',jsonb_build_object(
        'contract','M5_4_DETERMINISTIC_ASSESS_BRIDGE_V1',
        'semantic_plan_contract','M5_4_SEMANTIC_PLAN_V1',
        'facade','programacion.fn_input_deterministic_assess',
        'assessment_count',v_core_invocation_count,
        'semantic_plan_count',v_graph_build_count,
        'composition_timing','BEFORE_IMMUTABLE_INSERT',
        'legacy_seed_removal_checkpoint','NEGATIVE_NO_CLASSIFY'
      )
    );
  end if;
  v_graph_build_count:=coalesce(nullif(current_setting('lf.input_request_graph_build_count_v1',true),'')::integer,0);
  v_freshness_count:=coalesce(nullif(current_setting('lf.input_request_freshness_count_v1',true),'')::integer,0);
  if v_graph_build_count<>1 then
    raise exception 'INPUT_REQUEST_GRAPH_BUILD_COUNT_INVALID:%:%',p_pantalla_id,v_graph_build_count;
  end if;
  if v_freshness_count>1 then
    raise exception 'INPUT_REQUEST_FRESHNESS_COUNT_INVALID:%:%',p_pantalla_id,v_freshness_count;
  end if;
  perform set_config('lf.input_request_freshness_delta_cached_v1','',true);
  perform set_config('lf.input_request_context_v1','',true);
  perform set_config('lf.input_request_graph_build_count_v1','',true);
  perform set_config('lf.input_request_freshness_count_v1','',true);
  return v_result || jsonb_build_object(
    'request_context_summary',jsonb_build_object(
      'schema_version','INPUT_GOVERNANCE_REQUEST_CONTEXT_V1',
      'graph_build_count',v_graph_build_count,
      'freshness_delta_count',v_freshness_count,
      'graph_build_exactly_once',v_graph_build_count=1,
      'freshness_at_most_once',v_freshness_count<=1,
      'pantalla_id',p_pantalla_id,
      'version_id',v_version,
      'graph_sha256',v_context->>'graph_sha256',
      'context_sha256',programacion.fn_v09_sha256_jsonb(v_context)
    )
  );
exception when others then
  perform set_config('lf.input_request_freshness_delta_cached_v1','',true);
  perform set_config('lf.input_request_context_v1','',true);
  perform set_config('lf.input_request_graph_build_count_v1','',true);
  perform set_config('lf.input_request_freshness_count_v1','',true);
  raise;
end;
$function$;

comment on function programacion.fn_input_curator_compose_before_insert_v1() is
'EKB IG-CURATOR-POSTINSERT-IMMUTABLE-COLLISION-001. BEFORE INSERT M5.4 composition, exact request context; retains 5.13 guard and immutable evidence SHA.';
do $verify$
begin
 if position('update programacion.input_family_assessments' in lower(pg_get_functiondef(
  'programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)'::regprocedure)))>0 then
   raise exception 'IG_M710_POSTINSERT_CURATOR_MUTATION_REMAINS';
 end if;
 if position('CURATOR_FIELDS_IMMUTABLE' in pg_get_functiondef(
   'programacion.fn_guard_input_family_assessment_update()'::regprocedure))=0 then
   raise exception 'IG_M710_IMMUTABILITY_GUARD_UNEXPECTEDLY_MISSING';
 end if;
 if not exists(select 1 from pg_trigger where tgname='trg_input_family_assessment_00a_preinsert_composition'
 and tgrelid='programacion.input_family_assessments'::regclass and not tgisinternal) then
   raise exception 'IG_M710_PREINSERT_TRIGGER_MISSING';
 end if;
end $verify$;