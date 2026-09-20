do $pre$
declare c int;
begin
  if not exists (
    select 1
    from public.lf_operation_registry
    where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
      and lifecycle_state_code='OP_OPERATIONAL'
      and status='PRODUCCION_CONTROLADA'
  ) then
    raise exception 'RUNTIME_CLOSE_EFFECT_PRE_OPERATION_STATE_DRIFT';
  end if;

  if to_regprocedure('public.lf_runtime_update_trust_validation_v1(text,text,jsonb)') is null
     or to_regprocedure('public.lf_record_runtime_update_operation_step_v1(text,text,text,jsonb,text)') is null
  then
    raise exception 'RUNTIME_CLOSE_EFFECT_PRE_FUNCTION_MISSING';
  end if;

  if not exists (
    select 1
    from public.lf_operation_step_contracts
    where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
      and step_id='close'
      and status='ACTIVE_ENFORCEMENT'
      and required_evidence_keys @> '["runtime_unchanged","all_required_steps_clean","open_blockers","no_auto_promotion"]'::jsonb
  ) then
    raise exception 'RUNTIME_CLOSE_EFFECT_PRE_CLOSE_CONTRACT_DRIFT';
  end if;

  if exists (
    select 1
    from public.lf_operation_step_contracts
    where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
      and step_id='close'
      and status='ACTIVE_ENFORCEMENT'
      and required_evidence_keys @> '["runtime_change_state"]'::jsonb
  ) then
    raise exception 'RUNTIME_CLOSE_EFFECT_PRE_ALREADY_MIGRATED';
  end if;

  select count(*) into c
  from public.lf_operation_execution e
  where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
    and e.status='IN_PROGRESS'
    and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
    and e.target_path='supabase/migrations/20260920104500_lf_runtime_update_close_effect_state_v1.sql';
  if c<>1 then
    raise exception 'RUNTIME_CLOSE_EFFECT_PRE_ACTOR_COUNT:%',c;
  end if;
end
$pre$;

create or replace function public.lf_runtime_update_trust_validation_v1(
  p_execution_id text,
  p_step_id text,
  p_evidence_payload jsonb
) returns jsonb
language plpgsql
set search_path to 'pg_catalog','public'
as $fn$
declare
  e public.lf_operation_execution%rowtype;
  f text;
  hard jsonb := '[]'::jsonb;
  v_runtime_effect_rows integer := 0;
  v_migration_version text;
  v_migration_name text;
  v_migration_target boolean := false;
  v_ledger_exact boolean := false;
  v_runtime_change_state text;
  v_reported_effect_rows integer;
