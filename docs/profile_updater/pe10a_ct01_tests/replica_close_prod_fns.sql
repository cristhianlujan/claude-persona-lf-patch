-- Copias literales (pg_get_functiondef, produccion 2026-10-27) de dos funciones oficiales
CREATE OR REPLACE FUNCTION programacion.fn_engineering_checkpoint_assertion_record_v1(p_plan_code text, p_unit_code text, p_checkpoint_code text, p_result jsonb, p_actor text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
declare
  v_work_item_id bigint; v_checkpoint_id bigint; v_current_code text; v_spec jsonb; v_contract jsonb; v_contract_sha text;
  v_mode text; v_pass boolean := false; v_pass_when jsonb; v_result_sha text; v_evidence_ref text;
  v_recorded_at timestamptz := clock_timestamp(); v_receipt jsonb; v_receipt_sha text; v_observed jsonb;
begin
  if jsonb_typeof(p_result)<>'object' then
    raise exception 'ENGINEERING_ASSERTION_RESULT_OBJECT_REQUIRED:%/%/%',p_plan_code,p_unit_code,p_checkpoint_code;
  end if;
  select pu.work_item_id into v_work_item_id from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code and pu.disposition='ASSIGNED';
  if v_work_item_id is null then raise exception 'ENGINEERING_ASSERTION_UNIT_NOT_FOUND:%/%',p_plan_code,p_unit_code; end if;
  select c.id into v_checkpoint_id from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id and c.checkpoint_code=p_checkpoint_code for update;
  if v_checkpoint_id is null then raise exception 'ENGINEERING_ASSERTION_CHECKPOINT_NOT_FOUND:%/%/%',p_plan_code,p_unit_code,p_checkpoint_code; end if;
  select c.checkpoint_code into v_current_code from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id and c.status not in ('DONE','NOT_APPLICABLE') order by c.sequence_no limit 1;
  IF v_current_code IS DISTINCT FROM p_checkpoint_code
    AND NOT EXISTS (SELECT 1 FROM programacion.engineering_plan_units pu
      WHERE pu.work_item_id=v_work_item_id AND pu.plan_code=p_plan_code AND pu.unit_code=p_unit_code
        AND pu.disposition='ASSIGNED' AND pu.unit_metadata->>'checkpoint_ordering'='INDEPENDENT_METHOD_VARIANTS'
        AND pu.unit_metadata->>'method_execution_contract'='PE10_METHOD_V1'
        AND jsonb_typeof(pu.unit_metadata#>array['action_specs_v1',p_checkpoint_code,'assertion_contract','pass_when'])='object')
  THEN raise exception 'ENGINEERING_ASSERTION_CHECKPOINT_NOT_CURRENT:% current=%',p_checkpoint_code,coalesce(v_current_code,'<terminal>'); end if;
  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(p_plan_code,p_unit_code,p_checkpoint_code);
  v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(p_plan_code,p_unit_code,p_checkpoint_code,v_spec);
  if coalesce(v_contract->>'status','')<>'READY' then raise exception 'ENGINEERING_ASSERTION_CONTRACT_NOT_READY:%',coalesce(v_contract::text,'{}'); end if;
  v_contract_sha:=programacion.fn_v09_sha256_jsonb(v_contract);
  v_mode:=v_contract->>'mode'; v_observed:=p_result->'observed';
  if v_mode='EXPLICIT_PASS_WHEN_SUBSET' then
    v_pass_when:=v_contract->'pass_when';
    v_evidence_ref:=nullif(btrim(coalesce(p_result->>'evidence_ref','')),'');
    v_pass := p_result->>'status'='PASS' and jsonb_typeof(v_observed)='object' and v_observed @> v_pass_when and v_evidence_ref is not null;
  else raise exception 'ENGINEERING_ASSERTION_MODE_UNSUPPORTED:%',v_mode; end if;
  if not v_pass then raise exception 'ENGINEERING_ASSERTION_RESULT_FAILED:%/%/% mode=%',p_plan_code,p_unit_code,p_checkpoint_code,v_mode; end if;
  v_result_sha:=programacion.fn_v09_sha256_jsonb(p_result);
  v_receipt:=jsonb_build_object('schema_version','ENGINEERING_CHECKPOINT_ASSERTION_RECEIPT_V1','passed',true,'mode',v_mode,
    'plan_code',p_plan_code,'unit_code',p_unit_code,'checkpoint_code',p_checkpoint_code,'contract_sha256',v_contract_sha,
    'result_sha256',v_result_sha,'evidence_ref',v_evidence_ref,'recorded_at',v_recorded_at,
    'recorded_by',coalesce(nullif(btrim(p_actor),''),'ENGINEERING_ASSERTION_RECORDER'));
  v_receipt_sha:=programacion.fn_v09_sha256_jsonb(v_receipt);
  update programacion.engineering_work_checkpoints set assertion_contract_sha256=v_contract_sha, assertion_receipt=v_receipt,
     assertion_receipt_sha256=v_receipt_sha, assertion_recorded_at=v_recorded_at,
     assertion_recorded_by=coalesce(nullif(btrim(p_actor),''),'ENGINEERING_ASSERTION_RECORDER'), updated_at=now(),
     updated_by_execution_id=coalesce(nullif(btrim(p_actor),''),'ENGINEERING_ASSERTION_RECORDER') where id=v_checkpoint_id;
  return v_receipt || jsonb_build_object('assertion_receipt_sha256',v_receipt_sha);
end;
$function$;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_checkpoint_transition_v1(p_plan_code text, p_unit_code text, p_checkpoint_code text, p_new_status text, p_evidence_ref text, p_actor text, p_detail text DEFAULT NULL::text)
 RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
declare
  v_work_item_id bigint; v_current_code text; v_existing_status text; v_remaining int; v_open_blockers int; v_unmet_deps int;
  v_result jsonb; v_progress text; v_next text;
begin
  if p_new_status not in ('DONE','NOT_APPLICABLE','IN_PROGRESS') then raise exception 'STATUS_UNSUPPORTED'; end if;
  select pu.work_item_id into v_work_item_id from programacion.engineering_plan_units pu where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code;
  if v_work_item_id is null then raise exception 'Canonical unit not found: %/%',p_plan_code,p_unit_code; end if;
  select c.status into v_existing_status from programacion.engineering_work_checkpoints c where c.work_item_id=v_work_item_id and c.checkpoint_code=p_checkpoint_code;
  if v_existing_status in ('DONE','NOT_APPLICABLE') then
    return programacion.fn_engineering_unit_bootstrap_with_contract_repair_v1(p_plan_code,p_unit_code) || jsonb_build_object('transition',jsonb_build_object('status','NOOP_ALREADY_TERMINAL','checkpoint_code',p_checkpoint_code));
  end if;
  select c.checkpoint_code into v_current_code from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id and c.status not in ('DONE','NOT_APPLICABLE') order by c.sequence_no limit 1;
  IF v_current_code IS DISTINCT FROM p_checkpoint_code
    AND NOT EXISTS (SELECT 1 FROM programacion.engineering_plan_units pu WHERE pu.work_item_id=v_work_item_id AND pu.plan_code=p_plan_code AND pu.unit_code=p_unit_code
        AND pu.disposition='ASSIGNED' AND pu.unit_metadata->>'checkpoint_ordering'='INDEPENDENT_METHOD_VARIANTS'
        AND pu.unit_metadata->>'method_execution_contract'='PE10_METHOD_V1'
        AND jsonb_typeof(pu.unit_metadata#>array['action_specs_v1',p_checkpoint_code,'assertion_contract','pass_when'])='object')
  THEN raise exception 'Checkpoint % is not current; current=%',p_checkpoint_code,v_current_code; end if;
  if p_new_status in ('DONE','NOT_APPLICABLE') and coalesce(nullif(btrim(p_evidence_ref),''),nullif(btrim(p_detail),'')) is null then
    raise exception 'Terminal checkpoint transition requires evidence_ref or detail'; end if;
  update programacion.engineering_work_checkpoints set status=p_new_status, evidence_ref=coalesce(nullif(p_evidence_ref,''),evidence_ref),
     completed_at=case when p_new_status='DONE' then now() else completed_at end, updated_at=now(),
     updated_by_execution_id=coalesce(nullif(p_actor,''),'ENGINEERING_CHECKPOINT_TRANSITION_V1')
   where work_item_id=v_work_item_id and checkpoint_code=p_checkpoint_code;
  v_result:=programacion.fn_engineering_unit_bootstrap_with_contract_repair_v1(p_plan_code,p_unit_code);
  v_progress:=coalesce(v_result#>>'{state,progress_pct}','0'); v_next:=coalesce(v_result#>>'{terminal_action}','UNKNOWN');
  insert into programacion.engineering_work_updates(work_item_id,update_type,summary,detail,next_action,evidence_refs,reported_by,observed_at,created_by_execution_id)
  values (v_work_item_id,'PROGRESS','Checkpoint '||p_checkpoint_code||' -> '||p_new_status,p_detail,v_next,
    case when nullif(p_evidence_ref,'') is null then '[]'::jsonb else jsonb_build_array(p_evidence_ref) end,
    coalesce(nullif(p_actor,''),'ENGINEERING_CHECKPOINT_TRANSITION_V1'),now(),coalesce(nullif(p_actor,''),'ENGINEERING_CHECKPOINT_TRANSITION_V1'));
  return v_result || jsonb_build_object('transition',jsonb_build_object('status','APPLIED','checkpoint_code',p_checkpoint_code,'new_status',p_new_status));
end;
$function$;
