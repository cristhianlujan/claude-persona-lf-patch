-- LF_CARD_CREATION_DEFAULT_DESTINATION_V1
-- Root fix for CREACION_CARD_LF destination_validate.
-- Canonical repo matrix authorizes /cards/; prior successful Card executions use cards/<domain>/<slug>/CARD.md.
-- This migration installs only the reconciliation function. The row is materialized later under a real
-- CREACION_CARD_LF execution id so provenance is not synthetic.

create or replace function public.lf_card_creation_destination_reconcile_v1(p_execution_id text)
returns jsonb
language plpgsql
set search_path to 'pg_catalog','public'
as $$
declare
  e public.lf_operation_execution%rowtype;
  v_other_active integer := 0;
  v_result jsonb;
begin
  select * into e
  from public.lf_operation_execution
  where execution_id=p_execution_id
  for update;

  if not found
     or e.operation_code<>'CREACION_CARD_LF'
     or e.target_type<>'CARD'
     or e.status<>'IN_PROGRESS' then
    return jsonb_build_object(
      'valid',false,
      'code','CARD_DESTINATION_RECONCILE_EXECUTION_INVALID'
    );
  end if;

  select count(*) into v_other_active
  from public.lf_artifact_destination_registry
  where operation_code='CREACION_CARD_LF'
    and artifact_type='CARD'
    and status='ACTIVE'
    and destination_code<>'DEST_CREACION_CARD_LF_DEFAULT';

  if v_other_active>0 then
    return jsonb_build_object(
      'valid',false,
      'code','CARD_DESTINATION_AMBIGUOUS_EXISTING_ACTIVE',
      'other_active_count',v_other_active
    );
  end if;

  insert into public.lf_artifact_destination_registry(
    destination_code,operation_code,artifact_type,domain_key,
    repo,branch,base_folder,filename_prefix,filename_suffix,naming_rule,
    status,priority,notes,package_mode,package_files,template_code,
    required_files,optional_files,pack_selection_policy,
    created_by_execution_id,updated_by_execution_id
  )
  values(
    'DEST_CREACION_CARD_LF_DEFAULT',
    'CREACION_CARD_LF',
    'CARD',
    'DEFAULT',
    'cristhianlujan/claude-persona-lf-patch',
    'main',
    'cards',
    null,
    '.md',
    'SLUG_LOWER_UNDERSCORE',
    'ACTIVE',
    100,
    'Default governed destination for LF Cards. Canonical matrix authorizes /cards/. Real Card convention is cards/<domain>/<slug>/CARD.md; target_path must remain under cards/. No /cards/_template dependency.',
    'SINGLE_FILE',
    '[]'::jsonb,
    null,
    '[]'::jsonb,
    '[]'::jsonb,
    'STATIC_SINGLE_FILE',
    p_execution_id,
    p_execution_id
  )
  on conflict(destination_code) do update
  set operation_code=excluded.operation_code,
      artifact_type=excluded.artifact_type,
      domain_key=excluded.domain_key,
      repo=excluded.repo,
      branch=excluded.branch,
      base_folder=excluded.base_folder,
      filename_prefix=excluded.filename_prefix,
      filename_suffix=excluded.filename_suffix,
      naming_rule=excluded.naming_rule,
      status=excluded.status,
      priority=excluded.priority,
      notes=excluded.notes,
      package_mode=excluded.package_mode,
      package_files=excluded.package_files,
      template_code=excluded.template_code,
      required_files=excluded.required_files,
      optional_files=excluded.optional_files,
      pack_selection_policy=excluded.pack_selection_policy,
      updated_by_execution_id=p_execution_id;

  v_result:=public.fn_lf_resolve_artifact_destination_v2(p_execution_id,null);

  return jsonb_build_object(
    'valid',coalesce((v_result->>'ready')::boolean,false),
    'code',case when coalesce((v_result->>'ready')::boolean,false)
                then 'CARD_DEFAULT_DESTINATION_RECONCILED'
                else 'CARD_DEFAULT_DESTINATION_RECONCILE_READBACK_FAILED' end,
    'resolver_readback',v_result,
    'destination_code','DEST_CREACION_CARD_LF_DEFAULT',
    'reconciled_by_execution_id',p_execution_id
  );
end
$$;
