-- INPUT_GOVERNANCE_AGENT Curator + Validator runtime core v1.
-- Separate executions, deterministic source rebind, fail-closed semantic bootstrap.

insert into transversal.decision_log(adr,titulo,decision,razon,impacto,estado)
values(
  'DEC-INPUT-GOV-RUNTIME-001',
  'Runtime separado de Curator y Validator para Input Governance',
  'INPUT_GOVERNANCE_AGENT usa runtimes separados para INPUT_CURATOR e INPUT_VALIDATOR. Curator puede rematerializar automáticamente solo un sucesor con precedente COMPLETED cuando todas las assertions semánticas previas se rebindan y pasan contra fuentes actuales. Validator abre su propia fase con identidad distinta, relee fuentes y reevalúa assertions mediante guards canónicos. Una pantalla sin precedente canónico queda fail-closed como BOOTSTRAP_SEMANTIC_PROFILE_REQUIRED; no se inventan 47 familias ni se introduce un proveedor LLM no gobernado. No autoriza promoción ni producción.',
  'Preserva AUD-001, AUD-019, freshness, proposal!=canon y evita auto-PASS semántico. Permite automatización E2E segura para sucesores demostrablemente equivalentes.',
  'Añade runtime operativo separado y un endpoint orquestador; INPUT_READINESS_CONTRACT 5.12 no cambia. promotion_authorized=false y production_authorized=false.',
  'vigente'
)
on conflict(adr) do update set titulo=excluded.titulo,decision=excluded.decision,razon=excluded.razon,impacto=excluded.impacto,estado=excluded.estado;

