-- R5-E infrastructure only. Installs a disabled, versioned batch runner.
-- Activation requires a separate owner-approved migration.

do $r5e_preflight$
declare
  v_revision text;
  v_contract_sha text;
  v_actual text;
  v_bad bigint;
begin
  select c.especificacion->>'contract_revision',
         programacion.fn_v09_sha256_jsonb(jsonb_build_object(
           'id',c.id,'version_id',c.version_id,'contrato_codigo',c.contrato_codigo,
           'fail_closed',c.fail_closed,'estado',c.estado,'especificacion',c.especificacion
         ))
    into v_revision,v_contract_sha
  from programacion.contratos c
  where c.version_id=19
    and c.contrato_codigo='INPUT_READINESS_CONTRACT'
    and c.estado='defined'
    and c.fail_closed;

  if v_revision is distinct from '5.13.1'
     or v_contract_sha is distinct from 'dc78d22793bfbb78a3d678b91ffdff39a3499a36d3824c65c181734e80c57516' then
    raise exception 'R5E_CONTRACT_5131_REQUIRED revision=% sha=%',
      coalesce(v_revision,'<NULL>'),coalesce(v_contract_sha,'<NULL>');
  end if;

  v_actual:=md5(pg_get_functiondef('programacion.fn_guard_input_family_assessment_update()'::regprocedure));
  if v_actual is distinct from '3992ea214300ed7a4c444667d9927f1e' then
    raise exception 'R5E_ASSESSMENT_GUARD_DRIFT:%',v_actual;
  end if;

  v_actual:=md5(pg_get_functiondef('programacion.fn_input_validator_evidence_rehydrate_v1(jsonb)'::regprocedure));
  if v_actual is distinct from '1fcbd090ac0d38945d61bc385870ab64' then
    raise exception 'R5E_REHYDRATOR_DRIFT:%',v_actual;
  end if;

  v_actual:=md5(pg_get_functiondef('programacion.fn_input_validator_storage_compaction_check_v1(jsonb,jsonb)'::regprocedure));
  if v_actual is distinct from 'b4f3ae8ceda163032d804b6a956834fd' then
    raise exception 'R5E_STORAGE_COMPACTION_CHECK_DRIFT:%',v_actual;
  end if;

  if to_regclass('programacion.input_validator_compaction_checkpoint_v1') is not null
     or to_regprocedure('programacion.fn_input_validator_compaction_batch_v1(integer)') is not null then
    raise exception 'R5E_OBJECT_ALREADY_EXISTS';
  end if;

  if exists(select 1 from cron.job where jobname='lf-r5e-validator-compaction-v1') then
    raise exception 'R5E_CRON_JOB_ALREADY_EXISTS';
  end if;

  select count(*)
    into v_bad
  from programacion.input_family_assessments a
  left join programacion.input_validator_assertion_sets_v1 s
    on s.assertion_set_sha256=programacion.fn_v09_sha256_jsonb(a.validator_evidence->'assertions')
  where a.validator_outcome<>'PENDING'
    and a.validator_evidence ? 'assertions'
    and not (a.validator_evidence ? 'assertion_set_sha256')
    and (
      s.assertion_set_sha256 is null
      or s.assertions is distinct from a.validator_evidence->'assertions'
      or programacion.fn_v09_sha256_jsonb(s.assertions) is distinct from s.assertion_set_sha256
    );

  if v_bad<>0 then
    raise exception 'R5E_BASELINE_ASSERTION_SET_MISMATCH rows=%',v_bad;
  end if;
end;
$r5e_preflight$;

create table programacion.input_validator_compaction_checkpoint_v1(
  control_id smallint primary key check(control_id=1),
  enabled boolean not null default false,
  status text not null check(status in ('DISABLED','READY','RUNNING','VERIFIED','FAILED')),
  execution_id uuid,
  baseline_contract_sha256 text,
  baseline_eligible_count bigint,
  baseline_max_assessment_id bigint,
  baseline_assertion_set_count bigint,
  last_verified_assessment_id bigint not null default 0,
  compacted_count bigint not null default 0,
  batch_no bigint not null default 0,
  last_batch_count integer not null default 0,
  last_batch_digest text,
  cumulative_digest text not null default repeat('0',64),
  final_sample_ids bigint[] not null default '{}'::bigint[],
  final_sample_verified_count integer not null default 0,
  last_error_sqlstate text,
  last_error_message text,
  started_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  check(baseline_contract_sha256 is null or baseline_contract_sha256 ~ '^[0-9a-f]{64}$'),
  check(last_batch_digest is null or last_batch_digest ~ '^[0-9a-f]{64}$'),
  check(cumulative_digest ~ '^[0-9a-f]{64}$')
);

