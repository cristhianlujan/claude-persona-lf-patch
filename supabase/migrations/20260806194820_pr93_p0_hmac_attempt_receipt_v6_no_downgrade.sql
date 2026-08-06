-- PR93 HMAC delivery V6: attempt-linked signatures, environment config,
-- receiver/dispatcher HTTP semantics, replay controls, and idempotent constraints.


do $preflight$
declare
  v_bad integer;
begin
  if to_regclass('private.lf_architecture_delivery_secrets_v4') is null
     or to_regclass('private.lf_architecture_notification_attempts_v4') is null
     or to_regclass('private.lf_architecture_notification_outbox_v4') is null
     or to_regclass('private.lf_architecture_notification_receipts_v4') is null then
    raise exception using errcode='55000', message='HMAC V6 baseline relations missing';
  end if;

  select count(*) into v_bad
  from private.lf_architecture_delivery_secrets_v4
  where secret_id = 1 and octet_length(secret_key) >= 32;
  if v_bad <> 1 then
    raise exception using errcode='55000', message='HMAC V6 baseline secret invalid';
  end if;

  select count(*) into v_bad
  from private.lf_architecture_notification_outbox_v4
  where payload_sha256 is distinct from
    encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex');
  if v_bad <> 0 then
    raise exception using errcode='55000', message='HMAC V6 outbox payload digest drift';
  end if;

  select count(*) into v_bad
  from private.lf_architecture_notification_attempts_v4
  where completed_at is null;
  if v_bad <> 0 then
    raise exception using errcode='55000', message='HMAC V6 requires zero open legacy attempts';
  end if;
end
$preflight$;

create table if not exists private.lf_architecture_delivery_config_v6 (
  config_id smallint primary key,
  project_ref text not null,
  function_slug text not null,
  enabled boolean not null default false,
  updated_by_execution_id text not null,
  updated_at timestamptz not null default clock_timestamp(),
  constraint lf_architecture_delivery_config_v6_singleton_check check (config_id = 1),
  constraint lf_architecture_delivery_config_v6_project_ref_check check (project_ref ~ '^[a-z0-9]{20}$'),
  constraint lf_architecture_delivery_config_v6_function_slug_check check (function_slug = 'lf-architecture-alert-sink-v4')
);

revoke all on table private.lf_architecture_delivery_config_v6 from public, anon, authenticated, service_role;

alter table private.lf_architecture_delivery_secrets_v4
  add column if not exists is_active boolean not null default false,
  add column if not exists not_before timestamptz not null default clock_timestamp(),
  add column if not exists not_after timestamptz;

alter table private.lf_architecture_delivery_secrets_v4
  drop constraint if exists lf_architecture_delivery_secrets_v4_secret_id_check,
  drop constraint if exists lf_architecture_delivery_secrets_v4_validity_check;

alter table private.lf_architecture_delivery_secrets_v4
  add constraint lf_architecture_delivery_secrets_v4_secret_id_check check (secret_id > 0),
  add constraint lf_architecture_delivery_secrets_v4_validity_check
    check (not_after is null or not_after > not_before);

update private.lf_architecture_delivery_secrets_v4
set is_active = true
where secret_id = 1
  and not exists (
    select 1 from private.lf_architecture_delivery_secrets_v4 where is_active
  );

create unique index if not exists uq_lf_architecture_delivery_secrets_v4_active
  on private.lf_architecture_delivery_secrets_v4 ((1))
  where is_active;

alter table private.lf_architecture_notification_attempts_v4
  add column if not exists delivery_schema_version text,
  add column if not exists signature_issued_at timestamptz,
  add column if not exists signature_nonce uuid,
  add column if not exists secret_version smallint,
  add column if not exists receiver_received_at timestamptz,
  add column if not exists receiver_receipt_id bigint,
  add column if not exists receiver_response_status integer,
  add column if not exists dispatcher_observed_http_status integer,
  add column if not exists dispatcher_response_body_sha256 text;

alter table private.lf_architecture_notification_receipts_v4
  add column if not exists attempt_id bigint,
  add column if not exists delivery_schema_version text,
  add column if not exists signature_nonce uuid,
  add column if not exists secret_version smallint,
  add column if not exists receiver_response_status integer;

