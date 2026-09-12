-- INPUT_GOVERNANCE_AGENT safe canonical autofix v1
-- Root fix: internal remediation first; canonical write only under explicit positive authority.

insert into transversal.decision_log(adr,titulo,decision,razon,impacto,estado)
values(
  'DEC-INPUT-GOV-SAFE-AUTOFIX-001',
  'Input Governance safe autofix allowlist',
  'INPUT_GOVERNANCE_AGENT debe intentar autorremediacion dentro del propio agente. La escritura canonica automatica queda DENY por defecto y solo se permite mediante allowlist explicita. V1 autoriza unicamente BIND_EXISTING_COMPONENT_EXPLICIT_TOKEN: el elemento fuente debe nombrar exactamente un component_token_code, el token debe ser VIGENTE, pertenecer al Design System resuelto de la pantalla y no existir alternativa/conflicto. Queda prohibido inventar reglas, objetivos, estados, transiciones, timings, permisos, perfiles, textos, claims, contratos API o elegir entre alternativas ambiguas. Todo write requiere propuesta validada, readback y nueva recuracion/Validator.',
  'Evita escalar gaps simples cuando existe autoridad exacta, sin convertir inferencias o similitud semantica en fuente canonica.',
  'INPUT_GOVERNANCE_EXECUTION_CONTRACT 1.4; readiness 5.12 sin cambios; promotion y production permanecen false.',
  'vigente'
)
on conflict (adr) do update set decision=excluded.decision,razon=excluded.razon,impacto=excluded.impacto,estado='vigente';

update programacion.contratos
set especificacion = jsonb_set(
      jsonb_set(especificacion,'{contract_revision}','"1.4"'::jsonb,true),
      '{analysis_revision}','"INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX"'::jsonb,true
    ) || jsonb_build_object(
      'auto_canonicalization','DENY_BY_DEFAULT_EXPLICIT_SAFE_ALLOWLIST',
      'safe_canonical_write_allowlist',jsonb_build_array('BIND_EXISTING_COMPONENT_EXPLICIT_TOKEN'),
      'safe_autofix_contract',jsonb_build_object(
        'decision','DEC-INPUT-GOV-SAFE-AUTOFIX-001',
        'must_run_inside_agent',true,
        'requires_validated_proposal',true,
        'requires_positive_source_authority',true,
        'requires_exact_unique_target',true,
        'requires_readback',true,
        'requires_successor_recuration_and_independent_validator',true,
        'semantic_similarity_is_authority',false,
        'proposal_is_canonical_source',false,
        'forbidden_write_classes',jsonb_build_array('NEW_RULE','OBJECTIVE','STATE','TRANSITION','TIMING','PERMISSION','PROFILE','COPY','LEGAL_CLAIM','API_CONTRACT','NEW_COMPONENT_TOKEN')
      )
    )
where version_id=19 and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT';

create or replace function programacion.fn_input_governance_safe_autofix_v1(p_run_id bigint)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,programacion,lf_ops,lf_design
as $function$
declare
  v_run record;
  v_ds jsonb;
  v_ds_id bigint;
  e record;
  v_explicit_codes text[];
  v_code text;
  v_token_id bigint;
  v_token_count integer;
  v_applied integer:=0;
  v_skipped integer:=0;
  v_actions jsonb:='[]'::jsonb;
  v_before jsonb;
  v_after jsonb;