insert into programacion.input_validator_compaction_checkpoint_v1(
  control_id,enabled,status
) values (1,false,'DISABLED');

revoke all on programacion.input_validator_compaction_checkpoint_v1 from public,anon,authenticated;
grant select,insert,update on programacion.input_validator_compaction_checkpoint_v1 to postgres;

create or replace function programacion.fn_input_validator_compaction_batch_v1(p_limit integer default 100)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','programacion','cron'
set lock_timeout to '5s'
as $function$
declare
  v_cp programacion.input_validator_compaction_checkpoint_v1%rowtype;
  v_row record;
  v_sample record;
  v_old_evidence jsonb;
  v_new_evidence jsonb;
  v_after_evidence jsonb;
  v_rehydrated jsonb;
  v_assertions jsonb;
  v_set_sha text;
  v_set_assertions jsonb;
  v_old_validator_sha text;
  v_after_validator_sha text;
  v_receipt_sha text;
  v_batch_receipts jsonb:='[]'::jsonb;
  v_batch_count integer:=0;
  v_batch_digest text;
  v_cumulative_digest text;
  v_last_id bigint;
  v_remaining bigint;
  v_baseline_count bigint;
  v_baseline_max_id bigint;
  v_baseline_sets bigint;
  v_compacted_total bigint;
  v_sample_ids bigint[]:='{}'::bigint[];
  v_sample_count integer:=0;
  v_sqlstate text;
  v_message text;
  v_unschedule_error text;
  v_contract_revision text;
  v_contract_sha text;
  v_actual text;
