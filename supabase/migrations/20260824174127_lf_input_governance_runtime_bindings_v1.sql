-- Bind INPUT_GOVERNANCE execution contract to separate Edge runtimes.
update programacion.contratos
set especificacion=especificacion||jsonb_build_object(
  'contract_revision','1.2',
  'runtime_decision','DEC-INPUT-GOV-RUNTIME-001',
  'runtime_orchestrator','SUPABASE_EDGE_FUNCTION:input-governance-agent-v1',
  'curator_runtime','SUPABASE_EDGE_FUNCTION:input-governance-curator-v1',
  'validator_runtime','SUPABASE_EDGE_FUNCTION:input-governance-validator-v1',
  'automatic_successor_policy','ASSERTION_REBIND_SAFE_SUCCESSOR_ONLY',
  'new_screen_policy','BOOTSTRAP_SEMANTIC_PROFILE_REQUIRED_FAIL_CLOSED',
  'semantic_provider','NO_UNGOVERNED_EXTERNAL_LLM',
  'promotion_authorized',false,
  'production_authorized',false
)
where version_id=19 and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT' and estado='defined';

create or replace function programacion.fn_input_governance_worker_spec(p_pantalla_id integer,p_consumer text default 'STORY_CREATOR')
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','public','programacion','lf_ops'
as $function$
declare
  v_exec jsonb; v_version bigint; v_code text; v_active boolean; v_latest bigint; v_latest_status text; v_current bigint;
  v_role text; v_reason text; v_rev text; v_sha text; v_payload jsonb; v_count integer:=0; v_expected integer:=0;
