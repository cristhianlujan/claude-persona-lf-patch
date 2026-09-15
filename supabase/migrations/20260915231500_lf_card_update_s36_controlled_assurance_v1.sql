-- LF_CARD_UPDATE_S36_CONTROLLED_ASSURANCE_V1
-- Purpose: let S36 execute ACTUALIZACION_CARD_LF pre-promotion E2E autonomously on read-only controlled Cards.
-- This does NOT authorize production/runtime activation, OP promotion, Router activation, or general Card writes.
-- Any controlled assurance write must be exact-qualification-bound, reversible, read back, and rolled back before close.

begin;

-- Preserve candidate lifecycle while declaring the narrowly bounded assurance mode.
update public.lf_operation_contracts
set allowed = coalesce(allowed,'{}'::jsonb) || jsonb_build_object(
      's36_controlled_assurance_write', true,
      's36_controlled_assurance_mode', 'S36_CONTROLLED_ASSURANCE',
      's36_controlled_assurance_scope', 'CARD_UPDATE_I8_PREPROMOTION_E2E',
      's36_controlled_assurance_requires_exact_qualifying_receipt', true,
      's36_controlled_assurance_requires_readback', true,
      's36_controlled_assurance_requires_rollback_before_close', true,
      's36_controlled_assurance_runtime_activation', false,
      's36_controlled_assurance_production_activation', false,
      's36_controlled_assurance_promotion_authorized', false,
      's36_controlled_assurance_router_activation_authorized', false
    ),
    blocked = coalesce(blocked,'[]'::jsonb) || jsonb_build_array(
      'controlled assurance outside S36_CONTROLLED_ASSURANCE mode',
      'controlled assurance without exact QUAL_QUALIFYING receipt',
      'controlled assurance against writable/production-impact Card',
      'controlled assurance without exact rollback',
      'controlled assurance attempts runtime production promotion or Router activation'
    ),
    updated_at = now(),
    updated_by_execution_id = 'EXEC-S36-I8-CONTROLLED-ASSURANCE-IMPLEMENT-20260915-001'
where operation_code='ACTUALIZACION_CARD_LF'
  and status='CANDIDATO_READ_ONLY';

create or replace function public.lf_card_update_controlled_assurance_context_v1(
  p_execution_id text
)
returns jsonb
language plpgsql
security invoker
set search_path to 'pg_catalog','public'
as $function$
declare
  v_execution public.lf_operation_execution%rowtype;
  v_registry public.lf_operation_registry%rowtype;
  v_card public.lf_activos%rowtype;
  v_content public.lf_card_content_versions%rowtype;
  v_qualification public.lf_qualification_receipts%rowtype;
  v_revision text;
  v_fingerprint text;
  v_binding jsonb;
  v_step80 boolean := false;
  v_step85 boolean := false;
