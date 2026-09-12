-- PR93 P0: atomically reconcile HMAC alert attempts with durable receipts.
-- Applied first to LF_SUPABASE_SANDBOX as migration
-- pr93_p0_hmac_attempt_receipt_reconciliation_v5.

begin;

alter table private.lf_architecture_notification_attempts_v4
  add column if not exists completed_at timestamptz,
  add column if not exists success boolean,
  add column if not exists http_status integer,
  add column if not exists response_body_sha256 text,
  add column if not exists receipt_id bigint,
  add column if not exists completion_source text;

alter table private.lf_architecture_notification_attempts_v4
  alter column request_body_sha256 drop not null;

alter table private.lf_architecture_notification_attempts_v4
  drop constraint if exists lf_architecture_notification_attempts_v4_attempt_status_check;

alter table private.lf_architecture_notification_attempts_v4
  add constraint lf_architecture_notification_attempts_v4_attempt_status_check
  check (attempt_status = any (array[
    'PENDING'::text,
    'SUBMITTED'::text,
    'DELIVERED'::text,
    'REJECTED'::text,
    'FAILED'::text,
    'RECONCILED_DELIVERED'::text
  ]));

alter table private.lf_architecture_notification_attempts_v4
  add constraint lf_architecture_notification_attempts_v4_http_status_check
  check (http_status is null or http_status between 100 and 599),
  add constraint lf_architecture_notification_attempts_v4_response_body_sha256_check
  check (response_body_sha256 is null or response_body_sha256 ~ '^[0-9a-f]{64}$'),
  add constraint lf_architecture_notification_attempts_v4_receipt_id_fkey
  foreign key (receipt_id) references private.lf_architecture_notification_receipts_v4(id),
  add constraint lf_architecture_notification_attempts_v4_completion_source_check
  check (completion_source is null or completion_source = any (array[
    'RECEIPT_ATOMIC'::text,
    'HISTORICAL_OUTBOX_RECEIPT'::text,
    'DISPATCH_EXCEPTION'::text
  ]));

with latest_delivered as (
  select distinct on (outbox_id)
    id,
    outbox_id,
    http_status,
    response_sha256,
    received_at
  from private.lf_architecture_notification_receipts_v4
  where receipt_status = 'DELIVERED'
  order by outbox_id, id desc
)
update private.lf_architecture_notification_attempts_v4 a
set attempt_status = 'RECONCILED_DELIVERED',
    completed_at = r.received_at,
    success = true,
    http_status = r.http_status,
    response_body_sha256 = r.response_sha256,
    receipt_id = r.id,
    completion_source = 'HISTORICAL_OUTBOX_RECEIPT'
from latest_delivered r
where a.outbox_id = r.outbox_id
  and a.attempt_status = 'SUBMITTED'
  and a.completed_at is null;

update private.lf_architecture_notification_attempts_v4
set completed_at = created_at,
    success = false,
    completion_source = 'DISPATCH_EXCEPTION'
where attempt_status = 'FAILED'
  and completed_at is null;

alter table private.lf_architecture_notification_attempts_v4
  add constraint lf_architecture_notification_attempts_v4_lifecycle_check
  check (
    (
      attempt_status = 'PENDING'
      and request_id is null
      and request_body_sha256 is null
      and completed_at is null
      and success is null
      and http_status is null
      and response_body_sha256 is null
      and receipt_id is null
      and completion_source is null
    )
    or
    (
      attempt_status = 'SUBMITTED'
      and request_id is not null
      and request_body_sha256 ~ '^[0-9a-f]{64}$'
      and completed_at is null
      and success is null
      and http_status is null
      and response_body_sha256 is null
      and receipt_id is null
      and completion_source is null
    )
    or
    (
      attempt_status in ('DELIVERED','RECONCILED_DELIVERED')
      and completed_at is not null
      and success is true
      and http_status between 200 and 299
      and response_body_sha256 ~ '^[0-9a-f]{64}$'
      and receipt_id is not null
      and completion_source in ('RECEIPT_ATOMIC','HISTORICAL_OUTBOX_RECEIPT')
    )
    or
    (
      attempt_status = 'REJECTED'
      and completed_at is not null
      and success is false
      and http_status between 100 and 599
      and not (http_status between 200 and 299)
      and response_body_sha256 ~ '^[0-9a-f]{64}$'
      and receipt_id is not null
      and completion_source = 'RECEIPT_ATOMIC'
    )
    or
    (
      attempt_status = 'FAILED'
      and completed_at is not null
      and success is false
      and receipt_id is null
      and completion_source = 'DISPATCH_EXCEPTION'
    )
  );

