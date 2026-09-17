-- S30 / PRE_EKB_GATE v0.2
-- Transversal failure-to-EKB autopersistence; first enforced consumer: ACTUALIZACION_DB_LF.
-- Reuses LF_GATE_ERROR_V1, EJECUCION_SKILL_LF -> ACT-0057 -> ESCRITURA_BASE_CONOCIMIENTO_LF,
-- EVENT_CONTRACT_GOVERNANCE and EXECUTION_EVENT_READBACK_INDEX. No parallel error/EKB store.
-- Source-first only. Exact-version migration; do not use Supabase apply_migration.

do $pre$
declare
  v_execution_id constant text := 'EXEC-S30-PRE-EKB-DB-AUTOPERSIST-20260917-001';
begin
  if not exists (
    select 1
    from public.lf_operation_execution
    where execution_id=v_execution_id
      and operation_code='ACTUALIZACION_DB_LF'
      and target_type='MIGRATION'
      and target_code='PRE_EKB_GATE_DB_AUTOPERSIST_V1'
      and target_repo='cristhianlujan/claude-persona-lf-patch'
      and target_path='supabase/migrations/20260917232500_s30_pre_ekb_gate_db_autopersist_v1.sql'
      and status='IN_PROGRESS'
  ) then
    raise exception 'BLOCK_PRE_EKB_AUTOPERSIST_EXECUTION_BINDING';
  end if;

  if to_regprocedure('public.lf_record_gate_checks_v1(text,text,text,text,jsonb,jsonb,jsonb,text)') is null
     or to_regprocedure('public.lf_gate_check_diagnostic_v1(text,text,text,integer)') is null
     or to_regprocedure('public.lf_write_pipeline_ekb_v1(text,jsonb,text)') is null
     or to_regprocedure('public.fn_lf_operation_reserve_execution_v1(text,text,text,text,text,text,text,text,text,jsonb)') is null
     or to_regprocedure('public.lf_router_resolve_v1(text,text,text,text,text)') is null then
    raise exception 'BLOCK_PRE_EKB_AUTOPERSIST_DEPENDENCY_MISSING';
  end if;

  if not exists (
    select 1 from public.lf_activos
    where codigo_activo='PRE_EKB_GATE'
      and archived_at is null
  ) then
    raise exception 'BLOCK_PRE_EKB_GATE_ASSET_MISSING';
  end if;

  if not exists (
    select 1 from public.lf_activos
    where codigo_activo='ACT-0057'
      and nombre_canonico='SKILL_ESCRITURA_BASE_CONOCIMIENTO_LF'
      and tipo_activo='SKILL'
      and estado_operativo='APROBADO'
      and runtime_estado='APROBADO_PRODUCCION_CONTROLADA'
      and archived_at is null
  ) then
    raise exception 'BLOCK_PRE_EKB_TARGET_SKILL_NOT_CURRENT';
  end if;

  if not exists (
    select 1 from public.lf_router_action_registry
    where asset_type='SKILL'
      and action_code='SKILL_EXECUTION'
      and operation_code='EJECUCION_SKILL_LF'
      and operation_resolution='STATIC'
      and requires_existing_target
      and not write_allowed
      and status='ACTIVE'
  ) then
    raise exception 'BLOCK_PRE_EKB_SKILL_EXECUTION_ROUTE_MISSING';
  end if;

  if not exists (
    select 1 from public.lf_operation_contracts
    where operation_code='ESCRITURA_BASE_CONOCIMIENTO_LF'
      and contract_code='CONTRACT-PRE-EKB-GATE-LF-v0.1'
      and status='ACTIVE_ENFORCEMENT'
      and coalesce((required_before_write->>'pre_ekb_gate_required')::boolean,false)
  ) then
    raise exception 'BLOCK_PRE_EKB_WRITER_AUTHORITY_MISSING';
  end if;

  if not exists (
    select 1 from private.lf_event_type_contracts_v2
    where event_type='REMEDIACION_GOBERNANZA'
      and active
      and contract_mode='OPERATIONAL'
      and 'operational-event/v2'=any(allowed_evidence_schemas)
  ) then
    raise exception 'BLOCK_PRE_EKB_EVENT_CONTRACT_MISSING';
  end if;