begin
  select * into v_execution
  from public.lf_operation_execution
  where execution_id=p_execution_id;

  if not found
     or v_execution.operation_code is distinct from 'ACTUALIZACION_CARD_LF'
     or v_execution.target_type is distinct from 'CARD'
     or v_execution.status is distinct from 'IN_PROGRESS' then
    return jsonb_build_object('valid',false,'code','CARD_ASSURANCE_EXECUTION_INVALID');
  end if;

  if jsonb_typeof(v_execution.manifest) is distinct from 'object'
     or (v_execution.manifest->>'mode') is distinct from 'S36_CONTROLLED_ASSURANCE'
     or (v_execution.manifest->>'assurance_owner') is distinct from 'S36'
     or (v_execution.manifest->>'assurance_scope') is distinct from 'CARD_UPDATE_I8_PREPROMOTION_E2E'
     or v_execution.manifest->'controlled_write' is distinct from 'true'::jsonb
     or v_execution.manifest->'rollback_required' is distinct from 'true'::jsonb
     or v_execution.manifest->'runtime_activation' is distinct from 'false'::jsonb
     or v_execution.manifest->'production_activation' is distinct from 'false'::jsonb
     or v_execution.manifest->'promotion_authorized' is distinct from 'false'::jsonb
     or v_execution.manifest->'router_activation_authorized' is distinct from 'false'::jsonb then
    return jsonb_build_object('valid',false,'code','CARD_ASSURANCE_MODE_NOT_AUTHORIZED');
  end if;

  select * into v_registry
  from public.lf_operation_registry
  where operation_code='ACTUALIZACION_CARD_LF';

  if not found
     or v_registry.lifecycle_state_code is distinct from 'OP_CANDIDATE'
     or v_registry.status is distinct from 'CANDIDATO_READ_ONLY' then
    return jsonb_build_object('valid',false,'code','CARD_ASSURANCE_OPERATION_NOT_CANDIDATE');
  end if;

  if exists (
    select 1 from public.lf_router_action_registry
    where operation_code='ACTUALIZACION_CARD_LF' and status='ACTIVE'
  ) then
    return jsonb_build_object('valid',false,'code','CARD_ASSURANCE_ROUTER_ALREADY_ACTIVE');
  end if;

  select * into v_card
  from public.lf_activos
  where codigo_activo=v_execution.target_code
    and tipo_activo='CARD'
    and archived_at is null;

  if not found
     or v_card.estado_operativo is distinct from 'READ_ONLY'
     or v_card.impacto_automatico is distinct from 'BLOQUEADO'
     or v_card.runtime_estado not in ('PRODUCCION_CONTROLADA_READ_ONLY','CANDIDATE_READ_ONLY','SANDBOX_READ_ONLY') then
    return jsonb_build_object('valid',false,'code','CARD_ASSURANCE_TARGET_NOT_READ_ONLY_CONTROLLED');
  end if;

  if (v_card.metadata->'source_governance'->>'external_card_carriers_allowed')::boolean is distinct from false
     or (v_card.metadata->'source_governance'->>'operational_authority') is distinct from 'SUPABASE'
     or (v_card.metadata->'carrier_binding_v1'->>'carrier_type') is distinct from 'SUPABASE_NATIVE_CARD_CONTENT' then
    return jsonb_build_object('valid',false,'code','CARD_ASSURANCE_SUPABASE_AUTHORITY_INVALID');
  end if;

  v_binding:=v_card.metadata->'carrier_binding_v1';
  select * into v_content
  from public.lf_card_content_versions
  where id=(v_binding->>'content_row_id')::bigint
    and card_code=v_execution.target_code
    and status='CURRENT';

  if not found
     or v_content.content_sha256 is distinct from encode(extensions.digest(v_content.content_text,'sha256'),'hex')
     or v_content.content_chars is distinct from length(v_content.content_text) then
    return jsonb_build_object('valid',false,'code','CARD_ASSURANCE_CURRENT_CONTENT_INVALID');
  end if;

  v_revision:=public.lf_operation_revision_sha256_v1('ACTUALIZACION_CARD_LF');
  v_fingerprint:=public.lf_required_test_suite_fingerprint_v1('OPERATION','ACTUALIZACION_CARD_LF');

  select * into v_qualification
  from public.lf_qualification_receipts
  where qualification_id=nullif(v_execution.manifest->>'qualification_id','')::uuid
    and subject_type='OPERATION'
    and subject_code='ACTUALIZACION_CARD_LF'
    and lifecycle_state_code='QUAL_QUALIFYING'
    and invalidated_at is null
    and revision_sha256=v_revision
    and suite_set_fingerprint=v_fingerprint;

  if not found then
    return jsonb_build_object(
      'valid',false,
      'code','CARD_ASSURANCE_EXACT_QUALIFYING_RECEIPT_REQUIRED',
      'current_revision_sha256',v_revision,
      'current_suite_set_fingerprint',v_fingerprint
    );
  end if;

  select exists(
    select 1 from public.lf_operation_execution_steps
    where execution_id=p_execution_id
      and step_id='pre_write_execution_binding_gate'
      and step_order=80
      and status='STEP_PASS_WITH_EVIDENCE'
  ) into v_step80;

  select exists(
    select 1 from public.lf_operation_execution_steps
    where execution_id=p_execution_id
      and step_id='expertise_quality_gate'
      and step_order=85
      and status='STEP_PASS_WITH_EVIDENCE'
  ) into v_step85;

  if not v_step80 or not v_step85 then
    return jsonb_build_object('valid',false,'code','CARD_ASSURANCE_PREWRITE_OR_EXPERTISE_NOT_CLEAN','step80',v_step80,'step85',v_step85);
  end if;

  return jsonb_build_object(
    'valid',true,
    'code','CARD_ASSURANCE_CONTEXT_EXACT',
    'card_code',v_execution.target_code,
    'card_id',v_card.id,
    'qualification_id',v_qualification.qualification_id,
    'operation_revision_sha256',v_revision,
    'suite_set_fingerprint',v_fingerprint,
    'baseline_content_row_id',v_content.id,
    'baseline_content_version',v_content.content_version,
    'baseline_content_sha256',v_content.content_sha256,
    'baseline_content_chars',v_content.content_chars,
    'baseline_binding',v_binding,
    'runtime_activation',false,
    'production_activation',false,
    'promotion_authorized',false,
    'router_activation_authorized',false,
    'rollback_required',true
  );
