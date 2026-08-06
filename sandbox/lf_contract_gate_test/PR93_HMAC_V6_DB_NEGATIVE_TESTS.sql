begin;

create or replace function pg_temp.make_v6_attempt(
  p_outbox_id bigint,
  p_issued_at_unix bigint default null,
  p_nonce uuid default null,
  p_use_legacy_signature boolean default false
) returns table(
  attempt_id bigint,
  signature text,
  issued_at_unix bigint,
  nonce uuid,
  secret_version smallint,
  payload jsonb,
  payload_sha256 text
)
language plpgsql
set search_path = pg_catalog, private, extensions, pg_temp
as $$
declare
  v_outbox private.lf_architecture_notification_outbox_v4%rowtype;
  v_secret bytea;
  v_body_sha text;
begin
  select * into v_outbox
  from private.lf_architecture_notification_outbox_v4
  where id=p_outbox_id and channel='EXTERNAL_HTTP';
  if not found then raise exception 'TEST_OUTBOX_MISSING'; end if;

  select secret_id,secret_key into secret_version,v_secret
  from private.lf_architecture_delivery_secrets_v4 where is_active;
  if not found then raise exception 'TEST_SECRET_MISSING'; end if;

  issued_at_unix := coalesce(
    p_issued_at_unix,
    extract(epoch from date_trunc('second',clock_timestamp()))::bigint
  );
  nonce := coalesce(p_nonce,extensions.gen_random_uuid());
  payload := v_outbox.payload;
  payload_sha256 := v_outbox.payload_sha256;
  v_body_sha := encode(extensions.digest(convert_to('{}','UTF8'),'sha256'),'hex');

  insert into private.lf_architecture_notification_attempts_v4(
    outbox_id,request_id,endpoint,attempt_status,request_signature,
    request_body_sha256,error_message,created_by_execution_id,
    delivery_schema_version,signature_issued_at,signature_nonce,secret_version
  ) values(
    p_outbox_id,null,'https://example.invalid/v6','PENDING',repeat('0',64),
    null,null,'PR93-V6-DB-MATRIX',
    'lf-architecture-alert-delivery/v6',to_timestamp(issued_at_unix),nonce,secret_version
  ) returning id into attempt_id;

  if p_use_legacy_signature then
    signature := encode(
      extensions.hmac(
        convert_to(p_outbox_id::text || ':' || payload_sha256,'UTF8'),
        v_secret,'sha256'
      ),
      'hex'
    );
  else
    signature := encode(
      extensions.hmac(
        convert_to(
          private.fn_architecture_delivery_preimage_v6(
            'lf-architecture-alert-delivery/v6',
            p_outbox_id,attempt_id,payload_sha256,issued_at_unix,nonce,secret_version
          ),
          'UTF8'
        ),
        v_secret,'sha256'
      ),
      'hex'
    );
  end if;

  update private.lf_architecture_notification_attempts_v4
  set request_signature=signature,
      request_id=-attempt_id,
      request_body_sha256=v_body_sha,
      attempt_status='SUBMITTED'
  where id=attempt_id;

  return next;
end
$$;

do $tests$
declare
  o1 bigint;
  o2 bigint;
  a record;
  b record;
  c record;
  d record;
  e record;
  v_receipt_id bigint;