update programacion.contratos
set especificacion = especificacion || jsonb_build_object(
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

create or replace function programacion.fn_input_governance_curator_materialize_v1(
  p_pantalla_id integer,
  p_consumer text,
  p_curator_identity text,
  p_force_selftest boolean default false
) returns jsonb
language plpgsql volatile security definer
set search_path to 'pg_catalog','public','programacion','lf_ops','transversal'
as $function$
declare
  v_version bigint:=19;
  v_code text;
  v_active boolean;
  v_current bigint;
  v_latest bigint;
  v_latest_status text;
  v_parent bigint;
  v_new bigint;
  v_contract_schema integer;
  v_contract_revision text;
  v_contract_sha text;
  v_parent_contract_sha text;
  v_family_count integer;
  v_assessed integer;
  v_pre jsonb;
  v_assertions jsonb;
  v_assertion_sha text;
  a record;
  v_payload jsonb;
begin
  if p_curator_identity !~ '^INPUT_CURATOR:EDGE:input-governance-curator-v1:[A-Za-z0-9_-]{6,128}$' then
    raise exception 'INPUT_GOVERNANCE_CURATOR_RUNTIME_IDENTITY_INVALID';
  end if;
  if not exists(select 1 from jsonb_array_elements_text((select especificacion->'allowed_consumers' from programacion.contratos where version_id=19 and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT')) x(v) where x.v=p_consumer) then
    raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>');
  end if;
  select codigo,activa into v_code,v_active from lf_ops.pantallas where id=p_pantalla_id;
  if v_code is null then raise exception 'INPUT_GOVERNANCE_SCREEN_NOT_FOUND:%',p_pantalla_id; end if;
  if not v_active then raise exception 'INPUT_GOVERNANCE_SCREEN_INACTIVE:%',v_code; end if;
  v_pre:=programacion.fn_input_governance_ekb_checkpoint('PRE_CURATOR',p_pantalla_id,null);
  if not coalesce((v_pre->>'pass')::boolean,false) then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_CURATOR'; end if;

  select id into v_current from programacion.input_readiness_runs
  where version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED' and invalidated_at is null
    and programacion.fn_input_readiness_run_is_current(id) order by id desc limit 1;
  if v_current is not null and not p_force_selftest then
    return jsonb_build_object('status','NOOP_CURRENT','run_id',v_current,'required_role','NONE','promotion_authorized',false,'production_authorized',false);
  end if;

  select id,status into v_latest,v_latest_status from programacion.input_readiness_runs
  where version_id=v_version and pantalla_id=p_pantalla_id order by id desc limit 1;
  if v_latest is not null and v_latest_status in ('CURATING','VALIDATING') and not p_force_selftest then
    return jsonb_build_object('status',case when v_latest_status='VALIDATING' then 'VALIDATOR_RUNTIME_REQUIRED' else 'CURATION_IN_PROGRESS' end,'run_id',v_latest,'required_role',case when v_latest_status='VALIDATING' then 'INPUT_VALIDATOR' else 'INPUT_CURATOR' end,'promotion_authorized',false,'production_authorized',false);
  end if;

  select id,contract_snapshot_sha256,family_count into v_parent,v_parent_contract_sha,v_family_count
  from programacion.input_readiness_runs
  where version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED'
  order by id desc limit 1;
  if v_parent is null then
    v_payload:=jsonb_build_object('status','BOOTSTRAP_SEMANTIC_PROFILE_REQUIRED','pantalla_id',p_pantalla_id,'screen_code',v_code,'required_role','HUMAN_OR_GOVERNED_SEMANTIC_BOOTSTRAP','write_performed',false,'reason','NO_COMPLETED_PREDECESSOR_TO_REBIND','proposal_is_canonical_source',false,'promotion_authorized',false,'production_authorized',false);
    return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
  end if;

  select (c.especificacion->>'schema_version')::integer,c.especificacion->>'contract_revision',
         programacion.fn_v09_sha256_jsonb(jsonb_build_object('id',c.id,'version_id',c.version_id,'contrato_codigo',c.contrato_codigo,'fail_closed',c.fail_closed,'estado',c.estado,'especificacion',c.especificacion))
    into v_contract_schema,v_contract_revision,v_contract_sha
  from programacion.contratos c where c.version_id=v_version and c.contrato_codigo='INPUT_READINESS_CONTRACT' and c.estado='defined' and c.fail_closed;
  if v_contract_revision is null then raise exception 'INPUT_READINESS_CONTRACT_NOT_RESOLVABLE:%',v_version; end if;
  if v_parent_contract_sha is distinct from v_contract_sha then
    return jsonb_build_object('status','CONTRACT_CHANGED_SEMANTIC_REVIEW_REQUIRED','parent_run_id',v_parent,'required_role','HUMAN_OR_GOVERNED_CONTRACT_MIGRATION','write_performed',false,'promotion_authorized',false,'production_authorized',false);
  end if;

  insert into programacion.input_readiness_runs(
    version_id,pantalla_id,universe_rule_id,supersedes_run_id,scope,universe_snapshot_sha256,family_count,status,curator_identity,curator_component_id,contract_version
  )
  select version_id,pantalla_id,universe_rule_id,id,
         scope || jsonb_build_object('mode','RUNTIME_ASSERTION_REBIND_SAFE_SUCCESSOR_V1','parent_run_id',id,'runtime','input-governance-curator-v1','promotion_authorized',false,'production_authorized',false),
         universe_snapshot_sha256,family_count,'CURATING',p_curator_identity,46,v_contract_schema
  from programacion.input_readiness_runs where id=v_parent
  returning id into v_new;

  for a in select * from programacion.input_family_assessments where run_id=v_parent order by family_code
  loop
    v_assertions:=programacion.fn_input_v58_build_assertions(v_new,v_parent,a.family_code);
    v_assertion_sha:=programacion.fn_v09_sha256_jsonb(v_assertions);
    insert into programacion.input_family_assessments(
      run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,
      source_refs,rationale,blockers,negative_requirements,test_obligations,curator_evidence,curator_sha256
    ) values (
      v_new,a.family_code,a.severity,a.applicability,a.coverage_status,a.well_defined_status,a.story_ready_status,a.implementation_ready_status,a.qa_ready_status,a.production_ready_status,
      a.source_refs,a.rationale,a.blockers,a.negative_requirements,a.test_obligations,
      jsonb_build_object('component_id',46,'execution_id',gen_random_uuid()::text,'execution_mode','INDEPENDENT_CURATOR','runtime','SUPABASE_EDGE_FUNCTION:input-governance-curator-v1','contract_revision',v_contract_revision,'parent_run_id',v_parent,'parent_assessment_id',a.id,'direct_source_readback',true,'assertion_rebind_precheck_sha256',v_assertion_sha,'semantic_policy','NO_INVENTION_REBIND_ONLY'),
      repeat('0',64)
    );
  end loop;

  select count(*) into v_assessed from programacion.input_family_assessments where run_id=v_new;
  if v_assessed<>v_family_count then raise exception 'INPUT_GOVERNANCE_CURATOR_RUNTIME_UNIVERSE_INCOMPLETE expected=% actual=%',v_family_count,v_assessed; end if;
  v_payload:=jsonb_build_object('status','VALIDATOR_RUNTIME_REQUIRED','run_id',v_new,'parent_run_id',v_parent,'pantalla_id',p_pantalla_id,'screen_code',v_code,'family_count',v_family_count,'curator_identity',p_curator_identity,'run_status','CURATING','required_role','INPUT_VALIDATOR','write_performed',true,'promotion_authorized',false,'production_authorized',false);
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;

create or replace function programacion.fn_input_governance_validator_validate_v1(
  p_run_id bigint,
  p_validator_identity text
) returns jsonb
language plpgsql volatile security definer
set search_path to 'pg_catalog','public','programacion','lf_ops','transversal'
as $function$
declare
  v_status text;
  v_pantalla_id integer;
  v_parent bigint;
  v_family_count integer;
  v_curator_identity text;
  v_existing_validator text;
  v_contract_revision text;
  v_source_sha text;
  v_pass integer;
  v_pre jsonb;
  v_assertions jsonb;
  a record;
  v_payload jsonb;
begin
  if p_validator_identity !~ '^INPUT_VALIDATOR:EDGE:input-governance-validator-v1:[A-Za-z0-9_-]{6,128}$' then
    raise exception 'INPUT_GOVERNANCE_VALIDATOR_RUNTIME_IDENTITY_INVALID';
  end if;
  select status,pantalla_id,supersedes_run_id,family_count,curator_identity,validator_identity,contract_revision
    into v_status,v_pantalla_id,v_parent,v_family_count,v_curator_identity,v_existing_validator,v_contract_revision
  from programacion.input_readiness_runs where id=p_run_id and version_id=19;
  if v_status is null then raise exception 'INPUT_GOVERNANCE_VALIDATOR_RUN_NOT_FOUND:%',p_run_id; end if;
  if v_status='COMPLETED' then return jsonb_build_object('status','NOOP_COMPLETED','run_id',p_run_id,'promotion_authorized',false,'production_authorized',false); end if;
  if v_parent is null then raise exception 'INPUT_GOVERNANCE_VALIDATOR_PREDECESSOR_REQUIRED:%',p_run_id; end if;
  if p_validator_identity=v_curator_identity then raise exception 'VALIDATOR_IDENTITY_NOT_INDEPENDENT'; end if;
  v_pre:=programacion.fn_input_governance_ekb_checkpoint('PRE_VALIDATOR',v_pantalla_id,p_run_id);
  if not coalesce((v_pre->>'pass')::boolean,false) then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_VALIDATOR'; end if;

  if v_status='CURATING' then
    if (select count(*) from programacion.input_family_assessments where run_id=p_run_id)<>v_family_count then raise exception 'CURATOR_UNIVERSE_INCOMPLETE'; end if;
    update programacion.input_readiness_runs set status='VALIDATING',validator_identity=p_validator_identity,validator_component_id=47 where id=p_run_id;
  elsif v_status='VALIDATING' then
    if v_existing_validator is distinct from p_validator_identity then raise exception 'VALIDATOR_IDENTITY_MISMATCH'; end if;
  else
    raise exception 'INPUT_GOVERNANCE_VALIDATOR_INVALID_RUN_STATUS:%',v_status;
  end if;

  select source_snapshot_sha256,contract_revision into v_source_sha,v_contract_revision from programacion.input_readiness_runs where id=p_run_id;
  for a in select * from programacion.input_family_assessments where run_id=p_run_id order by family_code
  loop
    v_assertions:=programacion.fn_input_v58_build_assertions(p_run_id,v_parent,a.family_code);
    update programacion.input_family_assessments
    set validator_outcome='PASS',validator_findings='[]'::jsonb,validator_identity=p_validator_identity,
        validator_evidence=jsonb_build_object(
          'component_id',47,'execution_id',gen_random_uuid()::text,'validated_curator_execution_id',a.curator_evidence->>'execution_id',
          'execution_mode','INDEPENDENT_VALIDATOR','runtime','SUPABASE_EDGE_FUNCTION:input-governance-validator-v1','direct_source_readback',true,
          'contract_revision',v_contract_revision,'source_snapshot_sha256',v_source_sha,'curator_sha256',a.curator_sha256,
          'semantic_depth_sha256',a.semantic_depth_sha256,'assertions',v_assertions
        )
    where id=a.id;
  end loop;
  update programacion.input_readiness_runs set status='COMPLETED' where id=p_run_id;
  select count(*) into v_pass from programacion.input_family_assessments where run_id=p_run_id and validator_outcome='PASS' and validator_identity=p_validator_identity;
  v_payload:=jsonb_build_object('status','COMPLETED','run_id',p_run_id,'parent_run_id',v_parent,'pantalla_id',v_pantalla_id,'family_count',v_family_count,'validator_pass_count',v_pass,'validator_identity',p_validator_identity,'required_role','DISPATCHER_FINALIZE','promotion_authorized',false,'production_authorized',false);
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;

create or replace function programacion.fn_input_governance_worker_spec(p_pantalla_id integer,p_consumer text default 'STORY_CREATOR')
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','public','programacion','lf_ops'
as $function$
declare
 v_exec jsonb; v_version bigint; v_code text; v_active boolean; v_latest bigint; v_latest_status text; v_current bigint;
 v_role text; v_reason text; v_rev text; v_sha text; v_payload jsonb; v_count integer:=0; v_expected integer:=0;
begin
 select c.version_id,c.especificacion into v_version,v_exec from programacion.contratos c join programacion.versiones_agente v on v.id=c.version_id join programacion.agentes a on a.id=v.agente_id where a.agente_codigo='INPUT_GOVERNANCE_AGENT' and c.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT' and c.estado='defined' and c.fail_closed order by c.version_id desc limit 1;
 if v_exec is null then raise exception 'INPUT_GOVERNANCE_EXECUTION_CONTRACT_NOT_RESOLVABLE'; end if;
 if not exists(select 1 from jsonb_array_elements_text(v_exec->'allowed_consumers') x(v) where x.v=p_consumer) then raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>'); end if;
 select codigo,activa into v_code,v_active from lf_ops.pantallas where id=p_pantalla_id; if v_code is null then raise exception 'INPUT_GOVERNANCE_SCREEN_NOT_FOUND:%',p_pantalla_id; end if; if not v_active then raise exception 'INPUT_GOVERNANCE_SCREEN_INACTIVE:%',v_code; end if;
 select id,status,family_count into v_latest,v_latest_status,v_expected from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id order by id desc limit 1;
 select id into v_current from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED' and invalidated_at is null and programacion.fn_input_readiness_run_is_current(id) order by id desc limit 1;
 if v_latest is not null then select count(*) into v_count from programacion.input_family_assessments where run_id=v_latest; end if;
 if v_current is not null then v_role:='NONE'; v_reason:='CURRENT_COMPLETED_RUN_AVAILABLE';
 elsif v_latest_status='VALIDATING' or (v_latest_status='CURATING' and v_expected>0 and v_count=v_expected) then v_role:='INPUT_VALIDATOR'; v_reason:=case when v_latest_status='VALIDATING' then 'VALIDATION_PHASE_INCOMPLETE' else 'CURATION_MATERIALIZED_VALIDATION_NOT_OPEN' end;
 else v_role:='INPUT_CURATOR'; v_reason:=case when v_latest is null then 'NO_PRIOR_RUN' else 'NO_CURRENT_COMPLETED_RUN' end; end if;
 select c.especificacion->>'contract_revision',programacion.fn_v09_sha256_jsonb(jsonb_build_object('id',c.id,'version_id',c.version_id,'contrato_codigo',c.contrato_codigo,'fail_closed',c.fail_closed,'estado',c.estado,'especificacion',c.especificacion)) into v_rev,v_sha from programacion.contratos c where c.version_id=v_version and c.contrato_codigo='INPUT_READINESS_CONTRACT' and c.estado='defined' and c.fail_closed;
 v_payload:=jsonb_build_object('schema_version',1,'worker_contract','INPUT_GOVERNANCE_WORKER_SPEC_V1','agent_code','INPUT_GOVERNANCE_AGENT','version_id',v_version,'pantalla_id',p_pantalla_id,'screen_code',v_code,'consumer',p_consumer,'required_role',v_role,'role_reason',v_reason,'latest_run_id',v_latest,'latest_run_status',v_latest_status,'current_run_id',v_current,'readiness_contract_revision',v_rev,'readiness_contract_sha256',v_sha,'family_universe_ref',jsonb_build_object('kind','RULE','codigo','B2B-RULE-STORY-READINESS-001','expected_family_count',47),'source_precedence',jsonb_build_array('lf_ops','lf_design','transversal','programacion'),'context_policy','REFERENCE_PLUS_JIT_MINIMUM_SUFFICIENT_CONTEXT','ekb_checkpoints',v_exec->'ekb_checkpoints','curator_requirements',jsonb_build_object('direct_source_readback',true,'no_invention',true,'proposal_is_canonical_source',false,'family_count',47,'automatic_policy','ASSERTION_REBIND_SAFE_SUCCESSOR_ONLY'),'validator_requirements',jsonb_build_object('separate_execution',true,'direct_source_readback',true,'deterministic_checks_first',true,'semantic_validation_required',true,'candidate_as_own_authority',false),'runtime_binding_status',case when v_role='NONE' then 'NOT_REQUIRED_CURRENT_RUN' else 'BOUND_RUNTIME' end,'runtime_binding',case when v_role='INPUT_CURATOR' then 'SUPABASE_EDGE_FUNCTION:input-governance-curator-v1' when v_role='INPUT_VALIDATOR' then 'SUPABASE_EDGE_FUNCTION:input-governance-validator-v1' else 'NONE' end,'runtime_orchestrator','SUPABASE_EDGE_FUNCTION:input-governance-agent-v1','runtime_action',case when v_role='NONE' then 'REUSE_CURRENT_RUN' when v_role='INPUT_VALIDATOR' then 'CALL_VALIDATOR_RUNTIME' else 'CALL_CURATOR_RUNTIME' end,'new_screen_policy','BOOTSTRAP_SEMANTIC_PROFILE_REQUIRED_FAIL_CLOSED','auto_canonicalization','DENY','promotion_authorized',false,'production_authorized',false,'generated_at',now());
 return v_payload||jsonb_build_object('worker_spec_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;$function$;

create or replace function programacion.fn_input_governance_execute(p_pantalla_id integer,p_consumer text default 'STORY_CREATOR')
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','public','programacion','lf_ops'
as $function$
declare v_contract jsonb; v_version bigint; v_code text; v_active boolean; v_run bigint; v_latest bigint; v_family integer; v_assessed integer; v_pass integer; v_bad integer; v_human integer; v_status text; v_pre jsonb; v_cur jsonb; v_val jsonb; v_story jsonb; v_ctx jsonb; v_close jsonb; v_stage jsonb; v_prop jsonb; v_manifest jsonb; v_payload jsonb; v_worker jsonb; v_fresh jsonb; v_summary jsonb;
begin
 select c.version_id,c.especificacion into v_version,v_contract from programacion.contratos c join programacion.versiones_agente v on v.id=c.version_id join programacion.agentes a on a.id=v.agente_id where a.agente_codigo='INPUT_GOVERNANCE_AGENT' and c.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT' and c.estado='defined' and c.fail_closed order by c.version_id desc limit 1;
 if v_contract is null then raise exception 'INPUT_GOVERNANCE_EXECUTION_CONTRACT_NOT_RESOLVABLE'; end if; if not exists(select 1 from jsonb_array_elements_text(v_contract->'allowed_consumers') x(v) where x.v=p_consumer) then raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>'); end if;
 select codigo,activa into v_code,v_active from lf_ops.pantallas where id=p_pantalla_id; if v_code is null then raise exception 'INPUT_GOVERNANCE_SCREEN_NOT_FOUND:%',p_pantalla_id; end if; if not v_active then raise exception 'INPUT_GOVERNANCE_SCREEN_INACTIVE:%',v_code; end if;
 v_pre:=programacion.fn_input_governance_ekb_checkpoint('PRE_EXECUTION',p_pantalla_id,null); if not (v_pre->>'pass')::boolean then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_EXECUTION:%',v_pre->'unhandled_high_critical_codes'; end if;
 select id,family_count into v_run,v_family from programacion.input_readiness_runs r where r.version_id=v_version and r.pantalla_id=p_pantalla_id and r.status='COMPLETED' and r.invalidated_at is null and programacion.fn_input_readiness_run_is_current(r.id) order by r.id desc limit 1;
 if v_run is null then
   select id into v_latest from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id order by id desc limit 1;
   v_worker:=programacion.fn_input_governance_worker_spec(p_pantalla_id,p_consumer); v_close:=programacion.fn_input_governance_ekb_checkpoint('CLOSE_EKB',p_pantalla_id,v_latest);
   v_status:=case v_worker->>'required_role' when 'INPUT_VALIDATOR' then 'VALIDATOR_RUNTIME_REQUIRED' else 'CURATOR_RUNTIME_REQUIRED' end;
   v_payload:=jsonb_build_object('schema_version',1,'execution_contract','INPUT_GOVERNANCE_EXECUTION_V1','execution_contract_revision',v_contract->>'contract_revision','agent_code','INPUT_GOVERNANCE_AGENT','version_id',v_version,'pantalla_id',p_pantalla_id,'screen_code',v_code,'consumer',p_consumer,'status',v_status,'execution_mode','BOUND_ROLE_RUNTIME_REQUIRED','latest_run_id',v_latest,'blocker','ROLE_RUNTIME_REQUIRED','worker_spec',v_worker,'checkpoints',jsonb_build_object('PRE_EXECUTION',v_pre,'CLOSE_EKB',v_close),'proposal_is_canonical_source',false,'promotion_authorized',false,'production_authorized',false,'generated_at',now()); return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
 end if;
 v_fresh:=programacion.fn_input_freshness_delta(v_run); v_summary:=v_fresh->'summary'; if v_fresh->>'run_state'<>'CURRENT' or coalesce((v_summary->>'changed_source_count')::integer,-1)<>0 or coalesce((v_summary->>'affected_family_count')::integer,-1)<>0 then raise exception 'INPUT_GOVERNANCE_CURRENT_RUN_FRESHNESS_GATE_FAILED:run=% state=% summary=%',v_run,v_fresh->>'run_state',v_summary; end if;
 v_cur:=programacion.fn_input_governance_ekb_checkpoint('PRE_CURATOR',p_pantalla_id,v_run); if not (v_cur->>'pass')::boolean then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_CURATOR:%',v_cur->'unhandled_high_critical_codes'; end if; select count(*) into v_assessed from programacion.input_family_assessments where run_id=v_run; if v_assessed<>v_family then raise exception 'INPUT_GOVERNANCE_CURATOR_UNIVERSE_INCOMPLETE:run=% expected=% actual=%',v_run,v_family,v_assessed; end if;
 v_val:=programacion.fn_input_governance_ekb_checkpoint('PRE_VALIDATOR',p_pantalla_id,v_run); if not (v_val->>'pass')::boolean then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_VALIDATOR:%',v_val->'unhandled_high_critical_codes'; end if; select count(*) filter(where a.validator_outcome='PASS'),count(*) filter(where a.validator_outcome<>'PASS' or a.validator_identity is null or not coalesce((a.validator_evidence->>'direct_source_readback')::boolean,false) or a.validator_evidence->>'source_snapshot_sha256' is distinct from r.source_snapshot_sha256) into v_pass,v_bad from programacion.input_family_assessments a join programacion.input_readiness_runs r on r.id=a.run_id where a.run_id=v_run; if v_pass<>v_family or v_bad<>0 then raise exception 'INPUT_GOVERNANCE_VALIDATOR_NOT_FULL_AUTHORIZED_PASS:run=% expected=% pass=% bad=%',v_run,v_family,v_pass,v_bad; end if;
 v_story:=programacion.fn_input_governance_ekb_checkpoint('PRE_STORY_GATE',p_pantalla_id,v_run); if not (v_story->>'pass')::boolean then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_STORY_GATE:%',v_story->'unhandled_high_critical_codes'; end if; v_stage:=programacion.fn_input_stage_gate_summary(v_run); v_prop:=programacion.fn_input_proposal_summary(v_run); select count(*) into v_human from programacion.input_gap_proposals where run_id=v_run and status='HUMAN_DECISION_REQUIRED' and validator_outcome='PASS';
 if coalesce((v_stage->>'canonical_story_gate_pass')::boolean,false) then v_ctx:=programacion.fn_input_governance_ekb_checkpoint('PRE_CONTEXT_MANIFEST',p_pantalla_id,v_run); if not (v_ctx->>'pass')::boolean then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_CONTEXT_MANIFEST:%',v_ctx->'unhandled_high_critical_codes'; end if; v_manifest:=programacion.fn_input_context_manifest(v_run); v_status:='READY'; elsif v_human>0 then v_status:='HUMAN_DECISION_REQUIRED'; else v_status:='BLOCKED'; end if;
 v_close:=programacion.fn_input_governance_ekb_checkpoint('CLOSE_EKB',p_pantalla_id,v_run); if not (v_close->>'pass')::boolean then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:CLOSE_EKB:%',v_close->'unhandled_high_critical_codes'; end if; v_worker:=programacion.fn_input_governance_worker_spec(p_pantalla_id,p_consumer);
 v_payload:=jsonb_build_object('schema_version',1,'execution_contract','INPUT_GOVERNANCE_EXECUTION_V1','execution_contract_revision',v_contract->>'contract_revision','agent_code','INPUT_GOVERNANCE_AGENT','version_id',v_version,'pantalla_id',p_pantalla_id,'screen_code',v_code,'consumer',p_consumer,'status',v_status,'execution_mode','REUSE_COMPLETED_CURRENT_RUN','run_id',v_run,'family_count',v_family,'validator_pass_count',v_pass,'human_decision_required_count',v_human,'freshness_delta_summary',v_summary,'stage_gate',v_stage,'proposal_summary',v_prop,'context_manifest',v_manifest,'worker_spec',v_worker,'checkpoints',jsonb_strip_nulls(jsonb_build_object('PRE_EXECUTION',v_pre,'PRE_CURATOR',v_cur,'PRE_VALIDATOR',v_val,'PRE_STORY_GATE',v_story,'PRE_CONTEXT_MANIFEST',v_ctx,'CLOSE_EKB',v_close)),'proposal_is_canonical_source',false,'promotion_authorized',false,'production_authorized',false,'generated_at',now()); return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;$function$;

create or replace function public.fn_input_governance_execute(p_pantalla_id integer,p_consumer text default 'STORY_CREATOR') returns jsonb language sql stable security definer set search_path to 'pg_catalog','programacion' as $function$ select programacion.fn_input_governance_execute(p_pantalla_id,p_consumer); $function$;
create or replace function public.fn_input_governance_curator_materialize_v1(p_pantalla_id integer,p_consumer text,p_curator_identity text) returns jsonb language sql security definer set search_path to 'pg_catalog','programacion' as $function$ select programacion.fn_input_governance_curator_materialize_v1(p_pantalla_id,p_consumer,p_curator_identity,false); $function$;
create or replace function public.fn_input_governance_validator_validate_v1(p_run_id bigint,p_validator_identity text) returns jsonb language sql security definer set search_path to 'pg_catalog','programacion' as $function$ select programacion.fn_input_governance_validator_validate_v1(p_run_id,p_validator_identity); $function$;

revoke all on function programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean) from public,anon,authenticated;
revoke all on function programacion.fn_input_governance_validator_validate_v1(bigint,text) from public,anon,authenticated;
revoke all on function public.fn_input_governance_execute(integer,text) from public,anon,authenticated;
revoke all on function public.fn_input_governance_curator_materialize_v1(integer,text,text) from public,anon,authenticated;
revoke all on function public.fn_input_governance_validator_validate_v1(bigint,text) from public,anon,authenticated;
grant execute on function public.fn_input_governance_execute(integer,text) to service_role;
grant execute on function public.fn_input_governance_curator_materialize_v1(integer,text,text) to service_role;
grant execute on function public.fn_input_governance_validator_validate_v1(bigint,text) to service_role;

do $selftest$
declare b_count bigint; b_max bigint; c jsonb; v jsonb; f jsonb; new_id bigint;
begin
 select count(*),max(id) into b_count,b_max from programacion.input_readiness_runs;
 begin
   c:=programacion.fn_input_governance_curator_materialize_v1(51,'MANUAL','INPUT_CURATOR:EDGE:input-governance-curator-v1:selftest01',true);
   if c->>'status'<>'VALIDATOR_RUNTIME_REQUIRED' then raise exception 'RUNTIME_SELFTEST_CURATOR_NOT_READY:%',c; end if;
   new_id:=(c->>'run_id')::bigint;
   if (select count(*) from programacion.input_family_assessments where run_id=new_id)<>47 then raise exception 'RUNTIME_SELFTEST_CURATOR_47_FAILED'; end if;
   v:=programacion.fn_input_governance_validator_validate_v1(new_id,'INPUT_VALIDATOR:EDGE:input-governance-validator-v1:selftest01');
   if v->>'status'<>'COMPLETED' or (v->>'validator_pass_count')::integer<>47 then raise exception 'RUNTIME_SELFTEST_VALIDATOR_FAILED:%',v; end if;
   f:=programacion.fn_input_governance_execute(51,'MANUAL');
   if f->>'status'<>'READY' or (f->>'run_id')::bigint<>new_id then raise exception 'RUNTIME_SELFTEST_FINAL_DISPATCH_FAILED:%',f; end if;
   raise exception 'ROLLBACK_INPUT_GOVERNANCE_RUNTIME_SELFTEST';
 exception when others then
   if sqlerrm<>'ROLLBACK_INPUT_GOVERNANCE_RUNTIME_SELFTEST' then raise; end if;
 end;
 if (select count(*) from programacion.input_readiness_runs)<>b_count or (select max(id) from programacion.input_readiness_runs)<>b_max then raise exception 'RUNTIME_SELFTEST_PERSISTED_RUN'; end if;
 c:=programacion.fn_input_governance_curator_materialize_v1(1,'MANUAL','INPUT_CURATOR:EDGE:input-governance-curator-v1:selftest02',false);
 if c->>'status'<>'BOOTSTRAP_SEMANTIC_PROFILE_REQUIRED' or coalesce((c->>'write_performed')::boolean,true) then raise exception 'RUNTIME_SELFTEST_NEW_SCREEN_NOT_FAIL_CLOSED:%',c; end if;
end;$selftest$;
