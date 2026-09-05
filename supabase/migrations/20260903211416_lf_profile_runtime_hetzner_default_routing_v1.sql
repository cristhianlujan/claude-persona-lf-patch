begin;

alter table private.lf_profile_runtime_queue_v1
  alter column runtime_target set default 'HETZNER';

create or replace function private.fn_lf_profile_runtime_default_route_v1()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if new.runtime_target = 'HETZNER'
     and new.runtime_request_envelope is null
     and (
       new.input_image_base64 is not null
       or new.input_image_media_type is not null
       or new.input_image_sha256 is not null
     ) then
    new.runtime_target := 'GITHUB_ACTIONS';
  end if;
  return new;
end;
$function$;

revoke all on function private.fn_lf_profile_runtime_default_route_v1() from public;

drop trigger if exists trg_lf_profile_runtime_default_route_v1
  on private.lf_profile_runtime_queue_v1;
create trigger trg_lf_profile_runtime_default_route_v1
before insert on private.lf_profile_runtime_queue_v1
for each row execute function private.fn_lf_profile_runtime_default_route_v1();

create or replace function private.fn_lf_profile_runtime_claim_guard_v1()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if old.runtime_target = 'HETZNER'
     and new.status = 'RUNNING'
     and new.github_run_id is not null then
    raise exception using
      errcode = '23514',
      message = 'HETZNER_REQUEST_GITHUB_CLAIM_FORBIDDEN';
  end if;
  return new;
end;
$function$;

revoke all on function private.fn_lf_profile_runtime_claim_guard_v1() from public;

drop trigger if exists trg_lf_profile_runtime_claim_guard_v1
  on private.lf_profile_runtime_queue_v1;
create trigger trg_lf_profile_runtime_claim_guard_v1
before update on private.lf_profile_runtime_queue_v1
for each row execute function private.fn_lf_profile_runtime_claim_guard_v1();

comment on column private.lf_profile_runtime_queue_v1.runtime_target is
  'Execution transport. Default HETZNER for queue-native text profiles; GITHUB_ACTIONS remains explicit fallback and automatic fallback for image rows without governed envelope.';

commit;
