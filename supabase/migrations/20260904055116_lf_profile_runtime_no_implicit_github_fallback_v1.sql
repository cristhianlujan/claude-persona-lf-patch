begin;

-- HETZNER is the authoritative/default profile runtime.
-- GitHub Actions remains available only when a caller explicitly targets it.
-- Never silently downgrade an incomplete HETZNER request to the backup runtime.
create or replace function private.fn_lf_profile_runtime_default_route_v1()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if new.runtime_target = 'HETZNER'
     and new.runtime_request_envelope is null then
    raise exception using
      errcode = '23514',
      message = 'HETZNER_REQUEST_ENVELOPE_REQUIRED_NO_IMPLICIT_GITHUB_FALLBACK';
  end if;

  return new;
end;
$function$;

revoke all on function private.fn_lf_profile_runtime_default_route_v1() from public;

comment on column private.lf_profile_runtime_queue_v1.runtime_target is
  'Authoritative execution transport. Default HETZNER. GITHUB_ACTIONS is explicit backup/fallback only; automatic HETZNER-to-GITHUB downgrade is forbidden.';

commit;
