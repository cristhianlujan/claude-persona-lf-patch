-- CREATION_FACTORY_PARITY_REPAIR_V1
-- Scope: CREACION_CARD_LF + CREACION_SKILL_LF.
-- Installs reusable guards/wrappers only. Governance rows are reconciled by a real
-- in-progress execution of the same operation_code, so provenance is never fabricated.

create or replace function public.lf_creation_factory_parity_guard_v1(p_operation_code text)
returns jsonb
language plpgsql
stable
set search_path to 'pg_catalog','public'
as $$
declare
  v_active integer;
  v_contract_ok integer;
  v_binding_ok integer;
  v_judge_ok integer;
  v_missing jsonb;
begin
  if p_operation_code not in ('CREACION_CARD_LF','CREACION_SKILL_LF','CREACION_PERFIL_LF') then
    return jsonb_build_object('valid',false,'verdict','BLOCK','code','UNSUPPORTED_CREATION_FACTORY');
  end if;

  select count(*) into v_active
  from public.lf_operation_steps s
  where s.operation_code=p_operation_code and s.active is true;

  select count(*) into v_contract_ok
  from public.lf_operation_steps s
  where s.operation_code=p_operation_code and s.active is true
    and (select count(*) from public.lf_operation_step_contracts c
         where c.operation_code=s.operation_code and c.step_id=s.step_id
           and c.step_order=s.step_order and c.status='ACTIVE')=1;

  select count(*) into v_binding_ok
  from public.lf_operation_steps s
  where s.operation_code=p_operation_code and s.active is true
    and (select count(*) from public.lf_operation_step_judge_bindings b
         where b.operation_code=s.operation_code and b.step_id=s.step_id
           and b.step_order=s.step_order and b.status='ACTIVE_ENFORCEMENT')=1;

  select count(*) into v_judge_ok
  from public.lf_operation_steps s
  where s.operation_code=p_operation_code and s.active is true
    and exists (
      select 1
      from public.lf_operation_step_judge_bindings b
      join public.lf_operation_judges j
        on j.operation_code=b.operation_code and j.judge_code=b.judge_code
      where b.operation_code=s.operation_code and b.step_id=s.step_id
        and b.step_order=s.step_order and b.status='ACTIVE_ENFORCEMENT'
        and j.status='ACTIVE_ENFORCEMENT'
    );

  select coalesce(jsonb_agg(jsonb_build_object(
    'step_id',s.step_id,'step_order',s.step_order,'execution_order',s.execution_order,
    'contract_count',(select count(*) from public.lf_operation_step_contracts c
      where c.operation_code=s.operation_code and c.step_id=s.step_id and c.step_order=s.step_order and c.status='ACTIVE'),
    'binding_count',(select count(*) from public.lf_operation_step_judge_bindings b
      where b.operation_code=s.operation_code and b.step_id=s.step_id and b.step_order=s.step_order and b.status='ACTIVE_ENFORCEMENT')
  ) order by coalesce(s.execution_order,s.step_order),s.step_order),'[]'::jsonb)
  into v_missing
  from public.lf_operation_steps s
  where s.operation_code=p_operation_code and s.active is true
    and (
      (select count(*) from public.lf_operation_step_contracts c
       where c.operation_code=s.operation_code and c.step_id=s.step_id and c.step_order=s.step_order and c.status='ACTIVE')<>1
      or
      (select count(*) from public.lf_operation_step_judge_bindings b
       where b.operation_code=s.operation_code and b.step_id=s.step_id and b.step_order=s.step_order and b.status='ACTIVE_ENFORCEMENT')<>1
      or not exists (
        select 1 from public.lf_operation_step_judge_bindings b
        join public.lf_operation_judges j on j.operation_code=b.operation_code and j.judge_code=b.judge_code
        where b.operation_code=s.operation_code and b.step_id=s.step_id and b.step_order=s.step_order
          and b.status='ACTIVE_ENFORCEMENT' and j.status='ACTIVE_ENFORCEMENT'
      )
    );

  return jsonb_build_object(
    'valid',v_active>0 and v_active=v_contract_ok and v_active=v_binding_ok and v_active=v_judge_ok,
    'verdict',case when v_active>0 and v_active=v_contract_ok and v_active=v_binding_ok and v_active=v_judge_ok then 'PASS' else 'BLOCK' end,
    'operation_code',p_operation_code,
    'active_steps',v_active,
    'contract_exact_steps',v_contract_ok,
    'binding_exact_steps',v_binding_ok,
    'judge_exact_steps',v_judge_ok,
    'missing_or_ambiguous',v_missing
  );
