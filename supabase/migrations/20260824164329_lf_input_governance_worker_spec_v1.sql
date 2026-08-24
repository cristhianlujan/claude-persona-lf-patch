-- Input Governance role-specific worker handoff. No semantic self-execution.
update programacion.contratos
set especificacion=especificacion||jsonb_build_object(
 'contract_revision','1.1',
 'worker_spec','programacion.fn_input_governance_worker_spec(integer,text)',
 'runtime_binding_status','UNBOUND_SEMANTIC_RUNTIME',
 'semantic_curator_runtime','EXTERNAL_SEMANTIC_RUNTIME_REQUIRED_FOR_NEW_OR_CHANGED_SCOPE',
 'validator_runtime','SEPARATE_ATTESTED_EXECUTION_REQUIRED',
 'full_autonomous_new_screen',false,
 'stale_or_absent_policy','ROLE_SPECIFIC_RUNTIME_REQUIRED_FAIL_CLOSED',
 'new_run_materialization','CURATOR_THEN_SEPARATE_VALIDATOR_RUNTIME_REQUIRED')
where version_id=19 and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT' and estado='defined' and fail_closed;

create or replace function programacion.fn_input_governance_worker_spec(p_pantalla_id integer,p_consumer text default 'STORY_CREATOR')
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','public','programacion','lf_ops' as $f$
declare
 v_exec jsonb; v_version bigint; v_code text; v_active boolean; v_latest bigint; v_latest_status text;
 v_latest_invalidated timestamptz; v_current bigint; v_role text; v_reason text; v_rev text; v_sha text; v_payload jsonb;
begin
 select c.version_id,c.especificacion into v_version,v_exec
 from programacion.contratos c join programacion.versiones_agente v on v.id=c.version_id join programacion.agentes a on a.id=v.agente_id
 where a.agente_codigo='INPUT_GOVERNANCE_AGENT' and c.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
   and c.estado='defined' and c.fail_closed order by c.version_id desc limit 1;
 if v_exec is null then raise exception 'INPUT_GOVERNANCE_EXECUTION_CONTRACT_NOT_RESOLVABLE'; end if;
 if not exists(select 1 from jsonb_array_elements_text(v_exec->'allowed_consumers') x(v) where x.v=p_consumer) then
   raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>');
 end if;
 select codigo,activa into v_code,v_active from lf_ops.pantallas where id=p_pantalla_id;
 if v_code is null then raise exception 'INPUT_GOVERNANCE_SCREEN_NOT_FOUND:%',p_pantalla_id; end if;
 if not v_active then raise exception 'INPUT_GOVERNANCE_SCREEN_INACTIVE:%',v_code; end if;

 select id,status,invalidated_at into v_latest,v_latest_status,v_latest_invalidated
 from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id order by id desc limit 1;
 select id into v_current from programacion.input_readiness_runs
 where version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED' and invalidated_at is null
   and programacion.fn_input_readiness_run_is_current(id) order by id desc limit 1;
 if v_current is not null then v_role:='NONE'; v_reason:='CURRENT_COMPLETED_RUN_AVAILABLE';
 elsif v_latest is not null and v_latest_invalidated is null and v_latest_status='VALIDATING' then v_role:='INPUT_VALIDATOR'; v_reason:='VALIDATION_PHASE_INCOMPLETE';
 else v_role:='INPUT_CURATOR'; v_reason:=case when v_latest is null then 'NO_PRIOR_RUN' else 'NO_CURRENT_COMPLETED_RUN' end; end if;

 select c.especificacion->>'contract_revision',
        programacion.fn_v09_sha256_jsonb(jsonb_build_object('id',c.id,'version_id',c.version_id,'contrato_codigo',c.contrato_codigo,'fail_closed',c.fail_closed,'estado',c.estado,'especificacion',c.especificacion))
 into v_rev,v_sha from programacion.contratos c
 where c.version_id=v_version and c.contrato_codigo='INPUT_READINESS_CONTRACT' and c.estado='defined' and c.fail_closed;
 if v_rev is null or v_sha is null then raise exception 'INPUT_READINESS_CONTRACT_NOT_RESOLVABLE:%',v_version; end if;

 v_payload:=jsonb_build_object(
  'schema_version',1,'worker_contract','INPUT_GOVERNANCE_WORKER_SPEC_V1','agent_code','INPUT_GOVERNANCE_AGENT',
  'version_id',v_version,'pantalla_id',p_pantalla_id,'screen_code',v_code,'consumer',p_consumer,
  'required_role',v_role,'role_reason',v_reason,'latest_run_id',v_latest,'latest_run_status',v_latest_status,'current_run_id',v_current,
  'readiness_contract_revision',v_rev,'readiness_contract_sha256',v_sha,
  'family_universe_ref',jsonb_build_object('kind','RULE','codigo','B2B-RULE-STORY-READINESS-001','expected_family_count',47),
  'source_precedence',jsonb_build_array('lf_ops','lf_design','transversal','programacion'),
  'retrieval_plan',jsonb_build_array('SCREEN','SCREEN_RULE_SET','SCREEN_STATE_SET','SCREEN_CANONICAL_GRAPH','DESIGN_BINDING_GRAPH_V2','API_CONTRACT_RESOLUTION_V1','EKB_DECISION_SET','EKB_PREVENTION_SET'),
  'context_policy','REFERENCE_PLUS_JIT_MINIMUM_SUFFICIENT_CONTEXT','ekb_checkpoints',v_exec->'ekb_checkpoints',
  'curator_requirements',jsonb_build_object('direct_source_readback',true,'no_invention',true,'proposal_is_canonical_source',false,'family_count',47),
  'validator_requirements',jsonb_build_object('separate_execution',true,'direct_source_readback',true,'deterministic_checks_first',true,'semantic_validation_required',true,'candidate_as_own_authority',false),
  'runtime_binding_status',case when v_role='NONE' then 'NOT_REQUIRED_CURRENT_RUN' else 'UNBOUND_SEMANTIC_RUNTIME' end,
  'runtime_action',case when v_role='NONE' then 'REUSE_CURRENT_RUN' when v_role='INPUT_VALIDATOR' then 'BIND_SEPARATE_VALIDATOR_RUNTIME_AND_CONTINUE' else 'BIND_CURATOR_RUNTIME_AND_MATERIALIZE' end,
  'auto_canonicalization','DENY','promotion_authorized',false,'production_authorized',false,'generated_at',now());
 return v_payload||jsonb_build_object('worker_spec_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;$f$;

revoke all on function programacion.fn_input_governance_worker_spec(integer,text) from public,anon,authenticated;
grant execute on function programacion.fn_input_governance_worker_spec(integer,text) to service_role;
comment on function programacion.fn_input_governance_worker_spec(integer,text) is 'Fail-closed INPUT_GOVERNANCE_AGENT worker handoff. It identifies the Curator or separate Validator runtime required and never performs semantic self-validation.';

do $check$ declare w jsonb; begin
 w:=programacion.fn_input_governance_worker_spec(51,'STORY_CREATOR');
 if w->>'required_role'<>'NONE' or (w->>'current_run_id')::bigint<>183 then raise exception 'INPUT_GOV_WORKER_CURRENT_SELFTEST:%',w; end if;
 w:=programacion.fn_input_governance_worker_spec(1,'STORY_CREATOR');
 if w->>'required_role'<>'INPUT_CURATOR' or w->>'runtime_binding_status'<>'UNBOUND_SEMANTIC_RUNTIME' then raise exception 'INPUT_GOV_WORKER_NEW_SCREEN_SELFTEST:%',w; end if;
end;$check$;