alter table private.lf_architecture_notification_receipts_v4
  alter column http_status drop not null;

create unique index if not exists uq_lf_architecture_attempts_v4_signature_nonce
  on private.lf_architecture_notification_attempts_v4(signature_nonce)
  where signature_nonce is not null;
create unique index if not exists uq_lf_architecture_receipts_v4_attempt
  on private.lf_architecture_notification_receipts_v4(attempt_id)
  where attempt_id is not null;
create unique index if not exists uq_lf_architecture_receipts_v4_signature_nonce
  on private.lf_architecture_notification_receipts_v4(signature_nonce)
  where signature_nonce is not null;

alter table private.lf_architecture_notification_attempts_v4
  drop constraint if exists lf_architecture_notification_attempts_v4_http_status_check,
  drop constraint if exists lf_architecture_notification_attempts_v4_response_body_sha256_c,
  drop constraint if exists lf_architecture_notification_attempts_v4_receipt_id_fkey,
  drop constraint if exists lf_architecture_notification_attempts_v4_lifecycle_check,
  drop constraint if exists lf_architecture_notification_attempts_v4_completion_source_chec,
  drop constraint if exists lf_architecture_notification_attempts_v4_receiver_receipt_fkey,
  drop constraint if exists lf_architecture_notification_attempts_v4_secret_version_fkey,
  drop constraint if exists lf_architecture_notification_attempts_v4_v6_fields_check;

alter table private.lf_architecture_notification_attempts_v4
  add constraint lf_architecture_notification_attempts_v4_http_status_check
    check (http_status is null or http_status between 100 and 599),
  add constraint lf_architecture_notification_attempts_v4_response_body_sha256_c
    check (response_body_sha256 is null or response_body_sha256 ~ '^[0-9a-f]{64}$'),
  add constraint lf_architecture_notification_attempts_v4_receipt_id_fkey
    foreign key (receipt_id) references private.lf_architecture_notification_receipts_v4(id),
  add constraint lf_architecture_notification_attempts_v4_receiver_receipt_fkey
    foreign key (receiver_receipt_id) references private.lf_architecture_notification_receipts_v4(id),
  add constraint lf_architecture_notification_attempts_v4_secret_version_fkey
    foreign key (secret_version) references private.lf_architecture_delivery_secrets_v4(secret_id),
  add constraint lf_architecture_notification_attempts_v4_completion_source_chec
    check (
      completion_source is null
      or completion_source in (
        'RECEIPT_ATOMIC',
        'HISTORICAL_OUTBOX_RECEIPT',
        'DISPATCH_EXCEPTION',
        'DISPATCHER_OBSERVED_HTTP'
      )
    ),
  add constraint lf_architecture_notification_attempts_v4_v6_fields_check
    check (
      delivery_schema_version is null
      or (
        delivery_schema_version = 'lf-architecture-alert-delivery/v6'
        and signature_issued_at is not null
        and signature_nonce is not null
        and secret_version is not null
        and (receiver_response_status is null or receiver_response_status between 100 and 599)
        and (dispatcher_observed_http_status is null or dispatcher_observed_http_status between 100 and 599)
        and (
          dispatcher_response_body_sha256 is null
          or dispatcher_response_body_sha256 ~ '^[0-9a-f]{64}$'
        )
      )
    );

alter table private.lf_architecture_notification_receipts_v4
  drop constraint if exists lf_architecture_notification_receipts_v4_http_status_check,
  drop constraint if exists lf_architecture_notification_receipts_v4_receipt_status_check,
  drop constraint if exists lf_architecture_notification_receipts_v4_v6_fields_check,
  drop constraint if exists lf_architecture_notification_receipts_v4_attempt_id_fkey,
  drop constraint if exists lf_architecture_notification_receipts_v4_secret_version_fkey;

