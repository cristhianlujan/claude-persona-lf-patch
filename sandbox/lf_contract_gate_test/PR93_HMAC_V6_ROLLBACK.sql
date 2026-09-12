-- Fail-closed rollback for PR93 HMAC delivery V6.
-- Does not restore insecure V4/V5 writers and preserves historical evidence.

update private.lf_architecture_delivery_config_v6
set enabled = false,
    updated_by_execution_id = 'PR93-HMAC-V6-ROLLBACK',
    updated_at = clock_timestamp()
where config_id = 1;

update private.lf_architecture_delivery_secrets_v4
set is_active = false,
    not_after = coalesce(not_after, clock_timestamp())
where is_active;

revoke all on function public.record_lf_alert_delivery_receipt_v6(
  text,bigint,bigint,text,jsonb,text,bigint,uuid,smallint,jsonb,text
) from public, anon, authenticated, service_role;

revoke all on function private.fn_dispatch_architecture_outbox_v4(text,integer)
  from public, anon, authenticated, service_role;
