-- R5-E first-batch calibration fallback.
-- Preserve checkpoint/baseline/progress; only reduce the recurring batch from 250 to 100.

do $pre$
declare
  v_cp programacion.input_validator_compaction_checkpoint_v1%rowtype;
  v_job record;
begin
  select * into v_cp
  from programacion.input_validator_compaction_checkpoint_v1
  where control_id=1
  for update;

  if not found
     or not v_cp.enabled
     or v_cp.status<>'RUNNING'
     or v_cp.baseline_eligible_count is null
     or v_cp.batch_no<1
     or v_cp.compacted_count<1 then
    raise exception 'R5E_FALLBACK_CHECKPOINT_NOT_RUNNING status=% enabled=% batch=% compacted=%',
      coalesce(v_cp.status,'<MISSING>'),coalesce(v_cp.enabled,false),
      coalesce(v_cp.batch_no,-1),coalesce(v_cp.compacted_count,-1);
  end if;

  select jobid,active,command into v_job
  from cron.job
  where jobname='lf-r5e-validator-compaction-v1';

  if not found or v_job.active is distinct from true then
    raise exception 'R5E_FALLBACK_JOB_NOT_ACTIVE';
  end if;

  if v_job.command is distinct from
     'select programacion.fn_input_validator_compaction_batch_v1(250);' then
    raise exception 'R5E_FALLBACK_JOB_COMMAND_DRIFT:%',coalesce(v_job.command,'<NULL>');
  end if;
end;
$pre$;

select cron.alter_job(
  (select jobid from cron.job where jobname='lf-r5e-validator-compaction-v1'),
  command=>'select programacion.fn_input_validator_compaction_batch_v1(100);',
  active=>true
);

do $post$
declare
  v_job record;
  v_cp record;
begin
  select active,command into v_job
  from cron.job
  where jobname='lf-r5e-validator-compaction-v1';

  if v_job.active is distinct from true
     or v_job.command is distinct from
        'select programacion.fn_input_validator_compaction_batch_v1(100);' then
    raise exception 'R5E_FALLBACK_POSTCHECK_JOB_FAILED';
  end if;

  select enabled,status,baseline_eligible_count,compacted_count,batch_no
    into v_cp
  from programacion.input_validator_compaction_checkpoint_v1
  where control_id=1;

  if v_cp.enabled is distinct from true
     or v_cp.status<>'RUNNING'
     or v_cp.baseline_eligible_count is null
     or v_cp.compacted_count<1
     or v_cp.batch_no<1 then
    raise exception 'R5E_FALLBACK_POSTCHECK_CHECKPOINT_CHANGED';
  end if;
end;
$post$;
