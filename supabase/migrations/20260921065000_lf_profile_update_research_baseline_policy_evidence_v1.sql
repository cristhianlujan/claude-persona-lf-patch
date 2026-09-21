begin;

CREATE OR REPLACE FUNCTION public.lf_profile_update_post_merge_reconcile_v1(p_execution_id text, p_merge_sha text, p_entrypoint_sha text, p_manifest_sha text, p_profile_pack_id text, p_pr_number integer, p_actor_execution_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
  v_research_mode text;
  v_research_contract jsonb;
  v_change_scope jsonb;
  v_research_policy_source text;
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

  select es.evidence_payload into v_change_scope
  from public.lf_operation_execution_steps es
  where es.execution_id=p_execution_id
    and es.step_id='change_scope'
    and es.status=(
      select b.clean_result_value
      from public.lf_operation_step_judge_bindings b
      where b.operation_code='ACTUALIZACION_PERFIL_LF'
        and b.step_id='change_scope'
        and b.status='ACTIVE_ENFORCEMENT'
      limit 1
    );

  if v_change_scope is null or jsonb_typeof(v_change_scope)<>'object' then
    raise exception 'LF_PROFILE_UPDATE_RECONCILE_CHANGE_SCOPE_NOT_CLEAN';
  end if;

  if (v_change_scope ? 'research_baseline_contract') and not (v_change_scope ? 'research_baseline_mode') then
    raise exception 'LF_PROFILE_UPDATE_RECONCILE_RESEARCH_BASELINE_POLICY_PARTIAL';
  end if;

  if v_change_scope ? 'research_baseline_mode' then
    v_research_mode:=nullif(v_change_scope->>'research_baseline_mode','');
    v_research_contract:=v_change_scope->'research_baseline_contract';
    v_research_policy_source:='CHANGE_SCOPE_EVIDENCE';
  else
    v_research_mode:=coalesce(nullif(x.manifest->>'research_baseline_mode',''),'NOT_REQUIRED');
    v_research_contract:=x.manifest->'research_baseline_contract';
    v_research_policy_source:=case
      when x.manifest ? 'research_baseline_mode' then 'EXECUTION_MANIFEST'
      else 'DEFAULT_NOT_REQUIRED'
    end;
  end if;

  if v_research_mode not in ('NOT_REQUIRED','PRE_RESEARCH_ALWAYS') then
    raise exception 'LF_PROFILE_UPDATE_RECONCILE_RESEARCH_BASELINE_MODE_INVALID:%',v_research_mode;
  end if;
  if v_research_mode='PRE_RESEARCH_ALWAYS' then
    if jsonb_typeof(v_research_contract)<>'object'
       or v_research_contract->>'contract_version'<>'PROFILE_RESEARCH_BASELINE_BINDING_V1'
       or nullif(btrim(coalesce(v_research_contract->>'capture_stage','')),'') is null
       or v_research_contract->>'profile_validator_binding'<>'PROFILE_OUTPUT_VALIDATOR_BOUND_V1'
       or jsonb_typeof(v_research_contract->'snapshot_schema')<>'object'
       or octet_length((v_research_contract->'snapshot_schema')::text)>12000
       or jsonb_typeof(v_research_contract->'snapshot_binding_paths')<>'object'
       or exists(
         select 1 from jsonb_each(v_research_contract->'snapshot_binding_paths') b(source,path)
         where source not in ('input_digest','profile_source_digest','evidence_refs','capture_stage')
            or jsonb_typeof(path)<>'array'
            or jsonb_array_length(path)=0
            or jsonb_array_length(path)>12
            or exists(
              select 1 from jsonb_array_elements(path) p(value)
              where jsonb_typeof(value)<>'string' or nullif(btrim(value#>>'{}'),'') is null
            )
       )
       or (select count(*) from (
         select path::text from jsonb_each(v_research_contract->'snapshot_binding_paths') b(source,path)
         group by path::text having count(*)>1
       ) d)>0
       or jsonb_typeof(v_research_contract->'output_snapshot_path')<>'array'
       or jsonb_array_length(v_research_contract->'output_snapshot_path')=0
       or jsonb_typeof(v_research_contract->'output_digest_path')<>'array'
       or jsonb_array_length(v_research_contract->'output_digest_path')=0
       or exists(select 1 from jsonb_array_elements(v_research_contract->'output_snapshot_path') x(value) where jsonb_typeof(value)<>'string' or nullif(btrim(value#>>'{}'),'') is null)
       or exists(select 1 from jsonb_array_elements(v_research_contract->'output_digest_path') x(value) where jsonb_typeof(value)<>'string' or nullif(btrim(value#>>'{}'),'') is null)
    then
      raise exception 'LF_PROFILE_UPDATE_RECONCILE_RESEARCH_BASELINE_CONTRACT_INVALID';
    end if;
  else
    if v_research_contract is not null and v_research_policy_source='CHANGE_SCOPE_EVIDENCE' then
      raise exception 'LF_PROFILE_UPDATE_RECONCILE_RESEARCH_BASELINE_CONTRACT_FORBIDDEN';
    end if;
    v_research_contract:=null;
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
      metadata=(coalesce(metadata,'{}'::jsonb) - 'research_baseline_contract')
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
          'post_merge_next_gate',next_gate,
          'research_baseline_mode',v_research_mode,
          'research_baseline_policy_source',v_research_policy_source
        )
        || case when v_research_mode='PRE_RESEARCH_ALWAYS'
             then jsonb_build_object('research_baseline_contract',v_research_contract)
             else '{}'::jsonb
           end,
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
     or a.metadata->>'last_governed_merge_sha'<>p_merge_sha
     or a.metadata->>'research_baseline_mode' is distinct from v_research_mode
     or (v_research_mode='PRE_RESEARCH_ALWAYS' and a.metadata->'research_baseline_contract' is distinct from v_research_contract)
     or (v_research_mode='NOT_REQUIRED' and a.metadata ? 'research_baseline_contract') then
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
    'research_baseline_policy_reconciled',true,
    'research_baseline_mode',v_research_mode,
    'research_baseline_contract',v_research_contract,
    'research_baseline_policy_source',v_research_policy_source,
    'automatic_promotion',false,
    'next_gate',next_gate
  );
end;
$function$

;

comment on function public.lf_profile_update_post_merge_reconcile_v1(text,text,text,text,text,integer,text) is
'Governed post-merge profile reconciliation. Research baseline policy is sourced from clean change_scope evidence when declared, with execution-manifest/default fallback for compatibility; profile state remains preserved.';

do $post$
begin
  if position('CHANGE_SCOPE_EVIDENCE' in pg_get_functiondef('public.lf_profile_update_post_merge_reconcile_v1(text,text,text,text,text,integer,text)'::regprocedure))=0
     or position('LF_PROFILE_UPDATE_RECONCILE_RESEARCH_BASELINE_POLICY_PARTIAL' in pg_get_functiondef('public.lf_profile_update_post_merge_reconcile_v1(text,text,text,text,text,integer,text)'::regprocedure))=0 then
    raise exception 'LF_PROFILE_UPDATE_RESEARCH_BASELINE_POLICY_EVIDENCE_POSTCHECK_FAILED';
  end if;
end
$post$;

commit;