alter table private.lf_architecture_notification_receipts_v4
  add constraint lf_architecture_notification_receipts_v4_http_status_check
    check (http_status is null or http_status between 100 and 599),
  add constraint lf_architecture_notification_receipts_v4_receipt_status_check
    check (receipt_status in ('DELIVERED','REJECTED','RECEIVED')),
  add constraint lf_architecture_notification_receipts_v4_attempt_id_fkey
    foreign key (attempt_id) references private.lf_architecture_notification_attempts_v4(id),
  add constraint lf_architecture_notification_receipts_v4_secret_version_fkey
    foreign key (secret_version) references private.lf_architecture_delivery_secrets_v4(secret_id),
  add constraint lf_architecture_notification_receipts_v4_v6_fields_check
    check (
      delivery_schema_version is null
      or (
        delivery_schema_version = 'lf-architecture-alert-delivery/v6'
        and receipt_status = 'RECEIVED'
        and http_status is null
        and attempt_id is not null
        and signature_nonce is not null
        and secret_version is not null
        and receiver_response_status between 200 and 299
      )
    );

alter table private.lf_architecture_notification_attempts_v4
  add constraint lf_architecture_notification_attempts_v4_lifecycle_check
  check (
    (
      delivery_schema_version is null
      and (
        (attempt_status = 'PENDING' and request_id is null and request_body_sha256 is null and completed_at is null and success is null and http_status is null and response_body_sha256 is null and receipt_id is null and completion_source is null)
        or
        (attempt_status = 'SUBMITTED' and request_id is not null and request_body_sha256 ~ '^[0-9a-f]{64}$' and completed_at is null and success is null and http_status is null and response_body_sha256 is null and receipt_id is null and completion_source is null)
        or
        (attempt_status in ('DELIVERED','RECONCILED_DELIVERED') and completed_at is not null and success is true and http_status between 200 and 299 and response_body_sha256 ~ '^[0-9a-f]{64}$' and receipt_id is not null and completion_source in ('RECEIPT_ATOMIC','HISTORICAL_OUTBOX_RECEIPT'))
        or
        (attempt_status = 'REJECTED' and completed_at is not null and success is false and http_status between 100 and 599 and http_status not between 200 and 299 and response_body_sha256 ~ '^[0-9a-f]{64}$' and receipt_id is not null and completion_source = 'RECEIPT_ATOMIC')
        or
        (attempt_status = 'FAILED' and completed_at is not null and success is false and receipt_id is null and completion_source = 'DISPATCH_EXCEPTION')
      )
    )
    or
    (
      delivery_schema_version = 'lf-architecture-alert-delivery/v6'
      and http_status is null
      and response_body_sha256 is null
      and receipt_id is null
      and (
        (
          attempt_status = 'PENDING'
          and request_id is null
          and request_body_sha256 is null
          and completed_at is null
          and success is null
          and receiver_received_at is null
          and receiver_receipt_id is null
          and receiver_response_status is null
          and dispatcher_observed_http_status is null
          and dispatcher_response_body_sha256 is null
          and completion_source is null
        )
        or
        (
          attempt_status = 'SUBMITTED'
          and request_id is not null
          and request_body_sha256 ~ '^[0-9a-f]{64}$'
          and completed_at is null
          and success is null
          and dispatcher_observed_http_status is null
          and dispatcher_response_body_sha256 is null
          and completion_source is null
        )
        or
        (
          attempt_status = 'DELIVERED'
          and completed_at is not null
          and success is true
          and dispatcher_observed_http_status between 200 and 299
          and dispatcher_response_body_sha256 ~ '^[0-9a-f]{64}$'
          and receiver_received_at is not null
          and receiver_receipt_id is not null
          and receiver_response_status between 200 and 299
          and completion_source = 'DISPATCHER_OBSERVED_HTTP'
        )
        or
        (
          attempt_status = 'REJECTED'
          and completed_at is not null
          and success is false
          and dispatcher_observed_http_status between 100 and 599
          and dispatcher_observed_http_status not between 200 and 299
          and dispatcher_response_body_sha256 ~ '^[0-9a-f]{64}$'
          and completion_source = 'DISPATCHER_OBSERVED_HTTP'
        )
        or
        (
          attempt_status = 'FAILED'
          and completed_at is not null
          and success is false
          and (
            (
              completion_source = 'DISPATCH_EXCEPTION'
              and dispatcher_observed_http_status is null
              and dispatcher_response_body_sha256 is null
            )
            or
            (
              completion_source = 'DISPATCHER_OBSERVED_HTTP'
              and dispatcher_response_body_sha256 ~ '^[0-9a-f]{64}$'
            )
          )
        )
      )
    )
  );

