begin;

-- S30 / lf-contract-check PRE_EKB consumer binding v1.
-- Extends the existing PRE_EKB_GATE capability to the real operation
-- GITHUB_CONTRACT_GATE_LF. No new EKB writer, error store, Router or gate engine.
-- Productive ingress remains public.lf_record_gate_checks_v1; the existing
-- AFTER INSERT trigger owns PRE_EKB dispatch and ACT-0057 canonical EKB writes.

do $pre$
declare
  v_consumers jsonb;
begin
  if to_regprocedure('public.lf_record_gate_checks_v1(text,text,text,text,jsonb,jsonb,jsonb,text)') is null
     or to_regprocedure('public.lf_pre_ekb_gate_consumer_v1(text)') is null
     or to_regprocedure('public.lf_pre_ekb_gate_check_dispatch_v1(bigint)') is null
     or to_regprocedure('public.fn_lf_operation_reserve_execution_v1(text,text,text,text,text,text,text,text,text,jsonb)') is null then
    raise exception 'BLOCK_LF_CONTRACT_PRE_EKB_DEPENDENCY_MISSING';
  end if;

  if not exists (
    select 1
    from information_schema.triggers
    where event_object_schema='public'
      and event_object_table='lf_operation_gate_check_results'
      and trigger_name='trg_lf_pre_ekb_gate_check_autopersist_v1'
      and action_timing='AFTER'
      and event_manipulation='INSERT'
  ) then
    raise exception 'BLOCK_LF_CONTRACT_PRE_EKB_TRIGGER_MISSING';
  end if;

  select metadata #> '{transversal_inventory,consumers_known}'
    into v_consumers
  from public.lf_activos
  where codigo_activo='PRE_EKB_GATE'
    and archived_at is null
    and estado_operativo='ACTIVO'
    and runtime_estado='SUPABASE_ENFORCED'
    and metadata #>> '{transversal_inventory,inventory_status}'='ACTIVE_SHARED_ENFORCEMENT';

  if v_consumers is null then
    raise exception 'BLOCK_LF_CONTRACT_PRE_EKB_ASSET_NOT_CURRENT';
  end if;

  if not exists (
    select 1
    from public.lf_operation_registry
    where operation_code='GITHUB_CONTRACT_GATE_LF'
      and lifecycle_state_code='OP_OPERATIONAL'
  ) then
    raise exception 'BLOCK_LF_CONTRACT_PRE_EKB_OPERATION_NOT_OPERATIONAL';
  end if;

  if not exists (
    select 1
    from public.lf_operation_steps
    where operation_code='GITHUB_CONTRACT_GATE_LF'
      and step_id='contract_judge'
      and active
  ) then
    raise exception 'BLOCK_LF_CONTRACT_PRE_EKB_CANONICAL_STEP_MISSING';
  end if;
end
$pre$;

