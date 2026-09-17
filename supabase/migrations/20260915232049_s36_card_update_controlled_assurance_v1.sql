-- LF_CARD_UPDATE_S36_CONTROLLED_ASSURANCE_V1
-- S36 may execute a reversible pre-promotion Card update assurance canary without production/runtime/promotion/Router authority.

begin;

update public.lf_operation_contracts
set allowed = coalesce(allowed,'{}'::jsonb) || jsonb_build_object(
      's36_controlled_assurance_write',true,
      's36_controlled_assurance_mode','S36_CONTROLLED_ASSURANCE',
      's36_controlled_assurance_scope','CARD_UPDATE_I8_PREPROMOTION_E2E',
      's36_controlled_assurance_requires_exact_qualifying_receipt',true,
      's36_controlled_assurance_requires_exact_readback',true,
      's36_controlled_assurance_requires_exact_rollback',true,
      's36_controlled_assurance_runtime_activation',false,
      's36_controlled_assurance_production_activation',false,
      's36_controlled_assurance_promotion_authorized',false,
      's36_controlled_assurance_router_activation_authorized',false
    ),
    blocked = coalesce(blocked,'[]'::jsonb) || jsonb_build_array(
      'controlled assurance outside S36_CONTROLLED_ASSURANCE mode',
      'controlled assurance without exact QUAL_QUALIFYING receipt',
      'controlled assurance against non-read-only or impact-enabled Card',
      'controlled assurance without exact rollback',
      'controlled assurance requests runtime production promotion or Router activation'
    ),
    updated_at=now(),
    updated_by_execution_id='EXEC-CARD-UPDATE-I8-CONTROLLED-ASSURANCE-PATCH-20260915-001'
where operation_code='ACTUALIZACION_CARD_LF'
  and status='CANDIDATO_READ_ONLY';

create or replace function public.lf_run_card_update_controlled_assurance_e2e_v1(
  p_execution_id text,
  p_new_content_text text
)
returns jsonb
language plpgsql
security invoker
set search_path to 'pg_catalog','public'
as $function$
declare
  x public.lf_operation_execution%rowtype;
  r public.lf_operation_registry%rowtype;
  a public.lf_activos%rowtype;
  oldc public.lf_card_content_versions%rowtype;
  newc public.lf_card_content_versions%rowtype;
  q public.lf_qualification_receipts%rowtype;
  binding_before jsonb;
  binding_after jsonb;
  revision_now text;
  fingerprint_now text;
  new_sha text;
  new_version text;
  parent_count int;
  step80_ok boolean;
  step85_ok boolean;
  receipt jsonb;