create or replace function private.fn_architecture_delivery_preimage_v6(
  p_schema_version text,
  p_outbox_id bigint,
  p_attempt_id bigint,
  p_payload_sha256 text,
  p_issued_at_unix bigint,
  p_nonce uuid,
  p_secret_version smallint
) returns text
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select concat_ws(
    '|',
    'schema=' || p_schema_version,
    'outbox_id=' || p_outbox_id::text,
    'attempt_id=' || p_attempt_id::text,
    'payload_sha256=' || p_payload_sha256,
    'issued_at_unix=' || p_issued_at_unix::text,
    'nonce=' || p_nonce::text,
    'secret_version=' || p_secret_version::text
  )
$$;

revoke all on function private.fn_architecture_delivery_preimage_v6(text,bigint,bigint,text,bigint,uuid,smallint)
  from public, anon, authenticated, service_role;

create or replace function public.record_lf_alert_delivery_receipt_v4(
  p_outbox_id bigint,
  p_payload_sha256 text,
  p_signature text,
  p_http_status integer,
  p_response_sha256 text,
  p_details jsonb,
  p_execution_id text
) returns bigint
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  raise exception using errcode='0A000', message='legacy alert receipt v4 disabled';
end
$$;

create or replace function public.record_lf_alert_delivery_receipt_v5(
  p_attempt_id bigint,
  p_outbox_id bigint,
  p_payload_sha256 text,
  p_signature text,
  p_http_status integer,
  p_response_body_sha256 text,
  p_details jsonb,
  p_execution_id text
) returns bigint
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  raise exception using errcode='0A000', message='legacy alert receipt v5 disabled';
end
$$;

revoke all on function public.record_lf_alert_delivery_receipt_v4(bigint,text,text,integer,text,jsonb,text)
  from public, anon, authenticated, service_role;
revoke all on function public.record_lf_alert_delivery_receipt_v5(bigint,bigint,text,text,integer,text,jsonb,text)
  from public, anon, authenticated, service_role;

create or replace function public.record_lf_alert_delivery_receipt_v6(
  p_delivery_schema_version text,
  p_attempt_id bigint,
  p_outbox_id bigint,
  p_payload_sha256 text,
  p_payload jsonb,
  p_signature text,
  p_signature_issued_at_unix bigint,
  p_signature_nonce uuid,
  p_secret_version smallint,
  p_details jsonb,
  p_execution_id text
) returns bigint
language plpgsql
security definer
set search_path = pg_catalog, private, extensions
as $$
declare
  v_attempt private.lf_architecture_notification_attempts_v4%rowtype;
  v_secret bytea;
  v_outbox_sha text;
  v_payload_sha text;
  v_expected text;
  v_preimage text;
  v_issued_at timestamptz;
  v_receipt_id bigint;
