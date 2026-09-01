create or replace function programacion.fn_input_governance_worker_spec_known_current_v1(p_pantalla_id integer,p_consumer text,p_current_run_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public,programacion,lf_ops
as $function$
declare
  v_exec jsonb; v_version bigint; v_code text; v_active boolean; v_latest bigint; v_latest_status text;
  v_current bigint; v_role text; v_reason text; v_rev text; v_sha text; v_payload jsonb; v_count integer:=0; v_expected integer:=0;
begin
  if p_current_run_id is null then return programacion.fn_input_governance_worker_spec(p_pantalla_id,p_consumer); end if;
  select c.version_id,c.especificacion into v_version,v_exec
  from programacion.contratos c join programacion.versiones_agente v on v.id=c.version_id join programacion.agentes a on a.id=v.agente_id
  where a.agente_codigo='INPUT_GOVERNANCE_AGENT' and c.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT' and c.estado='defined' and c.fail_closed order by c.version_id desc limit 1;
  if v_exec is null then raise exception 'INPUT_GOVERNANCE_EXECUTION_CONTRACT_NOT_RESOLVABLE'; end if;
  if not exists(select 1 from jsonb_array_elements_text(v_exec->'allowed_consumers') x(v) where x.v=p_consumer) then raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>'); end if;
  select codigo,activa into v_code,v_active from lf_ops.pantallas where id=p_pantalla_id;
  if v_code is null then raise exception 'INPUT_GOVERNANCE_SCREEN_NOT_FOUND:%',p_pantalla_id; end if;
  if not v_active then raise exception 'INPUT_GOVERNANCE_SCREEN_INACTIVE:%',v_code; end if;
  if not exists(select 1 from programacion.input_readiness_runs r where r.id=p_current_run_id and r.version_id=v_version and r.pantalla_id=p_pantalla_id and r.status='COMPLETED' and r.invalidated_at is null) then raise exception 'INPUT_GOVERNANCE_KNOWN_CURRENT_RUN_BINDING_INVALID:%',p_current_run_id; end if;
  v_current:=p_current_run_id;
  select id,status,family_count into v_latest,v_latest_status,v_expected from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id order by id desc limit 1;
  if v_latest is not null then select count(*) into v_count from programacion.input_family_assessments where run_id=v_latest; end if;
  v_role:='NONE'; v_reason:='CURRENT_COMPLETED_RUN_AVAILABLE';
  select c.especificacion->>'contract_revision',programacion.fn_v09_sha256_jsonb(jsonb_build_object('id',c.id,'version_id',c.version_id,'contrato_codigo',c.contrato_codigo,'fail_closed',c.fail_closed,'estado',c.estado,'especificacion',c.especificacion)) into v_rev,v_sha
  from programacion.contratos c where c.version_id=v_version and c.contrato_codigo='INPUT_READINESS_CONTRACT' and c.estado='defined' and c.fail_closed;
  v_payload:=jsonb_build_object('schema_version',1,'worker_contract','INPUT_GOVERNANCE_WORKER_SPEC_V1','agent_code','INPUT_GOVERNANCE_AGENT','version_id',v_version,'pantalla_id',p_pantalla_id,'screen_code',v_code,'consumer',p_consumer,'required_role',v_role,'role_reason',v_reason,'latest_run_id',v_latest,'latest_run_status',v_latest_status,'current_run_id',v_current,'readiness_contract_revision',v_rev,'readiness_contract_sha256',v_sha,'family_universe_ref',jsonb_build_object('kind','RULE','codigo','B2B-RULE-STORY-READINESS-001','expected_family_count',47),'source_precedence',jsonb_build_array('lf_ops','lf_design','transversal','programacion'),'retrieval_plan',jsonb_build_array('SCREEN','SCREEN_RULE_SET','SCREEN_STATE_SET','SCREEN_CANONICAL_GRAPH','DESIGN_BINDING_GRAPH_V4','API_CONTRACT_RESOLUTION_V1','EKB_DECISION_SET','EKB_PREVENTION_SET'),'context_policy','REFERENCE_PLUS_JIT_MINIMUM_SUFFICIENT_CONTEXT','ekb_checkpoints',v_exec->'ekb_checkpoints','curator_requirements',jsonb_build_object('direct_source_readback',true,'no_invention',true,'proposal_is_canonical_source',false,'family_count',47,'automatic_policy','ASSERTION_REBIND_OR_GOVERNED_CANONICAL_BOOTSTRAP'),'validator_requirements',jsonb_build_object('separate_execution',true,'direct_source_readback',true,'deterministic_checks_first',true,'semantic_validation_required',true,'candidate_as_own_authority',false),'runtime_binding_status','NOT_REQUIRED_CURRENT_RUN','runtime_binding','NONE','runtime_orchestrator','SUPABASE_EDGE_FUNCTION:input-governance-agent-v1','runtime_action','REUSE_CURRENT_RUN','new_screen_policy','GOVERNED_CANONICAL_BOOTSTRAP_FAIL_CLOSED','bootstrap_decision','DEC-INPUT-GOV-BOOTSTRAP-001','auto_canonicalization',coalesce(v_exec->>'auto_canonicalization','DENY'),'safe_canonical_write_allowlist',coalesce(v_exec->'safe_canonical_write_allowlist','[]'::jsonb),'safe_autofix_contract',v_exec->'safe_autofix_contract','promotion_authorized',false,'production_authorized',false,'generated_at',now());
  return v_payload||jsonb_build_object('worker_spec_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;