do $$
declare
  v_ddl text;
  v_old text := $old$    union all
    select jsonb_build_object('kind','API_CONTRACT_RESOLUTION_V1','pantalla_id',v_run.pantalla_id)
  )$old$;
  v_new text := $new$    union all
    select jsonb_build_object('kind','API_CONTRACT_RESOLUTION_V1','pantalla_id',v_run.pantalla_id)
    union all
    select jsonb_build_object('kind','INPUT_FRESHNESS_DELTA_V1','run_id',v_run.id)
  )$new$;
begin
  select pg_get_functiondef(p.oid) into v_ddl
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion' and p.proname='fn_input_context_manifest';
  if v_ddl is null or position(v_old in v_ddl)=0 then
    raise exception 'INPUT_CONTEXT_MANIFEST_HANDLE_PATCH_TARGET_NOT_FOUND';
  end if;
  execute replace(v_ddl,v_old,v_new);
end;
$$;

create or replace function programacion.fn_input_resolve_retrieval_handle(
  p_run_id bigint,
  p_handle jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, programacion, lf_ops
as $$
declare
  v_run programacion.input_readiness_runs%rowtype;
  v_manifest jsonb;
  v_kind text;
  v_payload jsonb;
  v_ref jsonb;
  v_receipt jsonb;
begin
  if jsonb_typeof(p_handle)<>'object' then
    raise exception 'INPUT_RETRIEVAL_HANDLE_MUST_BE_OBJECT';
  end if;
  select * into v_run from programacion.input_readiness_runs where id=p_run_id;
  if not found then raise exception 'INPUT_RETRIEVAL_RUN_NOT_FOUND:%',p_run_id; end if;

  -- Manifest generation enforces COMPLETED + CURRENT and therefore pins the authorized handle universe.
  v_manifest:=programacion.fn_input_context_manifest(p_run_id);
  if not exists(
    select 1 from jsonb_array_elements(v_manifest->'retrieval_handles') e(value)
    where e.value=p_handle
  ) then
    raise exception 'INPUT_RETRIEVAL_HANDLE_NOT_AUTHORIZED_FOR_RUN:%:%',p_run_id,p_handle::text;
  end if;

  v_kind:=p_handle->>'kind';
  case v_kind
    when 'SOURCE_REF' then
      v_ref:=p_handle->'ref';
      if v_ref->>'kind'='SCREEN_CANONICAL_GRAPH' then
        v_payload:=programacion.fn_input_screen_canonical_graph(v_run.pantalla_id,v_run.version_id);
      else
        v_receipt:=programacion.fn_input_resolve_source_ref(v_ref,v_run.pantalla_id,v_run.version_id);
        v_payload:=v_receipt;
      end if;
    when 'SCREEN_CANONICAL_GRAPH' then
      if (p_handle->>'pantalla_id')::integer<>v_run.pantalla_id or (p_handle->>'version_id')::bigint<>v_run.version_id then
        raise exception 'INPUT_RETRIEVAL_SCREEN_GRAPH_HANDLE_IDENTITY_MISMATCH';
      end if;
      v_payload:=programacion.fn_input_screen_canonical_graph(v_run.pantalla_id,v_run.version_id);
    when 'DESIGN_BINDING_GRAPH_V2' then
      if (p_handle->>'pantalla_id')::integer<>v_run.pantalla_id then
        raise exception 'INPUT_RETRIEVAL_DESIGN_HANDLE_IDENTITY_MISMATCH';
      end if;
      v_payload:=programacion.fn_input_design_binding_graph_v2(v_run.pantalla_id);
    when 'API_CONTRACT_RESOLUTION_V1' then
      if (p_handle->>'pantalla_id')::integer<>v_run.pantalla_id then
        raise exception 'INPUT_RETRIEVAL_API_HANDLE_IDENTITY_MISMATCH';
      end if;
      v_payload:=programacion.fn_input_api_contract_resolution(v_run.pantalla_id);
    when 'INPUT_FRESHNESS_DELTA_V1' then
      if (p_handle->>'run_id')::bigint<>p_run_id then
        raise exception 'INPUT_RETRIEVAL_FRESHNESS_HANDLE_IDENTITY_MISMATCH';
      end if;
      v_payload:=programacion.fn_input_freshness_delta(p_run_id);
    else
      raise exception 'INPUT_RETRIEVAL_HANDLE_KIND_UNSUPPORTED:%',coalesce(v_kind,'NULL');
  end case;

  return jsonb_build_object(
    'retrieval_contract','INPUT_RETRIEVAL_HANDLE_V1',
    'run_id',p_run_id,
    'handle',p_handle,
    'resolved_at',now(),
    'payload_sha256',programacion.fn_v09_sha256_jsonb(v_payload),
    'payload',v_payload
  );
end;
$$;

revoke all on function programacion.fn_input_resolve_retrieval_handle(bigint,jsonb) from public;

insert into programacion.contratos(
  version_id,contrato_codigo,tipo,nombre,descripcion,productor_componente_id,consumidor_componente_id,
  especificacion,fail_closed,estado
)
select 18,
       'INPUT_RETRIEVAL_HANDLE_CONTRACT',
       'RETRIEVAL_INTERFACE',
       'Input Governance JIT retrieval handles',
       'Resolver read-only y fail-closed para handles emitidos por INPUT_CONTEXT_MANIFEST_V1. Solo permite recuperar fuentes/graphs autorizados por el run completed/current.',
       45,
       null,
       jsonb_build_object(
         'schema_version',1,
         'contract_revision','1.0',
         'retrieval_contract','INPUT_RETRIEVAL_HANDLE_V1',
         'authorization','HANDLE_MUST_EXIST_IN_CURRENT_INPUT_CONTEXT_MANIFEST',
         'supported_kinds',jsonb_build_array('SOURCE_REF','SCREEN_CANONICAL_GRAPH','DESIGN_BINDING_GRAPH_V2','API_CONTRACT_RESOLUTION_V1','INPUT_FRESHNESS_DELTA_V1'),
         'mode','READ_ONLY_JIT',
         'arbitrary_source_fetch','DENY',
         'stale_run_fetch','DENY',
         'runtime_secret_fetch','DENY_BY_SOURCE_SCOPE',
         'persistence','NONE_AT_INPUT_GOVERNANCE_LAYER',
         'downstream_retrieval_audit','USE_EXISTING programacion.retrieval_runs/items WHEN execution_id EXISTS',
         'fail_closed',true
       ),
       true,
       'defined'
where not exists(
  select 1 from programacion.contratos
  where version_id=18 and contrato_codigo='INPUT_RETRIEVAL_HANDLE_CONTRACT'
);