end
$$;

create or replace function public.lf_creation_factory_reconcile_v1(p_execution_id text)
returns jsonb
language plpgsql
set search_path to 'pg_catalog','public'
as $$
declare
  e public.lf_operation_execution%rowtype;
  v_parity jsonb;
begin
  select * into e
  from public.lf_operation_execution
  where execution_id=p_execution_id
  for update;

  if not found
     or e.operation_code not in ('CREACION_CARD_LF','CREACION_SKILL_LF')
     or e.status<>'IN_PROGRESS' then
    return jsonb_build_object('valid',false,'code','CREATION_FACTORY_RECONCILE_EXECUTION_INVALID');
  end if;

  if e.operation_code='CREACION_SKILL_LF' then
    update public.lf_operation_steps
    set execution_order = case step_id
      when 'init_execution' then 0
      when 'router' then 10
      when 'operational_source' then 20
      when 'creator_asset' then 30
      when 'repo_matrix_read' then 40
      when 'contract_read' then 50
      when 'repo_inventory_full' then 60
      when 'destination_validate' then 70
      when 'intake' then 80
      when 'duplicate_check' then 90
      when 'classification' then 100
      when 'generic_vs_specific' then 110
      when 'research_pack' then 120
      when 'research_to_rules_matrix' then 130
      when 'decision_matrix' then 140
      when 'canonical_design' then 150
      when 'operational_evidence_pack_check' then 160
      when 'step_depth_validation' then 170
      when 'pack_internal_depth_validation' then 180
      when 'examples_depth_validation' then 190
      when 'evals_depth_validation' then 200
      when 'judge_depth_validation' then 210
      when 'schema_depth_validation' then 220
      when 'output_modes_validation' then 230
      when 'blocking_overrides_validation' then 240
      when 'completeness' then 250
      when 'compatibility' then 260
      when 'rubric' then 270
      when 'sandbox' then 280
      when 'manifest' then 290
      when 'rule_trace' then 300
      when 'partial_scope_guard' then 310
      when 'pre_write_execution_binding_gate' then 320
      when 'github_write' then 330
      when 'github_readback' then 340
      when 'evidence_log' then 350
      when 'contract_judge' then 360
      when 'close' then 370
      when 'report_output' then 380
      else execution_order
    end,
    updated_at=now(),
    updated_by_execution_id=p_execution_id
    where operation_code='CREACION_SKILL_LF' and active is true;

    insert into public.lf_operation_steps(
      operation_code,step_order,step_id,required,evidence_required,source_path,source_sha,active,
      execution_order,created_by_execution_id,updated_by_execution_id
    )
    select
      'CREACION_SKILL_LF',38,'partial_scope_guard',true,
      'complete_operation_scope_confirmed_or_blocked',
      'gobernanza/procedimientos/creacion_skill_lf_steps_validation.yaml',
      '1012a6ce037bfb5540a87c5706960e6465244df2',
      true,310,p_execution_id,p_execution_id
    where not exists (
      select 1 from public.lf_operation_steps
      where operation_code='CREACION_SKILL_LF' and step_id='partial_scope_guard'
    );

    update public.lf_operation_steps
    set source_path='gobernanza/procedimientos/creacion_skill_lf_steps_validation.yaml',
        source_sha='1012a6ce037bfb5540a87c5706960e6465244df2',
        updated_at=now(),
        updated_by_execution_id=p_execution_id
    where operation_code='CREACION_SKILL_LF'
      and step_id in (
        'canonical_design','operational_evidence_pack_check','completeness','compatibility','rubric','sandbox',
        'manifest','rule_trace','partial_scope_guard','pre_write_execution_binding_gate','github_write',
        'github_readback','evidence_log','step_depth_validation','pack_internal_depth_validation',
        'examples_depth_validation','evals_depth_validation','judge_depth_validation','schema_depth_validation',
        'output_modes_validation','blocking_overrides_validation','contract_judge','close','report_output'
      );

    insert into public.lf_operation_step_contracts(
      operation_code,step_id,step_order,execution_order,contract_code,purpose,input_required,resolver_ref,
      output_payload,pass_condition,block_condition,blocking_code,mini_judge_code,required_evidence_keys,
      next_if_pass,next_if_blocked,status,notes,created_by_execution_id,updated_by_execution_id
    )
    select
      'CREACION_SKILL_LF','partial_scope_guard',38,310,
      'CONTRACT_CREACION_SKILL_LF_PARTIAL_SCOPE_GUARD_V1',
      'Bloquear cualquier intento de ejecutar o cerrar sólo una fracción del protocolo obligatorio de creación de Skill.',
      '["skill_request_packet","operation_steps","complete_operation_scope_confirmed_or_blocked"]'::jsonb,
      'public.lf_operation_step_judge_bindings + public.lf_operation_judges',
      '{"step_result":"PASS|BLOCKED","blocking_codes":[],"complete_operation_scope_confirmed_or_blocked":true}'::jsonb,
      '{"must_have_evidence":"complete_operation_scope_confirmed_or_blocked","must_not_be_generic":true,"must_match_step_purpose":true,"required_if_step_required":true}'::jsonb,
      '{"scope_bypass":true,"generic_payload":true,"missing_evidence":"complete_operation_scope_confirmed_or_blocked","invented_source_or_destination":true}'::jsonb,
      'BLOCKED_PARTIAL_SCOPE_GUARD_NOT_CLEAN',
      'MINI_JUDGE_CREACION_SKILL_LF_PARTIAL_SCOPE_GUARD_V1',
      '["complete_operation_scope_confirmed_or_blocked","step_result","blocking_codes"]'::jsonb,
      'NEXT_BY_EXECUTION_ORDER','RETURN_TO_WORKER_FOR_SELF_REPAIR_OR_BACKEND_CONFIG','ACTIVE',
      'Materialized from governed Skill v0.7 source; no parallel runtime.',
      p_execution_id,p_execution_id
    where not exists (
      select 1 from public.lf_operation_step_contracts
      where operation_code='CREACION_SKILL_LF' and step_id='partial_scope_guard'
    );

    update public.lf_operation_step_contracts c
    set execution_order=s.execution_order,
        step_order=s.step_order,
        updated_at=now(),
        updated_by_execution_id=p_execution_id
    from public.lf_operation_steps s
    where c.operation_code='CREACION_SKILL_LF'
      and s.operation_code=c.operation_code
      and s.step_id=c.step_id
      and c.status='ACTIVE';

    update public.lf_operation_registry
    set version='v0.7',
        notes=case
          when coalesce(notes,'') like '%CREATION_FACTORY_PARITY_REPAIR_V1%' then notes
          else coalesce(notes,'')||' | CREATION_FACTORY_PARITY_REPAIR_V1: source-authoritative execution order restored; partial-scope guard restored; judge/binding parity enforced by common guard.'
        end,
        updated_at=now(),
        updated_by_execution_id=p_execution_id
    where operation_code='CREACION_SKILL_LF';
  end if;

  insert into public.lf_operation_judges(
    operation_code,judge_code,judge_path,judge_sha,pass_if,fail_if,result_values,status,
    created_by_execution_id,updated_by_execution_id
  )
  select
    c.operation_code,
    c.mini_judge_code,
    'supabase://public/lf_operation_step_contracts/'||c.operation_code||'/'||c.step_id,
    c.contract_code,
    case
      when jsonb_typeof(c.pass_condition)='object'
        and jsonb_typeof(c.pass_condition->'pass_minimum')='array'
        then c.pass_condition->'pass_minimum'
      else '{"pass_condition_met":true,"step_contract_present":true,"generic_payload_rejected":true,"required_evidence_keys_present":true}'::jsonb
    end,
    case
      when jsonb_typeof(c.block_condition)='object'
        and not exists (
          select 1 from jsonb_each(c.block_condition) x where jsonb_typeof(x.value)<>'boolean'
        )
        then c.block_condition || '{"step_contract_missing":true,"required_evidence_missing":true}'::jsonb
      else c.block_condition
    end,
    jsonb_build_object(
      'pass','STEP_CLEAN_PASS',
      'return','RETURN_TO_WORKER_FOR_SELF_REPAIR',
      'blocked',coalesce(nullif(c.blocking_code,''),'BLOCKED_STEP_NOT_CLEAN')
    ),
    'ACTIVE_ENFORCEMENT',p_execution_id,p_execution_id
  from public.lf_operation_step_contracts c
  join public.lf_operation_steps s
    on s.operation_code=c.operation_code and s.step_id=c.step_id and s.step_order=c.step_order
  where c.operation_code=e.operation_code
    and c.status='ACTIVE'
    and s.active is true
    and c.mini_judge_code is not null
    and not exists (
      select 1 from public.lf_operation_judges j
      where j.operation_code=c.operation_code and j.judge_code=c.mini_judge_code
    );

  insert into public.lf_operation_step_judge_bindings(
    operation_code,step_order,step_id,judge_code,clean_result_value,blocked_result_value,
    return_result_value,required_evidence_keys,status,created_by_execution_id,updated_by_execution_id
  )
  select
    c.operation_code,c.step_order,c.step_id,c.mini_judge_code,
    'STEP_CLEAN_PASS',
    coalesce(nullif(c.blocking_code,''),'BLOCKED_STEP_NOT_CLEAN'),
    'RETURN_TO_WORKER_FOR_SELF_REPAIR',
    c.required_evidence_keys,
    'ACTIVE_ENFORCEMENT',p_execution_id,p_execution_id
  from public.lf_operation_step_contracts c
  join public.lf_operation_steps s
    on s.operation_code=c.operation_code and s.step_id=c.step_id and s.step_order=c.step_order
  join public.lf_operation_judges j
    on j.operation_code=c.operation_code and j.judge_code=c.mini_judge_code
  where c.operation_code=e.operation_code
    and c.status='ACTIVE'
    and s.active is true
    and j.status='ACTIVE_ENFORCEMENT'
    and not exists (
      select 1 from public.lf_operation_step_judge_bindings b
      where b.operation_code=c.operation_code and b.step_order=c.step_order and b.step_id=c.step_id
    );

  v_parity:=public.lf_creation_factory_parity_guard_v1(e.operation_code);
  return v_parity||jsonb_build_object('reconciled_by_execution_id',p_execution_id);
