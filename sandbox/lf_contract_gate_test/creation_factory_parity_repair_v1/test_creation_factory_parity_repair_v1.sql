-- Regression: CREATION_FACTORY_PARITY_REPAIR_V1
-- Run after applying 20261006190000_creation_factory_parity_repair_v1.sql.
-- All probes run in a transaction and roll back.

begin;

do $$
declare
  v_card_exec text := 'TEST-CARD-CREATION-FACTORY-PARITY-V1';
  v_skill_exec text := 'TEST-SKILL-CREATION-FACTORY-PARITY-V1';
  v_card jsonb;
  v_skill jsonb;
  v_profile jsonb;
  v_router jsonb;
  v_negative jsonb;
  v_plan jsonb;
  v_hash text;
  v_trust jsonb;
  v_orders integer[];
begin
  perform public.lf_reserve_creation_factory_execution_v1(
    v_card_exec,'CREACION_CARD_LF','CARD_FACTORY_PARITY_TEST',
    'test-card-creation-factory-parity-v1',repeat('a',64),v_card_exec,
    'cristhianlujan/claude-persona-lf-patch',
    'cards/systemic_root_cause_repair/material_front_coverage/CARD.md',
    '{"test":true}'::jsonb
  );

  perform public.lf_reserve_creation_factory_execution_v1(
    v_skill_exec,'CREACION_SKILL_LF','SKILL_FACTORY_PARITY_TEST',
    'test-skill-creation-factory-parity-v1',repeat('b',64),v_skill_exec,
    'cristhianlujan/claude-persona-lf-patch',
    'skills/test/creation_factory_parity/SKILL.md',
    '{"test":true}'::jsonb
  );

  v_card:=public.lf_creation_factory_parity_guard_v1('CREACION_CARD_LF');
  v_skill:=public.lf_creation_factory_parity_guard_v1('CREACION_SKILL_LF');
  v_profile:=public.lf_creation_factory_parity_guard_v1('CREACION_PERFIL_LF');

  if v_card->>'verdict'<>'PASS'
     or (v_card->>'active_steps')::int<>39
     or (v_card->>'binding_exact_steps')::int<>39
     or (v_card->>'judge_exact_steps')::int<>39 then
    raise exception 'CARD_FACTORY_PARITY_FAIL:%',v_card::text;
  end if;

  if v_skill->>'verdict'<>'PASS'
     or (v_skill->>'active_steps')::int<>39
     or (v_skill->>'binding_exact_steps')::int<>39
     or (v_skill->>'judge_exact_steps')::int<>39 then
    raise exception 'SKILL_FACTORY_PARITY_FAIL:%',v_skill::text;
  end if;

  if v_profile->>'verdict'<>'PASS'
     or (v_profile->>'active_steps')::int<>40
     or (v_profile->>'binding_exact_steps')::int<>40
     or (v_profile->>'judge_exact_steps')::int<>40 then
    raise exception 'PROFILE_FACTORY_REGRESSION:%',v_profile::text;
  end if;

  select array_agg(execution_order order by execution_order)
  into v_orders
  from public.lf_operation_steps
  where operation_code='CREACION_SKILL_LF'
    and step_id in (
      'rule_trace','partial_scope_guard','pre_write_execution_binding_gate',
      'github_write','github_readback','contract_judge','close'
    );

  if v_orders is distinct from array[300,310,320,330,340,360,370] then
    raise exception 'SKILL_FACTORY_WRITE_ORDER_FAIL:%',v_orders;
  end if;

  if not exists (
    select 1 from public.lf_operation_execution_steps
    where execution_id=v_skill_exec and step_id='init_execution' and status='STEP_CLEAN_PASS'
  ) then
    raise exception 'SKILL_FACTORY_INIT_NOT_CLEAN';
  end if;

  v_router:=public.lf_record_creacion_card_step_v1(
    v_card_exec,'router','supabase://public.lf_router_resolve_v1#test',
    '{"router_read":true,"step_result":"PASS","blocking_codes":[]}'::jsonb,v_card_exec
  );
  if v_router->>'outcome'<>'STEP_RECORDED' or v_router->>'status'<>'STEP_CLEAN_PASS' then
    raise exception 'CARD_ROUTER_RECORD_FAIL:%',v_router::text;
  end if;

  v_router:=public.lf_record_creacion_skill_step_v1(
    v_skill_exec,'router','supabase://public.lf_router_resolve_v1#test',
    '{"router_read":true,"step_result":"PASS","blocking_codes":[]}'::jsonb,v_skill_exec
  );
  if v_router->>'outcome'<>'STEP_RECORDED' or v_router->>'status'<>'STEP_CLEAN_PASS' then
    raise exception 'SKILL_ROUTER_RECORD_FAIL:%',v_router::text;
  end if;

  v_plan:=jsonb_build_array(jsonb_build_object(
    'path','skills/test/creation_factory_parity/SKILL.md',
    'sha256',repeat('1',64)
  ));
  v_hash:=encode(extensions.digest(convert_to(v_plan::text,'UTF8'),'sha256'),'hex');

  v_trust:=public.lf_creation_factory_trust_validation_v1(
    v_skill_exec,'pre_write_execution_binding_gate',
    jsonb_build_object(
      'execution_binding_verified',true,'write_plan',v_plan,'write_plan_hash',v_hash,
      'step_result','PASS','blocking_codes','[]'::jsonb
    )
  );
  if coalesce((v_trust->>'valid')::boolean,false) is not true then
    raise exception 'SKILL_PREWRITE_POSITIVE_FAIL:%',v_trust::text;
  end if;

  v_trust:=public.lf_creation_factory_trust_validation_v1(
    v_skill_exec,'pre_write_execution_binding_gate',
    jsonb_build_object(
      'execution_binding_verified',true,'write_plan',v_plan,'write_plan_hash',repeat('0',64),
      'step_result','PASS','blocking_codes','[]'::jsonb
    )
  );
  if coalesce((v_trust->>'valid')::boolean,true) is not false
     or v_trust#>>'{details,hard_fails,0}'<>'skill_prewrite_plan_hash_mismatch' then
    raise exception 'SKILL_PREWRITE_BAD_HASH_NOT_BLOCKED:%',v_trust::text;
  end if;

  v_negative:=public.lf_record_creacion_card_step_v1(
    v_card_exec,'github_write','github://test/not-written',
    '{"file_commit_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","step_result":"PASS","blocking_codes":[]}'::jsonb,
    v_card_exec
  );
  if v_negative->>'outcome'<>'BLOCKED'
     or v_negative->>'code'<>'PRIOR_REQUIRED_STEP_NOT_CLEAN' then
    raise exception 'CARD_WRITE_BEFORE_PREWRITE_NOT_BLOCKED:%',v_negative::text;
  end if;
end
$$;

rollback;