begin
  if p_delivery_schema_version <> 'lf-architecture-alert-delivery/v6'
     or p_attempt_id is null or p_attempt_id <= 0
     or p_outbox_id is null or p_outbox_id <= 0
     or coalesce(p_payload_sha256,'') !~ '^[0-9a-f]{64}$'
     or jsonb_typeof(p_payload) <> 'object'
     or coalesce(p_signature,'') !~ '^[0-9a-f]{64}$'
     or p_signature_issued_at_unix is null or p_signature_issued_at_unix <= 0
     or p_signature_nonce is null
     or p_secret_version is null or p_secret_version <= 0
     or jsonb_typeof(p_details) <> 'object'
     or nullif(btrim(coalesce(p_execution_id,'')),'') is null then
    raise exception using errcode='23514', message='invalid alert delivery receipt v6';
  end if;

  v_issued_at := to_timestamp(p_signature_issued_at_unix);
  if v_issued_at < clock_timestamp() - interval '5 minutes'
     or v_issued_at > clock_timestamp() + interval '30 seconds' then
    raise exception using errcode='28000', message='delivery signature timestamp outside window';
  end if;

  select * into v_attempt
  from private.lf_architecture_notification_attempts_v4
  where id = p_attempt_id and outbox_id = p_outbox_id
  for update;
  if not found then
    raise exception using errcode='28000', message='attempt outbox mismatch';
  end if;

  if v_attempt.delivery_schema_version is distinct from p_delivery_schema_version
     or extract(epoch from v_attempt.signature_issued_at)::bigint <> p_signature_issued_at_unix
     or v_attempt.signature_nonce is distinct from p_signature_nonce
     or v_attempt.secret_version is distinct from p_secret_version
     or v_attempt.request_signature is distinct from p_signature
     or v_attempt.attempt_status <> 'SUBMITTED' then
    raise exception using errcode='28000', message='attempt signature context mismatch';
  end if;

  if v_attempt.receiver_received_at is not null or v_attempt.receiver_receipt_id is not null then
    raise exception using errcode='28000', message='delivery replay rejected';
  end if;

  select payload_sha256 into v_outbox_sha
  from private.lf_architecture_notification_outbox_v4
  where id = p_outbox_id and channel = 'EXTERNAL_HTTP';
  if not found or v_outbox_sha is distinct from p_payload_sha256 then
    raise exception using errcode='28000', message='outbox payload mismatch';
  end if;

  v_payload_sha := encode(extensions.digest(convert_to(p_payload::text,'UTF8'),'sha256'),'hex');
  if v_payload_sha is distinct from p_payload_sha256 then
    raise exception using errcode='28000', message='payload digest mismatch';
  end if;

  select secret_key into v_secret
  from private.lf_architecture_delivery_secrets_v4
  where secret_id = p_secret_version
    and not_before <= v_issued_at
    and (not_after is null or v_issued_at < not_after);
  if not found then
    raise exception using errcode='28000', message='secret version invalid for issuance time';
  end if;

  v_preimage := private.fn_architecture_delivery_preimage_v6(
    p_delivery_schema_version,
    p_outbox_id,
    p_attempt_id,
    p_payload_sha256,
    p_signature_issued_at_unix,
    p_signature_nonce,
    p_secret_version
  );
  v_expected := encode(
    extensions.hmac(convert_to(v_preimage,'UTF8'),v_secret,'sha256'),
    'hex'
  );
  if v_expected <> p_signature then
    raise exception using errcode='28000', message='invalid alert delivery signature v6';
  end if;

  insert into private.lf_architecture_notification_receipts_v4(
    outbox_id,
    receipt_status,
    http_status,
    payload_sha256,
    response_sha256,
    details,
    received_by_execution_id,
    attempt_id,
    delivery_schema_version,
    signature_nonce,
    secret_version,
    receiver_response_status
  ) values (
    p_outbox_id,
    'RECEIVED',
    null,
    p_payload_sha256,
    null,
    p_details || jsonb_build_object(
      'receiver_response_status',202,
      'receiver_semantics','EMITTED_NOT_DISPATCHER_OBSERVED'
    ),
    p_execution_id,
    p_attempt_id,
    p_delivery_schema_version,
    p_signature_nonce,
    p_secret_version,
    202
  ) returning id into v_receipt_id;

  update private.lf_architecture_notification_attempts_v4
  set receiver_received_at = clock_timestamp(),
      receiver_receipt_id = v_receipt_id,
      receiver_response_status = 202
  where id = p_attempt_id;

  return v_receipt_id;
end
$$;

revoke all on function public.record_lf_alert_delivery_receipt_v6(
  text,bigint,bigint,text,jsonb,text,bigint,uuid,smallint,jsonb,text
) from public, anon, authenticated;
grant execute on function public.record_lf_alert_delivery_receipt_v6(
  text,bigint,bigint,text,jsonb,text,bigint,uuid,smallint,jsonb,text
) to service_role;

create or replace function private.fn_reconcile_architecture_delivery_attempts_v6(
  p_execution_id text,
  p_limit integer default 100
) returns integer
language plpgsql
security definer
set search_path = pg_catalog, private, extensions, net
as $$
declare
  r record;
  v_hash text;
  v_count integer := 0;
