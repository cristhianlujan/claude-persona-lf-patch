-- S30 / PRE_EKB_GATE v0.2.1 canonical code normalization
-- Repairs a post-apply finding from PR #888 without editing the applied source.
-- Centralizes code construction so lowercase/mixed-case operation/step/gate/check/error identifiers
-- are normalized before the A-Z0-9 allowlist is applied.

do $pre$
declare
  v_execution_id constant text := 'EXEC-S30-PRE-EKB-CODE-NORMALIZATION-20260917-001';
begin
  if not exists (
    select 1 from public.lf_operation_execution
    where execution_id=v_execution_id
      and operation_code='ACTUALIZACION_DB_LF'
      and target_type='MIGRATION'
      and target_code='PRE_EKB_CANONICAL_CODE_NORMALIZATION_V1'
      and target_repo='cristhianlujan/claude-persona-lf-patch'
      and target_path='supabase/migrations/20260917235000_s30_pre_ekb_canonical_code_normalization_v1.sql'
      and status='IN_PROGRESS'
  ) then
    raise exception 'BLOCK_PRE_EKB_CODE_NORMALIZATION_EXECUTION_BINDING';
  end if;

  if to_regprocedure('public.lf_pre_ekb_gate_check_dispatch_v1(bigint)') is null
     or to_regprocedure('public.lf_pre_ekb_step_failure_dispatch_v1(text,text)') is null
     or to_regprocedure('public.lf_pre_ekb_exception_dispatch_v1(text,text,text,text,text,text,text,jsonb)') is null then
    raise exception 'BLOCK_PRE_EKB_CODE_NORMALIZATION_BASE_FUNCTIONS_MISSING';
  end if;

  if not exists (
    select 1 from public.lf_activos
    where codigo_activo='PRE_EKB_GATE'
      and version='v0.2'
      and estado_operativo='ACTIVO'
      and archived_at is null
  ) then
    raise exception 'BLOCK_PRE_EKB_CODE_NORMALIZATION_BASE_ASSET_NOT_CURRENT';
  end if;
end
$pre$;

create or replace function public.lf_pre_ekb_canonical_code_v1(
  p_parts text[]
)
returns text
language plpgsql
immutable
security invoker
set search_path = pg_catalog, public
as $function$
declare
  v_raw text;
  v_code text;
begin
  if p_parts is null or cardinality(p_parts)=0
     or exists(select 1 from unnest(p_parts) x where nullif(btrim(coalesce(x,'')),'') is null) then
    raise exception 'PRE_EKB_CANONICAL_CODE_PARTS_INVALID';
  end if;

  v_raw:=array_to_string(p_parts,'-');
  v_code:=regexp_replace(upper(v_raw),'[^A-Z0-9]+','-','g');
  v_code:=trim(both '-' from v_code);

  if v_code !~ '^[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+$' then
    raise exception 'PRE_EKB_CANONICAL_CODE_INVALID:%',v_code;
  end if;

  return v_code;
end;
$function$;