begin
  select c.version_id,c.especificacion into v_version,v_exec
  from programacion.contratos c
  join programacion.versiones_agente v on v.id=c.version_id
  join programacion.agentes a on a.id=v.agente_id
  where a.agente_codigo='INPUT_GOVERNANCE_AGENT'
    and c.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
    and c.estado='defined' and c.fail_closed
  order by c.version_id desc limit 1;
  if v_exec is null then raise exception 'INPUT_GOVERNANCE_EXECUTION_CONTRACT_NOT_RESOLVABLE'; end if;
  if not exists(select 1 from jsonb_array_elements_text(v_exec->'allowed_consumers') x(v) where x.v=p_consumer) then
    raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>');
  end if;

  select codigo,activa into v_code,v_active from lf_ops.pantallas where id=p_pantalla_id;
  if v_code is null then raise exception 'INPUT_GOVERNANCE_SCREEN_NOT_FOUND:%',p_pantalla_id; end if;
  if not v_active then raise exception 'INPUT_GOVERNANCE_SCREEN_INACTIVE:%',v_code; end if;

  select id,status,family_count into v_latest,v_latest_status,v_expected
  from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id order by id desc limit 1;
  select id into v_current
  from programacion.input_readiness_runs
  where version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED' and invalidated_at is null
    and programacion.fn_input_readiness_run_is_current(id)
  order by id desc limit 1;
  if v_latest is not null then select count(*) into v_count from programacion.input_family_assessments where run_id=v_latest; end if;

  if v_current is not null then
    v_role:='NONE'; v_reason:='CURRENT_COMPLETED_RUN_AVAILABLE';
  elsif v_latest_status='VALIDATING' or (v_latest_status='CURATING' and v_expected>0 and v_count=v_expected) then
    v_role:='INPUT_VALIDATOR';
    v_reason:=case when v_latest_status='VALIDATING' then 'VALIDATION_PHASE_INCOMPLETE' else 'CURATION_MATERIALIZED_VALIDATION_NOT_OPEN' end;
  else
    v_role:='INPUT_CURATOR';
    v_reason:=case when v_latest is null then 'NO_PRIOR_RUN' else 'NO_CURRENT_COMPLETED_RUN' end;
  end if;

  select c.especificacion->>'contract_revision',
         programacion.fn_v09_sha256_jsonb(jsonb_build_object('id',c.id,'version_id',c.version_id,'contrato_codigo',c.contrato_codigo,'fail_closed',c.fail_closed,'estado',c.estado,'especificacion',c.especificacion))
  into v_rev,v_sha
  from programacion.contratos c
  where c.version_id=v_version and c.contrato_codigo='INPUT_READINESS_CONTRACT' and c.estado='defined' and c.fail_closed;

  v_payload:=jsonb_build_object(
    'schema_version',1,'worker_contract','INPUT_GOVERNANCE_WORKER_SPEC_V1','agent_code','INPUT_GOVERNANCE_AGENT',
    'version_id',v_version,'pantalla_id',p_pantalla_id,'screen_code',v_code,'consumer',p_consumer,
    'required_role',v_role,'role_reason',v_reason,'latest_run_id',v_latest,'latest_run_status',v_latest_status,'current_run_id',v_current,
    'readiness_contract_revision',v_rev,'readiness_contract_sha256',v_sha,
    'family_universe_ref',jsonb_build_object('kind','RULE','codigo','B2B-RULE-STORY-READINESS-001','expected_family_count',47),
    'source_precedence',jsonb_build_array('lf_ops','lf_design','transversal','programacion'),
    'retrieval_plan',jsonb_build_array('SCREEN','SCREEN_RULE_SET','SCREEN_STATE_SET','SCREEN_CANONICAL_GRAPH','DESIGN_BINDING_GRAPH_V2','API_CONTRACT_RESOLUTION_V1','EKB_DECISION_SET','EKB_PREVENTION_SET'),
    'context_policy','REFERENCE_PLUS_JIT_MINIMUM_SUFFICIENT_CONTEXT','ekb_checkpoints',v_exec->'ekb_checkpoints',
    'curator_requirements',jsonb_build_object('direct_source_readback',true,'no_invention',true,'proposal_is_canonical_source',false,'family_count',47,'automatic_policy','ASSERTION_REBIND_SAFE_SUCCESSOR_ONLY'),
    'validator_requirements',jsonb_build_object('separate_execution',true,'direct_source_readback',true,'deterministic_checks_first',true,'semantic_validation_required',true,'candidate_as_own_authority',false),
    'runtime_binding_status',case when v_role='NONE' then 'NOT_REQUIRED_CURRENT_RUN' else 'BOUND_RUNTIME' end,
    'runtime_binding',case when v_role='INPUT_CURATOR' then 'SUPABASE_EDGE_FUNCTION:input-governance-curator-v1' when v_role='INPUT_VALIDATOR' then 'SUPABASE_EDGE_FUNCTION:input-governance-validator-v1' else 'NONE' end,
    'runtime_orchestrator','SUPABASE_EDGE_FUNCTION:input-governance-agent-v1',
    'runtime_action',case when v_role='NONE' then 'REUSE_CURRENT_RUN' when v_role='INPUT_VALIDATOR' then 'CALL_VALIDATOR_RUNTIME' else 'CALL_CURATOR_RUNTIME' end,
    'new_screen_policy','BOOTSTRAP_SEMANTIC_PROFILE_REQUIRED_FAIL_CLOSED','auto_canonicalization','DENY',
    'promotion_authorized',false,'production_authorized',false,'generated_at',now()
  );
  return v_payload||jsonb_build_object('worker_spec_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;

create or replace function programacion.fn_input_governance_execute(p_pantalla_id integer,p_consumer text default 'STORY_CREATOR')
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','public','programacion','lf_ops'
as $function$
declare
  v_contract jsonb; v_version bigint; v_code text; v_active boolean; v_run bigint; v_latest bigint; v_family integer;
  v_assessed integer; v_pass integer; v_bad integer; v_human integer; v_status text;
  v_pre jsonb; v_cur jsonb; v_val jsonb; v_story jsonb; v_ctx jsonb; v_close jsonb;
  v_stage jsonb; v_prop jsonb; v_manifest jsonb; v_payload jsonb; v_worker jsonb; v_fresh jsonb; v_summary jsonb;
begin
  select c.version_id,c.especificacion into v_version,v_contract
  from programacion.contratos c
  join programacion.versiones_agente v on v.id=c.version_id
  join programacion.agentes a on a.id=v.agente_id
  where a.agente_codigo='INPUT_GOVERNANCE_AGENT'
    and c.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
    and c.estado='defined' and c.fail_closed
  order by c.version_id desc limit 1;
  if v_contract is null then raise exception 'INPUT_GOVERNANCE_EXECUTION_CONTRACT_NOT_RESOLVABLE'; end if;
  if not exists(select 1 from jsonb_array_elements_text(v_contract->'allowed_consumers') x(v) where x.v=p_consumer) then
    raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>');
  end if;
  select codigo,activa into v_code,v_active from lf_ops.pantallas where id=p_pantalla_id;
  if v_code is null then raise exception 'INPUT_GOVERNANCE_SCREEN_NOT_FOUND:%',p_pantalla_id; end if;
  if not v_active then raise exception 'INPUT_GOVERNANCE_SCREEN_INACTIVE:%',v_code; end if;

  v_pre:=programacion.fn_input_governance_ekb_checkpoint('PRE_EXECUTION',p_pantalla_id,null);
  if not (v_pre->>'pass')::boolean then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_EXECUTION:%',v_pre->'unhandled_high_critical_codes'; end if;

  select id,family_count into v_run,v_family
  from programacion.input_readiness_runs r
  where r.version_id=v_version and r.pantalla_id=p_pantalla_id and r.status='COMPLETED' and r.invalidated_at is null
    and programacion.fn_input_readiness_run_is_current(r.id)
  order by r.id desc limit 1;

  if v_run is null then
    select id into v_latest from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id order by id desc limit 1;
    v_worker:=programacion.fn_input_governance_worker_spec(p_pantalla_id,p_consumer);
    v_close:=programacion.fn_input_governance_ekb_checkpoint('CLOSE_EKB',p_pantalla_id,v_latest);
    v_status:=case v_worker->>'required_role' when 'INPUT_VALIDATOR' then 'VALIDATOR_RUNTIME_REQUIRED' else 'CURATOR_RUNTIME_REQUIRED' end;
    v_payload:=jsonb_build_object(
      'schema_version',1,'execution_contract','INPUT_GOVERNANCE_EXECUTION_V1','execution_contract_revision',v_contract->>'contract_revision',
      'agent_code','INPUT_GOVERNANCE_AGENT','version_id',v_version,'pantalla_id',p_pantalla_id,'screen_code',v_code,'consumer',p_consumer,
      'status',v_status,'execution_mode','BOUND_ROLE_RUNTIME_REQUIRED','latest_run_id',v_latest,
      'blocker','ROLE_RUNTIME_REQUIRED','worker_spec',v_worker,
      'checkpoints',jsonb_build_object('PRE_EXECUTION',v_pre,'CLOSE_EKB',v_close),
      'proposal_is_canonical_source',false,'promotion_authorized',false,'production_authorized',false,'generated_at',now()
    );
    return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
  end if;

  v_fresh:=programacion.fn_input_freshness_delta(v_run); v_summary:=v_fresh->'summary';
  if v_fresh->>'run_state'<>'CURRENT'
     or coalesce((v_summary->>'changed_source_count')::integer,-1)<>0
     or coalesce((v_summary->>'affected_family_count')::integer,-1)<>0 then
    raise exception 'INPUT_GOVERNANCE_CURRENT_RUN_FRESHNESS_GATE_FAILED:run=% state=% summary=%',v_run,v_fresh->>'run_state',v_summary;
  end if;

  v_cur:=programacion.fn_input_governance_ekb_checkpoint('PRE_CURATOR',p_pantalla_id,v_run);
  if not (v_cur->>'pass')::boolean then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_CURATOR:%',v_cur->'unhandled_high_critical_codes'; end if;
  select count(*) into v_assessed from programacion.input_family_assessments where run_id=v_run;
  if v_assessed<>v_family then raise exception 'INPUT_GOVERNANCE_CURATOR_UNIVERSE_INCOMPLETE:run=% expected=% actual=%',v_run,v_family,v_assessed; end if;

  v_val:=programacion.fn_input_governance_ekb_checkpoint('PRE_VALIDATOR',p_pantalla_id,v_run);
  if not (v_val->>'pass')::boolean then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_VALIDATOR:%',v_val->'unhandled_high_critical_codes'; end if;
  select count(*) filter(where a.validator_outcome='PASS'),
         count(*) filter(where a.validator_outcome<>'PASS' or a.validator_identity is null
           or not coalesce((a.validator_evidence->>'direct_source_readback')::boolean,false)
           or a.validator_evidence->>'source_snapshot_sha256' is distinct from r.source_snapshot_sha256)
  into v_pass,v_bad
  from programacion.input_family_assessments a
  join programacion.input_readiness_runs r on r.id=a.run_id
  where a.run_id=v_run;
  if v_pass<>v_family or v_bad<>0 then raise exception 'INPUT_GOVERNANCE_VALIDATOR_NOT_FULL_AUTHORIZED_PASS:run=% expected=% pass=% bad=%',v_run,v_family,v_pass,v_bad; end if;

  v_story:=programacion.fn_input_governance_ekb_checkpoint('PRE_STORY_GATE',p_pantalla_id,v_run);
  if not (v_story->>'pass')::boolean then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_STORY_GATE:%',v_story->'unhandled_high_critical_codes'; end if;
  v_stage:=programacion.fn_input_stage_gate_summary(v_run); v_prop:=programacion.fn_input_proposal_summary(v_run);
  select count(*) into v_human from programacion.input_gap_proposals where run_id=v_run and status='HUMAN_DECISION_REQUIRED' and validator_outcome='PASS';
  if coalesce((v_stage->>'canonical_story_gate_pass')::boolean,false) then
    v_ctx:=programacion.fn_input_governance_ekb_checkpoint('PRE_CONTEXT_MANIFEST',p_pantalla_id,v_run);
    if not (v_ctx->>'pass')::boolean then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_CONTEXT_MANIFEST:%',v_ctx->'unhandled_high_critical_codes'; end if;
    v_manifest:=programacion.fn_input_context_manifest(v_run); v_status:='READY';
  elsif v_human>0 then v_status:='HUMAN_DECISION_REQUIRED'; else v_status:='BLOCKED'; end if;

  v_close:=programacion.fn_input_governance_ekb_checkpoint('CLOSE_EKB',p_pantalla_id,v_run);
  if not (v_close->>'pass')::boolean then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:CLOSE_EKB:%',v_close->'unhandled_high_critical_codes'; end if;
  v_worker:=programacion.fn_input_governance_worker_spec(p_pantalla_id,p_consumer);
  v_payload:=jsonb_build_object(
    'schema_version',1,'execution_contract','INPUT_GOVERNANCE_EXECUTION_V1','execution_contract_revision',v_contract->>'contract_revision',
    'agent_code','INPUT_GOVERNANCE_AGENT','version_id',v_version,'pantalla_id',p_pantalla_id,'screen_code',v_code,'consumer',p_consumer,
    'status',v_status,'execution_mode','REUSE_COMPLETED_CURRENT_RUN','run_id',v_run,'family_count',v_family,'validator_pass_count',v_pass,
    'human_decision_required_count',v_human,'freshness_delta_summary',v_summary,
    'stage_gate',v_stage,'proposal_summary',v_prop,'context_manifest',v_manifest,'worker_spec',v_worker,
    'checkpoints',jsonb_strip_nulls(jsonb_build_object('PRE_EXECUTION',v_pre,'PRE_CURATOR',v_cur,'PRE_VALIDATOR',v_val,'PRE_STORY_GATE',v_story,'PRE_CONTEXT_MANIFEST',v_ctx,'CLOSE_EKB',v_close)),
    'proposal_is_canonical_source',false,'promotion_authorized',false,'production_authorized',false,'generated_at',now()
  );
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;

create or replace function public.fn_input_governance_execute(p_pantalla_id integer,p_consumer text default 'STORY_CREATOR')
returns jsonb language sql stable security definer set search_path to 'pg_catalog','programacion'
as $function$
  select programacion.fn_input_governance_execute(p_pantalla_id,p_consumer);
$function$;
revoke all on function public.fn_input_governance_execute(integer,text) from public,anon,authenticated;
grant execute on function public.fn_input_governance_execute(integer,text) to service_role;

do $selftest$
declare r jsonb; b bigint;
begin
  select count(*) into b from programacion.input_readiness_runs;
  r:=programacion.fn_input_governance_execute(51,'STORY_CREATOR');
  if r->>'status'<>'READY' or (r->'worker_spec'->>'runtime_binding_status')<>'NOT_REQUIRED_CURRENT_RUN' then raise exception 'INPUT_GOV_RUNTIME_BINDING_CURRENT_FAILED:%',r; end if;
  r:=programacion.fn_input_governance_execute(1,'MANUAL');
  if r->>'status'<>'CURATOR_RUNTIME_REQUIRED'
     or r->>'execution_mode'<>'BOUND_ROLE_RUNTIME_REQUIRED'
     or r->'worker_spec'->>'runtime_binding'<>'SUPABASE_EDGE_FUNCTION:input-governance-curator-v1'
     or r->'worker_spec'->>'runtime_binding_status'<>'BOUND_RUNTIME' then raise exception 'INPUT_GOV_RUNTIME_BINDING_CURATOR_FAILED:%',r; end if;
  if (select count(*) from programacion.input_readiness_runs)<>b then raise exception 'INPUT_GOV_RUNTIME_BINDING_SMOKE_WROTE_RUN'; end if;
end;$selftest$;
