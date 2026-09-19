-- LF_PROFILE_UPDATE_BEGIN_RECONCILE_V1
-- Completes the ACTUALIZACION_PERFIL_LF lifecycle in two places:
-- 1) transactional begin = execution reservation + immutable init_execution
-- 2) post-merge registry reconciliation without runtime promotion
--
-- This migration never enables runtime, never changes operational/document state,
-- and never changes automatic-impact policy.

create or replace function public.lf_profile_update_begin_v1(
  p_execution_id text,
  p_target_code text,
  p_target_repo text,
  p_target_path text,
  p_request_sha256 text,
  p_idempotency_key text,
  p_actor_execution_id text,
  p_manifest jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
set search_path to 'pg_catalog','public'
as $function$
declare
  r jsonb;
  x public.lf_operation_execution%rowtype;
  st public.lf_operation_steps%rowtype;
  b public.lf_operation_step_judge_bindings%rowtype;
  oc public.lf_operation_contracts%rowtype;
  existing public.lf_operation_execution_steps%rowtype;
  route_count integer;
  contract_count integer;
  ep jsonb;
begin
  if btrim(coalesce(p_execution_id,''))=''
     or btrim(coalesce(p_target_code,''))=''
     or btrim(coalesce(p_target_repo,''))=''
     or btrim(coalesce(p_target_path,''))=''
     or coalesce(p_request_sha256,'') !~ '^[0-9a-f]{64}$'
     or btrim(coalesce(p_idempotency_key,''))=''
     or btrim(coalesce(p_actor_execution_id,''))=''
     or p_manifest is null
     or jsonb_typeof(p_manifest)<>'object' then
    raise exception 'LF_PROFILE_UPDATE_BEGIN_INPUT_INVALID';
  end if;
  if p_target_code !~ '^PERFIL-[A-Z0-9-]+$' then
    raise exception 'LF_PROFILE_UPDATE_TARGET_CODE_INVALID:%',p_target_code;
  end if;
  if p_target_repo <> 'cristhianlujan/claude-persona-lf-patch' then
    raise exception 'LF_PROFILE_UPDATE_REPO_INVALID';
  end if;
  if p_target_path !~ '^profiles/[a-z0-9][a-z0-9_/-]*$'
     or position('..' in p_target_path)>0 then
    raise exception 'LF_PROFILE_UPDATE_TARGET_PATH_INVALID';
  end if;

  select count(*) into route_count
  from public.lf_router_action_registry
  where asset_type='PERFIL'
    and action_code='PROFILE_UPDATE'
    and operation_code='ACTUALIZACION_PERFIL_LF'
    and status='ACTIVE'
    and write_allowed is true;
  if route_count<>1 then
    raise exception 'LF_PROFILE_UPDATE_ROUTE_NOT_ACTIVE:%',route_count;
  end if;

  if not exists(
    select 1
    from public.lf_operation_registry
    where operation_code='ACTUALIZACION_PERFIL_LF'
      and applies_to_asset_type='PERFIL'
      and lifecycle_state_code='OP_OPERATIONAL'
  ) then
    raise exception 'LF_PROFILE_UPDATE_OPERATION_NOT_OPERATIONAL';
  end if;

  select count(*) into contract_count
  from public.lf_operation_contracts
  where operation_code='ACTUALIZACION_PERFIL_LF'
    and status='ACTIVE_ENFORCEMENT';
  if contract_count<>1 then
    raise exception 'LF_PROFILE_UPDATE_CONTRACT_NOT_EXACT:%',contract_count;
  end if;
  select * into oc
  from public.lf_operation_contracts
  where operation_code='ACTUALIZACION_PERFIL_LF'
    and status='ACTIVE_ENFORCEMENT'
  limit 1;

  r:=public.fn_lf_operation_reserve_execution_v1(
    p_execution_id,
    'ACTUALIZACION_PERFIL_LF',
    'PERFIL',
    p_target_code,
    p_idempotency_key,
    p_request_sha256,
    p_actor_execution_id,
    p_target_repo,
    p_target_path,
    p_manifest || jsonb_build_object(
      'contract_code',oc.contract_code,
      'contract_sha',oc.contract_sha,
      'begin_rpc','lf_profile_update_begin_v1',
      'automatic_runtime_promotion',false
    )
  );

  select * into x
  from public.lf_operation_execution
  where execution_id=r->>'execution_id'
  for update;
  if not found
     or x.operation_code<>'ACTUALIZACION_PERFIL_LF'
     or x.target_type<>'PERFIL'
     or x.target_code is distinct from p_target_code
     or x.target_repo is distinct from p_target_repo
     or x.target_path is distinct from p_target_path
     or x.status<>'IN_PROGRESS' then
    raise exception 'LF_PROFILE_UPDATE_EXECUTION_BINDING_MISMATCH';
  end if;

  perform public.lf_operation_execution_qualification_guard_v1(
    'ACTUALIZACION_PERFIL_LF',x.started_at
  );

  select * into st
  from public.lf_operation_steps
  where operation_code='ACTUALIZACION_PERFIL_LF'
    and step_id='init_execution'
    and active=true;
  if not found then
    raise exception 'LF_PROFILE_UPDATE_INIT_STEP_NOT_ACTIVE';
  end if;

  select * into b
  from public.lf_operation_step_judge_bindings
  where operation_code='ACTUALIZACION_PERFIL_LF'
    and step_id='init_execution'
    and step_order=st.step_order
    and status='ACTIVE_ENFORCEMENT';
  if not found then
    raise exception 'LF_PROFILE_UPDATE_INIT_BINDING_NOT_ACTIVE';
  end if;

  select * into existing
  from public.lf_operation_execution_steps
  where execution_id=x.execution_id
    and step_order=st.step_order;
  if found then
    if existing.step_id='init_execution'
       and existing.status=b.clean_result_value then
      return r || jsonb_build_object(
        'init_step','ALREADY_RECORDED_IDEMPOTENT',
        'next_step','router'
      );
    end if;
    raise exception 'LF_PROFILE_UPDATE_INIT_STEP_CONFLICT';
  end if;

  ep:=jsonb_build_object(
    'execution_id_created',x.execution_id,
    'execution_row_created',true,
    'operation_code','ACTUALIZACION_PERFIL_LF',
    'target_type','PERFIL',
    'status',x.status,
    'target_code',p_target_code,
    'target_repo',p_target_repo,
    'target_path',p_target_path,
    'assertions_checked',jsonb_build_array(
      'execution_row_created',
      'operation_code_exact',
      'target_type_perfil',
      'status_in_progress'
    ),
    'hard_fails_checked','[]'::jsonb,
    'blocking_findings','[]'::jsonb,
    'return_to_worker_reasons','[]'::jsonb,
    'step_result',b.clean_result_value,
    'blocking_codes','[]'::jsonb,
    'mini_judge_code',b.judge_code,
    'mini_judge_result',b.clean_result_value,
    'recorded_by_rpc','lf_profile_update_begin_v1'
  );

  insert into public.lf_operation_execution_steps(
    execution_id,step_order,step_id,status,evidence_ref,evidence_payload,notes,
    created_by_execution_id
  ) values(
    x.execution_id,st.step_order,'init_execution',b.clean_result_value,
    format('supabase://public/lf_operation_execution/%s',x.execution_id),
    ep,
    'Initialized transactionally by governed Profile Update begin RPC.',
    p_actor_execution_id
  );

  select * into existing
  from public.lf_operation_execution_steps
  where execution_id=x.execution_id
    and step_order=st.step_order
    and step_id='init_execution';
  if not found or existing.status<>b.clean_result_value then
    raise exception 'LF_PROFILE_UPDATE_BEGIN_READBACK_FAILED';
  end if;

  return r || jsonb_build_object(
    'init_step','RECORDED',
    'contract_code',oc.contract_code,
    'contract_sha',oc.contract_sha,
    'next_step','router'
  );
end;
$function$;

revoke all on function public.lf_profile_update_begin_v1(
  text,text,text,text,text,text,text,jsonb
) from public,anon,authenticated;
grant execute on function public.lf_profile_update_begin_v1(
  text,text,text,text,text,text,text,jsonb
) to service_role;

-- Version the Profile Update PASS policy so the lifecycle declaration and
-- active operation steps stay in sync. In-flight executions remain pinned to
-- their immutable start snapshot.
update public.lf_policy_versions
set status='SUPERSEDED',
    superseded_at=clock_timestamp(),
    updated_by_execution_id='EXEC-LF-SRCR-PROFILE-PARTITION-V1-20260919-001',
    updated_at=clock_timestamp()
where policy_code='POL-PROFILE-UPDATE-PASS'
  and policy_version='v1.0'
  and status='ACTIVE';

do $policy$
declare
  p jsonb;
begin
  p:=jsonb_build_object(
    'policy_id','POL-PROFILE-UPDATE-PASS',
    'policy_kind','PROFILE_UPDATE_PASS_POLICY',
    'authority','SUPABASE',
    'applies_to_operation_code','ACTUALIZACION_PERFIL_LF',
    'distribution_contract',jsonb_build_object(
      'modes',jsonb_build_array('ROUTER','DIRECT'),
      'snapshot_view','public.v_lf_operation_policy_snapshot',
      'required_fields',jsonb_build_array('policy_code','policy_version','policy_sha','policy_payload'),
      'precedent_usage','EVIDENCE_ONLY_NOT_AUTHORITY'
    ),
    'required_steps',jsonb_build_array(
      'init_execution','router','profile_resolve','baseline_read','change_scope','regression_plan',
      'pre_write_execution_binding_gate','github_write','github_readback','deterministic_validation',
      'semantic_judge','regression_after','post_merge_reconcile','close','report_output'
    ),
    'required_behaviors',jsonb_build_object(
      'ekb_first',true,
      'policy_snapshot_before_write',true,
      'execution_binding_before_write',true,
      'branch_from_exact_main',true,
      'minimal_patch',true,
      'github_readback_exact_head',true,
      'deterministic_validation',true,
      'semantic_judge',true,
      'adversarial_and_holdout',true,
      'router_direct_consistency',true,
      'all_required_ci_success_exact_head',true,
      'pre_merge_main_reread',true,
      'pre_merge_policy_reread',true,
      'force_push_for_base_drift_forbidden',true,
      'post_merge_readback',true,
      'post_merge_reconciliation',true,
      'runtime_refresh_or_activation_gate',true,
      'ekb_close',true,
      'automatic_runtime_promotion',false
    ),
    'blocking_rules',jsonb_build_array(
      'BLOCK_PROFILE_UPDATE_POLICY_MISSING',
      'BLOCK_PROFILE_UPDATE_POLICY_SHA_MISMATCH',
      'BLOCK_STALE_PROFILE_UPDATE_POLICY',
      'BLOCK_WRITE_BEFORE_BINDING',
      'BLOCK_INCOMPLETE_EVIDENCE',
      'BLOCK_SEMANTIC_REGRESSION',
      'BLOCK_ROUTER_DIRECT_DIVERGENCE',
      'BLOCK_POST_MERGE_RECONCILIATION_MISSING'
    ),
    'stale_policy_action','BLOCK_STALE_PROFILE_UPDATE_POLICY',
    'precedent_rule','PRs are historical evidence only; never an operational source of truth'
  );

  insert into public.lf_policy_versions(
    policy_code,policy_version,policy_payload,policy_sha,status,effective_at,
    source_ref,created_by_execution_id,updated_by_execution_id
  )
  values(
    'POL-PROFILE-UPDATE-PASS','v1.1',p,
    encode(extensions.digest(convert_to(p::text,'UTF8'),'sha256'),'hex'),
    'ACTIVE',clock_timestamp(),'GOV-036',
    'EXEC-LF-SRCR-PROFILE-PARTITION-V1-20260919-001',
    'EXEC-LF-SRCR-PROFILE-PARTITION-V1-20260919-001'
  )
  on conflict (policy_code,policy_version) do update
  set policy_payload=excluded.policy_payload,
      policy_sha=excluded.policy_sha,
      status='ACTIVE',
      effective_at=excluded.effective_at,
      superseded_at=null,
      source_ref=excluded.source_ref,
      updated_by_execution_id=excluded.updated_by_execution_id,
      updated_at=clock_timestamp();
end;
$policy$;

update public.lf_activos
set version='v1.1',
    metadata=coalesce(metadata,'{}'::jsonb)
      || jsonb_build_object(
        'profile_update_policy_version','v1.1',
        'post_merge_reconciliation_required',true,
        'automatic_runtime_promotion',false
      ),
    updated_by_execution_id='EXEC-LF-SRCR-PROFILE-PARTITION-V1-20260919-001',
    updated_at=clock_timestamp()
where codigo_activo='POL-PROFILE-UPDATE-PASS';

-- Add the missing post-merge reconciliation step immediately before close.
insert into public.lf_operation_steps(
  operation_code,step_order,step_id,required,evidence_required,source_path,source_sha,
  active,execution_order,created_by_execution_id,updated_by_execution_id
)
values(
  'ACTUALIZACION_PERFIL_LF',
  115,
  'post_merge_reconcile',
  true,
  'reconciliation_disposition; merge_sha; entrypoint_sha; manifest_sha; profile_pack_id; runtime_state_before; runtime_state_after; operational_state_preserved; automatic_impact_preserved; next_gate',
  'public.lf_operation_step_contracts/ACTUALIZACION_PERFIL_LF/post_merge_reconcile',
  null,
  true,
  115,
  'EXEC-LF-SRCR-PROFILE-PARTITION-V1-20260919-001',
  'EXEC-LF-SRCR-PROFILE-PARTITION-V1-20260919-001'
)
on conflict (operation_code,step_id) do update
set step_order=excluded.step_order,
    execution_order=excluded.execution_order,
    required=excluded.required,
    evidence_required=excluded.evidence_required,
    source_path=excluded.source_path,
    active=excluded.active,
    updated_by_execution_id=excluded.updated_by_execution_id,
    updated_at=clock_timestamp();

update public.lf_operation_step_contracts
set next_if_pass='post_merge_reconcile',
    updated_by_execution_id='EXEC-LF-SRCR-PROFILE-PARTITION-V1-20260919-001',
    updated_at=clock_timestamp()
where operation_code='ACTUALIZACION_PERFIL_LF'
  and step_id='regression_after'
  and status='ACTIVE_ENFORCEMENT';

insert into public.lf_operation_step_contracts(
  operation_code,step_id,step_order,execution_order,contract_code,purpose,
  input_required,resolver_ref,output_payload,pass_condition,block_condition,
  blocking_code,mini_judge_code,required_evidence_keys,next_if_pass,next_if_blocked,
  status,created_by_execution_id,updated_by_execution_id
)
values(
  'ACTUALIZACION_PERFIL_LF',
  'post_merge_reconcile',
  115,
  115,
  'CONTRACT-ACTUALIZACION-PERFIL-LF-v0.1',
  'Reconciliar fuente post-merge con el registro operativo sin promover runtime ni impacto automático.',
  '[]'::jsonb,
  'GPT_RUNTIME_WITH_SUPABASE_CONTEXT',
  '["reconciliation_disposition","merge_sha","entrypoint_sha","manifest_sha","profile_pack_id","runtime_state_before","runtime_state_after","operational_state_preserved","automatic_impact_preserved","next_gate"]'::jsonb,
  '{"must_not_be_generic":true,"must_match_step_purpose":true}'::jsonb,
  '{"generic_payload":true,"wrong_action_or_target":true,"missing_required_evidence":true}'::jsonb,
  'BLOCKED_ACTUALIZACION_PERFIL_LF_POST_MERGE_RECONCILE_NOT_CLEAN',
  'JUDGE-ACTUALIZACION-PERFIL-LF-v0.1',
  '["reconciliation_disposition","merge_sha","entrypoint_sha","manifest_sha","profile_pack_id","runtime_state_before","runtime_state_after","operational_state_preserved","automatic_impact_preserved","next_gate"]'::jsonb,
  'close',
  'RETURN_TO_ROUTER',
  'ACTIVE_ENFORCEMENT',
  'EXEC-LF-SRCR-PROFILE-PARTITION-V1-20260919-001',
  'EXEC-LF-SRCR-PROFILE-PARTITION-V1-20260919-001'
)
on conflict (operation_code,step_id) do update
set step_order=excluded.step_order,
    execution_order=excluded.execution_order,
    contract_code=excluded.contract_code,
    purpose=excluded.purpose,
    input_required=excluded.input_required,
    resolver_ref=excluded.resolver_ref,
    output_payload=excluded.output_payload,
    pass_condition=excluded.pass_condition,
    block_condition=excluded.block_condition,
    status=excluded.status,
    mini_judge_code=excluded.mini_judge_code,
    required_evidence_keys=excluded.required_evidence_keys,
    next_if_pass=excluded.next_if_pass,
    next_if_blocked=excluded.next_if_blocked,
    blocking_code=excluded.blocking_code,
    updated_by_execution_id=excluded.updated_by_execution_id,
    updated_at=clock_timestamp();

insert into public.lf_operation_step_judge_bindings(
  operation_code,step_id,step_order,judge_code,status,
  clean_result_value,blocked_result_value,return_result_value,
  required_evidence_keys,created_by_execution_id,updated_by_execution_id
)
values(
  'ACTUALIZACION_PERFIL_LF',
  'post_merge_reconcile',
  115,
  'JUDGE-ACTUALIZACION-PERFIL-LF-v0.1',
  'ACTIVE_ENFORCEMENT',
  'STEP_PASS_WITH_EVIDENCE',
  'BLOCKED_STEP_NOT_CLEAN',
  'RETURN_TO_ROUTER',
  '["reconciliation_disposition","merge_sha","entrypoint_sha","manifest_sha","profile_pack_id","runtime_state_before","runtime_state_after","operational_state_preserved","automatic_impact_preserved","next_gate"]'::jsonb,
  'EXEC-LF-SRCR-PROFILE-PARTITION-V1-20260919-001',
  'EXEC-LF-SRCR-PROFILE-PARTITION-V1-20260919-001'
)
on conflict (operation_code,step_id,step_order) do update
set judge_code=excluded.judge_code,
    status=excluded.status,
    clean_result_value=excluded.clean_result_value,
    blocked_result_value=excluded.blocked_result_value,
    return_result_value=excluded.return_result_value,
    required_evidence_keys=excluded.required_evidence_keys,
    updated_by_execution_id=excluded.updated_by_execution_id,
    updated_at=clock_timestamp();

create or replace function public.lf_profile_update_post_merge_reconcile_v1(
  p_execution_id text,
  p_merge_sha text,
  p_entrypoint_sha text,
  p_manifest_sha text,
  p_profile_pack_id text,
  p_pr_number integer,
  p_actor_execution_id text
) returns jsonb
language plpgsql
set search_path to 'pg_catalog','public'
as $function$
declare
  x public.lf_operation_execution%rowtype;
  a public.lf_activos%rowtype;
  runtime_before text;
  operational_before text;
  impact_before text;
  doc_before text;
  disposition text;
  next_gate text;
  prior_bad integer;
  prior_missing integer;
begin
  if btrim(coalesce(p_execution_id,''))=''
     or coalesce(p_merge_sha,'') !~ '^[0-9a-f]{40}$'
     or coalesce(p_entrypoint_sha,'') !~ '^[0-9a-f]{40}$'
     or coalesce(p_manifest_sha,'') !~ '^[0-9a-f]{40}$'
     or btrim(coalesce(p_profile_pack_id,''))=''
     or coalesce(p_pr_number,0)<=0
     or btrim(coalesce(p_actor_execution_id,''))='' then
    raise exception 'LF_PROFILE_UPDATE_RECONCILE_INPUT_INVALID';
  end if;

  select * into x
  from public.lf_operation_execution
  where execution_id=p_execution_id
  for update;
  if not found
     or x.operation_code<>'ACTUALIZACION_PERFIL_LF'
     or x.target_type<>'PERFIL'
     or x.status<>'IN_PROGRESS'
     or x.target_repo<>'cristhianlujan/claude-persona-lf-patch' then
    raise exception 'LF_PROFILE_UPDATE_RECONCILE_EXECUTION_INVALID';
  end if;

  -- The registry mutation is impossible until every required step before the
  -- reconciliation step is present and clean under its active binding.
  select count(*) into prior_missing
  from public.lf_operation_steps s
  where s.operation_code='ACTUALIZACION_PERFIL_LF'
    and s.required is true
    and s.active is true
    and coalesce(s.execution_order,s.step_order)<115
    and not exists(
      select 1
      from public.lf_operation_execution_steps es
      where es.execution_id=p_execution_id
        and es.step_order=s.step_order
        and es.step_id=s.step_id
    );

  select count(*) into prior_bad
  from public.lf_operation_steps s
  join public.lf_operation_execution_steps es
    on es.execution_id=p_execution_id
   and es.step_order=s.step_order
   and es.step_id=s.step_id
  left join public.lf_operation_step_judge_bindings b
    on b.operation_code=s.operation_code
   and b.step_order=s.step_order
   and b.step_id=s.step_id
   and b.status='ACTIVE_ENFORCEMENT'
  where s.operation_code='ACTUALIZACION_PERFIL_LF'
    and s.required is true
    and s.active is true
    and coalesce(s.execution_order,s.step_order)<115
    and (b.clean_result_value is null or es.status<>b.clean_result_value);

  if prior_missing>0 or prior_bad>0 then
    raise exception 'LF_PROFILE_UPDATE_RECONCILE_PRIOR_STEPS_NOT_CLEAN missing=% bad=%',
      prior_missing,prior_bad;
  end if;

  select * into a
  from public.lf_activos
  where codigo_activo=x.target_code
    and tipo_activo='PERFIL'
    and archived_at is null
  for update;
  if not found then
    raise exception 'LF_PROFILE_UPDATE_RECONCILE_PROFILE_ASSET_NOT_FOUND';
  end if;

  runtime_before:=a.runtime_estado;
  operational_before:=a.estado_operativo;
  impact_before:=a.impacto_automatico;
  doc_before:=a.estado_documental;

  if runtime_before is null
     or runtime_before in ('NO_HABILITADO','NO_APLICA') then
    disposition:='SOURCE_RECONCILED_ACTIVATION_REQUIRED';
    next_gate:='PROFILE_RUNTIME_ACTIVATION_REQUIRED';
  else
    disposition:='SOURCE_RECONCILED_RUNTIME_REFRESH_REQUIRED';
    next_gate:='PROFILE_RUNTIME_REFRESH_REQUIRED';
  end if;

  update public.lf_activos
  set raw_payload=coalesce(raw_payload,'{}'::jsonb)
        || jsonb_build_object(
          'skill_sha',p_entrypoint_sha,
          'profile_pack_id',p_profile_pack_id
        ),
      metadata=coalesce(metadata,'{}'::jsonb)
        || jsonb_build_object(
          'entrypoint_sha',p_entrypoint_sha,
          'manifest_sha',p_manifest_sha,
          'profile_pack_id',p_profile_pack_id,
          'last_governed_pr',p_pr_number,
          'last_governed_merge_sha',p_merge_sha,
          'last_update_execution_id',p_execution_id,
          'currentness_synced_at',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
          'currentness_reason','POST_MERGE_PROFILE_UPDATE_RECONCILIATION',
          'post_merge_reconciliation_disposition',disposition,
          'post_merge_next_gate',next_gate
        ),
      updated_by_execution_id=p_actor_execution_id
  where codigo_activo=x.target_code
    and tipo_activo='PERFIL'
    and archived_at is null;

  select * into a
  from public.lf_activos
  where codigo_activo=x.target_code
    and tipo_activo='PERFIL'
    and archived_at is null;

  if a.runtime_estado is distinct from runtime_before
     or a.estado_operativo is distinct from operational_before
     or a.impacto_automatico is distinct from impact_before
     or a.estado_documental is distinct from doc_before then
    raise exception 'LF_PROFILE_UPDATE_RECONCILE_STATE_DRIFT';
  end if;
  if a.metadata->>'entrypoint_sha'<>p_entrypoint_sha
     or a.metadata->>'manifest_sha'<>p_manifest_sha
     or a.metadata->>'profile_pack_id'<>p_profile_pack_id
     or a.metadata->>'last_governed_pr'<>p_pr_number::text
     or a.metadata->>'last_governed_merge_sha'<>p_merge_sha then
    raise exception 'LF_PROFILE_UPDATE_RECONCILE_READBACK_FAILED';
  end if;

  return jsonb_build_object(
    'outcome','RECONCILED',
    'execution_id',p_execution_id,
    'target_code',x.target_code,
    'reconciliation_disposition',disposition,
    'merge_sha',p_merge_sha,
    'entrypoint_sha',p_entrypoint_sha,
    'manifest_sha',p_manifest_sha,
    'profile_pack_id',p_profile_pack_id,
    'last_governed_pr',p_pr_number,
    'runtime_state_before',runtime_before,
    'runtime_state_after',a.runtime_estado,
    'operational_state_preserved',a.estado_operativo is not distinct from operational_before,
    'automatic_impact_preserved',a.impacto_automatico is not distinct from impact_before,
    'document_state_preserved',a.estado_documental is not distinct from doc_before,
    'automatic_promotion',false,
    'next_gate',next_gate
  );
end;
$function$;

revoke all on function public.lf_profile_update_post_merge_reconcile_v1(
  text,text,text,text,text,integer,text
) from public,anon,authenticated;
grant execute on function public.lf_profile_update_post_merge_reconcile_v1(
  text,text,text,text,text,integer,text
) to service_role;

do $verification$
declare
  v_count integer;
begin
  select count(*) into v_count
  from public.lf_operation_steps
  where operation_code='ACTUALIZACION_PERFIL_LF'
    and step_id='post_merge_reconcile'
    and execution_order=115
    and required is true
    and active is true;
  if v_count<>1 then
    raise exception 'LF_PROFILE_UPDATE_POST_MERGE_STEP_VERIFY_FAILED:%',v_count;
  end if;

  select count(*) into v_count
  from public.lf_operation_step_contracts
  where operation_code='ACTUALIZACION_PERFIL_LF'
    and step_id='post_merge_reconcile'
    and status='ACTIVE_ENFORCEMENT'
    and next_if_pass='close';
  if v_count<>1 then
    raise exception 'LF_PROFILE_UPDATE_POST_MERGE_CONTRACT_VERIFY_FAILED:%',v_count;
  end if;

  select count(*) into v_count
  from public.lf_operation_step_judge_bindings
  where operation_code='ACTUALIZACION_PERFIL_LF'
    and step_id='post_merge_reconcile'
    and status='ACTIVE_ENFORCEMENT';
  if v_count<>1 then
    raise exception 'LF_PROFILE_UPDATE_POST_MERGE_BINDING_VERIFY_FAILED:%',v_count;
  end if;
end;
$verification$;

