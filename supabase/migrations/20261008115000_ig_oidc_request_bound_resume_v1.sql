-- IG durable OIDC request continuation. One authenticated workflow run owns one
-- queue request, including polls after 202. No second enqueue on retry.
alter table programacion.ig_direct_requests_v1
  add column if not exists oidc_run_id text;
create unique index if not exists ig_direct_requests_oidc_idempotence_v1_uidx
 on programacion.ig_direct_requests_v1(pantalla_id,consumer,oidc_run_id)
 where oidc_run_id is not null;

create or replace function programacion.fn_input_governance_queue_submit_oidc_v1(
 p_pantalla_id integer,p_consumer text,p_oidc_run_id text)
returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog','programacion','public','lf_ops'
as $submit$
declare v_existing record; v_id bigint;
begin
 if p_pantalla_id is null or p_pantalla_id<1
    or p_consumer not in ('STORY_CREATOR','MANUAL')
    or p_oidc_run_id is null or p_oidc_run_id !~ '^[1-9][0-9]{4,19}$' then
  raise exception 'IG_OIDC_QUEUE_INPUT_INVALID';
 end if;
 if not exists(select 1 from lf_ops.pantallas where id=p_pantalla_id and activa) then
  raise exception 'IG_OIDC_QUEUE_SCREEN_NOT_ACTIVE:%',p_pantalla_id;
 end if;
 perform pg_advisory_xact_lock(hashtextextended(
  'IG_OIDC_QUEUE:'||p_pantalla_id::text||':'||p_consumer,0));
 select id,oidc_run_id,status into v_existing
 from programacion.ig_direct_requests_v1
 where pantalla_id=p_pantalla_id and consumer=p_consumer and status='QUEUED'
 order by id desc limit 1 for update;
 if found then
   if v_existing.oidc_run_id is distinct from p_oidc_run_id then
    raise exception 'IG_OIDC_QUEUE_SCREEN_ALREADY_OWNED';
   end if;
   v_id:=v_existing.id;
 else
   select id into v_id
   from programacion.ig_direct_requests_v1
   where pantalla_id=p_pantalla_id and consumer=p_consumer
     and oidc_run_id=p_oidc_run_id
   order by id desc limit 1;
   if v_id is null then
    insert into programacion.ig_direct_requests_v1(pantalla_id,consumer,oidc_run_id)
    values(p_pantalla_id,p_consumer,p_oidc_run_id) returning id into v_id;
   end if;
 end if;
 return jsonb_build_object(
  'status','RECEIVED','request_id',v_id,'pantalla_id',p_pantalla_id,
  'consumer',p_consumer,'idempotent',true);
end;
$submit$;

create or replace function programacion.fn_input_governance_queue_poll_oidc_v1(
 p_request_id bigint,p_oidc_run_id text)
returns jsonb
language plpgsql stable security definer
set search_path to 'pg_catalog','programacion'
as $poll$
declare v_valid boolean;
begin
 select true into v_valid from programacion.ig_direct_requests_v1
 where id=p_request_id and oidc_run_id=p_oidc_run_id
   and p_oidc_run_id ~ '^[1-9][0-9]{4,19}$';
 if not coalesce(v_valid,false) then
   raise exception 'IG_OIDC_QUEUE_REQUEST_NOT_OWNED';
 end if;
 return programacion.fn_input_governance_queue_read_v1(p_request_id);
end;
$poll$;

revoke all on function programacion.fn_input_governance_queue_submit_oidc_v1(integer,text,text)
 from public,anon,authenticated;
revoke all on function programacion.fn_input_governance_queue_poll_oidc_v1(bigint,text)
 from public,anon,authenticated;
grant execute on function programacion.fn_input_governance_queue_submit_oidc_v1(integer,text,text) to service_role;
grant execute on function programacion.fn_input_governance_queue_poll_oidc_v1(bigint,text) to service_role;

create or replace function public.fn_input_governance_queue_submit_oidc_v1(
 p_pantalla_id integer,p_consumer text,p_oidc_run_id text)
returns jsonb
language sql security definer set search_path to 'pg_catalog'
as $api$
 select programacion.fn_input_governance_queue_submit_oidc_v1(
  p_pantalla_id,p_consumer,p_oidc_run_id);
$api$;
create or replace function public.fn_input_governance_queue_poll_oidc_v1(
 p_request_id bigint,p_oidc_run_id text)
returns jsonb
language sql stable security definer set search_path to 'pg_catalog'
as $api$
 select programacion.fn_input_governance_queue_poll_oidc_v1(
  p_request_id,p_oidc_run_id);
$api$;

revoke all on function public.fn_input_governance_queue_submit_oidc_v1(integer,text,text)
 from public,anon,authenticated;
revoke all on function public.fn_input_governance_queue_poll_oidc_v1(bigint,text)
 from public,anon,authenticated;
grant execute on function public.fn_input_governance_queue_submit_oidc_v1(integer,text,text) to service_role;
grant execute on function public.fn_input_governance_queue_poll_oidc_v1(bigint,text) to service_role;

do $guard$
begin
 if has_function_privilege('anon',
   'public.fn_input_governance_queue_submit_oidc_v1(integer,text,text)','execute')
   or has_function_privilege('authenticated',
   'public.fn_input_governance_queue_poll_oidc_v1(bigint,text)','execute')
   or not has_function_privilege('service_role',
   'public.fn_input_governance_queue_poll_oidc_v1(bigint,text)','execute')
 then raise exception 'IG_OIDC_QUEUE_ACCESS_GUARD_FAILED'; end if;
end;
$guard$;