begin
  select id into o1 from private.lf_architecture_notification_outbox_v4
  where channel='EXTERNAL_HTTP' order by id limit 1;
  select id into o2 from private.lf_architecture_notification_outbox_v4
  where channel='EXTERNAL_HTTP' and id<>o1 order by id limit 1;
  if o1 is null or o2 is null then raise exception 'TEST_OUTBOX_BASELINE_MISSING'; end if;

  select * into a from pg_temp.make_v6_attempt(o1);
  v_receipt_id := public.record_lf_alert_delivery_receipt_v6(
    'lf-architecture-alert-delivery/v6',
    a.attempt_id,o1,a.payload_sha256,a.payload,a.signature,
    a.issued_at_unix,a.nonce,a.secret_version,
    '{"test":"valid"}'::jsonb,'PR93-V6-DB-VALID'
  );
  if v_receipt_id is null then raise exception 'VALID_RECEIPT_MISSING'; end if;
  if not exists(
    select 1 from private.lf_architecture_notification_attempts_v4 x
    where x.id=a.attempt_id
      and x.attempt_status='SUBMITTED'
      and x.receiver_receipt_id=v_receipt_id
      and x.receiver_response_status=202
      and x.dispatcher_observed_http_status is null
      and x.http_status is null
  ) then raise exception 'RECEIVER_HTTP_SEMANTICS_INVALID'; end if;

  begin
    perform public.record_lf_alert_delivery_receipt_v6(
      'lf-architecture-alert-delivery/v6',
      a.attempt_id,o1,a.payload_sha256,a.payload,a.signature,
      a.issued_at_unix,a.nonce,a.secret_version,
      '{"test":"replay"}'::jsonb,'PR93-V6-REPLAY'
    );
    raise exception 'REPLAY_ACCEPTED';
  exception when sqlstate '28000' then null;
  end;

  begin
    perform * from pg_temp.make_v6_attempt(o2,null,a.nonce,false);
    raise exception 'DUPLICATE_NONCE_ACCEPTED';
  exception when unique_violation then null;
  end;

  select * into b from pg_temp.make_v6_attempt(o1);
  begin
    perform public.record_lf_alert_delivery_receipt_v6(
      'lf-architecture-alert-delivery/v6',
      b.attempt_id,o1,b.payload_sha256,b.payload,a.signature,
      b.issued_at_unix,b.nonce,b.secret_version,
      '{"test":"cross_attempt"}'::jsonb,'PR93-V6-CROSS-ATTEMPT'
    );
    raise exception 'CROSS_ATTEMPT_ACCEPTED';
  exception when sqlstate '28000' then null;
  end;

  begin
    perform public.record_lf_alert_delivery_receipt_v6(
      'lf-architecture-alert-delivery/v6',
      b.attempt_id,o2,b.payload_sha256,b.payload,b.signature,
      b.issued_at_unix,b.nonce,b.secret_version,
      '{"test":"cross_outbox"}'::jsonb,'PR93-V6-CROSS-OUTBOX'
    );
    raise exception 'CROSS_OUTBOX_ACCEPTED';
  exception when sqlstate '28000' then null;
  end;

  begin
    perform public.record_lf_alert_delivery_receipt_v6(
      'lf-architecture-alert-delivery/v6',
      b.attempt_id,o1,b.payload_sha256,jsonb_build_object('tampered',true),b.signature,
      b.issued_at_unix,b.nonce,b.secret_version,
      '{"test":"payload"}'::jsonb,'PR93-V6-PAYLOAD-MISMATCH'
    );
    raise exception 'PAYLOAD_MISMATCH_ACCEPTED';
  exception when sqlstate '28000' then null;
  end;

  select * into c from pg_temp.make_v6_attempt(o1,null,null,true);
  begin
    perform public.record_lf_alert_delivery_receipt_v6(
      'lf-architecture-alert-delivery/v6',
      c.attempt_id,o1,c.payload_sha256,c.payload,c.signature,
      c.issued_at_unix,c.nonce,c.secret_version,
      '{"test":"legacy_signature"}'::jsonb,'PR93-V6-LEGACY-SIGNATURE'
    );
    raise exception 'LEGACY_SIGNATURE_ACCEPTED';
  exception when sqlstate '28000' then null;
  end;

  select * into d from pg_temp.make_v6_attempt(
    o1,
    extract(epoch from date_trunc('second',clock_timestamp()-interval '10 minutes'))::bigint
  );
  begin
    perform public.record_lf_alert_delivery_receipt_v6(
      'lf-architecture-alert-delivery/v6',
      d.attempt_id,o1,d.payload_sha256,d.payload,d.signature,
      d.issued_at_unix,d.nonce,d.secret_version,
      '{"test":"expired"}'::jsonb,'PR93-V6-EXPIRED'
    );
    raise exception 'EXPIRED_SIGNATURE_ACCEPTED';
  exception when sqlstate '28000' then null;
  end;

  select * into e from pg_temp.make_v6_attempt(
    o1,
    extract(epoch from date_trunc('second',clock_timestamp()+interval '2 minutes'))::bigint
  );
  begin
    perform public.record_lf_alert_delivery_receipt_v6(
      'lf-architecture-alert-delivery/v6',
      e.attempt_id,o1,e.payload_sha256,e.payload,e.signature,
      e.issued_at_unix,e.nonce,e.secret_version,
      '{"test":"future"}'::jsonb,'PR93-V6-FUTURE'
    );
    raise exception 'FUTURE_SIGNATURE_ACCEPTED';
  exception when sqlstate '28000' then null;
  end;
end
$tests$;

rollback;
select 'PASS_HMAC_V6_DB_MATRIX_8_OF_8' as result;
