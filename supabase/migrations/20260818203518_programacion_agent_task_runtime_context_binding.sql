create or replace function programacion.fn_agent_task_runtime_context(p_execution_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, programacion
as $function$
declare
  v_execution programacion.ejecuciones%rowtype;
  v_context programacion.context_packs%rowtype;
  v_preimage jsonb;
  v_runtime_sha256 text;
begin
  select * into v_execution
  from programacion.ejecuciones
  where id=p_execution_id;

  if not found then
    raise exception 'RUNTIME_CONTEXT_EXECUTION_NOT_FOUND: %',p_execution_id;
  end if;
  if v_execution.estado<>'RUNNING' then
    raise exception 'RUNTIME_CONTEXT_EXECUTION_NOT_RUNNING: %',v_execution.estado;
  end if;
  if v_execution.request_ref is null or v_execution.request_ref!~'^agent-task://[1-9][0-9]*$' then
    raise exception 'RUNTIME_CONTEXT_AGENT_TASK_REQUEST_REQUIRED';
  end if;
  if coalesce(v_execution.scope->>'bundle_sha256','')!~'^[0-9a-f]{64}$' then
    raise exception 'RUNTIME_CONTEXT_BUNDLE_PIN_MISSING';
  end if;

  select * into v_context
  from programacion.context_packs
  where execution_id=v_execution.id;

  if not found then
    raise exception 'RUNTIME_CONTEXT_PACK_NOT_FOUND: %',v_execution.id;
  end if;
  if v_context.estado<>'COMPLETE' then
    raise exception 'RUNTIME_CONTEXT_PACK_NOT_COMPLETE: %',v_context.estado;
  end if;
  if v_context.digest_version<>2 then
    raise exception 'RUNTIME_CONTEXT_PACK_V2_REQUIRED: %',v_context.digest_version;
  end if;

  v_preimage:=jsonb_build_object(
    'schema_version',1,
    'execution_id',v_execution.id,
    'request_ref',v_execution.request_ref,
    'repo_full_name',v_execution.repo_full_name,
    'head_sha',v_execution.head_sha,
    'source_snapshot_sha256',v_execution.source_snapshot_sha256,
    'bundle_sha256',v_execution.scope->>'bundle_sha256',
    'context_pack',jsonb_build_object(
      'id',v_context.id,
      'execution_id',v_context.execution_id,
      'estado',v_context.estado,
      'digest_version',v_context.digest_version,
      'repository_inventory',v_context.repository_inventory,
      'dependency_inventory',v_context.dependency_inventory,
      'architecture_inventory',v_context.architecture_inventory,
      'configuration_inventory',v_context.configuration_inventory,
      'test_inventory',v_context.test_inventory,
      'migration_inventory',v_context.migration_inventory,
      'public_api_inventory',v_context.public_api_inventory,
      'ekb_snapshot',v_context.ekb_snapshot,
      'missing_context',v_context.missing_context,
      'provenance',v_context.provenance,
      'context_sha256',v_context.context_sha256
    )
  );
  v_runtime_sha256:=programacion.fn_v09_sha256_jsonb(v_preimage);
  return v_preimage||jsonb_build_object('runtime_context_sha256',v_runtime_sha256);
end;
$function$;

revoke all on function programacion.fn_agent_task_runtime_context(bigint) from public, anon, authenticated;
grant execute on function programacion.fn_agent_task_runtime_context(bigint) to programacion_builder, programacion_auditor, programacion_verifier;