begin
  if nullif(btrim(coalesce(p_execution_id,'')),'') is null
     or nullif(btrim(coalesce(p_step_id,'')),'') is null
     or p_evidence_payload is null
     or jsonb_typeof(p_evidence_payload)<>'object' then
    return jsonb_build_object(
      'valid',false,
      'code','RUNTIME_UPDATE_TRUST_INPUT_INVALID',
      'details','{}'::jsonb,
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed')
    );
  end if;

  select * into e
  from public.lf_operation_execution
  where execution_id=p_execution_id;

  if not found
     or e.operation_code<>'ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
     or e.target_type<>'OPERATION_CODE'
     or e.target_code<>'EJECUCION_PERFIL_LF'
     or e.status<>'IN_PROGRESS' then
    return jsonb_build_object(
      'valid',false,
      'code','RUNTIME_UPDATE_EXECUTION_BINDING_INVALID',
      'details',jsonb_build_object('execution_id',p_execution_id),
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed')
    );
  end if;

  if p_step_id='runtime_resolve' and (
       p_evidence_payload->>'operation_code' is distinct from 'EJECUCION_PERFIL_LF'
       or coalesce((p_evidence_payload->>'exact_runtime_target_resolved')::boolean,false) is not true
       or nullif(btrim(coalesce(p_evidence_payload->>'runtime_path','')),'') is null
     ) then
    hard:=hard||jsonb_build_array('runtime_target_not_exact');

  elsif p_step_id='baseline_read'
        and coalesce(p_evidence_payload->>'baseline_revision','') !~ '^[0-9a-f]{40}$' then
    hard:=hard||jsonb_build_array('baseline_revision_invalid');

  elsif p_step_id='pre_write_execution_binding_gate' and (
       p_evidence_payload->>'execution_id' is distinct from p_execution_id
       or p_evidence_payload->>'target_code' is distinct from 'EJECUCION_PERFIL_LF'
       or p_evidence_payload->>'target_path' is distinct from coalesce(e.target_path,'')
       or coalesce((p_evidence_payload->>'pre_write_gate_passed')::boolean,false) is not true
       or coalesce((p_evidence_payload->>'execution_bound_to_target_before_change')::boolean,false) is not true
       or coalesce(p_evidence_payload->>'bound_revision','') !~ '^[0-9a-f]{40}$'
     ) then
    hard:=hard||jsonb_build_array('prewrite_binding_invalid');

  elsif p_step_id='github_write' then
    if coalesce((p_evidence_payload->>'identity_preserved')::boolean,false) is not true
       or coalesce(p_evidence_payload->>'commit_sha','') !~ '^[0-9a-f]{40}$'
       or jsonb_typeof(p_evidence_payload->'written_files')<>'array'
       or jsonb_array_length(p_evidence_payload->'written_files')=0
       or nullif(btrim(coalesce(p_evidence_payload->>'branch','')),'') is null
    then
      hard:=hard||jsonb_build_array('github_write_evidence_invalid');
    else
      for f in select jsonb_array_elements_text(p_evidence_payload->'written_files') loop
        if f like 'profiles/%' or f like 'adapters/%' then
          hard:=hard||jsonb_build_array('forbidden_authority_file_change');
        end if;
      end loop;
    end if;

  elsif p_step_id='github_readback' and (
       coalesce(p_evidence_payload->>'exact_head','') !~ '^[0-9a-f]{40}$'
       or coalesce((p_evidence_payload->>'sha_match')::boolean,false) is not true
       or coalesce((p_evidence_payload->>'identity_preserved')::boolean,false) is not true
     ) then
    hard:=hard||jsonb_build_array('github_readback_not_exact');

  elsif p_step_id='close' then
    select
      (select count(*) from public.lf_operation_registry
        where updated_by_execution_id=p_execution_id)
      +
      (select count(*) from public.lf_operation_contracts
        where updated_by_execution_id=p_execution_id)
      +
      (select count(*) from public.lf_operation_steps
        where updated_by_execution_id=p_execution_id)
      +
      (select count(*) from public.lf_operation_step_contracts
        where updated_by_execution_id=p_execution_id)
      +
      (select count(*) from public.lf_operation_step_judge_bindings
        where updated_by_execution_id=p_execution_id)
      +
      (select count(*) from public.lf_operation_judges
        where updated_by_execution_id=p_execution_id)
      +
      (select count(*) from public.lf_operation_policy_bindings
        where updated_by_execution_id=p_execution_id)
    into v_runtime_effect_rows;

    v_migration_version := substring(coalesce(e.target_path,'') from 'supabase/migrations/([0-9]{14})_');
    v_migration_name := substring(coalesce(e.target_path,'') from 'supabase/migrations/[0-9]{14}_(.+)\.sql$');
    v_migration_target := v_migration_version is not null and v_migration_name is not null;

    if v_migration_target then
      select exists (
        select 1
        from supabase_migrations.schema_migrations sm
        where sm.version=v_migration_version
          and sm.name=v_migration_name
      ) into v_ledger_exact;
    end if;

    v_runtime_change_state:=coalesce(p_evidence_payload->>'runtime_change_state','');

    if coalesce(p_evidence_payload->>'runtime_effect_rows','') !~ '^[0-9]+$' then
      hard:=hard||jsonb_build_array('runtime_effect_rows_invalid');
    else
      v_reported_effect_rows:=(p_evidence_payload->>'runtime_effect_rows')::integer;
      if v_reported_effect_rows is distinct from v_runtime_effect_rows then
        hard:=hard||jsonb_build_array('runtime_effect_rows_mismatch');
      end if;
    end if;

    if coalesce((p_evidence_payload->>'all_required_steps_clean')::boolean,false) is not true
       or coalesce((p_evidence_payload->>'no_auto_promotion')::boolean,false) is not true
       or coalesce((p_evidence_payload->>'live_readback_verified')::boolean,false) is not true
       or jsonb_typeof(p_evidence_payload->'open_blockers')<>'array'
       or jsonb_array_length(p_evidence_payload->'open_blockers')<>0
       or coalesce((p_evidence_payload->>'migration_ledger_exact')::boolean,false) is distinct from v_ledger_exact
    then
      hard:=hard||jsonb_build_array('close_common_contract_not_clean');
    end if;

    if v_runtime_change_state='NO_RUNTIME_CHANGE' then
      if coalesce((p_evidence_payload->>'runtime_unchanged')::boolean,false) is not true
         or coalesce((p_evidence_payload->>'live_apply_verified')::boolean,true) is not false
         or v_runtime_effect_rows<>0
         or v_ledger_exact
      then
        hard:=hard||jsonb_build_array('close_no_runtime_change_not_proven');
      end if;

    elsif v_runtime_change_state='APPLIED_VERIFIED' then
      if coalesce((p_evidence_payload->>'runtime_unchanged')::boolean,true) is not false
         or coalesce((p_evidence_payload->>'live_apply_verified')::boolean,false) is not true
         or v_runtime_effect_rows<=0
         or (v_migration_target and not v_ledger_exact)
      then
        hard:=hard||jsonb_build_array('close_applied_verified_not_proven');
      end if;

    else
      hard:=hard||jsonb_build_array('runtime_change_state_invalid');
    end if;

  elsif p_step_id='report_output' and (
       coalesce(p_evidence_payload->>'exact_head','') !~ '^[0-9a-f]{40}$'
       or jsonb_typeof(p_evidence_payload->'evidence_refs')<>'array'
       or jsonb_array_length(p_evidence_payload->'evidence_refs')=0
       or jsonb_typeof(p_evidence_payload->'open_blockers')<>'array'
       or jsonb_array_length(p_evidence_payload->'open_blockers')<>0
       or nullif(btrim(coalesce(p_evidence_payload->>'next_gate','')),'') is null
     ) then
    hard:=hard||jsonb_build_array('report_output_not_clean');
  end if;

  if jsonb_array_length(hard)>0 then
    return jsonb_build_object(
      'valid',false,
      'code','RUNTIME_UPDATE_SERVER_VALIDATION_FAILED',
      'details',jsonb_build_object(
        'step_id',p_step_id,
        'hard_fails',hard,
        'runtime_effect_rows',case when p_step_id='close' then v_runtime_effect_rows else null end,
        'migration_target',case when p_step_id='close' then v_migration_target else null end,
        'migration_ledger_exact',case when p_step_id='close' then v_ledger_exact else null end
      ),
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed')
    );
  end if;

  return jsonb_build_object(
    'valid',true,
    'code','RUNTIME_UPDATE_SERVER_VALIDATED',
    'details',jsonb_build_object(
      'step_id',p_step_id,
      'execution_id',p_execution_id,
      'runtime_effect_rows',case when p_step_id='close' then v_runtime_effect_rows else null end,
      'migration_target',case when p_step_id='close' then v_migration_target else null end,
      'migration_ledger_exact',case when p_step_id='close' then v_ledger_exact else null end
    ),
    'server_assertions',jsonb_build_array('server_validated'),
    'server_hard_fails','[]'::jsonb
  );
