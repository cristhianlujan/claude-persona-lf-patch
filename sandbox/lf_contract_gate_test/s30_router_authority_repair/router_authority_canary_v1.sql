begin;

-- Invalid distribution modes must fail closed before policy selection.
do $canary$
declare
  v_mode text;
  v_result jsonb;
begin
  foreach v_mode in array array['BYPASS','router','ROUTER ',' ROUTER','UNSUPPORTED_MODE']::text[]
  loop
    v_result := public.lf_router_resolve_v1(
      'Ejecutar skill ACT-0043',
      null,
      'SKILL_EXECUTION',
      'SKILL',
      v_mode
    );
    if coalesce(v_result->>'status','') <> 'BLOCKED'
       or coalesce(v_result->>'blocking_code','') <> 'BLOCK_UNSUPPORTED_DISTRIBUTION_MODE' then
      raise exception 'S30_ROUTER_INVALID_MODE_NOT_FAIL_CLOSED:%:%',v_mode,v_result;
    end if;
  end loop;

  v_result := public.lf_router_resolve_v1(
    'Ejecutar skill ACT-0043',
    null,
    'SKILL_EXECUTION',
    'SKILL',
    null
  );
  if coalesce(v_result->>'status','') <> 'BLOCKED'
     or coalesce(v_result->>'blocking_code','') <> 'BLOCK_UNSUPPORTED_DISTRIBUTION_MODE' then
    raise exception 'S30_ROUTER_NULL_MODE_NOT_FAIL_CLOSED:%',v_result;
  end if;
end
$canary$;

-- Contradictory target_hint is backward-compatible input only; it must not control discovery.
do $canary$
declare
  v_result jsonb;
  v_asset_code text;
begin
  v_result := public.lf_router_resolve_v1(
    'Ejecutar skill ACT-0043',
    'ACT-0036',
    'SKILL_EXECUTION',
    'SKILL',
    'ROUTER'
  );
  v_asset_code := coalesce(v_result#>>'{asset,codigo_activo}',v_result->>'asset_code');
  if v_asset_code = 'ACT-0036' then
    raise exception 'S30_ROUTER_TARGET_HINT_STILL_AUTHORITATIVE:%',v_result;
  end if;
  if v_asset_code is distinct from 'ACT-0043' then
    raise exception 'S30_ROUTER_REQUEST_TARGET_NOT_RESOLVED:%',v_result;
  end if;
end
$canary$;

-- The internal Router core must not be callable by service_role.
do $canary$
begin
  if has_function_privilege(
    'service_role',
    'public.lf_router_resolve_core_v1(text,text,text,text,text)',
    'EXECUTE'
  ) then
    raise exception 'S30_ROUTER_CORE_SERVICE_ROLE_EXECUTE_STILL_GRANTED';
  end if;
end
$canary$;

-- Generic reservation without a structurally replayable Router request must stop
-- before any execution row can be inserted.
do $canary$
begin
  begin
    perform public.fn_lf_operation_reserve_execution_v1(
      'EXEC-S30-ROUTER-AUTHORITY-CANARY-NO-PROV',
      'EJECUCION_SKILL_LF',
      'SKILL',
      'ACT-0043',
      'S30-ROUTER-AUTHORITY-CANARY-NO-PROV',
      repeat('0',64),
      'EXEC-S30-ROUTER-AUTHORITY-CANARY-NO-PROV',
      null,
      null,
      '{}'::jsonb
    );
    raise exception 'S30_RESERVATION_WITHOUT_ROUTER_PROVENANCE_WAS_ACCEPTED';
  exception
    when others then
      if sqlerrm not like 'ROUTER_PROVENANCE_REQUIRED%' then
        raise;
      end if;
  end;
end
$canary$;

-- The internal reservation core must not be callable by service_role.
do $canary$
begin
  if has_function_privilege(
    'service_role',
    'public.fn_lf_operation_reserve_execution_core_v1(text,text,text,text,text,text,text,text,text,jsonb)',
    'EXECUTE'
  ) then
    raise exception 'S30_RESERVATION_CORE_SERVICE_ROLE_EXECUTE_STILL_GRANTED';
  end if;
end
$canary$;

rollback;