end
$$;

create or replace function public.lf_creation_factory_trust_validation_v1(
  p_execution_id text,
  p_step_id text,
  p_evidence_payload jsonb
)
returns jsonb
language plpgsql
stable
set search_path to 'pg_catalog','public'
as $$
declare
  e public.lf_operation_execution%rowtype;
  s public.lf_operation_steps%rowtype;
  c public.lf_operation_step_contracts%rowtype;
  b public.lf_operation_step_judge_bindings%rowtype;
  j public.lf_operation_judges%rowtype;
  v_parity jsonb;
  v_missing text[] := array[]::text[];
  v_key text;
  v_assertions jsonb := '[]'::jsonb;
  v_hard jsonb := '[]'::jsonb;
  v_prior_missing integer := 0;
  v_prior_bad integer := 0;
  v_pred_bad integer := 0;
  v_contract_sha text;
begin
  if nullif(btrim(coalesce(p_execution_id,'')),'') is null
     or nullif(btrim(coalesce(p_step_id,'')),'') is null
     or p_evidence_payload is null
     or jsonb_typeof(p_evidence_payload)<>'object' then
    return jsonb_build_object('valid',false,'code','CREATION_FACTORY_TRUST_INPUT_INVALID',
      'server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('server_validation_failed'));
  end if;

  select * into e from public.lf_operation_execution where execution_id=p_execution_id;
  if not found
     or e.operation_code not in ('CREACION_CARD_LF','CREACION_SKILL_LF')
     or e.status<>'IN_PROGRESS'
     or (e.operation_code='CREACION_CARD_LF' and e.target_type<>'CARD')
     or (e.operation_code='CREACION_SKILL_LF' and e.target_type<>'SKILL') then
    return jsonb_build_object('valid',false,'code','CREATION_FACTORY_EXECUTION_BINDING_INVALID',
      'server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('server_validation_failed'));
  end if;

  v_parity:=public.lf_creation_factory_parity_guard_v1(e.operation_code);
  if coalesce((v_parity->>'valid')::boolean,false) is not true then
    return jsonb_build_object('valid',false,'code','CREATION_FACTORY_PARITY_NOT_CLEAN',
      'details',v_parity,'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('factory_parity_failed'));
  end if;

  select * into s from public.lf_operation_steps
  where operation_code=e.operation_code and step_id=p_step_id and active is true;
  if not found or p_step_id='init_execution' then
    return jsonb_build_object('valid',false,'code','CREATION_FACTORY_STEP_INVALID',
      'server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('server_validation_failed'));
  end if;

  select * into c from public.lf_operation_step_contracts
  where operation_code=e.operation_code and step_id=p_step_id
    and step_order=s.step_order and status='ACTIVE';
  select * into b from public.lf_operation_step_judge_bindings
  where operation_code=e.operation_code and step_id=p_step_id
    and step_order=s.step_order and status='ACTIVE_ENFORCEMENT';
  select * into j from public.lf_operation_judges
  where operation_code=e.operation_code and judge_code=b.judge_code
    and status='ACTIVE_ENFORCEMENT';

  if c.step_id is null or b.step_id is null or j.judge_code is null then
    return jsonb_build_object('valid',false,'code','CREATION_FACTORY_AUTHORITY_CHAIN_INCOMPLETE',
      'server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('server_validation_failed'));
  end if;

  for v_key in select jsonb_array_elements_text(b.required_evidence_keys) loop
    if not (p_evidence_payload ? v_key)
       or p_evidence_payload->v_key is null
       or p_evidence_payload->v_key='null'::jsonb
       or (jsonb_typeof(p_evidence_payload->v_key)='string' and btrim(p_evidence_payload->>v_key)='') then
      v_missing:=array_append(v_missing,v_key);
    end if;
  end loop;
  if cardinality(v_missing)>0 then
    v_hard:=v_hard||jsonb_build_array('required_evidence_missing');
  end if;

  if jsonb_typeof(p_evidence_payload->'blocking_codes')<>'array'
     or jsonb_array_length(coalesce(p_evidence_payload->'blocking_codes','["__invalid__"]'::jsonb))<>0 then
    v_hard:=v_hard||jsonb_build_array('blocking_codes_not_clean');
  end if;

  if p_step_id in ('github_write','github_readback') then
    select count(*) into v_pred_bad
    from public.lf_operation_steps ps
    left join public.lf_operation_step_judge_bindings pb
      on pb.operation_code=ps.operation_code and pb.step_id=ps.step_id and pb.step_order=ps.step_order
      and pb.status='ACTIVE_ENFORCEMENT'
    left join public.lf_operation_execution_steps pe
      on pe.execution_id=p_execution_id and pe.step_id=ps.step_id and pe.step_order=ps.step_order
    where ps.operation_code=e.operation_code
      and ps.step_id=case when p_step_id='github_write' then 'pre_write_execution_binding_gate' else 'github_write' end
      and (pe.step_id is null or pb.clean_result_value is null or pe.status<>pb.clean_result_value);
    if v_pred_bad<>0 then v_hard:=v_hard||jsonb_build_array('write_chain_predecessor_not_clean'); end if;

    if e.operation_code='CREACION_CARD_LF' and p_step_id='github_write'
       and coalesce(p_evidence_payload->>'file_commit_sha','') !~ '^[0-9a-f]{40}$' then
      v_hard:=v_hard||jsonb_build_array('card_file_commit_sha_invalid');
    elsif e.operation_code='CREACION_CARD_LF' and p_step_id='github_readback'
       and coalesce(p_evidence_payload->>'file_readback_sha','') !~ '^[0-9a-f]{40}$' then
      v_hard:=v_hard||jsonb_build_array('card_file_readback_sha_invalid');
    elsif e.operation_code='CREACION_SKILL_LF' and p_step_id='github_write' then
      if coalesce(p_evidence_payload->>'repo','')=''
         or coalesce(p_evidence_payload->>'branch','')=''
         or coalesce(p_evidence_payload->>'commit_sha','') !~ '^[0-9a-f]{40}$'
         or jsonb_typeof(p_evidence_payload->'written_files')<>'array'
         or jsonb_array_length(p_evidence_payload->'written_files')=0
         or coalesce((p_evidence_payload->>'partial_write_detected')::boolean,true) is not false then
        v_hard:=v_hard||jsonb_build_array('skill_github_write_evidence_invalid');
      end if;
    elsif e.operation_code='CREACION_SKILL_LF' and p_step_id='github_readback' then
      if coalesce(p_evidence_payload->>'repo','')=''
         or coalesce(p_evidence_payload->>'branch','')=''
         or p_evidence_payload->>'sha_match_status'<>'PASS'
         or jsonb_typeof(p_evidence_payload->'readback_files')<>'array'
         or jsonb_array_length(p_evidence_payload->'readback_files')=0
         or coalesce((p_evidence_payload->>'files_count')::integer,-1)<>jsonb_array_length(p_evidence_payload->'readback_files') then
        v_hard:=v_hard||jsonb_build_array('skill_github_readback_evidence_invalid');
      end if;
    end if;
  end if;

  if p_step_id in ('card_examples_depth_judge','contract_judge','close') then
    select count(*) into v_prior_missing
    from public.lf_operation_steps ps
    where ps.operation_code=e.operation_code and ps.required is true and ps.active is true
      and coalesce(ps.execution_order,ps.step_order)<coalesce(s.execution_order,s.step_order)
      and not exists (
        select 1 from public.lf_operation_execution_steps pe
        where pe.execution_id=p_execution_id and pe.step_id=ps.step_id and pe.step_order=ps.step_order
      );

    select count(*) into v_prior_bad
    from public.lf_operation_steps ps
    left join public.lf_operation_step_judge_bindings pb
      on pb.operation_code=ps.operation_code and pb.step_id=ps.step_id and pb.step_order=ps.step_order
      and pb.status='ACTIVE_ENFORCEMENT'
    join public.lf_operation_execution_steps pe
      on pe.execution_id=p_execution_id and pe.step_id=ps.step_id and pe.step_order=ps.step_order
    where ps.operation_code=e.operation_code and ps.required is true and ps.active is true
      and coalesce(ps.execution_order,ps.step_order)<coalesce(s.execution_order,s.step_order)
      and (pb.clean_result_value is null or pe.status<>pb.clean_result_value);

    if v_prior_missing>0 or v_prior_bad>0 then
      v_hard:=v_hard||jsonb_build_array('required_predecessor_not_clean');
    end if;
  end if;

  if p_step_id='card_examples_depth_judge'
     and coalesce((p_evidence_payload->>'card_examples_depth_judge_pass')::boolean,false) is not true then
    v_hard:=v_hard||jsonb_build_array('card_examples_depth_not_proven');
  end if;

  if p_step_id='contract_judge' then
    select contract_sha into v_contract_sha
    from public.lf_operation_contracts
    where operation_code=e.operation_code
      and contract_code=case when e.operation_code='CREACION_CARD_LF' then 'CONTRATO_CARD_LF' else 'CONTRATO_SKILL_LF' end
    limit 1;

    if (e.manifest->>'automatic_impact') is distinct from 'BLOQUEADO'
       or coalesce((e.manifest->>'runtime_enabled')::boolean,true) is not false
       or coalesce((e.manifest->>'production_impact')::boolean,true) is not false
       or p_evidence_payload->>'source_sha' is distinct from s.source_sha
       or p_evidence_payload->>'contract_sha' is distinct from v_contract_sha
       or p_evidence_payload->>'judge_sha' is distinct from j.judge_sha
       or (e.operation_code='CREACION_CARD_LF'
           and coalesce((p_evidence_payload->>'judge_pass_and_scope_confirmed')::boolean,false) is not true)
       or (e.operation_code='CREACION_SKILL_LF'
           and coalesce((p_evidence_payload->>'contract_judged')::boolean,false) is not true) then
      v_hard:=v_hard||jsonb_build_array('contract_judge_server_binding_invalid');
    end if;
  end if;

  if p_step_id='close' then
    if (e.manifest->>'automatic_impact') is distinct from 'BLOQUEADO'
       or coalesce((e.manifest->>'runtime_enabled')::boolean,true) is not false
       or coalesce((e.manifest->>'production_impact')::boolean,true) is not false
       or coalesce((e.manifest->>'security_hold_active')::boolean,false) is true
       or (e.operation_code='CREACION_CARD_LF'
           and coalesce((p_evidence_payload->>'no_blocking_observations_and_scope_confirmed')::boolean,false) is not true)
       or (e.operation_code='CREACION_SKILL_LF'
           and coalesce((p_evidence_payload->>'close_verified')::boolean,false) is not true) then
      v_hard:=v_hard||jsonb_build_array('close_server_binding_invalid');
    end if;
  end if;

  if jsonb_array_length(v_hard)>0 then
    return jsonb_build_object(
      'valid',false,
      'code','CREATION_FACTORY_SERVER_VALIDATION_FAILED',
      'details',jsonb_build_object('step_id',p_step_id,'missing_keys',to_jsonb(v_missing),'hard_fails',v_hard),
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed')
    );
  end if;

  if jsonb_typeof(j.pass_if)='array' then
    v_assertions:=j.pass_if;
  elsif jsonb_typeof(j.pass_if)='object' and jsonb_typeof(j.pass_if->'pass_if')='array' then
    v_assertions:=j.pass_if->'pass_if';
  elsif jsonb_typeof(j.pass_if)='object' then
    select coalesce(jsonb_agg(key order by key),'[]'::jsonb)
    into v_assertions
    from jsonb_each(j.pass_if)
    where value='true'::jsonb;
  else
    return jsonb_build_object('valid',false,'code','CREATION_FACTORY_JUDGE_PASS_SHAPE_INVALID',
      'server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('server_validation_failed'));
  end if;

  return jsonb_build_object(
    'valid',true,
    'code','CREATION_FACTORY_SERVER_VALIDATED',
    'details',jsonb_build_object('step_id',p_step_id,'execution_id',p_execution_id),
    'server_assertions',v_assertions,
    'server_hard_fails','[]'::jsonb
  );
end
$$;

create or replace function public.lf_reserve_creation_factory_execution_v1(
  p_execution_id text,
  p_operation_code text,
  p_target_code text,
  p_idempotency_key text,
  p_request_sha256 text,
  p_actor_execution_id text,
  p_target_repo text default null,
  p_target_path text default null,
  p_manifest jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
set search_path to 'pg_catalog','public'
as $$
declare
  v_target_type text;
  v_result jsonb;
  v_reconcile jsonb;
  v_init public.lf_operation_steps%rowtype;
  v_binding public.lf_operation_step_judge_bindings%rowtype;
begin
  select applies_to_asset_type into v_target_type
  from public.lf_operation_registry
  where operation_code=p_operation_code
    and operation_type='CREATION_PROTOCOL'
    and status in ('PRODUCCION_CONTROLADA_READ_ONLY','CANDIDATO_READ_ONLY');

  if v_target_type is null or p_operation_code not in ('CREACION_CARD_LF','CREACION_SKILL_LF') then
    return jsonb_build_object('result','BLOCKED','code','CREATION_FACTORY_OPERATION_NOT_ADMITTED');
  end if;

  v_result:=public.fn_lf_operation_reserve_execution_v1(
    p_execution_id,p_operation_code,v_target_type,p_target_code,p_idempotency_key,p_request_sha256,
    p_actor_execution_id,p_target_repo,p_target_path,
    coalesce(p_manifest,'{}'::jsonb)||jsonb_build_object(
      'creation_factory_guard','CREATION_FACTORY_PARITY_REPAIR_V1',
      'runtime_enabled',false,
      'production_impact',false,
      'automatic_impact','BLOQUEADO'
    )
  );

  if v_result->>'status'<>'IN_PROGRESS' then
    return v_result;
  end if;

  v_reconcile:=public.lf_creation_factory_reconcile_v1(p_execution_id);
  if coalesce((v_reconcile->>'valid')::boolean,false) is not true then
    return v_result||jsonb_build_object(
      'dispatch_permitted',false,
      'code','CREATION_FACTORY_RECONCILIATION_FAILED',
      'factory_parity',v_reconcile
    );
  end if;

  select * into v_init from public.lf_operation_steps
  where operation_code=p_operation_code and step_id='init_execution' and active is true;

  if v_init.step_id is not null then
    select * into v_binding from public.lf_operation_step_judge_bindings
    where operation_code=p_operation_code and step_id='init_execution'
      and step_order=v_init.step_order and status='ACTIVE_ENFORCEMENT';

    insert into public.lf_operation_execution_steps(
      execution_id,step_order,step_id,status,evidence_ref,evidence_payload,notes,created_by_execution_id
    )
    select
      p_execution_id,v_init.step_order,'init_execution',v_binding.clean_result_value,
      'supabase://public/lf_operation_execution/'||p_execution_id,
      jsonb_build_object(
        'execution_row_created',true,
        'execution_id',p_execution_id,
        'operation_code',p_operation_code,
        'target_type',v_target_type,
        'status','IN_PROGRESS',
        'step_result',v_binding.clean_result_value,
        'blocking_codes','[]'::jsonb,
        'blocking_findings','[]'::jsonb,
        'return_to_worker_reasons','[]'::jsonb,
        'assertions_checked',jsonb_build_array(
          'execution_row_created','operation_code_exact','target_type_skill','status_in_progress'
        ),
        'hard_fails_checked','[]'::jsonb,
        'recorded_by_rpc','lf_reserve_creation_factory_execution_v1'
      ),
      'Server-derived init_execution for governed creation factory.',
      p_execution_id
    where not exists (
      select 1 from public.lf_operation_execution_steps
      where execution_id=p_execution_id and step_id='init_execution'
    );
  end if;

  return v_result||jsonb_build_object('factory_parity',v_reconcile,'target_type',v_target_type);
end
$$;

create or replace function public.lf_record_creation_factory_step_v1(
  p_execution_id text,
  p_step_id text,
  p_evidence_ref text,
  p_evidence_payload jsonb,
  p_actor_execution_id text
)
returns jsonb
language plpgsql
set search_path to 'pg_catalog','public'
as $$
declare
  e public.lf_operation_execution%rowtype;
  v_trust jsonb;
  v_result jsonb;
  v_required_not_clean integer;
begin
  select * into e from public.lf_operation_execution where execution_id=p_execution_id;
  if not found or e.operation_code not in ('CREACION_CARD_LF','CREACION_SKILL_LF') then
    return jsonb_build_object('outcome','BLOCKED','code','CREATION_FACTORY_EXECUTION_IDENTITY_INVALID','durable',false);
  end if;

  v_trust:=public.lf_creation_factory_trust_validation_v1(p_execution_id,p_step_id,p_evidence_payload);

  v_result:=public.lf_record_operation_step_core_v1(
    p_execution_id,p_step_id,p_evidence_ref,p_evidence_payload,p_actor_execution_id,
    e.operation_code,e.target_type,
    'ACTIVE','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT',
    v_trust,false,'lf_record_creation_factory_step_v1'
  );

  if v_result->>'outcome'='STEP_RECORDED' and p_step_id='close' then
    select count(*) into v_required_not_clean
    from public.lf_operation_steps s
    left join public.lf_operation_execution_steps es
      on es.execution_id=p_execution_id and es.step_id=s.step_id and es.step_order=s.step_order
    left join public.lf_operation_step_judge_bindings b
      on b.operation_code=s.operation_code and b.step_id=s.step_id and b.step_order=s.step_order
      and b.status='ACTIVE_ENFORCEMENT'
    where s.operation_code=e.operation_code and s.required is true and s.active is true
      and (es.step_id is null or b.clean_result_value is null or es.status<>b.clean_result_value);

    if v_required_not_clean>0 then
      raise exception 'CREATION_FACTORY_COMPLETION_NOT_CLEAN execution=% required_not_clean=%',
        p_execution_id,v_required_not_clean;
    end if;

    update public.lf_operation_execution
    set status='CONTROLLED_READ_ONLY_PASS',
        completed_at=coalesce(completed_at,now()),
        manifest=coalesce(manifest,'{}'::jsonb)||jsonb_build_object(
          'operation_closed',true,
          'closure_allowed',true,
          'blocked_from_closure',false,
          'next_gate','report_output_optional'
        ),
        updated_by_execution_id=p_actor_execution_id,
        updated_at=now()
    where execution_id=p_execution_id and status='IN_PROGRESS';

    v_result:=v_result||jsonb_build_object('execution_status','CONTROLLED_READ_ONLY_PASS');
  end if;

  return v_result;
end
$$;

create or replace function public.lf_record_creacion_card_step_v1(
  p_execution_id text,p_step_id text,p_evidence_ref text,p_evidence_payload jsonb,p_actor_execution_id text
)
returns jsonb
language plpgsql
set search_path to 'pg_catalog','public'
as $$
begin
  if not exists (
    select 1 from public.lf_operation_execution
    where execution_id=p_execution_id and operation_code='CREACION_CARD_LF' and target_type='CARD'
  ) then
    return jsonb_build_object('outcome','BLOCKED','code','CARD_CREATION_EXECUTION_IDENTITY_INVALID','durable',false);
  end if;
  return public.lf_record_creation_factory_step_v1(
    p_execution_id,p_step_id,p_evidence_ref,p_evidence_payload,p_actor_execution_id
  );
end
$$;

create or replace function public.lf_record_creacion_skill_step_v1(
  p_execution_id text,p_step_id text,p_evidence_ref text,p_evidence_payload jsonb,p_actor_execution_id text
)
returns jsonb
language plpgsql
set search_path to 'pg_catalog','public'
as $$
begin
  if not exists (
    select 1 from public.lf_operation_execution
    where execution_id=p_execution_id and operation_code='CREACION_SKILL_LF' and target_type='SKILL'
  ) then
    return jsonb_build_object('outcome','BLOCKED','code','SKILL_CREATION_EXECUTION_IDENTITY_INVALID','durable',false);
  end if;
  return public.lf_record_creation_factory_step_v1(
    p_execution_id,p_step_id,p_evidence_ref,p_evidence_payload,p_actor_execution_id
  );
end
$$;
