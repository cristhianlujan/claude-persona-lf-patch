do $do$
declare
  v_def text;
  v_start integer;
  v_end integer;
  v_replacement text;
begin
  v_def := pg_get_functiondef('programacion.fn_external_verify_worker_v10_evidence_v1(bigint,bigint,text,text,text,text,text,text,jsonb,text)'::regprocedure);
  v_start := strpos(v_def, '  v_token:=p_verification_payload->>''channel_token'';');
  v_end := strpos(v_def, '  if p_verification_method <> ''GITHUB_ACTIONS_OIDC_WORKER_V10_EVIDENCE_V1''');
  if v_start = 0 or v_end = 0 or v_end <= v_start then
    raise exception 'V10_TOKEN_BOUNDARY_PATCH_TARGET_NOT_FOUND';
  end if;
  v_replacement := E'  select decrypted_secret into v_token\n  from vault.decrypted_secrets\n  where name=''EVIDENCE_VERIFIER_V1_TOKEN''\n  order by created_at desc limit 1;\n  if length(coalesce(v_token,''''))<32 then raise exception ''EVIDENCE_VERIFIER_V1_VAULT_SECRET_MISSING''; end if;\n  v_token_hash:=encode(extensions.digest(convert_to(v_token,''UTF8''),''sha256''),''hex'');\n  select secret_sha256 into v_channel_hash from programacion.provenance_channels where channel_code=''EVIDENCE_VERIFIER_V1'';\n  if v_channel_hash is distinct from v_token_hash then raise exception ''EVIDENCE_VERIFIER_V1_VAULT_CHANNEL_HASH_MISMATCH''; end if;\n  v_safe_payload:=p_verification_payload;\n';
  v_def := substr(v_def, 1, v_start - 1) || v_replacement || substr(v_def, v_end);
  execute v_def;
end
$do$;

do $do$
declare
  v_def text;
begin
  v_def := pg_get_functiondef('programacion.fn_external_verify_worker_v10_evidence_v1(bigint,bigint,text,text,text,text,text,text,jsonb,text)'::regprocedure);
  if position('channel_token' in v_def) > 0 then raise exception 'SELFTEST_V10_MANUAL_CHANNEL_TOKEN_STILL_REQUIRED'; end if;
  if position('vault.decrypted_secrets' in v_def) = 0 then raise exception 'SELFTEST_V10_INTERNAL_PROVENANCE_TOKEN_MISSING'; end if;
  if position('GITHUB_ACTIONS_OIDC_WORKER_V10_EVIDENCE_V1' in v_def) = 0 then raise exception 'SELFTEST_V10_OIDC_METHOD_MISSING'; end if;
  if position('EXTERNAL_V10_VERIFY_PAYLOAD_IDENTITY_MISMATCH' in v_def) = 0 then raise exception 'SELFTEST_V10_EXACT_BINDING_MISSING'; end if;
end
$do$;