exception
  when invalid_text_representation or numeric_value_out_of_range then
    return jsonb_build_object('valid',false,'code','CARD_ASSURANCE_CONTEXT_TYPE_INVALID');
end;
$function$;

create or replace function public.lf_card_update_controlled_write_v1(
  p_execution_id text,
  p_new_content_text text
)
returns jsonb
language plpgsql
security invoker
set search_path to 'pg_catalog','public'
as $function$
declare
  v_ctx jsonb;
  v_execution public.lf_operation_execution%rowtype;
  v_card public.lf_activos%rowtype;
  v_old public.lf_card_content_versions%rowtype;
  v_new public.lf_card_content_versions%rowtype;
  v_new_sha text;
  v_new_version text;
  v_new_binding jsonb;
  v_existing_receipt jsonb;
begin
  v_ctx:=public.lf_card_update_controlled_assurance_context_v1(p_execution_id);
  if v_ctx->'valid' is distinct from 'true'::jsonb then
    return jsonb_build_object('outcome','BLOCKED','code',coalesce(v_ctx->>'code','CARD_ASSURANCE_CONTEXT_INVALID'),'context',v_ctx);
  end if;

  if p_new_content_text is null or btrim(p_new_content_text)='' or length(p_new_content_text)>200000 then
    return jsonb_build_object('outcome','BLOCKED','code','CARD_ASSURANCE_NEW_CONTENT_INVALID');
  end if;

  select * into v_execution
  from public.lf_operation_execution
  where execution_id=p_execution_id
  for update;

  v_existing_receipt:=v_execution.manifest->'controlled_assurance_write_receipt';
  if jsonb_typeof(v_existing_receipt)='object' then
    select * into v_new
    from public.lf_card_content_versions
    where id=(v_existing_receipt->>'new_content_row_id')::bigint
      and card_code=v_execution.target_code;
    if found then
      return v_existing_receipt || jsonb_build_object('outcome','REPLAY_CONTROLLED_ASSURANCE_WRITE_RECEIPT');
    end if;
    return jsonb_build_object('outcome','BLOCKED','code','CARD_ASSURANCE_WRITE_RECEIPT_ROW_MISSING');
  end if;

  select * into v_card
  from public.lf_activos
  where codigo_activo=v_execution.target_code
  for update;

  select * into v_old
  from public.lf_card_content_versions
  where id=(v_ctx->>'baseline_content_row_id')::bigint
    and card_code=v_execution.target_code
    and status='CURRENT'
  for update;

  if not found
     or v_old.content_sha256 is distinct from (v_ctx->>'baseline_content_sha256')
     or (v_card.metadata->'carrier_binding_v1'->>'content_row_id')::bigint is distinct from v_old.id then
    return jsonb_build_object('outcome','BLOCKED','code','CARD_ASSURANCE_OPTIMISTIC_BASELINE_CHANGED');
  end if;

  v_new_sha:=encode(extensions.digest(p_new_content_text,'sha256'),'hex');
  if v_new_sha is not distinct from v_old.content_sha256 then
    return jsonb_build_object('outcome','BLOCKED','code','CARD_ASSURANCE_WRITE_MUST_CHANGE_CONTENT');
  end if;

  v_new_version:=v_old.content_version||'-s36-assurance-'||substr(encode(extensions.digest(p_execution_id,'sha256'),'hex'),1,12);

  update public.lf_card_content_versions
  set status='RETIRED',
      retired_at=clock_timestamp(),
      retired_by_execution_id=p_execution_id
  where id=v_old.id and status='CURRENT';

  insert into public.lf_card_content_versions(
    card_code,content_version,content_text,content_sha256,content_chars,content_format,status,
    supersedes_id,created_by_execution_id,metadata
  ) values (
    v_execution.target_code,v_new_version,p_new_content_text,v_new_sha,length(p_new_content_text),
    v_old.content_format,'CURRENT',v_old.id,p_execution_id,
    jsonb_build_object(
      'controlled_assurance',true,
      'assurance_owner','S36',
      'assurance_scope','CARD_UPDATE_I8_PREPROMOTION_E2E',
      'execution_id',p_execution_id,
      'rollback_required',true,
      'baseline_content_row_id',v_old.id,
      'baseline_content_version',v_old.content_version,
      'baseline_content_sha256',v_old.content_sha256
    )
  ) returning * into v_new;

  v_new_binding:=(v_ctx->'baseline_binding')
    || jsonb_build_object(
      'carrier_ref','supabase://public/lf_card_content_versions/'||v_new.id,
      'content_row_id',v_new.id,
      'content_version',v_new.content_version,
      'content_sha256',v_new.content_sha256,
      'content_chars',v_new.content_chars,
      'content_format',v_new.content_format,
      'binding_execution_id',p_execution_id,
      'observed_at',clock_timestamp(),
      'carrier_write_allowed',false,
      'controlled_assurance_active',true
    );

  update public.lf_activos
  set ultima_revision=v_new.content_version,
      metadata=jsonb_set(metadata,'{carrier_binding_v1}',v_new_binding,true),
      updated_by_execution_id=p_execution_id,
      updated_at=clock_timestamp()
  where id=v_card.id;

  update public.lf_operation_execution
  set manifest=manifest || jsonb_build_object(
        'controlled_assurance_write_receipt',jsonb_build_object(
          'outcome','CONTROLLED_ASSURANCE_WRITE_APPLIED',
          'execution_id',p_execution_id,
          'card_code',v_execution.target_code,
          'content_store_type','SUPABASE_NATIVE_CARD_CONTENT',
          'write_route','S36_CONTROLLED_ASSURANCE_SUPABASE_IMMUTABLE_CONTENT_VERSION_INSERT',
          'baseline_content_row_id',v_old.id,
          'baseline_content_version',v_old.content_version,
          'baseline_content_sha256',v_old.content_sha256,
          'baseline_binding',v_ctx->'baseline_binding',
          'new_content_row_id',v_new.id,
          'new_content_version',v_new.content_version,
          'new_content_sha256',v_new.content_sha256,
          'new_content_chars',v_new.content_chars,
          'supersedes_content_row_id',v_old.id,
          'optimistic_lock_applied',true,
          'rollback_required',true,
          'runtime_activation',false,
          'production_activation',false,
          'promotion_authorized',false,
          'router_activation_authorized',false
        )
      ),
      updated_by_execution_id=p_execution_id,
      updated_at=clock_timestamp()
  where execution_id=p_execution_id;

  return jsonb_build_object(
    'outcome','CONTROLLED_ASSURANCE_WRITE_APPLIED',
    'execution_id',p_execution_id,
    'card_code',v_execution.target_code,
    'content_store_type','SUPABASE_NATIVE_CARD_CONTENT',
    'write_route','S36_CONTROLLED_ASSURANCE_SUPABASE_IMMUTABLE_CONTENT_VERSION_INSERT',
    'new_content_row_id',v_new.id,
    'new_content_version',v_new.content_version,
    'new_content_sha256',v_new.content_sha256,
    'supersedes_content_row_id',v_old.id,
    'optimistic_lock_applied',true,
    'rollback_required',true
  );