begin
  select id,pantalla_id,status into v_run
  from programacion.input_readiness_runs where id=p_run_id and version_id=19;
  if not found or v_run.status<>'COMPLETED' then
    raise exception 'SAFE_AUTOFIX_REQUIRES_COMPLETED_RUN:%',p_run_id;
  end if;
  if not exists(
    select 1 from programacion.input_gap_proposals p
    where p.run_id=p_run_id and p.family_code='DESIGN_SYSTEM'
      and p.status='VALIDATED' and p.validator_outcome='PASS'
  ) then
    return jsonb_build_object('run_id',p_run_id,'applied_count',0,'skipped_count',0,'successor_required',false,'reason','NO_VALIDATED_DESIGN_REMEDIATION');
  end if;

  v_ds:=programacion.fn_input_design_system_resolution_v1(v_run.pantalla_id);
  if coalesce((v_ds->>'conflict_detected')::boolean,false) then
    raise exception 'SAFE_AUTOFIX_DESIGN_SYSTEM_CONFLICT:%',v_run.pantalla_id;
  end if;
  v_ds_id:=(v_ds->>'design_system_id')::bigint;
  if v_ds_id is null then raise exception 'SAFE_AUTOFIX_DESIGN_SYSTEM_UNRESOLVED:%',v_run.pantalla_id; end if;

  for e in
    select * from lf_ops.pantalla_elementos
    where pantalla_id=v_run.pantalla_id
      and required_for_implementation
      and status<>'DEPRECATED'
      and semantic_binding_status='PENDING_SEMANTIC_COMPONENT'
      and component_token_id is null
    order by element_id
  loop
    select array_agg(distinct substring(x.s from length('component_token_code:')+1) order by substring(x.s from length('component_token_code:')+1))
      into v_explicit_codes
    from (
      select value #>> '{}' as s
      from jsonb_array_elements(e.source_refs)
      where jsonb_typeof(value)='string'
    ) x
    where x.s like 'component_token_code:%';

    if coalesce(array_length(v_explicit_codes,1),0)<>1
       or not exists(select 1 from jsonb_array_elements_text(e.source_refs) z(v) where z.v like 'rule:%') then
      v_skipped:=v_skipped+1;
      v_actions:=v_actions||jsonb_build_array(jsonb_build_object('element_id',e.element_id,'element_code',e.element_code,'action','NO_WRITE','reason','EXACT_POSITIVE_COMPONENT_AUTHORITY_NOT_PRESENT'));
      continue;
    end if;

    v_code:=v_explicit_codes[1];
    select count(*),min(component_token_id) into v_token_count,v_token_id
    from lf_design.component_tokens
    where component_token_code=v_code and design_system_id=v_ds_id and status='VIGENTE';
    if v_token_count<>1 then
      v_skipped:=v_skipped+1;
      v_actions:=v_actions||jsonb_build_array(jsonb_build_object('element_id',e.element_id,'element_code',e.element_code,'action','NO_WRITE','reason','EXACT_TARGET_NOT_UNIQUE_VIGENTE','component_token_code',v_code));
      continue;
    end if;

    v_before:=jsonb_build_object('element_id',e.element_id,'component_token_id',e.component_token_id,'semantic_binding_status',e.semantic_binding_status,'source_refs',e.source_refs);
    update lf_ops.pantalla_elementos
       set component_token_id=v_token_id,
           semantic_binding_status='RESOLVED_ID',
           source_refs=source_refs||jsonb_build_array('autofix:DEC-INPUT-GOV-SAFE-AUTOFIX-001','component_token_code:'||v_code),
           updated_at=now()
     where element_id=e.element_id
       and component_token_id is null
       and semantic_binding_status='PENDING_SEMANTIC_COMPONENT';
    if not found then raise exception 'SAFE_AUTOFIX_CONCURRENT_CHANGE:%',e.element_id; end if;

    select jsonb_build_object('element_id',element_id,'component_token_id',component_token_id,'semantic_binding_status',semantic_binding_status,'source_refs',source_refs)
      into v_after from lf_ops.pantalla_elementos where element_id=e.element_id;
    if (v_after->>'component_token_id')::bigint<>v_token_id or v_after->>'semantic_binding_status'<>'RESOLVED_ID' then
      raise exception 'SAFE_AUTOFIX_READBACK_FAILED:%',e.element_id;
    end if;
    v_applied:=v_applied+1;
    v_actions:=v_actions||jsonb_build_array(jsonb_build_object('element_id',e.element_id,'element_code',e.element_code,'action','BIND_EXISTING_COMPONENT_EXPLICIT_TOKEN','component_token_code',v_code,'component_token_id',v_token_id,'before',v_before,'after',v_after));
  end loop;

  return jsonb_build_object(
    'run_id',p_run_id,'pantalla_id',v_run.pantalla_id,
    'contract','INPUT_GOV_SAFE_AUTOFIX_V1',
    'decision','DEC-INPUT-GOV-SAFE-AUTOFIX-001',
    'applied_count',v_applied,'skipped_count',v_skipped,
    'successor_required',(v_applied>0),
    'actions',v_actions,
    'promotion_authorized',false,'production_authorized',false
  );
