begin;

create or replace function public.lf_card_update_controlled_assurance_begin_v1(
  p_execution_id text,
  p_card_code text,
  p_qualification_id uuid,
  p_request_sha256 text,
  p_idempotency_key text,
  p_actor_execution_id text
)
returns jsonb
language plpgsql
security invoker
set search_path to 'pg_catalog','public'
as $function$
declare
  a public.lf_activos%rowtype;
  r public.lf_operation_registry%rowtype;
  q public.lf_qualification_receipts%rowtype;
  x public.lf_operation_execution%rowtype;
  st public.lf_operation_steps%rowtype;
  b public.lf_operation_step_judge_bindings%rowtype;
  e public.lf_operation_execution_steps%rowtype;
  reserve_result jsonb;
  revision_now text;
  fingerprint_now text;
  target_path text;
  init_payload jsonb;
begin
  if btrim(coalesce(p_execution_id,''))=''
     or btrim(coalesce(p_card_code,''))=''
     or p_qualification_id is null
     or coalesce(p_request_sha256,'') !~ '^[0-9a-f]{64}$'
     or btrim(coalesce(p_idempotency_key,''))=''
     or btrim(coalesce(p_actor_execution_id,''))='' then
    raise exception 'LF_CARD_ASSURANCE_BEGIN_INPUT_INVALID';
  end if;

  select * into r from public.lf_operation_registry where operation_code='ACTUALIZACION_CARD_LF';
  if not found or r.lifecycle_state_code is distinct from 'OP_CANDIDATE' or r.status is distinct from 'CANDIDATO_READ_ONLY' then
    raise exception 'LF_CARD_ASSURANCE_BEGIN_OPERATION_NOT_CANDIDATE';
  end if;
  if exists(select 1 from public.lf_router_action_registry where operation_code='ACTUALIZACION_CARD_LF' and status='ACTIVE') then
    raise exception 'LF_CARD_ASSURANCE_BEGIN_ROUTER_ALREADY_ACTIVE';
  end if;

  select * into a from public.lf_activos
  where codigo_activo=p_card_code and tipo_activo='CARD' and archived_at is null;
  if not found
     or a.estado_operativo is distinct from 'READ_ONLY'
     or a.impacto_automatico is distinct from 'BLOQUEADO'
     or a.runtime_estado not in ('PRODUCCION_CONTROLADA_READ_ONLY','CANDIDATE_READ_ONLY','SANDBOX_READ_ONLY') then
    raise exception 'LF_CARD_ASSURANCE_BEGIN_TARGET_NOT_READ_ONLY_CONTROLLED:%',p_card_code;
  end if;

  revision_now:=public.lf_operation_revision_sha256_v1('ACTUALIZACION_CARD_LF');
  fingerprint_now:=public.lf_required_test_suite_fingerprint_v1('OPERATION','ACTUALIZACION_CARD_LF');
  select * into q from public.lf_qualification_receipts
  where qualification_id=p_qualification_id
    and subject_type='OPERATION'
    and subject_code='ACTUALIZACION_CARD_LF'
    and lifecycle_state_code='QUAL_QUALIFYING'
    and invalidated_at is null
    and revision_sha256=revision_now
    and suite_set_fingerprint=fingerprint_now;
  if not found then
    raise exception 'LF_CARD_ASSURANCE_BEGIN_QUALIFICATION_NOT_EXACT:%',p_qualification_id;
  end if;

  target_path:='supabase://public/lf_activos/'||p_card_code;
  reserve_result:=public.fn_lf_operation_reserve_execution_v1(
    p_execution_id,
    'ACTUALIZACION_CARD_LF',
    'CARD',
    p_card_code,
    p_idempotency_key,
    p_request_sha256,
    p_actor_execution_id,
    null,
    target_path,
    jsonb_build_object(
      'mode','S36_CONTROLLED_ASSURANCE',
      'assurance_owner','S36',
      'assurance_scope','CARD_UPDATE_I8_PREPROMOTION_E2E',
      'qualification_id',p_qualification_id,
      'qualification_revision_sha256',revision_now,
      'qualification_suite_set_fingerprint',fingerprint_now,
      'controlled_write',true,
      'rollback_required',true,
      'runtime_activation',false,
      'production_activation',false,
      'promotion_authorized',false,
      'router_activation_authorized',false
    )
  );

  select * into x from public.lf_operation_execution where execution_id=reserve_result->>'execution_id' for update;
  if not found
     or x.status is distinct from 'IN_PROGRESS'
     or x.operation_code is distinct from 'ACTUALIZACION_CARD_LF'
     or x.target_type is distinct from 'CARD'
     or x.target_code is distinct from p_card_code
     or x.target_path is distinct from target_path then
    raise exception 'LF_CARD_ASSURANCE_BEGIN_EXECUTION_BINDING_INVALID';
  end if;

  select * into st from public.lf_operation_steps
  where operation_code='ACTUALIZACION_CARD_LF' and step_id='init_execution' and active=true;
  if not found then raise exception 'LF_CARD_ASSURANCE_BEGIN_INIT_STEP_NOT_ACTIVE'; end if;
  select * into b from public.lf_operation_step_judge_bindings
  where operation_code='ACTUALIZACION_CARD_LF' and step_id='init_execution'
    and step_order=st.step_order and status='CANDIDATO_READ_ONLY';
  if not found then raise exception 'LF_CARD_ASSURANCE_BEGIN_INIT_BINDING_NOT_ACTIVE'; end if;

  select * into e from public.lf_operation_execution_steps
  where execution_id=x.execution_id and step_order=st.step_order;
  if found then
    if e.step_id='init_execution' and e.status=b.clean_result_value then
      return reserve_result || jsonb_build_object(
        'init_step','ALREADY_RECORDED_IDEMPOTENT',
        'qualification_id',p_qualification_id,
        'operation_revision_sha256',revision_now,
        'suite_set_fingerprint',fingerprint_now,
        'next_step','router'
      );
    end if;
    raise exception 'LF_CARD_ASSURANCE_BEGIN_INIT_CONFLICT:%:%',e.step_id,e.status;
  end if;

  init_payload:=jsonb_build_object(
    'execution_id_created',x.execution_id,
    'target_code',p_card_code,
    'target_type','CARD',
    'qualification_id',p_qualification_id,
    'operation_revision_sha256',revision_now,
    'suite_set_fingerprint',fingerprint_now,
    'assurance_mode','S36_CONTROLLED_ASSURANCE',
    'runtime_activation',false,
    'production_activation',false,
    'promotion_authorized',false,
    'router_activation_authorized',false,
    'step_result',b.clean_result_value,
    'derived_result',b.clean_result_value,
    'mini_judge_code',b.judge_code,
    'mini_judge_result',b.clean_result_value,
    'assertions_checked',jsonb_build_array('required evidence present','prior required steps clean','Supabase operational authority preserved','external carrier not used as authority'),
    'hard_fails_checked','[]'::jsonb,
    'blocking_findings','[]'::jsonb,
    'blocking_codes','[]'::jsonb,
    'return_to_worker_reasons','[]'::jsonb,
    'attempt_history','[]'::jsonb,
    'recorded_by_rpc','lf_card_update_controlled_assurance_begin_v1'
  );

  insert into public.lf_operation_execution_steps(
    execution_id,step_order,step_id,status,evidence_ref,evidence_payload,notes,created_by_execution_id
  ) values (
    x.execution_id,st.step_order,'init_execution',b.clean_result_value,
    target_path,init_payload,
    'Transactional init for S36 controlled Card assurance; no production/runtime/promotion/Router authority.',
    x.execution_id
  );

  select * into e from public.lf_operation_execution_steps
  where execution_id=x.execution_id and step_order=st.step_order and step_id='init_execution';
  if not found or e.status is distinct from b.clean_result_value or e.evidence_payload->>'derived_result' is distinct from b.clean_result_value then
    raise exception 'LF_CARD_ASSURANCE_BEGIN_INIT_READBACK_FAILED';
  end if;

  return reserve_result || jsonb_build_object(
    'init_step','RECORDED',
    'qualification_id',p_qualification_id,
    'operation_revision_sha256',revision_now,
    'suite_set_fingerprint',fingerprint_now,
    'next_step','router'
  );
end;
$function$;

revoke all on function public.lf_card_update_controlled_assurance_begin_v1(text,text,uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.lf_card_update_controlled_assurance_begin_v1(text,text,uuid,text,text,text) to service_role;

commit;