begin
  if p_limit is null or p_limit<1 or p_limit>500 then
    raise exception 'R5E_BATCH_LIMIT_OUT_OF_RANGE:%',coalesce(p_limit,-1);
  end if;

  if not pg_try_advisory_xact_lock(hashtextextended('R5E_INPUT_VALIDATOR_COMPACTION_V1',0)) then
    return jsonb_build_object('status','BUSY','code','R5E_ADVISORY_LOCK_BUSY');
  end if;

  select * into v_cp
  from programacion.input_validator_compaction_checkpoint_v1
  where control_id=1
  for update;

  if not found then
    raise exception 'R5E_CHECKPOINT_MISSING';
  end if;

  if not v_cp.enabled then
    return jsonb_build_object(
      'status',v_cp.status,
      'enabled',false,
      'code','R5E_DISABLED'
    );
  end if;

  begin
    select c.especificacion->>'contract_revision',
           programacion.fn_v09_sha256_jsonb(jsonb_build_object(
             'id',c.id,'version_id',c.version_id,'contrato_codigo',c.contrato_codigo,
             'fail_closed',c.fail_closed,'estado',c.estado,'especificacion',c.especificacion
           ))
      into v_contract_revision,v_contract_sha
    from programacion.contratos c
    where c.version_id=19
      and c.contrato_codigo='INPUT_READINESS_CONTRACT'
      and c.estado='defined'
      and c.fail_closed;

    if v_contract_revision is distinct from '5.13.1'
       or v_contract_sha is distinct from 'dc78d22793bfbb78a3d678b91ffdff39a3499a36d3824c65c181734e80c57516' then
      raise exception 'R5E_CONTRACT_DRIFT revision=% sha=%',
        coalesce(v_contract_revision,'<NULL>'),coalesce(v_contract_sha,'<NULL>');
    end if;

    v_actual:=md5(pg_get_functiondef('programacion.fn_guard_input_family_assessment_update()'::regprocedure));
    if v_actual is distinct from '3992ea214300ed7a4c444667d9927f1e' then
      raise exception 'R5E_ASSESSMENT_GUARD_DRIFT:%',v_actual;
    end if;

    v_actual:=md5(pg_get_functiondef('programacion.fn_input_validator_evidence_rehydrate_v1(jsonb)'::regprocedure));
    if v_actual is distinct from '1fcbd090ac0d38945d61bc385870ab64' then
      raise exception 'R5E_REHYDRATOR_DRIFT:%',v_actual;
    end if;

    v_actual:=md5(pg_get_functiondef('programacion.fn_input_validator_storage_compaction_check_v1(jsonb,jsonb)'::regprocedure));
    if v_actual is distinct from 'b4f3ae8ceda163032d804b6a956834fd' then
      raise exception 'R5E_STORAGE_COMPACTION_CHECK_DRIFT:%',v_actual;
    end if;

    if v_cp.status='READY' then
      select count(*),coalesce(max(id),0)
        into v_baseline_count,v_baseline_max_id
      from programacion.input_family_assessments
      where validator_outcome<>'PENDING'
        and validator_evidence ? 'assertions'
        and not (validator_evidence ? 'assertion_set_sha256')
        and validator_sha256 is not null;

      select count(*) into v_baseline_sets
      from programacion.input_validator_assertion_sets_v1;

      update programacion.input_validator_compaction_checkpoint_v1
      set status='RUNNING',
          execution_id=gen_random_uuid(),
          baseline_contract_sha256=v_contract_sha,
          baseline_eligible_count=v_baseline_count,
          baseline_max_assessment_id=v_baseline_max_id,
          baseline_assertion_set_count=v_baseline_sets,
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
          started_at=clock_timestamp(),
          updated_at=clock_timestamp(),
          completed_at=null
      where control_id=1
      returning * into v_cp;
    end if;

    if v_cp.status<>'RUNNING' then
      raise exception 'R5E_CHECKPOINT_NOT_RUNNABLE:%',v_cp.status;
    end if;

    if v_cp.baseline_contract_sha256 is distinct from v_contract_sha then
      raise exception 'R5E_BASELINE_CONTRACT_SHA_DRIFT expected=% actual=%',
        v_cp.baseline_contract_sha256,v_contract_sha;
    end if;

    for v_row in
      select a.id,a.validator_evidence,a.validator_sha256
      from programacion.input_family_assessments a
      where a.id>v_cp.last_verified_assessment_id
        and a.validator_outcome<>'PENDING'
        and a.validator_evidence ? 'assertions'
        and not (a.validator_evidence ? 'assertion_set_sha256')
        and a.validator_sha256 is not null
      order by a.id
      limit p_limit
      for update
    loop
      v_old_evidence:=v_row.validator_evidence;
      v_old_validator_sha:=v_row.validator_sha256;
      v_assertions:=v_old_evidence->'assertions';

      if jsonb_typeof(v_assertions)<>'array'
         or jsonb_array_length(v_assertions)=0 then
        raise exception 'R5E_INLINE_ASSERTIONS_INVALID assessment_id=%',v_row.id;
      end if;

      v_set_sha:=programacion.fn_v09_sha256_jsonb(v_assertions);

      select s.assertions into v_set_assertions
      from programacion.input_validator_assertion_sets_v1 s
      where s.assertion_set_sha256=v_set_sha;

      if not found
         or v_set_assertions is distinct from v_assertions
         or programacion.fn_v09_sha256_jsonb(v_set_assertions) is distinct from v_set_sha then
        raise exception 'R5E_ASSERTION_SET_MISMATCH assessment_id=% set_sha=%',
          v_row.id,v_set_sha;
      end if;

      v_new_evidence:=(v_old_evidence-'assertions')
        || jsonb_build_object('assertion_set_sha256',v_set_sha);

      update programacion.input_family_assessments
      set validator_evidence=v_new_evidence
      where id=v_row.id
      returning validator_evidence,validator_sha256
        into v_after_evidence,v_after_validator_sha;

      if v_after_validator_sha is distinct from v_old_validator_sha then
        raise exception 'R5E_VALIDATOR_SHA_CHANGED assessment_id=% before=% after=%',
          v_row.id,v_old_validator_sha,v_after_validator_sha;
      end if;

      if v_after_evidence ? 'assertions'
         or not (v_after_evidence ? 'assertion_set_sha256') then
        raise exception 'R5E_POST_STORAGE_SHAPE_INVALID assessment_id=%',v_row.id;
      end if;

      v_rehydrated:=programacion.fn_input_validator_evidence_rehydrate_v1(v_after_evidence);
      if v_rehydrated is distinct from v_old_evidence then
        raise exception 'R5E_REHYDRATION_MISMATCH assessment_id=%',v_row.id;
      end if;

      v_receipt_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object(
        'assessment_id',v_row.id,
        'validator_sha256',v_old_validator_sha,
        'assertion_set_sha256',v_set_sha,
        'logical_evidence_sha256',programacion.fn_v09_sha256_jsonb(v_old_evidence)
      ));

      v_batch_receipts:=v_batch_receipts||jsonb_build_array(jsonb_build_object(
        'assessment_id',v_row.id,
        'receipt_sha256',v_receipt_sha
      ));
      v_batch_count:=v_batch_count+1;
      v_last_id:=v_row.id;
    end loop;

    if v_batch_count>0 then
      v_batch_digest:=programacion.fn_v09_sha256_jsonb(v_batch_receipts);
      v_cumulative_digest:=programacion.fn_v09_sha256_jsonb(jsonb_build_object(
        'previous',v_cp.cumulative_digest,
        'batch_no',v_cp.batch_no+1,
        'batch_digest',v_batch_digest
      ));

      update programacion.input_validator_compaction_checkpoint_v1
      set last_verified_assessment_id=v_last_id,
          compacted_count=compacted_count+v_batch_count,
          batch_no=batch_no+1,
          last_batch_count=v_batch_count,
          last_batch_digest=v_batch_digest,
          cumulative_digest=v_cumulative_digest,
          updated_at=clock_timestamp()
      where control_id=1
      returning * into v_cp;
    end if;

    select count(*) into v_remaining
    from programacion.input_family_assessments
    where validator_outcome<>'PENDING'
      and validator_evidence ? 'assertions'
      and not (validator_evidence ? 'assertion_set_sha256')
      and validator_sha256 is not null;

    if v_batch_count=0 and v_remaining>0 then
      raise exception 'R5E_HIGH_WATERMARK_GAP last_verified_id=% remaining=%',
        v_cp.last_verified_assessment_id,v_remaining;
    end if;

    if v_remaining=0 then
      select compacted_count into v_compacted_total
      from programacion.input_validator_compaction_checkpoint_v1
      where control_id=1;

      if v_compacted_total is distinct from v_cp.baseline_eligible_count then
        raise exception 'R5E_FINAL_COUNT_MISMATCH baseline=% compacted=%',
          v_cp.baseline_eligible_count,v_compacted_total;
      end if;

      for v_sample in
        select a.id,a.curator_sha256,a.semantic_depth_sha256,
               a.validator_outcome,a.validator_findings,a.validator_evidence,
               a.validator_identity,a.validator_assessed_at,a.validator_sha256,
               r.source_snapshot_sha256
        from programacion.input_family_assessments a
        join programacion.input_readiness_runs r on r.id=a.run_id
        where a.id<=v_cp.baseline_max_assessment_id
          and a.validator_outcome<>'PENDING'
          and a.validator_evidence ? 'assertion_set_sha256'
          and not (a.validator_evidence ? 'assertions')
        order by random()
        limit least(50,greatest(v_cp.baseline_eligible_count,0)::integer)
      loop
        v_rehydrated:=programacion.fn_input_validator_evidence_rehydrate_v1(v_sample.validator_evidence);

        if jsonb_typeof(v_rehydrated->'assertions')<>'array'
           or jsonb_array_length(v_rehydrated->'assertions')=0 then
          raise exception 'R5E_FINAL_SAMPLE_REHYDRATE_INVALID assessment_id=%',v_sample.id;
        end if;

        v_receipt_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object(
          'curator_sha256',v_sample.curator_sha256,
          'semantic_depth_sha256',v_sample.semantic_depth_sha256,
          'source_snapshot_sha256',v_sample.source_snapshot_sha256,
          'validator_outcome',v_sample.validator_outcome,
          'validator_findings',v_sample.validator_findings,
          'validator_evidence',v_rehydrated,
          'validator_identity',v_sample.validator_identity,
          'validator_assessed_at',v_sample.validator_assessed_at
        ));

        if v_receipt_sha is distinct from v_sample.validator_sha256 then
          raise exception 'R5E_FINAL_SAMPLE_RECEIPT_HASH_MISMATCH assessment_id=% expected=% actual=%',
            v_sample.id,v_sample.validator_sha256,v_receipt_sha;
        end if;

        v_sample_ids:=array_append(v_sample_ids,v_sample.id);
        v_sample_count:=v_sample_count+1;
      end loop;

      update programacion.input_validator_compaction_checkpoint_v1
      set enabled=false,
          status='VERIFIED',
          final_sample_ids=v_sample_ids,
          final_sample_verified_count=v_sample_count,
          completed_at=clock_timestamp(),
          updated_at=clock_timestamp()
      where control_id=1;

      begin
        if not cron.unschedule('lf-r5e-validator-compaction-v1') then
          raise exception 'R5E_CRON_UNSCHEDULE_RETURNED_FALSE';
        end if;
      exception when others then
        get stacked diagnostics v_unschedule_error=message_text;
        if exists(select 1 from cron.job where jobname='lf-r5e-validator-compaction-v1') then
          perform cron.alter_job(
            (select jobid from cron.job where jobname='lf-r5e-validator-compaction-v1'),
            active=>false
          );
        end if;
        update programacion.input_validator_compaction_checkpoint_v1
        set last_error_message='R5E_COMPLETED_BUT_UNSCHEDULE_FELL_BACK_TO_INACTIVE:'
          ||coalesce(v_unschedule_error,'UNKNOWN'),
            updated_at=clock_timestamp()
        where control_id=1;
      end;

      return jsonb_build_object(
        'status','VERIFIED',
        'execution_id',(select execution_id from programacion.input_validator_compaction_checkpoint_v1 where control_id=1),
        'baseline_eligible_count',v_cp.baseline_eligible_count,
        'compacted_count',v_compacted_total,
        'remaining_inline_eligible',0,
        'sample_verified_count',v_sample_count
      );
    end if;

    return jsonb_build_object(
      'status','RUNNING',
      'execution_id',v_cp.execution_id,
      'batch_no',v_cp.batch_no,
      'batch_count',v_batch_count,
      'last_verified_assessment_id',v_cp.last_verified_assessment_id,
      'compacted_count',v_cp.compacted_count,
      'remaining_inline_eligible',v_remaining,
      'last_batch_digest',v_cp.last_batch_digest,
      'cumulative_digest',v_cp.cumulative_digest
    );

  exception when others then
    get stacked diagnostics v_sqlstate=returned_sqlstate,v_message=message_text;

    update programacion.input_validator_compaction_checkpoint_v1
    set enabled=false,
        status='FAILED',
        last_error_sqlstate=v_sqlstate,
        last_error_message=v_message,
        updated_at=clock_timestamp()
    where control_id=1;

    begin
      if not cron.unschedule('lf-r5e-validator-compaction-v1') then
        raise exception 'R5E_CRON_UNSCHEDULE_RETURNED_FALSE';
      end if;
    exception when others then
      get stacked diagnostics v_unschedule_error=message_text;
      if exists(select 1 from cron.job where jobname='lf-r5e-validator-compaction-v1') then
        perform cron.alter_job(
          (select jobid from cron.job where jobname='lf-r5e-validator-compaction-v1'),
          active=>false
        );
      end if;
      update programacion.input_validator_compaction_checkpoint_v1
      set last_error_message=coalesce(last_error_message,'')
        ||' | scheduler_cleanup='||coalesce(v_unschedule_error,'UNKNOWN'),
          updated_at=clock_timestamp()
      where control_id=1;
    end;

    return jsonb_build_object(
      'status','FAILED',
      'sqlstate',v_sqlstate,
      'error',v_message
    );
  end;