end;
$function$;

create or replace function public.lf_card_update_controlled_readback_v1(
  p_execution_id text
)
returns jsonb
language plpgsql
security invoker
set search_path to 'pg_catalog','public'
as $function$
declare
  v_execution public.lf_operation_execution%rowtype;
  v_card public.lf_activos%rowtype;
  v_content public.lf_card_content_versions%rowtype;
  v_receipt jsonb;
  v_parent_count integer;
begin
  select * into v_execution
  from public.lf_operation_execution
  where execution_id=p_execution_id;

  if not found
     or v_execution.operation_code is distinct from 'ACTUALIZACION_CARD_LF'
     or v_execution.target_type is distinct from 'CARD'
     or v_execution.status is distinct from 'IN_PROGRESS' then
    return jsonb_build_object('valid',false,'code','CARD_ASSURANCE_READBACK_EXECUTION_INVALID');
  end if;

  v_receipt:=v_execution.manifest->'controlled_assurance_write_receipt';
  if jsonb_typeof(v_receipt) is distinct from 'object'
     or (v_receipt->>'outcome') is distinct from 'CONTROLLED_ASSURANCE_WRITE_APPLIED' then
    return jsonb_build_object('valid',false,'code','CARD_ASSURANCE_WRITE_RECEIPT_MISSING');
  end if;

  select * into v_card
  from public.lf_activos
  where codigo_activo=v_execution.target_code
    and archived_at is null;

  select * into v_content
  from public.lf_card_content_versions
  where id=(v_receipt->>'new_content_row_id')::bigint
    and card_code=v_execution.target_code
    and status='CURRENT';

  select count(*) into v_parent_count
  from public.lf_activo_relaciones
  where codigo_activo=v_execution.target_code and relacion_tipo='HIJO_DE';

  if not found
     or (v_card.metadata->'carrier_binding_v1'->>'content_row_id')::bigint is distinct from v_content.id
     or (v_card.metadata->'carrier_binding_v1'->>'content_sha256') is distinct from v_content.content_sha256
     or (v_card.metadata->'carrier_binding_v1'->>'content_version') is distinct from v_content.content_version
     or v_content.content_sha256 is distinct from encode(extensions.digest(v_content.content_text,'sha256'),'hex')
     or v_content.content_chars is distinct from length(v_content.content_text)
     or v_content.created_by_execution_id is distinct from p_execution_id
     or v_parent_count<>1 then
    return jsonb_build_object('valid',false,'code','CARD_ASSURANCE_READBACK_MISMATCH');
  end if;

  return jsonb_build_object(
    'valid',true,
    'code','CARD_ASSURANCE_READBACK_EXACT',
    'readback_content_row_id',v_content.id,
    'readback_content_version',v_content.content_version,
    'readback_content_hash',v_content.content_sha256,
    'parent_source_preserved',true,
    'independent_readback',true
  );
