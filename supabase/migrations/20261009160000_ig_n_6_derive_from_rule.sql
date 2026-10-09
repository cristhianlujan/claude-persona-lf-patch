-- IG N-6 / DERIVE_FROM_RULE (DEC-INPUT-GOV-SAFE-AUTOFIX-002, VIGENTE 2026-10-09).
-- Class DERIVE_FROM_VIGENTE_RULE_EXPLICIT_VALUE added to programacion.fn_input_governance_safe_autofix_v1:
--   * versioned key->column mapping COMPONENT_TOKEN_CODE_TO_ID v1 (source_ref 'component_token_code:<code>' -> lf_ops.pantalla_elementos.component_token_id),
--   * the row inherits the state of its source rule(s): all rules VIGENTE -> VIGENTE; any CANDIDATO -> CANDIDATO (INACTIVO rows keep their state),
--   * several explicit values -> SOURCE_CONFLICT (NO_WRITE); rule missing or pendiente_decision -> NO_WRITE (escalates); no literal value -> NO_WRITE,
--   * unchanged: DENY by default, needs a COMPLETED run with a VALIDATED/PASS DESIGN_SYSTEM remediation, unique VIGENTE target in the resolved design system,
--     readback of every write, no promotion/production.
-- The independent judge and the escalation negatives are later checkpoints of N-6 (INDEPENDENT_JUDGE, NEGATIVE_ESCALATE).
CREATE OR REPLACE FUNCTION programacion.fn_input_governance_safe_autofix_v1(p_run_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'lf_ops', 'lf_design'
AS $fn$
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
  v_conflicts integer:=0;
  v_actions jsonb:='[]'::jsonb;
  v_before jsonb;
  v_after jsonb;
  v_rules text[];
  v_rule_found integer;
  v_rule_pending integer;
  v_rule_candidate integer;
  v_inherited text;
  v_new_status text;
  v_mapping constant jsonb := jsonb_build_object(
    'mapping_code','COMPONENT_TOKEN_CODE_TO_ID','mapping_version',1,
    'class','DERIVE_FROM_VIGENTE_RULE_EXPLICIT_VALUE',
    'source_ref_prefix','component_token_code:','source_rule_prefix','rule:',
    'target','lf_ops.pantalla_elementos.component_token_id',
    'lookup','lf_design.component_tokens(component_token_code,design_system_id,status=VIGENTE)',
    'state_inheritance','SOURCE_RULE_STATE');
begin
  select id,pantalla_id,status into v_run
  from programacion.input_readiness_runs where id=p_run_id and version_id=public.fn_lf_version_compatibility_current_version_id_v1('PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT');
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

    select array_agg(distinct substring(x.s from length('rule:')+1) order by substring(x.s from length('rule:')+1))
      into v_rules
    from (
      select value #>> '{}' as s
      from jsonb_array_elements(e.source_refs)
      where jsonb_typeof(value)='string'
    ) x
    where x.s like 'rule:%';

    if coalesce(array_length(v_explicit_codes,1),0)>1 then
      v_skipped:=v_skipped+1; v_conflicts:=v_conflicts+1;
      v_actions:=v_actions||jsonb_build_array(jsonb_build_object('element_id',e.element_id,'element_code',e.element_code,'action','NO_WRITE','reason','SOURCE_CONFLICT_MULTIPLE_EXPLICIT_COMPONENT_CODES','component_token_codes',to_jsonb(v_explicit_codes)));
      continue;
    end if;
    if coalesce(array_length(v_explicit_codes,1),0)<>1 or coalesce(array_length(v_rules,1),0)=0 then
      v_skipped:=v_skipped+1;
      v_actions:=v_actions||jsonb_build_array(jsonb_build_object('element_id',e.element_id,'element_code',e.element_code,'action','NO_WRITE','reason','EXACT_POSITIVE_COMPONENT_AUTHORITY_NOT_PRESENT'));
      continue;
    end if;

    select count(*),
           count(*) filter (where coalesce(r.pendiente_decision,false)),
           count(*) filter (where r.estado='CANDIDATO')
      into v_rule_found,v_rule_pending,v_rule_candidate
    from lf_ops.reglas r where r.codigo=any(v_rules) and r.estado in ('VIGENTE','CANDIDATO');
    if v_rule_found<>cardinality(v_rules) then
      v_skipped:=v_skipped+1;
      v_actions:=v_actions||jsonb_build_array(jsonb_build_object('element_id',e.element_id,'element_code',e.element_code,'action','NO_WRITE','reason','SOURCE_RULE_NOT_FOUND_OR_NOT_ACTIVE','rules',to_jsonb(v_rules)));
      continue;
    end if;
    if v_rule_pending>0 then
      v_skipped:=v_skipped+1;
      v_actions:=v_actions||jsonb_build_array(jsonb_build_object('element_id',e.element_id,'element_code',e.element_code,'action','NO_WRITE','reason','SOURCE_RULE_PENDING_DECISION','rules',to_jsonb(v_rules)));
      continue;
    end if;
    v_inherited:=case when v_rule_candidate>0 then 'CANDIDATO' else 'VIGENTE' end;
    v_new_status:=case when e.status='INACTIVO' then e.status else v_inherited end;

    v_code:=v_explicit_codes[1];
    select count(*),min(component_token_id) into v_token_count,v_token_id
    from lf_design.component_tokens
    where component_token_code=v_code and design_system_id=v_ds_id and status='VIGENTE';
    if v_token_count<>1 then
      v_skipped:=v_skipped+1;
      v_actions:=v_actions||jsonb_build_array(jsonb_build_object('element_id',e.element_id,'element_code',e.element_code,'action','NO_WRITE','reason','EXACT_TARGET_NOT_UNIQUE_VIGENTE','component_token_code',v_code));
      continue;
    end if;

    v_before:=jsonb_build_object('element_id',e.element_id,'component_token_id',e.component_token_id,'semantic_binding_status',e.semantic_binding_status,'status',e.status,'source_refs',e.source_refs);
    update lf_ops.pantalla_elementos
       set component_token_id=v_token_id,
           semantic_binding_status='RESOLVED_ID',
           status=v_new_status,
           source_refs=source_refs||jsonb_build_array('autofix:DEC-INPUT-GOV-SAFE-AUTOFIX-001','derive:DERIVE_FROM_VIGENTE_RULE_EXPLICIT_VALUE:COMPONENT_TOKEN_CODE_TO_ID:v1','inherited_status:'||v_inherited,'component_token_code:'||v_code),
           updated_at=now()
     where element_id=e.element_id
       and component_token_id is null
       and semantic_binding_status='PENDING_SEMANTIC_COMPONENT';
    if not found then raise exception 'SAFE_AUTOFIX_CONCURRENT_CHANGE:%',e.element_id; end if;

    select jsonb_build_object('element_id',element_id,'component_token_id',component_token_id,'semantic_binding_status',semantic_binding_status,'status',status,'source_refs',source_refs)
      into v_after from lf_ops.pantalla_elementos where element_id=e.element_id;
    if (v_after->>'component_token_id')::bigint<>v_token_id or v_after->>'semantic_binding_status'<>'RESOLVED_ID' or v_after->>'status'<>v_new_status then
      raise exception 'SAFE_AUTOFIX_READBACK_FAILED:%',e.element_id;
    end if;
    v_applied:=v_applied+1;
    v_actions:=v_actions||jsonb_build_array(jsonb_build_object('element_id',e.element_id,'element_code',e.element_code,'action','BIND_EXISTING_COMPONENT_EXPLICIT_TOKEN','component_token_code',v_code,'component_token_id',v_token_id,'source_rules',to_jsonb(v_rules),'inherited_status',v_inherited,'before',v_before,'after',v_after));
  end loop;

  return jsonb_build_object(
    'run_id',p_run_id,'pantalla_id',v_run.pantalla_id,
    'contract','INPUT_GOV_SAFE_AUTOFIX_V1',
    'decision','DEC-INPUT-GOV-SAFE-AUTOFIX-001',
    'class','DERIVE_FROM_VIGENTE_RULE_EXPLICIT_VALUE','class_decision','DEC-INPUT-GOV-SAFE-AUTOFIX-002','mapping',v_mapping,
    'applied_count',v_applied,'skipped_count',v_skipped,'source_conflict_count',v_conflicts,
    'successor_required',(v_applied>0),
    'actions',v_actions,
    'promotion_authorized',false,'production_authorized',false
  );
end;
$fn$;