create index if not exists idx_lf_architecture_attempts_v4_open
  on private.lf_architecture_notification_attempts_v4(outbox_id, created_at desc)
  where completed_at is null;

create index if not exists idx_lf_architecture_attempts_v4_receipt
  on private.lf_architecture_notification_attempts_v4(receipt_id)
  where receipt_id is not null;

create or replace function public.record_lf_alert_delivery_receipt_v5(
  p_attempt_id bigint,
  p_outbox_id bigint,
  p_payload_sha256 text,
  p_signature text,
  p_http_status integer,
  p_response_body_sha256 text,
  p_details jsonb,
  p_execution_id text
)
returns bigint
language plpgsql
security definer
set search_path = 'pg_catalog', 'private', 'extensions'
as $function$
declare
  v_secret bytea;
  v_expected text;
  v_outbox_sha text;
  v_receipt_status text;
  v_receipt_id bigint;
  v_attempt private.lf_architecture_notification_attempts_v4%rowtype;
begin
  if p_attempt_id is null or p_attempt_id <= 0
     or p_outbox_id is null or p_outbox_id <= 0
     or coalesce(p_payload_sha256,'') !~ '^[0-9a-f]{64}$'
     or coalesce(p_signature,'') !~ '^[0-9a-f]{64}$'
     or p_http_status not between 100 and 599
     or coalesce(p_response_body_sha256,'') !~ '^[0-9a-f]{64}$'
     or jsonb_typeof(p_details) <> 'object'
     or nullif(btrim(coalesce(p_execution_id,'')),'') is null then
    raise exception using errcode='23514', message='invalid alert delivery receipt v5';
  end if;

  select * into v_attempt
  from private.lf_architecture_notification_attempts_v4
  where id = p_attempt_id and outbox_id = p_outbox_id
  for update;
  if not found then
    raise exception using errcode='28000', message='attempt outbox mismatch';
  end if;

  select payload_sha256 into v_outbox_sha
  from private.lf_architecture_notification_outbox_v4
  where id = p_outbox_id and channel = 'EXTERNAL_HTTP';
  if not found or v_outbox_sha is distinct from p_payload_sha256 then
    raise exception using errcode='28000', message='outbox payload mismatch';
  end if;

  select secret_key into v_secret
  from private.lf_architecture_delivery_secrets_v4
  where secret_id = 1;
  if not found then
    raise exception using errcode='P0002', message='delivery secret missing';
  end if;

  v_expected := encode(
    extensions.hmac(
      convert_to(p_outbox_id::text || ':' || p_payload_sha256, 'UTF8'),
      v_secret,
      'sha256'
    ),
    'hex'
  );
  if v_expected <> p_signature or v_attempt.request_signature <> p_signature then
    raise exception using errcode='28000', message='invalid alert delivery signature';
  end if;

  v_receipt_status := case when p_http_status between 200 and 299 then 'DELIVERED' else 'REJECTED' end;

  if v_attempt.completed_at is not null then
    if v_attempt.receipt_id is null
       or v_attempt.success is distinct from (v_receipt_status = 'DELIVERED')
       or v_attempt.http_status is distinct from p_http_status
       or v_attempt.response_body_sha256 is distinct from p_response_body_sha256 then
      raise exception using errcode='28000', message='attempt replay mismatch';
    end if;
    return v_attempt.receipt_id;
  end if;

  if v_attempt.attempt_status not in ('PENDING','SUBMITTED') then
    raise exception using errcode='28000', message='attempt lifecycle mismatch';
  end if;

  if v_receipt_status = 'DELIVERED' then
    select id into v_receipt_id
    from private.lf_architecture_notification_receipts_v4
    where outbox_id = p_outbox_id and receipt_status = 'DELIVERED'
    order by id
    limit 1;
  end if;

  if v_receipt_id is null then
    insert into private.lf_architecture_notification_receipts_v4(
      outbox_id,
      receipt_status,
      http_status,
      payload_sha256,
      response_sha256,
      details,
      received_by_execution_id
    ) values (
      p_outbox_id,
      v_receipt_status,
      p_http_status,
      p_payload_sha256,
      p_response_body_sha256,
      p_details,
      p_execution_id
    ) returning id into v_receipt_id;
  end if;

  update private.lf_architecture_notification_attempts_v4
  set attempt_status = v_receipt_status,
      completed_at = clock_timestamp(),
      success = (v_receipt_status = 'DELIVERED'),
      http_status = p_http_status,
      response_body_sha256 = p_response_body_sha256,
      receipt_id = v_receipt_id,
      completion_source = 'RECEIPT_ATOMIC',
      error_message = case
        when v_receipt_status = 'REJECTED' then 'HTTP_' || p_http_status::text
        else null
      end
  where id = p_attempt_id;

  return v_receipt_id;