end;
$function$;

revoke all on function programacion.fn_input_governance_safe_autofix_v1(bigint) from public,anon,authenticated;
grant execute on function programacion.fn_input_governance_safe_autofix_v1(bigint) to service_role;

-- Worker spec must expose the real policy; do not report the obsolete absolute DENY.
create or replace function programacion.fn_input_governance_worker_spec(p_pantalla_id integer,p_consumer text default 'STORY_CREATOR')
returns jsonb
language plpgsql stable security definer
set search_path=pg_catalog,public,programacion,lf_ops
as $function$
declare v_exec jsonb; v_version bigint; v_code text; v_active boolean; v_latest bigint; v_latest_status text; v_current bigint; v_role text; v_reason text; v_rev text; v_sha text; v_payload jsonb; v_count integer:=0; v_expected integer:=0;
begin
  select c.version_id,c.especificacion into v_version,v_exec from programacion.contratos c join programacion.versiones_agente v on v.id=c.version_id join programacion.agentes a on a.id=v.agente_id where a.agente_codigo='INPUT_GOVERNANCE_AGENT' and c.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT' and c.estado='defined' and c.fail_closed order by c.version_id desc limit 1;
  if v_exec is null then raise exception 'INPUT_GOVERNANCE_EXECUTION_CONTRACT_NOT_RESOLVABLE'; end if; if not exists(select 1 from jsonb_array_elements_text(v_exec->'allowed_consumers') x(v) where x.v=p_consumer) then raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>'); end if;
  select codigo,activa into v_code,v_active from lf_ops.pantallas where id=p_pantalla_id; if v_code is null then raise exception 'INPUT_GOVERNANCE_SCREEN_NOT_FOUND:%',p_pantalla_id; end if; if not v_active then raise exception 'INPUT_GOVERNANCE_SCREEN_INACTIVE:%',v_code; end if;
  select id,status,family_count into v_latest,v_latest_status,v_expected from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id order by id desc limit 1;
  select id into v_current from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED' and invalidated_at is null and programacion.fn_input_readiness_run_is_current(id) order by id desc limit 1; if v_latest is not null then select count(*) into v_count from programacion.input_family_assessments where run_id=v_latest; end if;
  if v_current is not null then v_role:='NONE'; v_reason:='CURRENT_COMPLETED_RUN_AVAILABLE'; elsif v_latest_status='VALIDATING' or (v_latest_status='CURATING' and v_expected>0 and v_count=v_expected) then v_role:='INPUT_VALIDATOR'; v_reason:=case when v_latest_status='VALIDATING' then 'VALIDATION_PHASE_INCOMPLETE' else 'CURATION_MATERIALIZED_VALIDATION_NOT_OPEN' end; else v_role:='INPUT_CURATOR'; v_reason:=case when v_latest is null then 'NO_PRIOR_RUN_GOVERNED_BOOTSTRAP' else 'NO_CURRENT_COMPLETED_RUN' end; end if;
  select c.especificacion->>'contract_revision',programacion.fn_v09_sha256_jsonb(jsonb_build_object('id',c.id,'version_id',c.version_id,'contrato_codigo',c.contrato_codigo,'fail_closed',c.fail_closed,'estado',c.estado,'especificacion',c.especificacion)) into v_rev,v_sha from programacion.contratos c where c.version_id=v_version and c.contrato_codigo='INPUT_READINESS_CONTRACT' and c.estado='defined' and c.fail_closed;
  v_payload:=jsonb_build_object('schema_version',1,'worker_contract','INPUT_GOVERNANCE_WORKER_SPEC_V1','agent_code','INPUT_GOVERNANCE_AGENT','version_id',v_version,'pantalla_id',p_pantalla_id,'screen_code',v_code,'consumer',p_consumer,'required_role',v_role,'role_reason',v_reason,'latest_run_id',v_latest,'latest_run_status',v_latest_status,'current_run_id',v_current,'readiness_contract_revision',v_rev,'readiness_contract_sha256',v_sha,'family_universe_ref',jsonb_build_object('kind','RULE','codigo','B2B-RULE-STORY-READINESS-001','expected_family_count',47),'source_precedence',jsonb_build_array('lf_ops','lf_design','transversal','programacion'),'retrieval_plan',jsonb_build_array('SCREEN','SCREEN_RULE_SET','SCREEN_STATE_SET','SCREEN_CANONICAL_GRAPH','DESIGN_BINDING_GRAPH_V4','API_CONTRACT_RESOLUTION_V1','EKB_DECISION_SET','EKB_PREVENTION_SET'),'context_policy','REFERENCE_PLUS_JIT_MINIMUM_SUFFICIENT_CONTEXT','ekb_checkpoints',v_exec->'ekb_checkpoints','curator_requirements',jsonb_build_object('direct_source_readback',true,'no_invention',true,'proposal_is_canonical_source',false,'family_count',47,'automatic_policy','ASSERTION_REBIND_OR_GOVERNED_CANONICAL_BOOTSTRAP'),'validator_requirements',jsonb_build_object('separate_execution',true,'direct_source_readback',true,'deterministic_checks_first',true,'semantic_validation_required',true,'candidate_as_own_authority',false),'runtime_binding_status',case when v_role='NONE' then 'NOT_REQUIRED_CURRENT_RUN' else 'BOUND_RUNTIME' end,'runtime_binding',case when v_role='INPUT_CURATOR' then 'SUPABASE_EDGE_FUNCTION:input-governance-curator-v1' when v_role='INPUT_VALIDATOR' then 'SUPABASE_EDGE_FUNCTION:input-governance-validator-v1' else 'NONE' end,'runtime_orchestrator','SUPABASE_EDGE_FUNCTION:input-governance-agent-v1','runtime_action',case when v_role='NONE' then 'REUSE_CURRENT_RUN' when v_role='INPUT_VALIDATOR' then 'CALL_VALIDATOR_RUNTIME' else 'CALL_CURATOR_RUNTIME' end,'new_screen_policy','GOVERNED_CANONICAL_BOOTSTRAP_FAIL_CLOSED','bootstrap_decision','DEC-INPUT-GOV-BOOTSTRAP-001','auto_canonicalization',coalesce(v_exec->>'auto_canonicalization','DENY'),'safe_canonical_write_allowlist',coalesce(v_exec->'safe_canonical_write_allowlist','[]'::jsonb),'safe_autofix_contract',v_exec->'safe_autofix_contract','promotion_authorized',false,'production_authorized',false,'generated_at',now());
  return v_payload||jsonb_build_object('worker_spec_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;

-- Negative regression on ONB_002: ambiguity/no explicit token must produce zero canonical writes.
do $block$
declare v_before jsonb; v_after jsonb; v_result jsonb;
begin
  select jsonb_agg(jsonb_build_object('element_id',element_id,'component_token_id',component_token_id,'semantic_binding_status',semantic_binding_status) order by element_id)
    into v_before from lf_ops.pantalla_elementos where pantalla_id=2 and element_id in (24,25);
  v_result:=programacion.fn_input_governance_safe_autofix_v1(196);
  select jsonb_agg(jsonb_build_object('element_id',element_id,'component_token_id',component_token_id,'semantic_binding_status',semantic_binding_status) order by element_id)
    into v_after from lf_ops.pantalla_elementos where pantalla_id=2 and element_id in (24,25);
  if coalesce((v_result->>'applied_count')::int,-1)<>0 or v_before is distinct from v_after then
    raise exception 'SAFE_AUTOFIX_NEGATIVE_AMBIGUITY_REGRESSION_FAILED:%',v_result;
  end if;
end;
$block$;