begin
  select * into x from public.lf_operation_execution where execution_id=p_execution_id for update;
  if not found
     or x.operation_code is distinct from 'ACTUALIZACION_CARD_LF'
     or x.target_type is distinct from 'CARD'
     or x.status is distinct from 'IN_PROGRESS' then
    return jsonb_build_object('outcome','BLOCKED','code','CARD_ASSURANCE_EXECUTION_INVALID');
  end if;

  if jsonb_typeof(x.manifest->'controlled_assurance_e2e_receipt')='object' then
    return (x.manifest->'controlled_assurance_e2e_receipt') || jsonb_build_object('outcome','REPLAY_PASS_WRITE_READBACK_ROLLBACK');
  end if;

  if jsonb_typeof(x.manifest) is distinct from 'object'
     or (x.manifest->>'mode') is distinct from 'S36_CONTROLLED_ASSURANCE'
     or (x.manifest->>'assurance_owner') is distinct from 'S36'
     or (x.manifest->>'assurance_scope') is distinct from 'CARD_UPDATE_I8_PREPROMOTION_E2E'
     or x.manifest->'controlled_write' is distinct from 'true'::jsonb
     or x.manifest->'rollback_required' is distinct from 'true'::jsonb
     or x.manifest->'runtime_activation' is distinct from 'false'::jsonb
     or x.manifest->'production_activation' is distinct from 'false'::jsonb
     or x.manifest->'promotion_authorized' is distinct from 'false'::jsonb
     or x.manifest->'router_activation_authorized' is distinct from 'false'::jsonb then
    return jsonb_build_object('outcome','BLOCKED','code','CARD_ASSURANCE_MODE_NOT_AUTHORIZED');
  end if;

  select * into r from public.lf_operation_registry where operation_code='ACTUALIZACION_CARD_LF';
  if not found or r.lifecycle_state_code is distinct from 'OP_CANDIDATE' or r.status is distinct from 'CANDIDATO_READ_ONLY' then
    return jsonb_build_object('outcome','BLOCKED','code','CARD_ASSURANCE_OPERATION_NOT_CANDIDATE');
  end if;

  if exists(select 1 from public.lf_router_action_registry where operation_code='ACTUALIZACION_CARD_LF' and status='ACTIVE') then
    return jsonb_build_object('outcome','BLOCKED','code','CARD_ASSURANCE_ROUTER_ALREADY_ACTIVE');
  end if;

  select * into a from public.lf_activos
  where codigo_activo=x.target_code and tipo_activo='CARD' and archived_at is null
  for update;

  if not found
     or a.estado_operativo is distinct from 'READ_ONLY'
     or a.impacto_automatico is distinct from 'BLOQUEADO'
     or a.runtime_estado not in ('PRODUCCION_CONTROLADA_READ_ONLY','CANDIDATE_READ_ONLY','SANDBOX_READ_ONLY') then
    return jsonb_build_object('outcome','BLOCKED','code','CARD_ASSURANCE_TARGET_NOT_READ_ONLY_CONTROLLED');
  end if;

  if (a.metadata->'source_governance'->>'external_card_carriers_allowed')::boolean is distinct from false
     or (a.metadata->'source_governance'->>'operational_authority') is distinct from 'SUPABASE'
     or (a.metadata->'carrier_binding_v1'->>'carrier_type') is distinct from 'SUPABASE_NATIVE_CARD_CONTENT' then
    return jsonb_build_object('outcome','BLOCKED','code','CARD_ASSURANCE_SUPABASE_AUTHORITY_INVALID');
  end if;

  binding_before:=a.metadata->'carrier_binding_v1';
  select * into oldc from public.lf_card_content_versions
  where id=(binding_before->>'content_row_id')::bigint and card_code=x.target_code and status='CURRENT'
  for update;

  if not found
     or oldc.content_sha256 is distinct from encode(extensions.digest(oldc.content_text,'sha256'),'hex')
     or oldc.content_chars is distinct from length(oldc.content_text) then
    return jsonb_build_object('outcome','BLOCKED','code','CARD_ASSURANCE_CURRENT_CONTENT_INVALID');
  end if;

  revision_now:=public.lf_operation_revision_sha256_v1('ACTUALIZACION_CARD_LF');
  fingerprint_now:=public.lf_required_test_suite_fingerprint_v1('OPERATION','ACTUALIZACION_CARD_LF');

  select * into q from public.lf_qualification_receipts
  where qualification_id=nullif(x.manifest->>'qualification_id','')::uuid
    and subject_type='OPERATION'
    and subject_code='ACTUALIZACION_CARD_LF'
    and lifecycle_state_code='QUAL_QUALIFYING'
    and invalidated_at is null
    and revision_sha256=revision_now
    and suite_set_fingerprint=fingerprint_now;

  if not found then
    return jsonb_build_object('outcome','BLOCKED','code','CARD_ASSURANCE_EXACT_QUALIFYING_RECEIPT_REQUIRED','current_revision_sha256',revision_now,'current_suite_set_fingerprint',fingerprint_now);
  end if;

  select exists(select 1 from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='pre_write_execution_binding_gate' and step_order=80 and status='STEP_PASS_WITH_EVIDENCE') into step80_ok;
  select exists(select 1 from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='expertise_quality_gate' and step_order=85 and status='STEP_PASS_WITH_EVIDENCE') into step85_ok;
  if not step80_ok or not step85_ok then
    return jsonb_build_object('outcome','BLOCKED','code','CARD_ASSURANCE_PREWRITE_OR_EXPERTISE_NOT_CLEAN','step80',step80_ok,'step85',step85_ok);
  end if;

  if p_new_content_text is null or btrim(p_new_content_text)='' or length(p_new_content_text)>200000 then
    return jsonb_build_object('outcome','BLOCKED','code','CARD_ASSURANCE_NEW_CONTENT_INVALID');
  end if;
  new_sha:=encode(extensions.digest(p_new_content_text,'sha256'),'hex');
  if new_sha is not distinct from oldc.content_sha256 then
    return jsonb_build_object('outcome','BLOCKED','code','CARD_ASSURANCE_WRITE_MUST_CHANGE_CONTENT');
  end if;

  new_version:=oldc.content_version||'-s36-assurance-'||substr(encode(extensions.digest(p_execution_id,'sha256'),'hex'),1,12);

  update public.lf_card_content_versions
  set status='RETIRED',retired_at=clock_timestamp(),retired_by_execution_id=p_execution_id
  where id=oldc.id and status='CURRENT';

  insert into public.lf_card_content_versions(
    card_code,content_version,content_text,content_sha256,content_chars,content_format,status,
    supersedes_id,created_by_execution_id,metadata
  ) values (
    x.target_code,new_version,p_new_content_text,new_sha,length(p_new_content_text),oldc.content_format,'CURRENT',oldc.id,p_execution_id,
    jsonb_build_object('controlled_assurance',true,'assurance_owner','S36','assurance_scope','CARD_UPDATE_I8_PREPROMOTION_E2E','rollback_required',true,'baseline_content_row_id',oldc.id,'baseline_content_sha256',oldc.content_sha256)
  ) returning * into newc;

  binding_after:=binding_before || jsonb_build_object(
    'carrier_ref','supabase://public/lf_card_content_versions/'||newc.id,
    'content_row_id',newc.id,
    'content_version',newc.content_version,
    'content_sha256',newc.content_sha256,
    'content_chars',newc.content_chars,
    'content_format',newc.content_format,
    'binding_execution_id',p_execution_id,
    'observed_at',clock_timestamp(),
    'carrier_write_allowed',false,
    'controlled_assurance_active',true
  );

  update public.lf_activos
  set ultima_revision=newc.content_version,
      metadata=jsonb_set(metadata,'{carrier_binding_v1}',binding_after,true),
      updated_by_execution_id=p_execution_id,
      updated_at=clock_timestamp()
  where id=a.id;

  select count(*) into parent_count from public.lf_activo_relaciones where codigo_activo=x.target_code and relacion_tipo='HIJO_DE';
  if parent_count<>1
     or not exists(
       select 1 from public.lf_activos aa
       join public.lf_card_content_versions cc on cc.id=(aa.metadata->'carrier_binding_v1'->>'content_row_id')::bigint
       where aa.id=a.id and cc.id=newc.id and cc.status='CURRENT'
         and cc.content_sha256=new_sha
         and cc.content_sha256=encode(extensions.digest(cc.content_text,'sha256'),'hex')
         and cc.content_chars=length(cc.content_text)
         and cc.created_by_execution_id=p_execution_id
     ) then
    raise exception 'CARD_ASSURANCE_WRITE_READBACK_FAILED';
  end if;

  -- Mandatory exact rollback before the function can return success.
  update public.lf_card_content_versions
  set status='RETIRED',retired_at=clock_timestamp(),retired_by_execution_id=p_execution_id
  where id=newc.id and status='CURRENT';

  update public.lf_card_content_versions
  set status='CURRENT',retired_at=null,retired_by_execution_id=null
  where id=oldc.id and status='RETIRED';

  update public.lf_activos
  set ultima_revision=oldc.content_version,
      metadata=jsonb_set(metadata,'{carrier_binding_v1}',binding_before,true),
      updated_by_execution_id=p_execution_id,
      updated_at=clock_timestamp()
  where id=a.id;

  if not exists(
    select 1 from public.lf_activos aa
    join public.lf_card_content_versions cc on cc.id=(aa.metadata->'carrier_binding_v1'->>'content_row_id')::bigint
    where aa.id=a.id and cc.id=oldc.id and cc.status='CURRENT'
      and cc.content_sha256=oldc.content_sha256
      and aa.ultima_revision=oldc.content_version
      and (aa.metadata->'carrier_binding_v1') is not distinct from binding_before
  ) or not exists(
    select 1 from public.lf_card_content_versions where id=newc.id and status='RETIRED'
  ) then
    raise exception 'CARD_ASSURANCE_ROLLBACK_READBACK_FAILED';
  end if;

  receipt:=jsonb_build_object(
    'outcome','PASS_WRITE_READBACK_ROLLBACK',
    'execution_id',p_execution_id,
    'card_code',x.target_code,
    'qualification_id',q.qualification_id,
    'operation_revision_sha256',revision_now,
    'suite_set_fingerprint',fingerprint_now,
    'content_store_type','SUPABASE_NATIVE_CARD_CONTENT',
    'write_route','S36_CONTROLLED_ASSURANCE_SUPABASE_IMMUTABLE_CONTENT_VERSION_INSERT',
    'baseline',jsonb_build_object('content_row_id',oldc.id,'content_version',oldc.content_version,'content_sha256',oldc.content_sha256,'binding',binding_before),
    'write',jsonb_build_object('content_row_id',newc.id,'content_version',newc.content_version,'content_sha256',newc.content_sha256,'supersedes_content_row_id',oldc.id,'optimistic_lock_applied',true),
    'readback',jsonb_build_object('content_row_id',newc.id,'content_version',newc.content_version,'content_sha256',newc.content_sha256,'parent_source_preserved',true,'independent_readback',true),
    'rollback',jsonb_build_object('exact_baseline_restored',true,'baseline_content_row_id',oldc.id,'assurance_content_row_id',newc.id,'assurance_content_status','RETIRED'),
    'runtime_activation',false,
    'production_activation',false,
    'promotion_authorized',false,
    'router_activation_authorized',false
  );

  update public.lf_operation_execution
  set manifest=manifest || jsonb_build_object('controlled_assurance_e2e_receipt',receipt),
      updated_by_execution_id=p_execution_id,
      updated_at=clock_timestamp()
  where execution_id=p_execution_id;

  return receipt;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    return jsonb_build_object('outcome','BLOCKED','code','CARD_ASSURANCE_TYPE_INVALID');