end;
$function$;

revoke all on function programacion.fn_input_validator_compaction_batch_v1(integer)
  from public,anon,authenticated;
grant execute on function programacion.fn_input_validator_compaction_batch_v1(integer)
  to postgres;

select cron.schedule(
  'lf-r5e-validator-compaction-v1',
  '* * * * *',
  'select programacion.fn_input_validator_compaction_batch_v1(100);'
);

select cron.alter_job(
  (select jobid from cron.job where jobname='lf-r5e-validator-compaction-v1'),
  active=>false
);

do $r5e_postcheck$
declare
  v_job_active boolean;
  v_cp record;
begin
  select active into v_job_active
  from cron.job
  where jobname='lf-r5e-validator-compaction-v1';

  if v_job_active is distinct from false then
    raise exception 'R5E_JOB_MUST_INSTALL_INACTIVE';
  end if;

  select * into v_cp
  from programacion.input_validator_compaction_checkpoint_v1
  where control_id=1;

  if v_cp.enabled is distinct from false
     or v_cp.status<>'DISABLED'
     or v_cp.execution_id is not null
     or v_cp.compacted_count<>0 then
    raise exception 'R5E_CHECKPOINT_MUST_INSTALL_DISABLED';
  end if;
end;
$r5e_postcheck$;