create or replace function public.lf_pre_ekb_gate_check_dispatch_v1(
  p_gate_check_result_id bigint
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public, lf_ops, extensions
as $function$
declare
  v_row public.lf_operation_gate_check_results%rowtype;
  v_exec public.lf_operation_execution%rowtype;
  v_catalog lf_ops.errores_catalogo%rowtype;
  v_code text;
  v_error_token text;
  v_severity text;
  v_fingerprint text;
  v_finding jsonb;
  v_receipt jsonb;
  v_gate_event_id bigint;
begin
  select * into v_row
  from public.lf_operation_gate_check_results
  where id=p_gate_check_result_id;

  if not found then
    raise exception 'PRE_EKB_GATE_CHECK_RESULT_NOT_FOUND:%',p_gate_check_result_id;
  end if;

  if v_row.check_status not in ('FAIL','BLOCKED') then
    return jsonb_build_object('result','NOT_REQUIRED','gate_check_result_id',v_row.id);
  end if;

  select * into v_exec
  from public.lf_operation_execution
  where execution_id=v_row.execution_id;

  if not found or not public.lf_pre_ekb_gate_consumer_v1(v_exec.operation_code) then
    return jsonb_build_object('result','NOT_BOUND','gate_check_result_id',v_row.id);
  end if;

  select * into v_catalog
  from lf_ops.errores_catalogo
  where error_id=v_row.error_id;

  v_error_token:=coalesce(nullif(v_row.error_class,''),v_row.check_status);
  v_code:=public.lf_pre_ekb_canonical_code_v1(
    array['GATE',v_exec.operation_code,v_row.gate_id,v_row.check_id,v_error_token]
  );

  v_severity:=initcap(lower(coalesce(nullif(v_catalog.severity,''),'High')));
  if v_severity not in ('Low','Medium','High','Critical') then
    v_severity:='High';
  end if;

  v_fingerprint:=encode(
    extensions.digest(
      convert_to(
        v_row.execution_id||'|'||v_row.step_id||'|'||v_row.gate_id||'|'||
        v_row.attempt_no::text||'|'||v_row.check_id||'|'||coalesce(v_row.error_class,'')||'|'||
        v_row.source_commit||'|'||v_row.expected::text||'|'||v_row.actual::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  v_finding:=jsonb_build_object(
    'codigo',v_code,
    'categoria','OPERATION_GATE_FAILURE',
    'titulo',format('%s / %s / %s: %s',v_exec.operation_code,v_row.gate_id,v_row.check_id,coalesce(v_row.error_class,v_row.check_status)),
    'descripcion',format(
      'Gate check %s failed at operation=%s step=%s gate=%s attempt=%s. condition=%s; expected=%s; actual=%s; downstream_impact=%s; owner=%s; next_action=%s.',
      v_row.check_id,v_exec.operation_code,v_row.step_id,v_row.gate_id,v_row.attempt_no,
      v_row.check_condition,v_row.expected::text,v_row.actual::text,v_row.downstream_impact::text,v_row.owner,v_row.next_action
    ),
    'causa_raiz',format(
      'Observed condition mismatch only; no deeper cause is invented. error_class=%s; condition=%s; expected=%s; actual=%s.',
      coalesce(v_row.error_class,'UNCLASSIFIED'),v_row.check_condition,v_row.expected::text,v_row.actual::text
    ),
    'patron',coalesce(v_row.error_class,v_row.check_status),
    'prevencion',format(
      'Do not allow repair/resume/next-gate handling for %s/%s until this diagnostic has a governed EKB receipt. Correct the condition using source_commit=%s and source_path=%s as the exact repair baseline.',
      v_row.gate_id,v_row.check_id,v_row.source_commit,v_row.source_path
    ),
    'validacion',format(
      'Rerun operation=%s step=%s gate=%s check=%s from resume_checkpoint=%s. Require PASS with current/exact source revision, expected/actual reconciliation, durable evidence readback and no missing EKB receipt if the failure recurs.',
      v_exec.operation_code,v_row.step_id,v_row.gate_id,v_row.check_id,v_row.step_id
    ),
    'severidad',v_severity,
    'lifecycle_phase',v_row.step_id,
    'consumer_role',jsonb_build_array(v_exec.operation_code,coalesce(nullif(v_row.owner,''),'UNASSIGNED_OWNER')),
    'root_cause_family','UNCLASSIFIED_WITH_REASON',
    'detectability','LOUD_EARLY',
    'source_context',format(
      'LF_GATE_ERROR_V1 operation=%s step=%s gate=%s attempt=%s check=%s owner=%s next_action=%s resume_checkpoint=%s rerun_scope=%s/%s',
      v_exec.operation_code,v_row.step_id,v_row.gate_id,v_row.attempt_no,v_row.check_id,v_row.owner,v_row.next_action,
      v_row.step_id,v_row.gate_id,v_row.check_id
    ),
    'source_ref',format(
      'github://cristhianlujan/claude-persona-lf-patch@%s/%s|%s|supabase://public/lf_operation_gate_check_results/%s',
      v_row.source_commit,v_row.source_path,v_row.evidence_ref,v_row.id
    ),
    'evidencia',jsonb_build_object(
      'contract','LF_GATE_ERROR_V1',
      'gate_check_result_id',v_row.id,
      'execution_id',v_row.execution_id,
      'operation_code',v_row.operation_code,
      'step_id',v_row.step_id,
      'gate_id',v_row.gate_id,
      'attempt_no',v_row.attempt_no,
      'check_id',v_row.check_id,
      'check_status',v_row.check_status,
      'error_id',v_row.error_id,
      'error_occurrence_id',v_row.error_occurrence_id,
      'error_class',v_row.error_class,
      'condition',v_row.check_condition,
      'expected',v_row.expected,
      'actual',v_row.actual,
      'evidence_ref',v_row.evidence_ref,
      'producer',v_row.producer,
      'run_id',v_row.run_id,
      'job_id',v_row.job_id,
      'source_commit',v_row.source_commit,
      'source_path',v_row.source_path,
      'trace_id',v_row.trace_id,
      'parent_trace_id',v_row.parent_trace_id,
      'rc',v_row.rc,
      'downstream_impact',v_row.downstream_impact,
      'owner',v_row.owner,
      'next_action',v_row.next_action,
      'resume_checkpoint',v_row.step_id,
      'rerun_scope',v_row.gate_id||'/'||v_row.check_id
    )::text
  );

  v_receipt:=public.lf_pre_ekb_child_dispatch_v1(v_row.execution_id,v_finding,v_fingerprint);

  select id into v_gate_event_id
  from public.lf_eventos
  where evento_tipo='REMEDIACION_GOBERNANZA'
    and created_by_execution_id=v_row.execution_id
    and origen='LF_PRE_EKB_GATE_AUTOPERSIST_V1'
    and payload->>'persistence_result'='EKB_PERSISTED'
    and payload->>'gate_check_result_id'=v_row.id::text
  order by id desc
  limit 1;

  if v_gate_event_id is null then
    insert into public.lf_eventos(
      evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,origen,created_by_execution_id
    ) values (
      'REMEDIACION_GOBERNANZA','LF_PRE_EKB_GATE_CHECK',v_code,
      'LF_GATE_ERROR_V1 check persisted to EKB with exact diagnostic binding',
      case when v_severity='Critical' then 'CRITICAL' when v_severity='High' then 'WARN' else 'INFO' end,
      jsonb_build_object(
        'evidence_schema_version','operational-event/v2',
        'execution_id',v_row.execution_id,
        'producer','LF_PRE_EKB_GATE_AUTOPERSIST_V1',
        'purpose','Bind one LF_GATE_ERROR_V1 non-pass check to its governed EKB writer receipt before repair or resume',
        'occurred_at',clock_timestamp(),
        'acceptance_declared',false,
        'persistence_result','EKB_PERSISTED',
        'gate_check_result_id',v_row.id,
        'operation_code',v_row.operation_code,
        'step_id',v_row.step_id,
        'gate_id',v_row.gate_id,
        'attempt_no',v_row.attempt_no,
        'check_id',v_row.check_id,
        'error_class',v_row.error_class,
        'finding_fingerprint',v_fingerprint,
        'child_execution_id',v_receipt->>'child_execution_id',
        'writer_receipt',v_receipt->'writer_receipt',
        'diagnostic_ref','supabase://public/lf_operation_gate_check_results/'||v_row.id
      ),
      'LF_PRE_EKB_GATE_AUTOPERSIST_V1',
      v_row.execution_id
    )
    returning id into v_gate_event_id;
  end if;

  return v_receipt
    || jsonb_build_object(
      'source_kind','LF_GATE_ERROR_V1',
      'gate_check_result_id',v_row.id,
      'gate_event_id',v_gate_event_id,
      'gate_id',v_row.gate_id,
      'check_id',v_row.check_id
    );
end;
$function$;

create or replace function public.lf_pre_ekb_step_failure_dispatch_v1(
  p_execution_id text,
  p_step_id text
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public, extensions
as $function$
declare
  v_exec public.lf_operation_execution%rowtype;
  v_step public.lf_operation_execution_steps%rowtype;
  v_block_code text;
  v_code text;
  v_evidence_sha text;
  v_fingerprint text;
  v_finding jsonb;
begin
  select * into v_exec
  from public.lf_operation_execution
  where execution_id=p_execution_id;

  select * into v_step
  from public.lf_operation_execution_steps
  where execution_id=p_execution_id and step_id=p_step_id;

  if v_exec.execution_id is null or v_step.execution_id is null then
    raise exception 'PRE_EKB_STEP_FAILURE_SOURCE_NOT_FOUND';
  end if;

  if not public.lf_pre_ekb_gate_consumer_v1(v_exec.operation_code) then
    return jsonb_build_object('result','NOT_BOUND');
  end if;

  if not (
    upper(v_step.status) like 'BLOCK%'
    or upper(v_step.status) like 'FAIL%'
    or upper(v_step.status) like 'RETURN%'
  ) then
    return jsonb_build_object('result','NOT_REQUIRED','status',v_step.status);
  end if;

  v_block_code:=coalesce(
    nullif(v_step.evidence_payload->>'blocked_reason_code',''),
    nullif(v_step.evidence_payload->'blocking_codes'->>0,''),
    nullif(v_step.evidence_payload->'blocking_findings'->>0,''),
    nullif(v_step.status,'')
  );

  if v_block_code is null or btrim(v_block_code)='' then
    raise exception 'PRE_EKB_STEP_FAILURE_DIAGNOSTIC_INCOMPLETE';
  end if;

  v_code:=public.lf_pre_ekb_canonical_code_v1(
    array['STEP',v_exec.operation_code,v_step.step_id,v_block_code]
  );

  v_evidence_sha:=encode(
    extensions.digest(convert_to(coalesce(v_step.evidence_payload,'{}'::jsonb)::text,'UTF8'),'sha256'),
    'hex'
  );
  v_fingerprint:=encode(
    extensions.digest(
      convert_to(v_exec.execution_id||'|'||v_step.step_id||'|'||v_step.status||'|'||v_block_code||'|'||v_evidence_sha,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  v_finding:=jsonb_build_object(
    'codigo',v_code,
    'categoria','OPERATION_STEP_FAILURE',
    'titulo',format('%s / step %s: %s',v_exec.operation_code,v_step.step_id,v_block_code),
    'descripcion',format(
      'Governed step returned non-pass status=%s at operation=%s step=%s. blocking_code=%s; evidence_ref=%s; evidence_sha256=%s.',
      v_step.status,v_exec.operation_code,v_step.step_id,v_block_code,coalesce(v_step.evidence_ref,'UNSPECIFIED'),v_evidence_sha
    ),
    'causa_raiz',format(
      'Observed blocking condition only; no deeper cause is invented. blocking_code=%s; step_status=%s; evidence_payload=%s.',
      v_block_code,v_step.status,coalesce(v_step.evidence_payload,'{}'::jsonb)::text
    ),
    'patron',v_block_code,
    'prevencion',format(
      'Persist the non-pass step through PRE_EKB_GATE before a clean retry. Repair the exact blocking_code=%s using the same execution/target/source evidence rather than bypassing the step.',
      v_block_code
    ),
    'validacion',format(
      'Retry operation=%s step=%s only after an EKB receipt exists for evidence_sha256=%s. Require the canonical step recorder to return its clean result and preserve attempt history/readback.',
      v_exec.operation_code,v_step.step_id,v_evidence_sha
    ),
    'severidad','High',
    'lifecycle_phase',v_step.step_id,
    'consumer_role',jsonb_build_array(v_exec.operation_code,'OPERATION_OWNER'),
    'root_cause_family','UNCLASSIFIED_WITH_REASON',
    'detectability','LOUD_EARLY',
    'source_context',format(
      'operation_step_failure operation=%s step=%s status=%s blocking_code=%s resume_checkpoint=%s',
      v_exec.operation_code,v_step.step_id,v_step.status,v_block_code,v_step.step_id
    ),
    'source_ref',coalesce(v_step.evidence_ref,'supabase://public/lf_operation_execution_steps/'||v_exec.execution_id||'/'||v_step.step_id),
    'evidencia',jsonb_build_object(
      'execution_id',v_exec.execution_id,
      'operation_code',v_exec.operation_code,
      'target_type',v_exec.target_type,
      'target_code',v_exec.target_code,
      'step_id',v_step.step_id,
      'step_order',v_step.step_order,
      'status',v_step.status,
      'blocking_code',v_block_code,
      'evidence_ref',v_step.evidence_ref,
      'evidence_sha256',v_evidence_sha,
      'evidence_payload',v_step.evidence_payload,
      'resume_checkpoint',v_step.step_id,
      'rerun_scope',v_step.step_id
    )::text
  );

  return public.lf_pre_ekb_child_dispatch_v1(v_exec.execution_id,v_finding,v_fingerprint)
    || jsonb_build_object(
      'source_kind','OPERATION_STEP_FAILURE',
      'step_id',v_step.step_id,
      'source_evidence_sha256',v_evidence_sha
    );
end;
$function$;

create or replace function public.lf_pre_ekb_exception_dispatch_v1(
  p_execution_id text,
  p_step_id text,
  p_error_code text,
  p_error_message text,
  p_source_ref text,
  p_owner text,
  p_next_action text,
  p_evidence jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public, extensions
as $function$
declare
  v_exec public.lf_operation_execution%rowtype;
  v_token text;
  v_code text;
  v_fingerprint text;
  v_finding jsonb;
begin
  select * into v_exec
  from public.lf_operation_execution
  where execution_id=p_execution_id;

  if not found or not public.lf_pre_ekb_gate_consumer_v1(v_exec.operation_code) then
    raise exception 'PRE_EKB_EXCEPTION_PARENT_NOT_BOUND';
  end if;

  if btrim(coalesce(p_step_id,''))=''
     or btrim(coalesce(p_error_code,''))=''
     or btrim(coalesce(p_error_message,''))=''
     or btrim(coalesce(p_source_ref,''))=''
     or btrim(coalesce(p_owner,''))=''
     or btrim(coalesce(p_next_action,''))='' then
    raise exception 'PRE_EKB_EXCEPTION_DIAGNOSTIC_INCOMPLETE';
  end if;

  v_token:=p_error_code;
  v_code:=public.lf_pre_ekb_canonical_code_v1(
    array['EXCEPTION',v_exec.operation_code,p_step_id,v_token]
  );

  v_fingerprint:=encode(
    extensions.digest(
      convert_to(
        p_execution_id||'|'||p_step_id||'|'||p_error_code||'|'||p_error_message||'|'||p_source_ref||'|'||coalesce(p_evidence,'{}'::jsonb)::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  v_finding:=jsonb_build_object(
    'codigo',v_code,
    'categoria','OPERATION_EXCEPTION',
    'titulo',format('%s / %s exception: %s',v_exec.operation_code,p_step_id,p_error_code),
    'descripcion',format(
      'Caught governed exception at operation=%s step=%s error_code=%s. message=%s; owner=%s; next_action=%s.',
      v_exec.operation_code,p_step_id,p_error_code,p_error_message,p_owner,p_next_action
    ),
    'causa_raiz',format(
      'Caught exception evidence only; deeper cause is not invented. error_code=%s; message=%s; evidence=%s.',
      p_error_code,p_error_message,coalesce(p_evidence,'{}'::jsonb)::text
    ),
    'patron',p_error_code,
    'prevencion','Catch the exception outside the failed mutation subtransaction, persist this governed diagnostic, and block repair/resume until the EKB receipt is readable.',
    'validacion',format(
      'Reproduce and rerun operation=%s step=%s after repair. Require no exception, exact source readback, and a governed recurrence receipt if the same exception is observed again.',
      v_exec.operation_code,p_step_id
    ),
    'severidad','High',
    'lifecycle_phase',p_step_id,
    'consumer_role',jsonb_build_array(v_exec.operation_code,p_owner),
    'root_cause_family','UNCLASSIFIED_WITH_REASON',
    'detectability','LOUD_EARLY',
    'source_context',format(
      'caught_exception operation=%s step=%s owner=%s next_action=%s resume_checkpoint=%s',
      v_exec.operation_code,p_step_id,p_owner,p_next_action,p_step_id
    ),
    'source_ref',p_source_ref,
    'evidencia',jsonb_build_object(
      'execution_id',p_execution_id,
      'operation_code',v_exec.operation_code,
      'target_type',v_exec.target_type,
      'target_code',v_exec.target_code,
      'step_id',p_step_id,
      'error_code',p_error_code,
      'error_message',p_error_message,
      'owner',p_owner,
      'next_action',p_next_action,
      'evidence',coalesce(p_evidence,'{}'::jsonb),
      'resume_checkpoint',p_step_id
    )::text
  );

  return public.lf_pre_ekb_child_dispatch_v1(p_execution_id,v_finding,v_fingerprint)
    || jsonb_build_object('source_kind','OPERATION_EXCEPTION','step_id',p_step_id);
end;
$function$;



update public.lf_activos
set version='v0.2.1',
    ultima_revision='PRE_EKB_GATE_V0_2_1_CANONICAL_CODE_NORMALIZATION_20260917',
    raw_payload=coalesce(raw_payload,'{}'::jsonb)||jsonb_build_object(
      'canonical_code_builder','public.lf_pre_ekb_canonical_code_v1',
      'canonical_code_normalization','UPPERCASE_WHOLE_INPUT_BEFORE_ALLOWLIST',
      'repair_ekb_code','PRE-EKB-CANONICAL-CODE-CASE-NORMALIZATION-001'
    ),
    updated_by_execution_id='EXEC-S30-PRE-EKB-CODE-NORMALIZATION-20260917-001',
    updated_at=clock_timestamp()
where codigo_activo='PRE_EKB_GATE'
  and archived_at is null;

do $post$
declare
  v_execution_id constant text := 'EXEC-S30-PRE-EKB-CODE-NORMALIZATION-20260917-001';
  v_auth jsonb;
begin
  if public.lf_pre_ekb_canonical_code_v1(
       array['EXCEPTION','ACTUALIZACION_DB_LF','preflight','live-controlled-exception']
     ) <> 'EXCEPTION-ACTUALIZACION-DB-LF-PREFLIGHT-LIVE-CONTROLLED-EXCEPTION' then
    raise exception 'BLOCK_PRE_EKB_CODE_NORMALIZATION_EXCEPTION_SELFTEST';
  end if;

  if public.lf_pre_ekb_canonical_code_v1(
       array['GATE','ACTUALIZACION_DB_LF','mixedGate','check_lower','Some_Error']
     ) <> 'GATE-ACTUALIZACION-DB-LF-MIXEDGATE-CHECK-LOWER-SOME-ERROR' then
    raise exception 'BLOCK_PRE_EKB_CODE_NORMALIZATION_GATE_SELFTEST';
  end if;

  if public.lf_pre_ekb_canonical_code_v1(
       array['STEP','ACTUALIZACION_DB_LF','verify','router_authority_stale']
     ) <> 'STEP-ACTUALIZACION-DB-LF-VERIFY-ROUTER-AUTHORITY-STALE' then
    raise exception 'BLOCK_PRE_EKB_CODE_NORMALIZATION_STEP_SELFTEST';
  end if;

  if public.lf_pre_ekb_canonical_code_v1(
       array['EXCEPTION','ACTUALIZACION_DB_LF','preflight','same-error']
     ) =
     public.lf_pre_ekb_canonical_code_v1(
       array['EXCEPTION','ACTUALIZACION_DB_LF','verify','same-error']
     ) then
    raise exception 'BLOCK_PRE_EKB_CODE_NORMALIZATION_STEP_COLLISION';
  end if;

  if not exists (
    select 1 from public.lf_activos
    where codigo_activo='PRE_EKB_GATE'
      and version='v0.2.1'
      and estado_operativo='ACTIVO'
      and archived_at is null
  ) then
    raise exception 'BLOCK_PRE_EKB_CODE_NORMALIZATION_ASSET_READBACK';
  end if;

  v_auth:=public.lf_router_downstream_authority_validate_v1(v_execution_id);
  if coalesce((v_auth->>'valid')::boolean,false) is not true then
    raise exception 'BLOCK_PRE_EKB_CODE_NORMALIZATION_ROUTER_REGRESSION:%',coalesce(v_auth->>'code','UNKNOWN');
  end if;
end
$post$;

revoke execute on function public.lf_pre_ekb_canonical_code_v1(text[]) from public,anon,authenticated;
grant execute on function public.lf_pre_ekb_canonical_code_v1(text[]) to service_role;

comment on function public.lf_pre_ekb_canonical_code_v1(text[]) is
'PRE_EKB_GATE deterministic canonical code builder. Uppercases the full joined identity before replacing non A-Z0-9 runs, preserving lowercase/mixed-case segments without collisions.';
