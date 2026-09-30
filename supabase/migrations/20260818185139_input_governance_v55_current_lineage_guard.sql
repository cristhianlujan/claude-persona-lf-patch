create or replace function programacion.fn_input_readiness_run_is_current(p_run_id bigint)
returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_status text;
  v_contract_version integer;
  v_stored_manifest jsonb;
  v_stored_sha text;
  v_current_manifest jsonb;
  v_current_sha text;
  v_has_terminal_successor boolean := false;
begin
  select status,contract_version,source_manifest,source_snapshot_sha256
    into v_status,v_contract_version,v_stored_manifest,v_stored_sha
  from programacion.input_readiness_runs
  where id=p_run_id;

  if v_status<>'COMPLETED' or v_contract_version not in (3,4) or v_stored_sha is null then
    return false;
  end if;

  select exists(
    select 1
    from programacion.input_readiness_runs n
    where n.supersedes_run_id=p_run_id
      and n.status in ('COMPLETED','BLOCKED')
  ) into v_has_terminal_successor;

  if v_has_terminal_successor then
    return false;
  end if;

  v_current_manifest:=programacion.fn_input_build_source_manifest(p_run_id);
  v_current_sha:=programacion.fn_v09_sha256_jsonb(v_current_manifest);
  return v_current_sha=v_stored_sha and v_current_manifest=v_stored_manifest;
exception when others then
  return false;
end;
$function$;