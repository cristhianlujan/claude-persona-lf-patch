-- PR93 follow-up: align the delivery read model with the V6 two-phase receipt contract.
--
-- V6 intentionally records the receiver-side acknowledgement as receipt_status='RECEIVED'.
-- The dispatcher independently observes the HTTP response and promotes the linked
-- attempt to attempt_status='DELIVERED'. The legacy delivery view only recognized
-- receipt_status='DELIVERED', so fully-bound V6 deliveries remained RETRY_DUE.
--
-- Forward-only fix: no historical rows are rewritten. A V6 outbox is considered
-- delivered only when BOTH the authenticated receiver receipt and the independently
-- reconciled dispatcher attempt are present and mutually bound.

begin;

do $preflight$
declare
  v_unbound bigint;
begin
  if to_regclass('private.lf_architecture_notification_outbox_v4') is null
     or to_regclass('private.lf_architecture_notification_attempts_v4') is null
     or to_regclass('private.lf_architecture_notification_receipts_v4') is null
     or to_regclass('public.v_lf_architecture_notification_delivery_v4') is null then
    raise exception using
      errcode='55000',
      message='notification delivery V4/V6 baseline objects are required';
  end if;

  -- Fail closed if a row already marked DELIVERED by the V6 dispatcher cannot be
  -- cryptographically/correlationally tied back to its receiver acknowledgement.
  select count(*)
    into v_unbound
  from private.lf_architecture_notification_attempts_v4 a
  join private.lf_architecture_notification_outbox_v4 o
    on o.id=a.outbox_id
   and o.channel='EXTERNAL_HTTP'
  left join private.lf_architecture_notification_receipts_v4 r
    on r.id=a.receiver_receipt_id
  where a.delivery_schema_version='lf-architecture-alert-delivery/v6'
    and a.attempt_status='DELIVERED'
    and a.success is true
    and not (
      r.id is not null
      and r.outbox_id=a.outbox_id
      and r.attempt_id=a.id
      and r.receipt_status='RECEIVED'
      and r.delivery_schema_version=a.delivery_schema_version
      and r.signature_nonce=a.signature_nonce
      and r.secret_version=a.secret_version
      and r.receiver_response_status between 200 and 299
      and r.payload_sha256=o.payload_sha256
      and a.receiver_response_status between 200 and 299
      and a.dispatcher_observed_http_status between 200 and 299
      and a.receiver_receipt_id=r.id
    );

  if v_unbound<>0 then
    raise exception using
      errcode='55000',
      message=format('V6 delivered attempts contain %s unbound receiver receipts',v_unbound);
  end if;
end
$preflight$;

create or replace view public.v_lf_architecture_notification_delivery_v4
as
select
  o.id as outbox_id,
  o.alert_id,
  o.payload_sha256,
  o.created_at as queued_at,
  coalesce(a.attempt_count,0::bigint) as attempt_count,
  a.latest_attempt_at,
  a.latest_request_id,
  coalesce(v6.receipt_id,legacy.receipt_id) as receipt_id,
  coalesce(v6.http_status,legacy.http_status) as http_status,
  coalesce(v6.received_at,legacy.received_at) as received_at,
  case
    when v6.receipt_id is not null or legacy.receipt_id is not null then 'DELIVERED'::text
    when a.latest_attempt_at is not null
         and a.latest_attempt_at < clock_timestamp()-interval '5 minutes'
      then 'RETRY_DUE'::text
    when a.latest_attempt_at is not null then 'IN_FLIGHT'::text
    else 'PENDING'::text
  end as delivery_state
from private.lf_architecture_notification_outbox_v4 o
left join lateral (
  select
    count(*) as attempt_count,
    max(x.created_at) as latest_attempt_at,
    (array_agg(x.request_id order by x.created_at desc,x.id desc))[1] as latest_request_id
  from private.lf_architecture_notification_attempts_v4 x
  where x.outbox_id=o.id
) a on true
left join lateral (
  -- Legacy V4/V5 contract: the receipt itself carries the terminal DELIVERED state.
  select
    r.id as receipt_id,
    r.http_status,
    r.received_at
  from private.lf_architecture_notification_receipts_v4 r
  where r.outbox_id=o.id
    and r.receipt_status='DELIVERED'
  order by r.received_at desc,r.id desc
  limit 1
) legacy on true
left join lateral (
  -- V6 contract: receiver acknowledgement + independent dispatcher observation.
  select
    r.id as receipt_id,
    coalesce(r.receiver_response_status,x.dispatcher_observed_http_status) as http_status,
    r.received_at
  from private.lf_architecture_notification_attempts_v4 x
  join private.lf_architecture_notification_receipts_v4 r
    on r.id=x.receiver_receipt_id
   and r.outbox_id=x.outbox_id
   and r.attempt_id=x.id
   and r.receipt_status='RECEIVED'
   and r.delivery_schema_version=x.delivery_schema_version
   and r.signature_nonce=x.signature_nonce
   and r.secret_version=x.secret_version
   and r.receiver_response_status between 200 and 299
   and r.payload_sha256=o.payload_sha256
  where x.outbox_id=o.id
    and x.delivery_schema_version='lf-architecture-alert-delivery/v6'
    and x.attempt_status='DELIVERED'
    and x.success is true
    and x.completed_at is not null
    and x.receiver_received_at is not null
    and x.receiver_response_status between 200 and 299
    and x.dispatcher_observed_http_status between 200 and 299
  order by x.completed_at desc,x.id desc
  limit 1
) v6 on true
where o.channel='EXTERNAL_HTTP';

comment on view public.v_lf_architecture_notification_delivery_v4 is
  'Notification delivery read model. Legacy V4/V5 accepts DELIVERED receipts; V6 requires a RECEIVED receiver receipt bound to an independently reconciled DELIVERED dispatcher attempt.';

do $postflight$
declare
  v_false_retry bigint;
begin
  select count(*)
    into v_false_retry
  from public.v_lf_architecture_notification_delivery_v4 d
  where d.delivery_state<>'DELIVERED'
    and exists (
      select 1
      from private.lf_architecture_notification_attempts_v4 a
      join private.lf_architecture_notification_receipts_v4 r
        on r.id=a.receiver_receipt_id
       and r.outbox_id=a.outbox_id
       and r.attempt_id=a.id
       and r.receipt_status='RECEIVED'
       and r.delivery_schema_version=a.delivery_schema_version
       and r.signature_nonce=a.signature_nonce
       and r.secret_version=a.secret_version
       and r.receiver_response_status between 200 and 299
      join private.lf_architecture_notification_outbox_v4 o
        on o.id=a.outbox_id
       and o.payload_sha256=r.payload_sha256
       and o.channel='EXTERNAL_HTTP'
      where a.outbox_id=d.outbox_id
        and a.delivery_schema_version='lf-architecture-alert-delivery/v6'
        and a.attempt_status='DELIVERED'
        and a.success is true
        and a.receiver_response_status between 200 and 299
        and a.dispatcher_observed_http_status between 200 and 299
    );

  if v_false_retry<>0 then
    raise exception using
      errcode='55000',
      message=format('delivery read model still reports %s fully-bound V6 deliveries as unresolved',v_false_retry);
  end if;
end
$postflight$;

commit;