begin
  if nullif(btrim(coalesce(p_execution_id,'')),'') is null or p_limit < 1 or p_limit > 500 then
    raise exception using errcode='23514', message='reconcile requires execution_id and limit 1..500';
  end if;

  for r in
    select
      a.id as attempt_id,
      a.receiver_receipt_id,
      h.status_code,
      h.content,
      h.timed_out,
      h.error_msg
    from private.lf_architecture_notification_attempts_v4 a
    join net._http_response h on h.id = a.request_id
    where a.delivery_schema_version = 'lf-architecture-alert-delivery/v6'
      and a.attempt_status = 'SUBMITTED'
      and a.completed_at is null
    order by a.id
    limit p_limit
    for update of a skip locked
  loop
    v_hash := encode(
      extensions.digest(convert_to(coalesce(r.content,''),'UTF8'),'sha256'),
      'hex'
    );

    if coalesce(r.timed_out,false) or r.error_msg is not null or r.status_code is null then
      update private.lf_architecture_notification_attempts_v4
      set attempt_status = 'FAILED',
          completed_at = clock_timestamp(),
          success = false,
          dispatcher_observed_http_status = r.status_code,
          dispatcher_response_body_sha256 = v_hash,
          error_message = case
            when coalesce(r.timed_out,false) then 'DISPATCHER_TIMEOUT'
            else 'DISPATCHER_TRANSPORT_ERROR'
          end,
          completion_source = 'DISPATCHER_OBSERVED_HTTP'
      where id = r.attempt_id;
    elsif r.status_code between 200 and 299 and r.receiver_receipt_id is not null then
      update private.lf_architecture_notification_attempts_v4
      set attempt_status = 'DELIVERED',
          completed_at = clock_timestamp(),
          success = true,
          dispatcher_observed_http_status = r.status_code,
          dispatcher_response_body_sha256 = v_hash,
          error_message = null,
          completion_source = 'DISPATCHER_OBSERVED_HTTP'
      where id = r.attempt_id;
    elsif r.status_code between 200 and 299 then
      update private.lf_architecture_notification_attempts_v4
      set attempt_status = 'FAILED',
          completed_at = clock_timestamp(),
          success = false,
          dispatcher_observed_http_status = r.status_code,
          dispatcher_response_body_sha256 = v_hash,
          error_message = 'RECEIVER_RECEIPT_MISSING',
          completion_source = 'DISPATCHER_OBSERVED_HTTP'
      where id = r.attempt_id;
    else
      update private.lf_architecture_notification_attempts_v4
      set attempt_status = 'REJECTED',
          completed_at = clock_timestamp(),
          success = false,
          dispatcher_observed_http_status = r.status_code,
          dispatcher_response_body_sha256 = v_hash,
          error_message = 'HTTP_' || r.status_code::text,
          completion_source = 'DISPATCHER_OBSERVED_HTTP'
      where id = r.attempt_id;
    end if;
    v_count := v_count + 1;
  end loop;

  return v_count;
end
$$;

create or replace function private.fn_dispatch_architecture_outbox_v4(
  p_execution_id text,
  p_limit integer default 20
) returns integer
language plpgsql
security definer
set search_path = pg_catalog, private, extensions, net
as $$
declare
  r record;
  v_config private.lf_architecture_delivery_config_v6%rowtype;
  v_secret bytea;
  v_secret_version smallint;
  v_signature text;
  v_preimage text;
  v_body jsonb;
  v_body_sha text;
  v_request_id bigint;
  v_attempt_id bigint;
  v_count integer := 0;
  v_endpoint text;
  v_issued_at timestamptz;
  v_issued_at_unix bigint;
  v_nonce uuid;
  v_reconciled integer;
