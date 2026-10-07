-- R5-E historical Validator evidence compaction activation.
-- Owner-approved activation only. No DELETE, trigger disable, VACUUM or REINDEX.

do $pre$
declare
  v_job record;
  v_cp programacion.input_validator_compaction_checkpoint_v1%rowtype;
begin
  if to_regprocedure('programacion.fn_input_validator_compaction_batch_v1(integer)') is null then
    raise exception 'R5E_ACTIVATION_RUNNER_MISSING';
  end if;

  select * into v_cp
  from programacion.input_validator_compaction_checkpoint_v1
  where control_id=1
  for update;

  if not found
     or v_cp.enabled
     or v_cp.status<>'DISABLED'
     or v_cp.execution_id is not null
     or v_cp.compacted_count<>0
     or v_cp.batch_no<>0 then
    raise exception 'R5E_ACTIVATION_CHECKPOINT_NOT_CLEAN status=% enabled=% compacted=% batch=%',
      coalesce(v_cp.status,'<MISSING>'),coalesce(v_cp.enabled,false),
      coalesce(v_cp.compacted_count,-1),coalesce(v_cp.batch_no,-1);
  end if;

  select jobid,active,command into v_job
  from cron.job
  where jobname='lf-r5e-validator-compaction-v1';

  if not found or v_job.active then
    raise exception 'R5E_ACTIVATION_JOB_NOT_INACTIVE';
  end if;

  if v_job.command is distinct from
     'select programacion.fn_input_validator_compaction_batch_v1(100);' then
    raise exception 'R5E_ACTIVATION_JOB_COMMAND_DRIFT:%',coalesce(v_job.command,'<NULL>');
  end if;
end;
$pre$;

update programacion.input_validator_compaction_checkpoint_v1
set enabled=true,
    status='READY',
    execution_id=null,
    baseline_contract_sha256=null,
    baseline_eligible_count=null,
    baseline_max_assessment_id=null,
    baseline_assertion_set_count=null,
    last_verified_assessment_id=0,
    compacted_count=0,
    batch_no=0,
    last_batch_count=0,
    last_batch_digest=null,
    cumulative_digest=repeat('0',64),
    final_sample_ids='{}'::bigint[],
    final_sample_verified_count=0,
    last_error_sqlstate=null,
    last_error_message=null,
    started_at=null,
    completed_at=null,
    updated_at=clock_timestamp()
where control_id=1;

select cron.alter_job(
  (select jobid from cron.job where jobname='lf-r5e-validator-compaction-v1'),
  schedule=>' * * * * *',
  command=>'select programacion.fn_input_validator_compaction_batch_v1(250);',
  active=>true
);

do $post$
declare
  v_cp record;
  v_job record;
begin
  select enabled,status,compacted_count,batch_no
    into v_cp
  from programacion.input_validator_compaction_checkpoint_v1
  where control_id=1;

  if v_cp.enabled is distinct from true
     or v_cp.status<>'READY'
     or v_cp.compacted_count<>0
     or v_cp.batch_no<>0 then
    raise exception 'R5E_ACTIVATION_POSTCHECK_CHECKPOINT_FAILED';
  end if;

  select active,schedule,command into v_job
  from cron.job where jobname='lf-r5e-validator-compaction-v1';

  if v_job.active is distinct from true
     or btrim(v_job.schedule)<>'* * * * *'
     or v_job.command is distinct from
        'select programacion.fn_input_validator_compaction_batch_v1(250);' then
    raise exception 'R5E_ACTIVATION_POSTCHECK_JOB_FAILED active=% schedule=% command=%',
      v_job.active,v_job.schedule,v_job.command;
  end if;
end;
$post$;