end
$fn$;

update public.lf_operation_step_contracts
set required_evidence_keys=(
      select jsonb_agg(distinct x order by x)
      from jsonb_array_elements_text(
        required_evidence_keys ||
        '["runtime_change_state","live_apply_verified","live_readback_verified","runtime_effect_rows","migration_ledger_exact"]'::jsonb
      ) x
    ),
    output_payload=(
      select jsonb_agg(distinct x order by x)
      from jsonb_array_elements_text(
        output_payload ||
        '["runtime_change_state","live_apply_verified","live_readback_verified","runtime_effect_rows","migration_ledger_exact"]'::jsonb
      ) x
    ),
    pass_condition=pass_condition||jsonb_build_object(
      'runtime_effect_state_server_derived',true,
      'allowed_runtime_change_states',jsonb_build_array('NO_RUNTIME_CHANGE','APPLIED_VERIFIED'),
      'migration_target_requires_exact_ledger',true,
      'definition_effect_rows_must_match_server',true
    ),
    updated_at=now(),
    updated_by_execution_id=(
      select e.execution_id
      from public.lf_operation_execution e
      where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
        and e.status='IN_PROGRESS'
        and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
        and e.target_path='supabase/migrations/20260920104500_lf_runtime_update_close_effect_state_v1.sql'
    )