begin
  if nullif(btrim(coalesce(p_execution_id,'')),'') is null or p_limit < 1 or p_limit > 100 then
    raise exception using errcode='23514', message='dispatch requires execution_id and limit 1..100';
  end if;

  select * into v_config
  from private.lf_architecture_delivery_config_v6
  where config_id = 1 and enabled;
  if not found then
    raise exception using errcode='P0002', message='delivery endpoint configuration missing or disabled';
  end if;
  v_endpoint := format(
    'https://%s.supabase.co/functions/v1/%s',
    v_config.project_ref,
    v_config.function_slug
  );

  select secret_id, secret_key into v_secret_version, v_secret
  from private.lf_architecture_delivery_secrets_v4
  where is_active
    and not_before <= clock_timestamp()
    and (not_after is null or clock_timestamp() < not_after);
  if not found then
    raise exception using errcode='P0002', message='active delivery secret missing';
  end if;

  v_reconciled := private.fn_reconcile_architecture_delivery_attempts_v6(
    p_execution_id || '-RECONCILE',
    100
  );

  for r in
    select o.*
    from private.lf_architecture_notification_outbox_v4 o
    where o.channel = 'EXTERNAL_HTTP'
      and not exists (
        select 1 from private.lf_architecture_notification_attempts_v4 a
        where a.outbox_id = o.id
          and a.delivery_schema_version = 'lf-architecture-alert-delivery/v6'
          and a.attempt_status = 'DELIVERED'
      )
      and not exists (
        select 1 from private.lf_architecture_notification_attempts_v4 a
        where a.outbox_id = o.id
          and a.attempt_status in ('PENDING','SUBMITTED')
          and a.completed_at is null
          and a.created_at > clock_timestamp() - interval '5 minutes'
      )
    order by o.id
    limit p_limit
    for update skip locked
  loop
    v_issued_at := date_trunc('second',clock_timestamp());
    v_issued_at_unix := extract(epoch from v_issued_at)::bigint;
    v_nonce := extensions.gen_random_uuid();

    insert into private.lf_architecture_notification_attempts_v4(
      outbox_id,
      request_id,
      endpoint,
      attempt_status,
      request_signature,
      request_body_sha256,
      error_message,
      created_by_execution_id,
      delivery_schema_version,
      signature_issued_at,
      signature_nonce,
      secret_version
    ) values (
      r.id,
      null,
      v_endpoint,
      'PENDING',
      repeat('0',64),
      null,
      null,
      p_execution_id,
      'lf-architecture-alert-delivery/v6',
      v_issued_at,
      v_nonce,
      v_secret_version
    ) returning id into v_attempt_id;

    v_preimage := private.fn_architecture_delivery_preimage_v6(
      'lf-architecture-alert-delivery/v6',
      r.id,
      v_attempt_id,
      r.payload_sha256,
      v_issued_at_unix,
      v_nonce,
      v_secret_version
    );
    v_signature := encode(
      extensions.hmac(convert_to(v_preimage,'UTF8'),v_secret,'sha256'),
      'hex'
    );

    update private.lf_architecture_notification_attempts_v4
    set request_signature = v_signature
    where id = v_attempt_id;

    v_body := jsonb_build_object(
      'delivery_schema_version','lf-architecture-alert-delivery/v6',
      'attempt_id',v_attempt_id,
      'outbox_id',r.id,
      'alert_id',r.alert_id,
      'payload_sha256',r.payload_sha256,
      'payload',r.payload,
      'signature',v_signature,
      'signature_issued_at_unix',v_issued_at_unix,
      'signature_nonce',v_nonce,
      'secret_version',v_secret_version
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
          error_message = 'DISPATCH_EXCEPTION',
          completed_at = clock_timestamp(),
          success = false,
          completion_source = 'DISPATCH_EXCEPTION'
      where id = v_attempt_id;
    end;
  end loop;

  return v_count;
end
$$;

revoke all on function private.fn_dispatch_architecture_outbox_v4(text,integer)
  from public, anon, authenticated, service_role;
revoke all on function private.fn_reconcile_architecture_delivery_attempts_v6(text,integer)
  from public, anon, authenticated, service_role;

revoke all on table private.lf_architecture_delivery_secrets_v4
  from public, anon, authenticated, service_role;
revoke all on table private.lf_architecture_notification_attempts_v4
  from public, anon, authenticated, service_role;
revoke all on table private.lf_architecture_notification_receipts_v4
  from public, anon, authenticated, service_role;