end;
$function$;

create or replace function public.lf_validate_card_update_step_evidence_v6(
  p_execution_id text,
  p_step_id text,
  p_evidence_payload jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path to 'pg_catalog','public'
as $function$
declare
  x public.lf_operation_execution%rowtype;
  receipt jsonb;
  assertions jsonb:=jsonb_build_array(
    'required evidence present',
    'prior required steps clean',
    'Supabase operational authority preserved',
    'external carrier not used as authority'
  );
begin
  if p_step_id in ('router','card_resolve','carrier_resolve','parent_source_read','baseline_read','change_scope','regression_plan','pre_write_execution_binding_gate') then
    return public.lf_validate_card_update_step_evidence_v5(p_execution_id,p_step_id,p_evidence_payload);
  end if;
  if p_evidence_payload is null or jsonb_typeof(p_evidence_payload) is distinct from 'object' then
    return jsonb_build_object('valid',false,'code','CARD_STEP_EVIDENCE_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
  end if;

  select * into x from public.lf_operation_execution where execution_id=p_execution_id;
  if not found or x.operation_code is distinct from 'ACTUALIZACION_CARD_LF' or x.target_type is distinct from 'CARD' or x.status is distinct from 'IN_PROGRESS' then
    return jsonb_build_object('valid',false,'code','CARD_ASSURANCE_EXECUTION_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
  end if;
  if (x.manifest->>'mode') is distinct from 'S36_CONTROLLED_ASSURANCE'
     or (x.manifest->>'assurance_owner') is distinct from 'S36'
     or x.manifest->'runtime_activation' is distinct from 'false'::jsonb
     or x.manifest->'production_activation' is distinct from 'false'::jsonb
     or x.manifest->'promotion_authorized' is distinct from 'false'::jsonb
     or x.manifest->'router_activation_authorized' is distinct from 'false'::jsonb then
    return jsonb_build_object('valid',false,'code','CARD_ASSURANCE_MODE_NOT_AUTHORIZED','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('runtime or automatic promotion requested'));
  end if;

  receipt:=x.manifest->'controlled_assurance_e2e_receipt';
  if jsonb_typeof(receipt) is distinct from 'object' or (receipt->>'outcome') is distinct from 'PASS_WRITE_READBACK_ROLLBACK' then
    return jsonb_build_object('valid',false,'code','CARD_ASSURANCE_E2E_RECEIPT_REQUIRED','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
  end if;

  if p_step_id='carrier_write_dispatch' then
    if (p_evidence_payload->>'content_store_type') is distinct from (receipt->>'content_store_type')
       or (p_evidence_payload->>'write_route') is distinct from (receipt->>'write_route')
       or jsonb_typeof(p_evidence_payload->'write_receipt') is distinct from 'object'
       or (p_evidence_payload->>'new_content_version') is distinct from (receipt->'write'->>'content_version')
       or (p_evidence_payload->>'new_content_sha256') is distinct from (receipt->'write'->>'content_sha256')
       or (p_evidence_payload->>'supersedes_content_row_id')::bigint is distinct from (receipt->'write'->>'supersedes_content_row_id')::bigint
       or p_evidence_payload->'optimistic_lock_applied' is distinct from 'true'::jsonb then
      return jsonb_build_object('valid',false,'code','CARD_ASSURANCE_WRITE_EVIDENCE_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
    end if;
  elsif p_step_id='carrier_readback' then
    if (p_evidence_payload->>'readback_content_row_id')::bigint is distinct from (receipt->'readback'->>'content_row_id')::bigint
       or (p_evidence_payload->>'readback_content_version') is distinct from (receipt->'readback'->>'content_version')
       or (p_evidence_payload->>'readback_content_hash') is distinct from (receipt->'readback'->>'content_sha256')
       or p_evidence_payload->'parent_source_preserved' is distinct from 'true'::jsonb
       or p_evidence_payload->'independent_readback' is distinct from 'true'::jsonb then
      return jsonb_build_object('valid',false,'code','CARD_ASSURANCE_READBACK_EVIDENCE_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
    end if;
  elsif p_step_id='deterministic_validation' then
    if p_evidence_payload->'content_binding_match' is distinct from 'true'::jsonb
       or p_evidence_payload->'version_match' is distinct from 'true'::jsonb
       or p_evidence_payload->'content_hash_match' is distinct from 'true'::jsonb
       or p_evidence_payload->'identity_match' is distinct from 'true'::jsonb
       or p_evidence_payload->'source_policy_match' is distinct from 'true'::jsonb
       or jsonb_typeof(p_evidence_payload->'negative_regressions') is distinct from 'object'
       or p_evidence_payload->'negative_regressions'->'direct_non_assurance_write_blocked' is distinct from 'true'::jsonb
       or p_evidence_payload->'negative_regressions'->'production_activation_blocked' is distinct from 'true'::jsonb
       or p_evidence_payload->'negative_regressions'->'router_activation_blocked' is distinct from 'true'::jsonb
       or p_evidence_payload->'negative_regressions'->'stale_or_wrong_qualification_blocked' is distinct from 'true'::jsonb then
      return jsonb_build_object('valid',false,'code','CARD_ASSURANCE_DETERMINISTIC_VALIDATION_FAILED','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
    end if;
  elsif p_step_id='semantic_judge' then
    if (p_evidence_payload->>'semantic_judge_result') is distinct from 'PASS_CONTROLLED_ASSURANCE_ONLY'
       or (p_evidence_payload->>'parent_source_check') is distinct from 'PRESERVED'
       or (p_evidence_payload->>'claim_ceiling_check') is distinct from 'ASSURANCE_ONLY_NO_RUNTIME_NO_PRODUCTION_NO_PROMOTION_NO_ROUTER'
       or jsonb_typeof(p_evidence_payload->'authority_checks') is distinct from 'object'
       or p_evidence_payload->'authority_checks'->'supabase_authority_preserved' is distinct from 'true'::jsonb
       or p_evidence_payload->'authority_checks'->'runtime_activation' is distinct from 'false'::jsonb
       or p_evidence_payload->'authority_checks'->'production_activation' is distinct from 'false'::jsonb
       or p_evidence_payload->'authority_checks'->'promotion_authorized' is distinct from 'false'::jsonb
       or p_evidence_payload->'authority_checks'->'router_activation_authorized' is distinct from 'false'::jsonb then
      return jsonb_build_object('valid',false,'code','CARD_ASSURANCE_SEMANTIC_JUDGE_FAILED','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
    end if;
  elsif p_step_id='regression_after' then
    if receipt->'rollback'->'exact_baseline_restored' is distinct from 'true'::jsonb
       or jsonb_typeof(p_evidence_payload->'before_after_matrix') is distinct from 'object'
       or p_evidence_payload->'before_after_matrix'->'exact_baseline_restored' is distinct from 'true'::jsonb
       or (p_evidence_payload->>'wrong_content_binding_negative') is distinct from 'PASS_BLOCKED'
       or (p_evidence_payload->>'stale_content_revision_negative') is distinct from 'PASS_BLOCKED'
       or (p_evidence_payload->>'missing_current_content_negative') is distinct from 'PASS_BLOCKED'
       or (p_evidence_payload->>'holdout_result') is distinct from 'PASS_I8_CONTROLLED_E2E' then
      return jsonb_build_object('valid',false,'code','CARD_ASSURANCE_REGRESSION_FAILED','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
    end if;
  elsif p_step_id='close' then
    if receipt->'rollback'->'exact_baseline_restored' is distinct from 'true'::jsonb
       or p_evidence_payload->'all_required_steps_clean' is distinct from 'true'::jsonb
       or jsonb_typeof(p_evidence_payload->'open_blockers') is distinct from 'array'
       or jsonb_array_length(p_evidence_payload->'open_blockers')<>0
       or p_evidence_payload->'runtime_unchanged' is distinct from 'true'::jsonb
       or p_evidence_payload->'no_auto_promotion' is distinct from 'true'::jsonb
       or p_evidence_payload->'history_preserved' is distinct from 'true'::jsonb
       or p_evidence_payload->'source_policy_current' is distinct from 'true'::jsonb then
      return jsonb_build_object('valid',false,'code','CARD_ASSURANCE_CLOSE_NOT_CLEAN','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
    end if;
  elsif p_step_id='report_output' then
    if (p_evidence_payload->>'result') is distinct from 'PASS_CONTROLLED_ASSURANCE_NO_PROMOTION'
       or (p_evidence_payload->>'card_code') is distinct from x.target_code
       or (p_evidence_payload->>'content_ref') is distinct from ('supabase://public/lf_card_content_versions/'||(receipt->'baseline'->>'content_row_id'))
       or jsonb_typeof(p_evidence_payload->'evidence_refs') is distinct from 'array'
       or jsonb_array_length(p_evidence_payload->'evidence_refs')<1
       or jsonb_typeof(p_evidence_payload->'open_blockers') is distinct from 'array'
       or jsonb_array_length(p_evidence_payload->'open_blockers')<>0
       or (p_evidence_payload->>'next_gate') is distinct from 'INDEPENDENT_REVIEW_FINALIZATION' then
      return jsonb_build_object('valid',false,'code','CARD_ASSURANCE_REPORT_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
    end if;
  else
    return jsonb_build_object('valid',false,'code','CARD_STEP_NOT_SUPPORTED_BY_V6','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
  end if;

  return jsonb_build_object('valid',true,'code','CARD_ASSURANCE_STEP_EXACT','server_assertions',assertions,'server_hard_fails','[]'::jsonb);
exception
  when invalid_text_representation or numeric_value_out_of_range then
    return jsonb_build_object('valid',false,'code','CARD_ASSURANCE_STEP_TYPE_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
end;
$function$;

create or replace function public.lf_record_card_operation_step_v1(
  p_execution_id text,
  p_step_id text,
  p_evidence_ref text,
  p_evidence_payload jsonb,
  p_actor_execution_id text
)
returns jsonb
language plpgsql
security invoker
set search_path to 'pg_catalog','public'
as $function$
declare
  step_order_now integer;
  validation jsonb;
  x public.lf_operation_execution%rowtype;
begin
  select step_order into step_order_now from public.lf_operation_steps
  where operation_code='ACTUALIZACION_CARD_LF' and step_id=p_step_id and active is true;
  if step_order_now is null then return jsonb_build_object('outcome','BLOCKED','code','STEP_NOT_ACTIVE','durable',false); end if;

  if step_order_now>85 then
    select * into x from public.lf_operation_execution where execution_id=p_execution_id;
    if not found
       or (x.manifest->>'mode') is distinct from 'S36_CONTROLLED_ASSURANCE'
       or (x.manifest->>'assurance_owner') is distinct from 'S36'
       or (x.manifest->'controlled_assurance_e2e_receipt'->>'outcome') is distinct from 'PASS_WRITE_READBACK_ROLLBACK' then
      validation:=jsonb_build_object(
        'valid',false,
        'code','CARD_UPDATE_WRITE_PHASE_NOT_AUTHORIZED_I8',
        'details',jsonb_build_object('step_order',step_order_now,'ceiling_step_order',85,'controlled_assurance_required',true),
        'server_assertions','[]'::jsonb,
        'server_hard_fails',jsonb_build_array('runtime or automatic promotion requested')
      );
    else
      validation:=public.lf_validate_card_update_step_evidence_v6(p_execution_id,p_step_id,p_evidence_payload);
    end if;
  elsif p_step_id='expertise_quality_gate' then
    validation:=public.lf_validate_card_expertise_gate_v1(p_execution_id,p_step_id,p_evidence_payload);
  else
    validation:=public.lf_validate_card_update_step_evidence_v6(p_execution_id,p_step_id,p_evidence_payload);
  end if;

  return public.lf_record_operation_step_core_v1(
    p_execution_id,p_step_id,p_evidence_ref,p_evidence_payload,p_actor_execution_id,
    'ACTUALIZACION_CARD_LF','CARD',
    'CANDIDATO_READ_ONLY','CANDIDATO_READ_ONLY','CANDIDATO_READ_ONLY',
    validation,true,'lf_record_card_operation_step_v1'
  );
end;
$function$;

update public.lf_operation_step_contracts
set notes=concat_ws(' | ',nullif(notes,''),'I8: steps 90-150 may be evidenced by S36 only after atomic PASS_WRITE_READBACK_ROLLBACK receipt from S36_CONTROLLED_ASSURANCE; no runtime, production, promotion or Router authority.'),
    updated_at=now(),
    updated_by_execution_id='EXEC-CARD-UPDATE-I8-CONTROLLED-ASSURANCE-PATCH-20260915-001'
where operation_code='ACTUALIZACION_CARD_LF'
  and step_order between 90 and 150
  and status='CANDIDATO_READ_ONLY';

revoke all on function public.lf_run_card_update_controlled_assurance_e2e_v1(text,text) from public,anon,authenticated;
revoke all on function public.lf_validate_card_update_step_evidence_v6(text,text,jsonb) from public,anon,authenticated;
revoke all on function public.lf_record_card_operation_step_v1(text,text,text,jsonb,text) from public,anon,authenticated;
grant execute on function public.lf_run_card_update_controlled_assurance_e2e_v1(text,text) to service_role;
grant execute on function public.lf_validate_card_update_step_evidence_v6(text,text,jsonb) to service_role;
grant execute on function public.lf_record_card_operation_step_v1(text,text,text,jsonb,text) to service_role;

do $$
declare
  recorder_def text;
  runner_def text;
  validator_def text;
begin
  select pg_get_functiondef('public.lf_record_card_operation_step_v1(text,text,text,jsonb,text)'::regprocedure) into recorder_def;
  select pg_get_functiondef('public.lf_run_card_update_controlled_assurance_e2e_v1(text,text)'::regprocedure) into runner_def;
  select pg_get_functiondef('public.lf_validate_card_update_step_evidence_v6(text,text,jsonb)'::regprocedure) into validator_def;
  if position('S36_CONTROLLED_ASSURANCE' in recorder_def)=0
     or position('CARD_UPDATE_WRITE_PHASE_NOT_AUTHORIZED_I8' in recorder_def)=0
     or position('PASS_WRITE_READBACK_ROLLBACK' in runner_def)=0
     or position('ROLLBACK_READBACK_FAILED' in runner_def)=0
     or position('PASS_CONTROLLED_ASSURANCE_NO_PROMOTION' in validator_def)=0 then
    raise exception 'CARD_UPDATE_S36_CONTROLLED_ASSURANCE_STRUCTURAL_ASSERTION_FAILED';
  end if;
  if exists(select 1 from public.lf_router_action_registry where operation_code='ACTUALIZACION_CARD_LF' and status='ACTIVE') then
    raise exception 'CARD_UPDATE_S36_CONTROLLED_ASSURANCE_MUST_NOT_ACTIVATE_ROUTER';
  end if;
  if not exists(select 1 from public.lf_operation_registry where operation_code='ACTUALIZACION_CARD_LF' and lifecycle_state_code='OP_CANDIDATE' and status='CANDIDATO_READ_ONLY') then
    raise exception 'CARD_UPDATE_S36_CONTROLLED_ASSURANCE_MUST_REMAIN_CANDIDATE';
  end if;
end $$;

commit;
