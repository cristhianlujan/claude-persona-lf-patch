do $do$
declare
  v_def text;
begin
  v_def := pg_get_functiondef('programacion.fn_external_verify_worker_v10_evidence_v1(bigint,bigint,text,text,text,text,text,text,jsonb,text)'::regprocedure);
  if position('v_safe_payload:=p_verification_payload;' in v_def)=0 then
    raise exception 'V10_SAFE_PAYLOAD_PATCH_TARGET_NOT_FOUND';
  end if;
  v_def := replace(v_def,'v_safe_payload:=p_verification_payload;','v_safe_payload:=p_verification_payload-''channel_token'';');
  execute v_def;
end
$do$;

do $do$
declare v_def text;
begin
  v_def := pg_get_functiondef('programacion.fn_external_verify_worker_v10_evidence_v1(bigint,bigint,text,text,text,text,text,text,jsonb,text)'::regprocedure);
  if position('EXTERNAL_V10_CHANNEL_TOKEN_REQUIRED' in v_def)>0 or position('EXTERNAL_V10_CHANNEL_TOKEN_MISMATCH' in v_def)>0 then
    raise exception 'SELFTEST_V10_MANUAL_SECRET_REQUIREMENT_STILL_ACTIVE';
  end if;
  if position('v_safe_payload:=p_verification_payload-''channel_token'';' in v_def)=0 then
    raise exception 'SELFTEST_V10_COMPAT_SENTINEL_NOT_SANITIZED';
  end if;
end
$do$;