update public.lf_activos
set version='v0.2.2',
    ultima_revision='PRE_EKB_GATE_V0_2_2_GITHUB_CONTRACT_GATE_20260918',
    metadata=jsonb_set(
      metadata,
      '{transversal_inventory,consumers_known}',
      case
        when jsonb_typeof(metadata #> '{transversal_inventory,consumers_known}')='array'
          then case
            when (metadata #> '{transversal_inventory,consumers_known}') ? 'GITHUB_CONTRACT_GATE_LF'
              then metadata #> '{transversal_inventory,consumers_known}'
            else (metadata #> '{transversal_inventory,consumers_known}') || '["GITHUB_CONTRACT_GATE_LF"]'::jsonb
          end
        when jsonb_typeof(metadata #> '{transversal_inventory,consumers_known}')='string'
          then case
            when metadata #>> '{transversal_inventory,consumers_known}'='GITHUB_CONTRACT_GATE_LF'
              then jsonb_build_array('GITHUB_CONTRACT_GATE_LF')
            else jsonb_build_array(
              metadata #>> '{transversal_inventory,consumers_known}',
              'GITHUB_CONTRACT_GATE_LF'
            )
          end
        else jsonb_build_array('GITHUB_CONTRACT_GATE_LF')
      end,
      true
    ),
    updated_by_execution_id='EXEC-S30-LF-CONTRACT-PRE-EKB-CONSUMER-20260918-001',
    updated_at=clock_timestamp()
where codigo_activo='PRE_EKB_GATE'
  and archived_at is null;

do $binding$
declare
  v_count integer;
begin
  if not public.lf_pre_ekb_gate_consumer_v1('GITHUB_CONTRACT_GATE_LF') then
    raise exception 'BLOCK_LF_CONTRACT_PRE_EKB_BINDING_READBACK';
  end if;

  select count(*) into v_count
  from jsonb_array_elements_text(
    (
      select metadata #> '{transversal_inventory,consumers_known}'
      from public.lf_activos
      where codigo_activo='PRE_EKB_GATE' and archived_at is null
    )
  ) x(value)
  where value='GITHUB_CONTRACT_GATE_LF';

  if v_count<>1 then
    raise exception 'BLOCK_LF_CONTRACT_PRE_EKB_BINDING_CARDINALITY:%',v_count;
  end if;
end
$binding$;

-- Transactional canary. The inner exception rolls back all canary executions,
-- gate rows, EKB writes and events while preserving the consumer binding above.
do $canary$
declare
  v_exec_fail constant text := 'EXEC-CANARY-LF-CONTRACT-PRE-EKB-FAIL-20260918';
  v_exec_recur constant text := 'EXEC-CANARY-LF-CONTRACT-PRE-EKB-RECUR-20260918';
  v_exec_pass constant text := 'EXEC-CANARY-LF-CONTRACT-PRE-EKB-PASS-20260918';
  v_exec_block constant text := 'EXEC-CANARY-LF-CONTRACT-PRE-EKB-BLOCK-20260918';
  v_request text;
  v_result jsonb;
  v_event jsonb;
  v_first_class text;
  v_second_class text;
  v_count integer;
begin
  begin
    v_request:=encode(
      extensions.digest(convert_to('LF_CONTRACT_PRE_EKB_FAIL_CANARY_20260918','UTF8'),'sha256'),
      'hex'
    );
    perform public.fn_lf_operation_reserve_execution_v1(
      v_exec_fail,
      'GITHUB_CONTRACT_GATE_LF',
      'REPOSITORY_GOVERNED_PATHS',
      'LF_CONTRACT_PRE_EKB_FAIL_CANARY',
      'LF-CONTRACT-PRE-EKB:FAIL:20260918',
      v_request,
      v_exec_fail,
      'cristhianlujan/claude-persona-lf-patch',
      '.github/workflows/lf-contract-check.yml',
      jsonb_build_object('mode','TRANSACTIONAL_ROLLBACK_CANARY','persistent_effect_allowed',false)
    );

    v_result:=public.lf_record_gate_checks_v1(
      v_exec_fail,
      'contract_judge',
      'LF_CONTRACT_CHECK_PRE_EKB_CANARY',
      'COLLECT_ALL',
      '["CANARY-001"]'::jsonb,
      jsonb_build_array(jsonb_build_object(
        'check_id','CANARY-001',
        'status','FAIL',
        'critical',true,
        'error_class','ASSERTION_FAILURE',
        'condition','deliberate PRE_EKB consumer canary exits with rc=0',
        'expected',jsonb_build_object('rc',0),
        'actual',jsonb_build_object('rc',1),
        'input_ref','.github/workflows/lf-contract-check.yml',
        'evidence_ref','migration://20260918145500#fail-canary',
        'producer','LF_CONTRACT_PRE_EKB_CONSUMER_CANARY',
        'rc',1,
        'downstream_impact',jsonb_build_array('EKB','CI_GOVERNANCE'),
        'owner','GITHUB_CONTRACT_GATE_LF',
        'next_action','ROLLBACK_CANARY_ONLY'
      )),
      jsonb_build_object(
        'source_commit',repeat('a',40),
        'source_path','.github/workflows/lf-contract-check.yml',
        'run_id','PRE-EKB-CANARY-FAIL',
        'job_id','migration-canary',
        'owner','GITHUB_CONTRACT_GATE_LF',
        'next_action','ROLLBACK_CANARY_ONLY',
        'environment','CANDIDATE',
        'attempt_no',1
      ),
      v_exec_fail
    );

    if v_result->>'outcome'<>'RECORDED' or v_result->>'gate_result'<>'FAIL' then
      raise exception 'BLOCK_LF_CONTRACT_PRE_EKB_FAIL_CANARY_RECORD:%',v_result;
    end if;

    select payload->'writer_receipt'
      into v_event
    from public.lf_eventos
    where created_by_execution_id=v_exec_fail
      and origen='LF_PRE_EKB_GATE_AUTOPERSIST_V1'
      and payload->>'persistence_result'='EKB_PERSISTED'
    order by id desc
    limit 1;

    if v_event is null then
      raise exception 'BLOCK_LF_CONTRACT_PRE_EKB_FAIL_CANARY_NO_RECEIPT';
    end if;
    v_first_class:=v_event->>'classification';
    if v_first_class<>'NEW_ERROR' then
      raise exception 'BLOCK_LF_CONTRACT_PRE_EKB_FAIL_CANARY_CLASS:%',v_first_class;
    end if;

    v_request:=encode(
      extensions.digest(convert_to('LF_CONTRACT_PRE_EKB_RECUR_CANARY_20260918','UTF8'),'sha256'),
      'hex'
    );
    perform public.fn_lf_operation_reserve_execution_v1(
      v_exec_recur,
      'GITHUB_CONTRACT_GATE_LF',
      'REPOSITORY_GOVERNED_PATHS',
      'LF_CONTRACT_PRE_EKB_RECUR_CANARY',
      'LF-CONTRACT-PRE-EKB:RECUR:20260918',
      v_request,
      v_exec_recur,
      'cristhianlujan/claude-persona-lf-patch',
      '.github/workflows/lf-contract-check.yml',
      jsonb_build_object('mode','TRANSACTIONAL_ROLLBACK_CANARY','persistent_effect_allowed',false)
    );

    v_result:=public.lf_record_gate_checks_v1(
      v_exec_recur,
      'contract_judge',
      'LF_CONTRACT_CHECK_PRE_EKB_CANARY',
      'COLLECT_ALL',
      '["CANARY-001"]'::jsonb,
      jsonb_build_array(jsonb_build_object(
        'check_id','CANARY-001',
        'status','FAIL',
        'critical',true,
        'error_class','ASSERTION_FAILURE',
        'condition','deliberate PRE_EKB consumer canary exits with rc=0',
        'expected',jsonb_build_object('rc',0),
        'actual',jsonb_build_object('rc',1),
        'input_ref','.github/workflows/lf-contract-check.yml',
        'evidence_ref','migration://20260918145500#recurrence-canary',
        'producer','LF_CONTRACT_PRE_EKB_CONSUMER_CANARY',
        'rc',1,
        'downstream_impact',jsonb_build_array('EKB','CI_GOVERNANCE'),
        'owner','GITHUB_CONTRACT_GATE_LF',
        'next_action','ROLLBACK_CANARY_ONLY'
      )),
      jsonb_build_object(
        'source_commit',repeat('a',40),
        'source_path','.github/workflows/lf-contract-check.yml',
        'run_id','PRE-EKB-CANARY-RECUR',
        'job_id','migration-canary',
        'owner','GITHUB_CONTRACT_GATE_LF',
        'next_action','ROLLBACK_CANARY_ONLY',
        'environment','CANDIDATE',
        'attempt_no',1
      ),
      v_exec_recur
    );

    select payload->'writer_receipt'
      into v_event
    from public.lf_eventos
    where created_by_execution_id=v_exec_recur
      and origen='LF_PRE_EKB_GATE_AUTOPERSIST_V1'
      and payload->>'persistence_result'='EKB_PERSISTED'
    order by id desc
    limit 1;

    if v_event is null then
      raise exception 'BLOCK_LF_CONTRACT_PRE_EKB_RECUR_CANARY_NO_RECEIPT';
    end if;
    v_second_class:=v_event->>'classification';
    if v_second_class<>'RECURRENCE' then
      raise exception 'BLOCK_LF_CONTRACT_PRE_EKB_RECUR_CANARY_CLASS:%',v_second_class;
    end if;

    v_request:=encode(
      extensions.digest(convert_to('LF_CONTRACT_PRE_EKB_PASS_CANARY_20260918','UTF8'),'sha256'),
      'hex'
    );
    perform public.fn_lf_operation_reserve_execution_v1(
      v_exec_pass,
      'GITHUB_CONTRACT_GATE_LF',
      'REPOSITORY_GOVERNED_PATHS',
      'LF_CONTRACT_PRE_EKB_PASS_CANARY',
      'LF-CONTRACT-PRE-EKB:PASS:20260918',
      v_request,
      v_exec_pass,
      'cristhianlujan/claude-persona-lf-patch',
      '.github/workflows/lf-contract-check.yml',
      jsonb_build_object('mode','TRANSACTIONAL_ROLLBACK_CANARY','persistent_effect_allowed',false)
    );

    v_result:=public.lf_record_gate_checks_v1(
      v_exec_pass,
      'contract_judge',
      'LF_CONTRACT_CHECK_PRE_EKB_PASS_CANARY',
      'COLLECT_ALL',
      '["CANARY-PASS-001"]'::jsonb,
      jsonb_build_array(jsonb_build_object(
        'check_id','CANARY-PASS-001',
        'status','PASS',
        'critical',true,
        'condition','deliberate PRE_EKB pass canary exits with rc=0',
        'expected',jsonb_build_object('rc',0),
        'actual',jsonb_build_object('rc',0),
        'input_ref','.github/workflows/lf-contract-check.yml',
        'evidence_ref','migration://20260918145500#pass-canary',
        'producer','LF_CONTRACT_PRE_EKB_CONSUMER_CANARY',
        'rc',0,
        'downstream_impact','[]'::jsonb,
        'owner','GITHUB_CONTRACT_GATE_LF',
        'next_action','NONE'
      )),
      jsonb_build_object(
        'source_commit',repeat('a',40),
        'source_path','.github/workflows/lf-contract-check.yml',
        'run_id','PRE-EKB-CANARY-PASS',
        'job_id','migration-canary',
        'owner','GITHUB_CONTRACT_GATE_LF',
        'next_action','NONE',
        'environment','CANDIDATE',
        'attempt_no',1
      ),
      v_exec_pass
    );

    if v_result->>'outcome'<>'RECORDED' or v_result->>'gate_result'<>'PASS' then
      raise exception 'BLOCK_LF_CONTRACT_PRE_EKB_PASS_CANARY_RECORD:%',v_result;
    end if;

    select count(*) into v_count
    from public.lf_eventos
    where created_by_execution_id=v_exec_pass
      and origen='LF_PRE_EKB_GATE_AUTOPERSIST_V1';

    if v_count<>0 then
      raise exception 'BLOCK_LF_CONTRACT_PRE_EKB_PASS_CANARY_CREATED_EKB:%',v_count;
    end if;

    v_request:=encode(
      extensions.digest(convert_to('LF_CONTRACT_PRE_EKB_BLOCK_CANARY_20260918','UTF8'),'sha256'),
      'hex'
    );
    perform public.fn_lf_operation_reserve_execution_v1(
      v_exec_block,
      'GITHUB_CONTRACT_GATE_LF',
      'REPOSITORY_GOVERNED_PATHS',
      'LF_CONTRACT_PRE_EKB_BLOCK_CANARY',
      'LF-CONTRACT-PRE-EKB:BLOCK:20260918',
      v_request,
      v_exec_block,
      'cristhianlujan/claude-persona-lf-patch',
      '.github/workflows/lf-contract-check.yml',
      jsonb_build_object('mode','TRANSACTIONAL_ROLLBACK_CANARY','persistent_effect_allowed',false)
    );

    v_result:=public.lf_record_gate_checks_v1(
      v_exec_block,
      'contract_judge',
      'LF_CONTRACT_CHECK_PRE_EKB_BLOCK_CANARY',
      'COLLECT_ALL',
      '["CANARY-BLOCK-001"]'::jsonb,
      jsonb_build_array(jsonb_build_object(
        'check_id','CANARY-BLOCK-001',
        'status','BLOCKED',
        'critical',true,
        'error_class','DEPENDENCY_BLOCKED',
        'condition','deliberate PRE_EKB blocked canary dependency is available',
        'expected',jsonb_build_object('dependency','READY'),
        'actual',jsonb_build_object('dependency','BLOCKED'),
        'input_ref','.github/workflows/lf-contract-check.yml',
        'evidence_ref','migration://20260918145500#blocked-canary',
        'producer','LF_CONTRACT_PRE_EKB_CONSUMER_CANARY',
        'rc',2,
        'downstream_impact',jsonb_build_array('EKB','CI_GOVERNANCE'),
        'owner','GITHUB_CONTRACT_GATE_LF',
        'next_action','ROLLBACK_CANARY_ONLY'
      )),
      jsonb_build_object(
        'source_commit',repeat('a',40),
        'source_path','.github/workflows/lf-contract-check.yml',
        'run_id','PRE-EKB-CANARY-BLOCK',
        'job_id','migration-canary',
        'owner','GITHUB_CONTRACT_GATE_LF',
        'next_action','ROLLBACK_CANARY_ONLY',
        'environment','CANDIDATE',
        'attempt_no',1
      ),
      v_exec_block
    );

    if v_result->>'outcome'<>'RECORDED' or v_result->>'gate_result'<>'BLOCKED' then
      raise exception 'BLOCK_LF_CONTRACT_PRE_EKB_BLOCK_CANARY_RECORD:%',v_result;
    end if;

    if not exists (
      select 1
      from public.lf_eventos
      where created_by_execution_id=v_exec_block
        and origen='LF_PRE_EKB_GATE_AUTOPERSIST_V1'
        and payload->>'persistence_result'='EKB_PERSISTED'
    ) then
      raise exception 'BLOCK_LF_CONTRACT_PRE_EKB_BLOCK_CANARY_NO_RECEIPT';
    end if;

    if exists (
      select 1
      from public.lf_eventos
      where created_by_execution_id in (v_exec_fail,v_exec_recur,v_exec_block)
        and origen='LF_PRE_EKB_GATE_AUTOPERSIST_V1'
        and payload->>'persistence_result'='BLOCKED_EKB_PERSISTENCE'
    ) then
      raise exception 'BLOCK_LF_CONTRACT_PRE_EKB_CANARY_AUTOPERSIST_BLOCKED';
    end if;

    raise exception using errcode='P0E41',message='LF_CONTRACT_PRE_EKB_CANARY_ROLLBACK';
  exception when sqlstate 'P0E41' then
    null;
  end;

  if exists (
    select 1 from public.lf_operation_execution
    where execution_id in (v_exec_fail,v_exec_recur,v_exec_pass,v_exec_block)
  ) then
    raise exception 'BLOCK_LF_CONTRACT_PRE_EKB_CANARY_EXECUTION_RESIDUE';
  end if;

  if exists (
    select 1 from public.lf_operation_gate_check_results
    where execution_id in (v_exec_fail,v_exec_recur,v_exec_pass,v_exec_block)
  ) then
    raise exception 'BLOCK_LF_CONTRACT_PRE_EKB_CANARY_GATE_RESIDUE';
  end if;

  if exists (
    select 1 from public.lf_eventos
    where created_by_execution_id in (v_exec_fail,v_exec_recur,v_exec_pass,v_exec_block)
  ) then
    raise exception 'BLOCK_LF_CONTRACT_PRE_EKB_CANARY_EVENT_RESIDUE';
  end if;

  if exists (
    select 1 from transversal.error_knowledge
    where codigo like 'GATE-GITHUB-CONTRACT-GATE-LF-LF-CONTRACT-CHECK-PRE-EKB-%'
  ) then
    raise exception 'BLOCK_LF_CONTRACT_PRE_EKB_CANARY_EKB_RESIDUE';
  end if;
end
$canary$;

do $post$
begin
  if not public.lf_pre_ekb_gate_consumer_v1('GITHUB_CONTRACT_GATE_LF') then
    raise exception 'BLOCK_LF_CONTRACT_PRE_EKB_POST_READBACK';
  end if;

  if not exists (
    select 1
    from public.lf_activos
    where codigo_activo='PRE_EKB_GATE'
      and archived_at is null
      and estado_operativo='ACTIVO'
      and runtime_estado='SUPABASE_ENFORCED'
      and version='v0.2.2'
      and ultima_revision='PRE_EKB_GATE_V0_2_2_GITHUB_CONTRACT_GATE_20260918'
      and metadata #>> '{transversal_inventory,documentation,readme_ref}'=
        'sandbox/lf_contract_gate_test/pre_ekb_gate/README.md'
  ) then
    raise exception 'BLOCK_LF_CONTRACT_PRE_EKB_ASSET_POST_READBACK';
  end if;
end
$post$;

commit;