where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
  and step_id='close'
  and status='ACTIVE_ENFORCEMENT';

update public.lf_operation_step_judge_bindings
set required_evidence_keys=(
      select jsonb_agg(distinct x order by x)
      from jsonb_array_elements_text(
        required_evidence_keys ||
        '["runtime_change_state","live_apply_verified","live_readback_verified","runtime_effect_rows","migration_ledger_exact"]'::jsonb
      ) x
    ),
    updated_at=now(),
    updated_by_execution_id=(
      select e.execution_id
      from public.lf_operation_execution e
      where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
        and e.status='IN_PROGRESS'
        and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
        and e.target_path='supabase/migrations/20260920104500_lf_runtime_update_close_effect_state_v1.sql'
    )
where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
  and step_id='close'
  and status='ACTIVE_ENFORCEMENT';

update public.lf_operation_steps
set evidence_required='all_required_steps_clean; open_blockers; no_auto_promotion; runtime_unchanged; runtime_change_state; live_apply_verified; live_readback_verified; runtime_effect_rows; migration_ledger_exact',
    updated_at=now(),
    updated_by_execution_id=(
      select e.execution_id
      from public.lf_operation_execution e
      where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
        and e.status='IN_PROGRESS'
        and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
        and e.target_path='supabase/migrations/20260920104500_lf_runtime_update_close_effect_state_v1.sql'
    )
where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
  and step_id='close';

update public.lf_operation_registry
set notes=coalesce(notes,'')||
  ' | 2026-09-20 closure effect-state repair: close derives canonical runtime-definition effects and exact migration-ledger binding; NO_RUNTIME_CHANGE and APPLIED_VERIFIED are mutually exclusive evidence states.',
    updated_at=now(),
    updated_by_execution_id=(
      select e.execution_id
      from public.lf_operation_execution e
      where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
        and e.status='IN_PROGRESS'
        and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
        and e.target_path='supabase/migrations/20260920104500_lf_runtime_update_close_effect_state_v1.sql'
    )
where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF';

do $post$
declare c int;
begin
  if not exists (
    select 1
    from public.lf_operation_step_contracts
    where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
      and step_id='close'
      and status='ACTIVE_ENFORCEMENT'
      and required_evidence_keys @> '[
        "runtime_unchanged",
        "runtime_change_state",
        "live_apply_verified",
        "live_readback_verified",
        "runtime_effect_rows",
        "migration_ledger_exact"
      ]'::jsonb
      and pass_condition->>'runtime_effect_state_server_derived'='true'
      and pass_condition->>'migration_target_requires_exact_ledger'='true'
  ) then
    raise exception 'RUNTIME_CLOSE_EFFECT_POST_CONTRACT_INVALID';
  end if;

  if position('APPLIED_VERIFIED' in pg_get_functiondef(
       'public.lf_runtime_update_trust_validation_v1(text,text,jsonb)'::regprocedure
     ))=0
     or position('runtime_effect_rows_mismatch' in pg_get_functiondef(
       'public.lf_runtime_update_trust_validation_v1(text,text,jsonb)'::regprocedure
     ))=0
  then
    raise exception 'RUNTIME_CLOSE_EFFECT_POST_FUNCTION_INVALID';
  end if;

  select count(*) into c
  from public.lf_operation_steps
  where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
    and active;
  if c<>14 then
    raise exception 'RUNTIME_CLOSE_EFFECT_POST_STEP_COUNT:%',c;
  end if;

  if not exists (
    select 1
    from public.lf_operation_registry
    where operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
      and lifecycle_state_code='OP_OPERATIONAL'
      and status='PRODUCCION_CONTROLADA'
  ) then
    raise exception 'RUNTIME_CLOSE_EFFECT_POST_OPERATION_STATE_CHANGED';
  end if;
end
$post$;