exception
  when invalid_text_representation or numeric_value_out_of_range then
    return jsonb_build_object('valid',false,'code','CARD_ASSURANCE_READBACK_TYPE_INVALID');
end;
$function$;

create or replace function public.lf_card_update_controlled_rollback_v1(
  p_execution_id text
)
returns jsonb
language plpgsql
security invoker
set search_path to 'pg_catalog','public'
as $function$
declare
  v_execution public.lf_operation_execution%rowtype;
  v_card public.lf_activos%rowtype;
  v_old public.lf_card_content_versions%rowtype;
  v_new public.lf_card_content_versions%rowtype;
  v_receipt jsonb;
  v_rollback jsonb;
begin
  select * into v_execution
  from public.lf_operation_execution
  where execution_id=p_execution_id
  for update;

  if not found
     or v_execution.operation_code is distinct from 'ACTUALIZACION_CARD_LF'
     or v_execution.target_type is distinct from 'CARD'
     or v_execution.status is distinct from 'IN_PROGRESS' then
    return jsonb_build_object('outcome','BLOCKED','code','CARD_ASSURANCE_ROLLBACK_EXECUTION_INVALID');
  end if;

  if jsonb_typeof(v_execution.manifest->'controlled_assurance_rollback_receipt')='object' then
    return (v_execution.manifest->'controlled_assurance_rollback_receipt') || jsonb_build_object('outcome','REPLAY_ROLLBACK_EXACT_BASELINE_RESTORED');
  end if;

  v_receipt:=v_execution.manifest->'controlled_assurance_write_receipt';
  if jsonb_typeof(v_receipt) is distinct from 'object'
     or (v_receipt->>'outcome') is distinct from 'CONTROLLED_ASSURANCE_WRITE_APPLIED' then
    return jsonb_build_object('outcome','BLOCKED','code','CARD_ASSURANCE_ROLLBACK_WRITE_RECEIPT_MISSING');
  end if;

  select * into v_card
  from public.lf_activos
  where codigo_activo=v_execution.target_code
  for update;

  select * into v_new
  from public.lf_card_content_versions
  where id=(v_receipt->>'new_content_row_id')::bigint
    and card_code=v_execution.target_code
  for update;

  select * into v_old
  from public.lf_card_content_versions
  where id=(v_receipt->>'baseline_content_row_id')::bigint
    and card_code=v_execution.target_code
  for update;

  if v_new.id is null or v_old.id is null
     or v_new.status is distinct from 'CURRENT'
     or v_old.status is distinct from 'RETIRED'
     or (v_card.metadata->'carrier_binding_v1'->>'content_row_id')::bigint is distinct from v_new.id then
    return jsonb_build_object('outcome','BLOCKED','code','CARD_ASSURANCE_ROLLBACK_STATE_MISMATCH');
  end if;

  update public.lf_card_content_versions
  set status='RETIRED',
      retired_at=clock_timestamp(),
      retired_by_execution_id=p_execution_id
  where id=v_new.id and status='CURRENT';

  update public.lf_card_content_versions
  set status='CURRENT',
      retired_at=null,
      retired_by_execution_id=null
  where id=v_old.id and status='RETIRED';

  update public.lf_activos
  set ultima_revision=v_old.content_version,
      metadata=jsonb_set(metadata,'{carrier_binding_v1}',v_receipt->'baseline_binding',true),
      updated_by_execution_id=p_execution_id,
      updated_at=clock_timestamp()
  where id=v_card.id;

  if not exists (
    select 1
    from public.lf_card_content_versions c
    join public.lf_activos a on a.codigo_activo=c.card_code
    where c.id=v_old.id
      and c.status='CURRENT'
      and c.content_sha256=(v_receipt->>'baseline_content_sha256')
      and (a.metadata->'carrier_binding_v1') is not distinct from (v_receipt->'baseline_binding')
      and a.ultima_revision=(v_receipt->>'baseline_content_version')
  ) then
    raise exception 'CARD_ASSURANCE_ROLLBACK_READBACK_FAILED';
  end if;

  v_rollback:=jsonb_build_object(
    'outcome','ROLLBACK_EXACT_BASELINE_RESTORED',
    'execution_id',p_execution_id,
    'card_code',v_execution.target_code,
    'baseline_content_row_id',v_old.id,
    'baseline_content_version',v_old.content_version,
    'baseline_content_sha256',v_old.content_sha256,
    'assurance_content_row_id',v_new.id,
    'assurance_content_status','RETIRED',
    'exact_baseline_restored',true,
    'runtime_activation',false,
    'production_activation',false,
    'promotion_authorized',false,
    'router_activation_authorized',false
  );

  update public.lf_operation_execution
  set manifest=manifest || jsonb_build_object('controlled_assurance_rollback_receipt',v_rollback),
      updated_by_execution_id=p_execution_id,
      updated_at=clock_timestamp()
  where execution_id=p_execution_id;

  return v_rollback;
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
  v_ctx jsonb;
  v_execution public.lf_operation_execution%rowtype;
  v_write jsonb;
  v_readback jsonb;
  v_rollback jsonb;
  v_assertions jsonb:=jsonb_build_array(
    'required evidence present',
    'prior required steps clean',
    'Supabase operational authority preserved',
    'external carrier not used as authority'
  );