end
$function$;

revoke all on function public.record_lf_alert_delivery_receipt_v5(bigint,bigint,text,text,integer,text,jsonb,text) from public, anon, authenticated;
grant execute on function public.record_lf_alert_delivery_receipt_v5(bigint,bigint,text,text,integer,text,jsonb,text) to service_role;

create or replace function private.fn_dispatch_architecture_outbox_v4(
  p_execution_id text,
  p_limit integer default 20
)
returns integer
language plpgsql
security definer
set search_path = 'pg_catalog', 'private', 'extensions', 'net'
as $function$
declare
  r record;
  v_secret bytea;
  v_signature text;
  v_body jsonb;
  v_body_sha text;
  v_request_id bigint;
  v_attempt_id bigint;
  v_count integer := 0;
  v_endpoint constant text := 'https://mhwmirqcgxxukpctffuv.supabase.co/functions/v1/lf-architecture-alert-sink-v4';
begin
  if nullif(btrim(coalesce(p_execution_id,'')),'') is null or p_limit < 1 or p_limit > 100 then
    raise exception using errcode='23514', message='dispatch requires execution_id and limit 1..100';
  end if;

  select secret_key into v_secret
  from private.lf_architecture_delivery_secrets_v4
  where secret_id = 1;
  if not found then
    raise exception using errcode='P0002', message='delivery secret missing';
  end if;

  for r in
    select o.*
    from private.lf_architecture_notification_outbox_v4 o
    where o.channel = 'EXTERNAL_HTTP'
      and not exists (
        select 1
        from private.lf_architecture_notification_receipts_v4 x
        where x.outbox_id = o.id and x.receipt_status = 'DELIVERED'
      )
      and not exists (
        select 1
        from private.lf_architecture_notification_attempts_v4 a
        where a.outbox_id = o.id
          and a.attempt_status in ('PENDING','SUBMITTED')
          and a.completed_at is null
          and a.created_at > clock_timestamp() - interval '5 minutes'
      )
    order by o.id
    limit p_limit
    for update skip locked
  loop
    v_signature := encode(
      extensions.hmac(
        convert_to(r.id::text || ':' || r.payload_sha256, 'UTF8'),
        v_secret,
        'sha256'
      ),
      'hex'
    );

    insert into private.lf_architecture_notification_attempts_v4(
      outbox_id,
      request_id,
      endpoint,
      attempt_status,
      request_signature,
      request_body_sha256,
      error_message,
      created_by_execution_id
    ) values (
      r.id,
      null,
      v_endpoint,
      'PENDING',
      v_signature,
      null,
      null,
      p_execution_id
    ) returning id into v_attempt_id;

    v_body := jsonb_build_object(
      'delivery_schema_version','lf-architecture-alert-delivery/v5',
      'attempt_id',v_attempt_id,
      'outbox_id',r.id,
      'alert_id',r.alert_id,
      'payload_sha256',r.payload_sha256,
      'signature',v_signature,
      'payload',r.payload,
      'created_at',r.created_at
    );
    v_body_sha := encode(extensions.digest(convert_to(v_body::text,'UTF8'),'sha256'),'hex');

    begin
      v_request_id := net.http_post(
        v_endpoint,
        v_body,
        '{}'::jsonb,
        jsonb_build_object('Content-Type','application/json'),
        5000
      );

      update private.lf_architecture_notification_attempts_v4
      set request_id = v_request_id,
          request_body_sha256 = v_body_sha,
          attempt_status = 'SUBMITTED'
      where id = v_attempt_id;
      v_count := v_count + 1;
    exception when others then
      update private.lf_architecture_notification_attempts_v4
      set request_body_sha256 = v_body_sha,
          attempt_status = 'FAILED',
          error_message = sqlerrm,
          completed_at = clock_timestamp(),
          success = false,
          completion_source = 'DISPATCH_EXCEPTION'
      where id = v_attempt_id;
    end;
  end loop;

  return v_count;
end
$function$;

revoke all on function private.fn_dispatch_architecture_outbox_v4(text,integer) from public, anon, authenticated, service_role;
grant execute on function private.fn_dispatch_architecture_outbox_v4(text,integer) to postgres;

commit;