end
$pre$;

create or replace function public.lf_pre_ekb_gate_consumer_v1(
  p_operation_code text
)
returns boolean
language sql
stable
security invoker
set search_path = pg_catalog, public
as $function$
  select coalesce(
    (
      select case
        when jsonb_typeof(a.metadata #> '{transversal_inventory,consumers_known}')='array'
          then (a.metadata #> '{transversal_inventory,consumers_known}') ? p_operation_code
        when jsonb_typeof(a.metadata #> '{transversal_inventory,consumers_known}')='string'
          then (a.metadata #>> '{transversal_inventory,consumers_known}')=p_operation_code
        else false
      end
      from public.lf_activos a
      where a.codigo_activo='PRE_EKB_GATE'
        and a.archived_at is null
        and a.estado_operativo='ACTIVO'
      limit 1
    ),
    false
  );
$function$;

create or replace function public.lf_pre_ekb_child_dispatch_v1(
  p_parent_execution_id text,
  p_finding jsonb,
  p_finding_fingerprint text
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public, extensions
as $function$
declare
  v_parent public.lf_operation_execution%rowtype;
  v_child public.lf_operation_execution%rowtype;
  v_router jsonb;
  v_reserve jsonb;
  v_writer jsonb;
  v_prior public.lf_eventos%rowtype;
  v_child_seed text;
  v_child_execution_id text;
  v_idem text;
  v_request_sha text;
  v_payload_sha text;
  v_code text;
  v_enriched jsonb;
  v_parent_event_id bigint;
begin
  select * into v_parent
  from public.lf_operation_execution
  where execution_id=p_parent_execution_id;

  if not found
     or not public.lf_pre_ekb_gate_consumer_v1(v_parent.operation_code)
     or v_parent.status not in ('IN_PROGRESS','BLOCKED','FAILED') then
    raise exception 'PRE_EKB_PARENT_EXECUTION_NOT_AUTHORIZED:%',p_parent_execution_id;
  end if;

  if p_finding is null or jsonb_typeof(p_finding)<>'object' then
    raise exception 'PRE_EKB_FINDING_NOT_OBJECT';
  end if;
  if coalesce(p_finding_fingerprint,'') !~ '^[0-9a-f]{64}$' then
    raise exception 'PRE_EKB_FINDING_FINGERPRINT_INVALID';
  end if;

  v_code:=upper(btrim(coalesce(p_finding->>'codigo','')));
  if v_code='' or v_code !~ '^[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+$' then
    raise exception 'PRE_EKB_FINDING_CODE_INVALID:%',v_code;
  end if;

  v_router:=public.lf_router_resolve_v1(
    'governed EKB child skill dispatch',
    'ACT-0057',
    'SKILL_EXECUTION',
    'SKILL',
    'ROUTER'
  );
  if coalesce(v_router->>'status','')<>'READY_TO_EXECUTE'
     or coalesce((v_router->>'downstream_execution_allowed')::boolean,false) is not true
     or v_router->>'router' is distinct from 'ACT-0001'
     or v_router->>'operation_code' is distinct from 'EJECUCION_SKILL_LF'
     or v_router->>'asset_type' is distinct from 'SKILL'
     or v_router->>'action_code' is distinct from 'SKILL_EXECUTION' then
    raise exception 'PRE_EKB_CHILD_ROUTER_NOT_READY:%',coalesce(v_router->>'status','UNKNOWN');
  end if;

  if not exists (
    select 1 from public.lf_activos
    where codigo_activo='ACT-0057'
      and nombre_canonico='SKILL_ESCRITURA_BASE_CONOCIMIENTO_LF'
      and tipo_activo='SKILL'
      and estado_operativo='APROBADO'
      and runtime_estado='APROBADO_PRODUCCION_CONTROLADA'
      and archived_at is null
  ) then
    raise exception 'PRE_EKB_TARGET_SKILL_NOT_CURRENT';
  end if;

  if not exists (
    select 1 from public.lf_operation_contracts
    where operation_code='ESCRITURA_BASE_CONOCIMIENTO_LF'
      and contract_code='CONTRACT-PRE-EKB-GATE-LF-v0.1'
      and status='ACTIVE_ENFORCEMENT'
      and coalesce((required_before_write->>'pre_ekb_gate_required')::boolean,false)
  ) then
    raise exception 'PRE_EKB_WRITER_AUTHORITY_NOT_CURRENT';
  end if;

  v_payload_sha:=encode(extensions.digest(convert_to(p_finding::text,'UTF8'),'sha256'),'hex');
  v_child_seed:=encode(
    extensions.digest(convert_to(p_parent_execution_id||'|'||p_finding_fingerprint,'UTF8'),'sha256'),
    'hex'
  );
  v_child_execution_id:='EXEC-EKB-LF-'||upper(substr(v_child_seed,1,32));
  v_idem:='LF-EKB-WRITE:'||v_child_seed;
  v_request_sha:=encode(
    extensions.digest(
      convert_to(
        p_parent_execution_id||'|EJECUCION_SKILL_LF|ACT-0057|ESCRITURA_BASE_CONOCIMIENTO_LF|'||
        v_code||'|'||p_finding_fingerprint||'|'||v_payload_sha,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  v_reserve:=public.fn_lf_operation_reserve_execution_v1(
    v_child_execution_id,
    'EJECUCION_SKILL_LF',
    'SKILL',
    'ACT-0057',
    v_idem,
    v_request_sha,
    p_parent_execution_id,
    'cristhianlujan/claude-persona-lf-patch',
    'skills/escritura_base_conocimiento_lf/',
    jsonb_build_object(
      'dispatch_schema','LF_PRE_EKB_CHILD_DISPATCH_V1',
      'parent_execution_id',p_parent_execution_id,
      'parent_operation_code',v_parent.operation_code,
      'router','ACT-0001',
      'router_action_code','SKILL_EXECUTION',
      'child_execution_operation','EJECUCION_SKILL_LF',
      'target_skill_code','ACT-0057',
      'writer_authority_operation','ESCRITURA_BASE_CONOCIMIENTO_LF',
      'finding_fingerprint',p_finding_fingerprint,
      'finding_payload_sha256',v_payload_sha,
      'error_code',v_code
    )
  );

  select * into v_child
  from public.lf_operation_execution
  where execution_id=v_reserve->>'execution_id';

  if not found
     or v_child.operation_code<>'EJECUCION_SKILL_LF'
     or v_child.target_type<>'SKILL'
     or v_child.target_code<>'ACT-0057'
     or v_child.manifest->>'parent_execution_id'<>p_parent_execution_id
     or v_child.manifest->>'writer_authority_operation'<>'ESCRITURA_BASE_CONOCIMIENTO_LF'
     or v_child.manifest->>'finding_fingerprint'<>p_finding_fingerprint
     or v_child.request_sha256<>v_request_sha
     or not (v_child.manifest ? 'operation_policy_snapshots') then
    raise exception 'PRE_EKB_CHILD_EXECUTION_READBACK_MISMATCH';
  end if;

  select * into v_prior
  from public.lf_eventos
  where evento_tipo='REMEDIACION_GOBERNANZA'
    and created_by_execution_id=v_child.execution_id
    and origen='LF_PIPELINE_EKB_WRITER_V1'
    and payload->>'operation_code'='ESCRITURA_BASE_CONOCIMIENTO_LF'
    and payload->>'error_code'=v_code
  order by id desc
  limit 1;

  if v_prior.id is not null then
    v_writer:=jsonb_build_object(
      'classification','REPLAY_EXISTING_WRITER_RECEIPT',
      'error_code',v_code,
      'ekb_id',v_prior.payload->>'ekb_id',
      'event_id',v_prior.id,
      'readback',v_prior.payload
    );
  else
    v_enriched:=p_finding||jsonb_build_object(
      'source_execution_id',p_parent_execution_id,
      'parent_operation_code',v_parent.operation_code,
      'ekb_child_execution_id',v_child.execution_id,
      'ekb_child_execution_operation','EJECUCION_SKILL_LF',
      'ekb_target_skill_code','ACT-0057',
      'writer_authority_operation','ESCRITURA_BASE_CONOCIMIENTO_LF',
      'finding_fingerprint',p_finding_fingerprint
    );

    v_writer:=public.lf_write_pipeline_ekb_v1(
      'ESCRITURA_BASE_CONOCIMIENTO_LF',
      v_enriched,
      v_child.execution_id
    );
  end if;

  update public.lf_operation_execution
  set status='COMPLETED',
      completed_at=coalesce(completed_at,clock_timestamp()),
      checkpoint_payload=jsonb_build_object(
        'lot_code','PRE_EKB_CHILD_WRITE',
        'parent_execution_id',p_parent_execution_id,
        'router_action','SKILL_EXECUTION',
        'target_skill_code','ACT-0057',
        'writer_authority_operation','ESCRITURA_BASE_CONOCIMIENTO_LF',
        'finding_fingerprint',p_finding_fingerprint,
        'writer_receipt',v_writer,
        'readback_result','PASS'
      ),
      updated_at=clock_timestamp(),
      updated_by_execution_id=v_child.execution_id
  where execution_id=v_child.execution_id
    and status='IN_PROGRESS';

  select * into v_child
  from public.lf_operation_execution
  where execution_id=v_child.execution_id;

  if v_child.status<>'COMPLETED' then
    raise exception 'PRE_EKB_CHILD_EXECUTION_NOT_COMPLETED:%',v_child.status;
  end if;

  select id into v_parent_event_id
  from public.lf_eventos
  where evento_tipo='REMEDIACION_GOBERNANZA'
    and created_by_execution_id=p_parent_execution_id
    and origen='LF_PRE_EKB_GATE_AUTOPERSIST_V1'
    and payload->>'finding_fingerprint'=p_finding_fingerprint
    and payload->>'persistence_result'='EKB_PERSISTED'
  order by id desc
  limit 1;

  if v_parent_event_id is null then
    insert into public.lf_eventos(
      evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,origen,created_by_execution_id
    ) values (
      'REMEDIACION_GOBERNANZA','LF_PRE_EKB_AUTOPERSIST',v_code,
      'Failure diagnostic persisted to EKB through governed child skill execution',
      case when upper(coalesce(p_finding->>'severidad',''))='CRITICAL' then 'CRITICAL'
           when upper(coalesce(p_finding->>'severidad',''))='HIGH' then 'WARN'
           else 'INFO' end,
      jsonb_build_object(
        'evidence_schema_version','operational-event/v2',
        'execution_id',p_parent_execution_id,
        'producer','LF_PRE_EKB_GATE_AUTOPERSIST_V1',
        'purpose','Bind one durable operation failure diagnostic to one governed EKB child write and readback receipt',
        'occurred_at',clock_timestamp(),
        'acceptance_declared',false,
        'parent_operation_code',v_parent.operation_code,
        'child_execution_id',v_child.execution_id,
        'child_execution_operation','EJECUCION_SKILL_LF',
        'target_skill_code','ACT-0057',
        'writer_authority_operation','ESCRITURA_BASE_CONOCIMIENTO_LF',
        'finding_fingerprint',p_finding_fingerprint,
        'finding_payload_sha256',v_payload_sha,
        'error_code',v_code,
        'persistence_result','EKB_PERSISTED',
        'writer_receipt',v_writer
      ),
      'LF_PRE_EKB_GATE_AUTOPERSIST_V1',
      p_parent_execution_id
    )
    returning id into v_parent_event_id;
  end if;

  return jsonb_build_object(
    'result',case when v_reserve->>'result'='RESERVED_NEW_EXECUTION' then 'EKB_CHILD_DISPATCHED' else 'EKB_CHILD_REPLAYED' end,
    'parent_execution_id',p_parent_execution_id,
    'parent_operation_code',v_parent.operation_code,
    'child_execution_id',v_child.execution_id,
    'child_execution_operation',v_child.operation_code,
    'target_skill_code',v_child.target_code,
    'writer_authority_operation','ESCRITURA_BASE_CONOCIMIENTO_LF',
    'child_status',v_child.status,
    'finding_fingerprint',p_finding_fingerprint,
    'finding_payload_sha256',v_payload_sha,
    'writer_receipt',v_writer,
    'parent_event_id',v_parent_event_id
  );
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

  v_error_token:=upper(regexp_replace(
    coalesce(nullif(v_row.error_class,''),v_row.check_status),
    '[^A-Z0-9]+','-','g'
  ));
  v_error_token:=trim(both '-' from v_error_token);

  v_code:=upper(regexp_replace(
    'GATE-'||v_exec.operation_code||'-'||v_row.gate_id||'-'||v_row.check_id||'-'||v_error_token,
    '[^A-Z0-9]+','-','g'
  ));
  v_code:=trim(both '-' from v_code);

  if v_code !~ '^[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+$' then
    raise exception 'PRE_EKB_GATE_CHECK_CODE_NOT_CANONICAL:%',v_code;
  end if;

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

  return public.lf_pre_ekb_child_dispatch_v1(v_row.execution_id,v_finding,v_fingerprint)
    || jsonb_build_object(
      'source_kind','LF_GATE_ERROR_V1',
      'gate_check_result_id',v_row.id,
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

  v_code:=upper(regexp_replace(
    'STEP-'||v_exec.operation_code||'-'||v_step.step_id||'-'||v_block_code,
    '[^A-Z0-9]+','-','g'
  ));
  v_code:=trim(both '-' from v_code);

  if v_code !~ '^[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+$' then
    raise exception 'PRE_EKB_STEP_FAILURE_CODE_NOT_CANONICAL:%',v_code;
  end if;

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

  v_token:=upper(regexp_replace(p_error_code,'[^A-Z0-9]+','-','g'));
  v_token:=trim(both '-' from v_token);
  v_code:=upper(regexp_replace(
    'EXCEPTION-'||v_exec.operation_code||'-'||p_step_id||'-'||v_token,
    '[^A-Z0-9]+','-','g'
  ));
  v_code:=trim(both '-' from v_code);

  if v_code !~ '^[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+$' then
    raise exception 'PRE_EKB_EXCEPTION_CODE_NOT_CANONICAL:%',v_code;
  end if;

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

create or replace function private.fn_lf_pre_ekb_gate_check_autopersist_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
declare
  v_receipt jsonb;
  v_err text;
begin
  if new.check_status not in ('FAIL','BLOCKED')
     or not public.lf_pre_ekb_gate_consumer_v1(new.operation_code) then
    return new;
  end if;

  begin
    v_receipt:=public.lf_pre_ekb_gate_check_dispatch_v1(new.id);
  exception when others then
    v_err:=sqlstate||':'||sqlerrm;

    insert into public.lf_eventos(
      evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,origen,created_by_execution_id
    ) values (
      'REMEDIACION_GOBERNANZA','LF_PRE_EKB_AUTOPERSIST','BLOCKED_EKB_PERSISTENCE',
      'Gate diagnostic is durable but EKB autopersistence failed; repair/resume remains blocked',
      'WARN',
      jsonb_build_object(
        'evidence_schema_version','operational-event/v2',
        'execution_id',new.execution_id,
        'producer','LF_PRE_EKB_GATE_AUTOPERSIST_V1',
        'purpose','Persist fail-closed evidence that a durable gate diagnostic could not yet be written to EKB',
        'occurred_at',clock_timestamp(),
        'acceptance_declared',false,
        'persistence_result','BLOCKED_EKB_PERSISTENCE',
        'gate_check_result_id',new.id,
        'operation_code',new.operation_code,
        'step_id',new.step_id,
        'gate_id',new.gate_id,
        'check_id',new.check_id,
        'error_class',new.error_class,
        'error',v_err,
        'diagnostic_ref','supabase://public/lf_operation_gate_check_results/'||new.id
      ),
      'LF_PRE_EKB_GATE_AUTOPERSIST_V1',
      new.execution_id
    );

    return new;
  end;

  return new;
end;
$function$;

drop trigger if exists trg_lf_pre_ekb_gate_check_autopersist_v1
on public.lf_operation_gate_check_results;

create trigger trg_lf_pre_ekb_gate_check_autopersist_v1
after insert on public.lf_operation_gate_check_results
for each row execute function private.fn_lf_pre_ekb_gate_check_autopersist_v1();

create or replace function private.fn_lf_pre_ekb_step_failure_autopersist_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
declare
  v_operation text;
  v_receipt jsonb;
  v_err text;
begin
  select operation_code into v_operation
  from public.lf_operation_execution
  where execution_id=new.execution_id;

  if not public.lf_pre_ekb_gate_consumer_v1(v_operation)
     or not (
       upper(new.status) like 'BLOCK%'
       or upper(new.status) like 'FAIL%'
       or upper(new.status) like 'RETURN%'
     ) then
    return new;
  end if;

  begin
    v_receipt:=public.lf_pre_ekb_step_failure_dispatch_v1(new.execution_id,new.step_id);
  exception when others then
    v_err:=sqlstate||':'||sqlerrm;

    insert into public.lf_eventos(
      evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,origen,created_by_execution_id
    ) values (
      'REMEDIACION_GOBERNANZA','LF_PRE_EKB_AUTOPERSIST','BLOCKED_EKB_PERSISTENCE',
      'Step failure is durable but EKB autopersistence failed; clean retry remains blocked',
      'WARN',
      jsonb_build_object(
        'evidence_schema_version','operational-event/v2',
        'execution_id',new.execution_id,
        'producer','LF_PRE_EKB_GATE_AUTOPERSIST_V1',
        'purpose','Persist fail-closed evidence that a durable non-pass step could not yet be written to EKB',
        'occurred_at',clock_timestamp(),
        'acceptance_declared',false,
        'persistence_result','BLOCKED_EKB_PERSISTENCE',
        'operation_code',v_operation,
        'step_id',new.step_id,
        'status',new.status,
        'evidence_ref',new.evidence_ref,
        'error',v_err
      ),
      'LF_PRE_EKB_GATE_AUTOPERSIST_V1',
      new.execution_id
    );

    return new;
  end;

  return new;
end;
$function$;

drop trigger if exists trg_lf_pre_ekb_step_failure_autopersist_v1
on public.lf_operation_execution_steps;

create trigger trg_lf_pre_ekb_step_failure_autopersist_v1
after insert or update of status on public.lf_operation_execution_steps
for each row execute function private.fn_lf_pre_ekb_step_failure_autopersist_v1();

create or replace function private.fn_lf_pre_ekb_clean_retry_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_operation text;
  v_evidence_sha text;
  v_missing_gate bigint;
begin
  if new.status<>'PASS_CLEAN' then
    return new;
  end if;

  select operation_code into v_operation
  from public.lf_operation_execution
  where execution_id=new.execution_id;

  if not public.lf_pre_ekb_gate_consumer_v1(v_operation) then
    return new;
  end if;

  select r.id into v_missing_gate
  from public.lf_operation_gate_check_results r
  where r.execution_id=new.execution_id
    and r.check_status in ('FAIL','BLOCKED')
    and not exists (
      select 1
      from public.lf_eventos e
      where e.evento_tipo='REMEDIACION_GOBERNANZA'
        and e.created_by_execution_id=r.execution_id
        and e.origen='LF_PRE_EKB_GATE_AUTOPERSIST_V1'
        and e.payload->>'persistence_result'='EKB_PERSISTED'
        and (e.payload->>'gate_check_result_id')::bigint=r.id
    )
  order by r.id
  limit 1;

  if v_missing_gate is not null then
    raise exception 'BLOCKED_EKB_PERSISTENCE:GATE_CHECK_RESULT:%',v_missing_gate;
  end if;

  if tg_op='UPDATE'
     and (
       upper(old.status) like 'BLOCK%'
       or upper(old.status) like 'FAIL%'
       or upper(old.status) like 'RETURN%'
     ) then
    v_evidence_sha:=encode(
      extensions.digest(convert_to(coalesce(old.evidence_payload,'{}'::jsonb)::text,'UTF8'),'sha256'),
      'hex'
    );

    if not exists (
      select 1
      from public.lf_eventos e
      where e.evento_tipo='REMEDIACION_GOBERNANZA'
        and e.created_by_execution_id=new.execution_id
        and e.origen='LF_PRE_EKB_GATE_AUTOPERSIST_V1'
        and e.payload->>'persistence_result'='EKB_PERSISTED'
        and e.payload->'writer_receipt' is not null
        and exists (
          select 1
          from public.lf_operation_execution c
          where c.execution_id=e.payload->>'child_execution_id'
            and c.checkpoint_payload->>'finding_fingerprint'=e.payload->>'finding_fingerprint'
        )
        and e.payload->>'finding_fingerprint'=encode(
          extensions.digest(
            convert_to(new.execution_id||'|'||new.step_id||'|'||old.status||'|'||
              coalesce(
                nullif(old.evidence_payload->>'blocked_reason_code',''),
                nullif(old.evidence_payload->'blocking_codes'->>0,''),
                nullif(old.evidence_payload->'blocking_findings'->>0,''),
                old.status
              )||'|'||v_evidence_sha,'UTF8'
            ),
            'sha256'
          ),
          'hex'
        )
    ) then
      raise exception 'BLOCKED_EKB_PERSISTENCE:STEP_FAILURE:%',new.step_id;
    end if;
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_lf_pre_ekb_clean_retry_guard_v1
on public.lf_operation_execution_steps;

create trigger trg_lf_pre_ekb_clean_retry_guard_v1
before insert or update of status on public.lf_operation_execution_steps
for each row execute function private.fn_lf_pre_ekb_clean_retry_guard_v1();

-- Upgrade the existing PRE_EKB_GATE asset. This is not a new EKB/error engine.
update public.lf_activos
set estado_documental='VIGENTE',
    estado_operativo='ACTIVO',
    version='v0.2',
    runtime_estado='SUPABASE_ENFORCED',
    impacto_automatico='TRANSVERSAL',
    ultima_revision='PRE_EKB_GATE_V0_2_DB_AUTOPERSIST_20260917',
    raw_payload=coalesce(raw_payload,'{}'::jsonb)||jsonb_build_object(
      'status','ACTIVE_SHARED_ENFORCEMENT',
      'first_enforced_consumer','ACTUALIZACION_DB_LF',
      'failure_contract','LF_GATE_ERROR_V1',
      'child_execution_operation','EJECUCION_SKILL_LF',
      'target_skill','ACT-0057',
      'writer_authority','ESCRITURA_BASE_CONOCIMIENTO_LF',
      'autopersist_function','public.lf_pre_ekb_gate_check_dispatch_v1',
      'exception_bridge','public.lf_pre_ekb_exception_dispatch_v1',
      'repair_guard','private.fn_lf_pre_ekb_clean_retry_guard_v1'
    ),
    metadata=jsonb_set(
      jsonb_set(
        jsonb_set(
          coalesce(metadata,'{}'::jsonb),
          '{transversal_inventory,inventory_status}',
          '"ACTIVE_SHARED_ENFORCEMENT"'::jsonb,
          true
        ),
        '{transversal_inventory,gap}',
        '"coverage is not universal yet; ACTUALIZACION_DB_LF is the first enforced consumer; add other operations by binding, not by duplicating the engine"'::jsonb,
        true
      ),
      '{transversal_inventory,consumers_known}',
      case
        when jsonb_typeof(metadata #> '{transversal_inventory,consumers_known}')='array'
          then (metadata #> '{transversal_inventory,consumers_known}') || '["ACTUALIZACION_DB_LF"]'::jsonb
        when jsonb_typeof(metadata #> '{transversal_inventory,consumers_known}')='string'
          then jsonb_build_array(metadata #>> '{transversal_inventory,consumers_known}','ACTUALIZACION_DB_LF')
        else '["ACTUALIZACION_DB_LF"]'::jsonb
      end,
      true
    ),
    updated_by_execution_id='EXEC-S30-PRE-EKB-DB-AUTOPERSIST-20260917-001',
    updated_at=clock_timestamp()
where codigo_activo='PRE_EKB_GATE'
  and archived_at is null;

do $post$
declare
  v_execution_id constant text := 'EXEC-S30-PRE-EKB-DB-AUTOPERSIST-20260917-001';
  v_auth jsonb;
begin
  if not public.lf_pre_ekb_gate_consumer_v1('ACTUALIZACION_DB_LF') then
    raise exception 'BLOCK_PRE_EKB_CONSUMER_BINDING_READBACK';
  end if;

  if to_regprocedure('public.lf_pre_ekb_child_dispatch_v1(text,jsonb,text)') is null
     or to_regprocedure('public.lf_pre_ekb_gate_check_dispatch_v1(bigint)') is null
     or to_regprocedure('public.lf_pre_ekb_step_failure_dispatch_v1(text,text)') is null
     or to_regprocedure('public.lf_pre_ekb_exception_dispatch_v1(text,text,text,text,text,text,text,jsonb)') is null then
    raise exception 'BLOCK_PRE_EKB_FUNCTION_READBACK';
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgname='trg_lf_pre_ekb_gate_check_autopersist_v1' and tgenabled<>'D'
  ) or not exists (
    select 1 from pg_trigger
    where tgname='trg_lf_pre_ekb_step_failure_autopersist_v1' and tgenabled<>'D'
  ) or not exists (
    select 1 from pg_trigger
    where tgname='trg_lf_pre_ekb_clean_retry_guard_v1' and tgenabled<>'D'
  ) then
    raise exception 'BLOCK_PRE_EKB_TRIGGER_READBACK';
  end if;

  if not exists (
    select 1 from public.lf_activos
    where codigo_activo='PRE_EKB_GATE'
      and estado_documental='VIGENTE'
      and estado_operativo='ACTIVO'
      and version='v0.2'
      and metadata #>> '{transversal_inventory,inventory_status}'='ACTIVE_SHARED_ENFORCEMENT'
      and (metadata #> '{transversal_inventory,consumers_known}') ? 'ACTUALIZACION_DB_LF'
      and archived_at is null
  ) then
    raise exception 'BLOCK_PRE_EKB_ASSET_READBACK';
  end if;

  -- This migration intentionally does not mutate ACTUALIZACION_DB_LF registry/contracts/steps,
  -- so the server-bound Router receipt remains current across the self-update.
  v_auth:=public.lf_router_downstream_authority_validate_v1(v_execution_id);
  if coalesce((v_auth->>'valid')::boolean,false) is not true then
    raise exception 'BLOCK_PRE_EKB_ROUTER_AUTHORITY_REGRESSION:%',coalesce(v_auth->>'code','UNKNOWN');
  end if;
end
$post$;

revoke execute on function public.lf_pre_ekb_gate_consumer_v1(text) from public,anon,authenticated;
revoke execute on function public.lf_pre_ekb_child_dispatch_v1(text,jsonb,text) from public,anon,authenticated;
revoke execute on function public.lf_pre_ekb_gate_check_dispatch_v1(bigint) from public,anon,authenticated;
revoke execute on function public.lf_pre_ekb_step_failure_dispatch_v1(text,text) from public,anon,authenticated;
revoke execute on function public.lf_pre_ekb_exception_dispatch_v1(text,text,text,text,text,text,text,jsonb) from public,anon,authenticated;

grant execute on function public.lf_pre_ekb_gate_consumer_v1(text) to service_role;
grant execute on function public.lf_pre_ekb_child_dispatch_v1(text,jsonb,text) to service_role;
grant execute on function public.lf_pre_ekb_gate_check_dispatch_v1(bigint) to service_role;
grant execute on function public.lf_pre_ekb_step_failure_dispatch_v1(text,text) to service_role;
grant execute on function public.lf_pre_ekb_exception_dispatch_v1(text,text,text,text,text,text,text,jsonb) to service_role;

comment on function public.lf_pre_ekb_child_dispatch_v1(text,jsonb,text) is
'PRE_EKB_GATE v0.2 transversal governed child dispatch: EJECUCION_SKILL_LF -> ACT-0057 -> ESCRITURA_BASE_CONOCIMIENTO_LF. Idempotent by parent execution + finding fingerprint.';

comment on function public.lf_pre_ekb_gate_check_dispatch_v1(bigint) is
'Maps one durable LF_GATE_ERROR_V1 FAIL/BLOCKED check into a complete non-generic EKB finding with expected/actual, exact source, owner, next action, resume checkpoint and rerun scope.';

comment on function public.lf_pre_ekb_exception_dispatch_v1(text,text,text,text,text,text,text,jsonb) is
'Explicit post-rollback bridge for caught operation exceptions. Incomplete diagnostics fail closed instead of writing generic EKB entries.';