begin
  if p_step_id in (
    'router','card_resolve','carrier_resolve','parent_source_read','baseline_read',
    'change_scope','regression_plan','pre_write_execution_binding_gate'
  ) then
    return public.lf_validate_card_update_step_evidence_v5(p_execution_id,p_step_id,p_evidence_payload);
  end if;

  if p_evidence_payload is null or jsonb_typeof(p_evidence_payload) is distinct from 'object' then
    return jsonb_build_object('valid',false,'code','CARD_STEP_EVIDENCE_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
  end if;

  v_ctx:=public.lf_card_update_controlled_assurance_context_v1(p_execution_id);
  if v_ctx->'valid' is distinct from 'true'::jsonb then
    return jsonb_build_object('valid',false,'code',coalesce(v_ctx->>'code','CARD_ASSURANCE_CONTEXT_INVALID'),'details',v_ctx,'server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('runtime or automatic promotion requested'));
  end if;

  select * into v_execution
  from public.lf_operation_execution
  where execution_id=p_execution_id;
  v_write:=v_execution.manifest->'controlled_assurance_write_receipt';
  v_rollback:=v_execution.manifest->'controlled_assurance_rollback_receipt';

  if p_step_id='carrier_write_dispatch' then
    if jsonb_typeof(v_write) is distinct from 'object'
       or (v_write->>'outcome') is distinct from 'CONTROLLED_ASSURANCE_WRITE_APPLIED'
       or (p_evidence_payload->>'content_store_type') is distinct from 'SUPABASE_NATIVE_CARD_CONTENT'
       or (p_evidence_payload->>'write_route') is distinct from 'S36_CONTROLLED_ASSURANCE_SUPABASE_IMMUTABLE_CONTENT_VERSION_INSERT'
       or (p_evidence_payload->>'new_content_version') is distinct from (v_write->>'new_content_version')
       or (p_evidence_payload->>'new_content_sha256') is distinct from (v_write->>'new_content_sha256')
       or (p_evidence_payload->>'supersedes_content_row_id')::bigint is distinct from (v_write->>'supersedes_content_row_id')::bigint
       or p_evidence_payload->'optimistic_lock_applied' is distinct from 'true'::jsonb
       or jsonb_typeof(p_evidence_payload->'write_receipt') is distinct from 'object' then
      return jsonb_build_object('valid',false,'code','CARD_ASSURANCE_WRITE_EVIDENCE_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
    end if;
  elsif p_step_id='carrier_readback' then
    v_readback:=public.lf_card_update_controlled_readback_v1(p_execution_id);
    if v_readback->'valid' is distinct from 'true'::jsonb
       or (p_evidence_payload->>'readback_content_row_id')::bigint is distinct from (v_readback->>'readback_content_row_id')::bigint
       or (p_evidence_payload->>'readback_content_version') is distinct from (v_readback->>'readback_content_version')
       or (p_evidence_payload->>'readback_content_hash') is distinct from (v_readback->>'readback_content_hash')
       or p_evidence_payload->'parent_source_preserved' is distinct from 'true'::jsonb
       or p_evidence_payload->'independent_readback' is distinct from 'true'::jsonb then
      return jsonb_build_object('valid',false,'code','CARD_ASSURANCE_READBACK_EVIDENCE_MISMATCH','details',v_readback,'server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
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
    if jsonb_typeof(v_rollback) is distinct from 'object'
       or (v_rollback->>'outcome') is distinct from 'ROLLBACK_EXACT_BASELINE_RESTORED'
       or jsonb_typeof(p_evidence_payload->'before_after_matrix') is distinct from 'object'
       or p_evidence_payload->'before_after_matrix'->'exact_baseline_restored' is distinct from 'true'::jsonb
       or (p_evidence_payload->>'wrong_content_binding_negative') is distinct from 'PASS_BLOCKED'
       or (p_evidence_payload->>'stale_content_revision_negative') is distinct from 'PASS_BLOCKED'
       or (p_evidence_payload->>'missing_current_content_negative') is distinct from 'PASS_BLOCKED'
       or (p_evidence_payload->>'holdout_result') is distinct from 'PASS_I8_CONTROLLED_E2E' then
      return jsonb_build_object('valid',false,'code','CARD_ASSURANCE_REGRESSION_OR_ROLLBACK_FAILED','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
    end if;
  elsif p_step_id='close' then
    if jsonb_typeof(v_rollback) is distinct from 'object'
       or (v_rollback->>'outcome') is distinct from 'ROLLBACK_EXACT_BASELINE_RESTORED'
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
       or (p_evidence_payload->>'card_code') is distinct from (v_execution.target_code)
       or jsonb_typeof(p_evidence_payload->'evidence_refs') is distinct from 'array'
       or jsonb_array_length(p_evidence_payload->'evidence_refs')<1
       or jsonb_typeof(p_evidence_payload->'open_blockers') is distinct from 'array'
       or jsonb_array_length(p_evidence_payload->'open_blockers')<>0
       or (p_evidence_payload->>'next_gate') is distinct from 'INDEPENDENT_REVIEW_FINALIZATION'
       or (p_evidence_payload->>'content_ref') is distinct from ('supabase://public/lf_card_content_versions/'||(v_write->>'baseline_content_row_id')) then
      return jsonb_build_object('valid',false,'code','CARD_ASSURANCE_REPORT_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
    end if;
  else
    return jsonb_build_object('valid',false,'code','CARD_STEP_NOT_SUPPORTED_BY_V6','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
  end if;

  return jsonb_build_object(
    'valid',true,
    'code','CARD_ASSURANCE_STEP_EXACT',
    'server_assertions',v_assertions,
    'server_hard_fails','[]'::jsonb,
    'details',jsonb_build_object(
      'mode','S36_CONTROLLED_ASSURANCE',
      'runtime_activation',false,
      'production_activation',false,
      'promotion_authorized',false,
      'router_activation_authorized',false,
      'rollback_required',true
    )
  );
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
  v_step_order integer;
  v_server_validation jsonb;
  v_ctx jsonb;
begin
  select step_order into v_step_order
  from public.lf_operation_steps
  where operation_code='ACTUALIZACION_CARD_LF'
    and step_id=p_step_id
    and active is true;

  if v_step_order is null then
    return jsonb_build_object('outcome','BLOCKED','code','STEP_NOT_ACTIVE','durable',false);
  end if;

  if v_step_order>85 then
    v_ctx:=public.lf_card_update_controlled_assurance_context_v1(p_execution_id);
    if v_ctx->'valid' is distinct from 'true'::jsonb then
      v_server_validation:=jsonb_build_object(
        'valid',false,
        'code','CARD_UPDATE_WRITE_PHASE_NOT_AUTHORIZED_I8',
        'details',jsonb_build_object(
          'step_order',v_step_order,
          'ceiling_step_order',85,
          'controlled_assurance_required',true,
          'controlled_assurance_context',v_ctx
        ),
        'server_assertions','[]'::jsonb,
        'server_hard_fails',jsonb_build_array('runtime or automatic promotion requested')
      );
    else
      v_server_validation:=public.lf_validate_card_update_step_evidence_v6(
        p_execution_id,p_step_id,p_evidence_payload
      );
    end if;
  elsif p_step_id='expertise_quality_gate' then
    v_server_validation:=public.lf_validate_card_expertise_gate_v1(
      p_execution_id,p_step_id,p_evidence_payload
    );
  else
    v_server_validation:=public.lf_validate_card_update_step_evidence_v6(
      p_execution_id,p_step_id,p_evidence_payload
    );
  end if;

  return public.lf_record_operation_step_core_v1(
    p_execution_id,p_step_id,p_evidence_ref,p_evidence_payload,p_actor_execution_id,
    'ACTUALIZACION_CARD_LF','CARD',
    'CANDIDATO_READ_ONLY','CANDIDATO_READ_ONLY','CANDIDATO_READ_ONLY',
    v_server_validation,true,'lf_record_card_operation_step_v1'
  );
end;
$function$;

-- Make the controlled-assurance restriction visible in step contracts without adding a parallel workflow.
update public.lf_operation_step_contracts
set notes=concat_ws(' | ',nullif(notes,''),'S36 controlled assurance may execute this step only in S36_CONTROLLED_ASSURANCE mode with exact QUAL_QUALIFYING receipt, read-only/BLOQUEADO Card target, no active Router, and mandatory exact rollback before close.'),
    updated_at=now(),
    updated_by_execution_id='EXEC-S36-I8-CONTROLLED-ASSURANCE-IMPLEMENT-20260915-001'
where operation_code='ACTUALIZACION_CARD_LF'
  and step_order between 90 and 150
  and status='CANDIDATO_READ_ONLY';

revoke all on function public.lf_card_update_controlled_assurance_context_v1(text) from public,anon,authenticated;
revoke all on function public.lf_card_update_controlled_write_v1(text,text) from public,anon,authenticated;
revoke all on function public.lf_card_update_controlled_readback_v1(text) from public,anon,authenticated;
revoke all on function public.lf_card_update_controlled_rollback_v1(text) from public,anon,authenticated;
revoke all on function public.lf_validate_card_update_step_evidence_v6(text,text,jsonb) from public,anon,authenticated;
revoke all on function public.lf_record_card_operation_step_v1(text,text,text,jsonb,text) from public,anon,authenticated;

grant execute on function public.lf_card_update_controlled_assurance_context_v1(text) to service_role;
grant execute on function public.lf_card_update_controlled_write_v1(text,text) to service_role;
grant execute on function public.lf_card_update_controlled_readback_v1(text) to service_role;
grant execute on function public.lf_card_update_controlled_rollback_v1(text) to service_role;
grant execute on function public.lf_validate_card_update_step_evidence_v6(text,text,jsonb) to service_role;
grant execute on function public.lf_record_card_operation_step_v1(text,text,text,jsonb,text) to service_role;

-- Structural fail-closed assertions.
do $$
declare
  v_recorder text;
  v_validator text;
  v_write text;
begin
  select pg_get_functiondef('public.lf_record_card_operation_step_v1(text,text,text,jsonb,text)'::regprocedure) into v_recorder;
  select pg_get_functiondef('public.lf_validate_card_update_step_evidence_v6(text,text,jsonb)'::regprocedure) into v_validator;
  select pg_get_functiondef('public.lf_card_update_controlled_write_v1(text,text)'::regprocedure) into v_write;

  if position('S36_CONTROLLED_ASSURANCE' in v_recorder)=0
     or position('CARD_UPDATE_WRITE_PHASE_NOT_AUTHORIZED_I8' in v_recorder)=0
     or position('lf_validate_card_update_step_evidence_v6' in v_recorder)=0
     or position('ROLLBACK_EXACT_BASELINE_RESTORED' in v_validator)=0
     or position('PASS_CONTROLLED_ASSURANCE_NO_PROMOTION' in v_validator)=0
     or position('rollback_required' in v_write)=0
     or position('promotion_authorized' in v_write)=0 then
    raise exception 'CARD_UPDATE_S36_CONTROLLED_ASSURANCE_STRUCTURAL_ASSERTION_FAILED';
  end if;

  if exists (
    select 1 from public.lf_router_action_registry
    where operation_code='ACTUALIZACION_CARD_LF' and status='ACTIVE'
  ) then
    raise exception 'CARD_UPDATE_S36_CONTROLLED_ASSURANCE_MUST_NOT_ACTIVATE_ROUTER';
  end if;

  if not exists (
    select 1 from public.lf_operation_registry
    where operation_code='ACTUALIZACION_CARD_LF'
      and lifecycle_state_code='OP_CANDIDATE'
      and status='CANDIDATO_READ_ONLY'
  ) then
    raise exception 'CARD_UPDATE_S36_CONTROLLED_ASSURANCE_MUST_REMAIN_CANDIDATE';
  end if;
end $$;

commit;
