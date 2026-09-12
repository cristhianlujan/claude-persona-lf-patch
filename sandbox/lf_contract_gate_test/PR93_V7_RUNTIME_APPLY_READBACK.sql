\set ON_ERROR_STOP on

do $runtime_readback$
declare
  v_scope text := 'reconciliation-v7';
  v_execution text := 'PR93-V7-RUNTIME-CI-PROBE';
  v_payload_hash text;
  v_preimage text;
  v_nonce text;
  v_key_material text;
  v_signature text;
  v_consumed boolean;
  v_replay boolean;
begin
  if current_setting('server_version_num')::integer < 170000
     or current_setting('server_version_num')::integer >= 180000 then
    raise exception 'runtime gate requires PostgreSQL 17';
  end if;

  if pg_get_userbyid(
       (select relowner from pg_class
        where oid='private.lf_writer_hmac_keys_v7'::regclass)
     ) <> 'postgres' then
    raise exception 'writer key table owner readback mismatch';
  end if;

  if pg_get_userbyid(
       (select relowner from pg_class
        where oid='private.lf_reconciliation_writer_nonces_v7'::regclass)
     ) <> 'lf_writer_verifier_v7' then
    raise exception 'nonce table source owner readback mismatch';
  end if;

  if not exists (
       select 1 from pg_class
       where oid='private.lf_reconciliation_writer_nonces_v7'::regclass
         and relrowsecurity and relforcerowsecurity
     ) then
    raise exception 'nonce table RLS readback mismatch';
  end if;

  if (select count(*) from pg_policy
      where polrelid='private.lf_reconciliation_writer_nonces_v7'::regclass) <> 2 then
    raise exception 'nonce table policy readback mismatch';
  end if;

  if not exists (
       select 1 from pg_trigger
       where tgrelid='private.lf_reconciliation_writer_nonces_v7'::regclass
         and tgname='trg_block_lf_writer_nonces_v7_truncate'
         and tgenabled='A'
         and not tgisinternal
     ) then
    raise exception 'nonce table trigger readback mismatch';
  end if;

  if not has_schema_privilege(
       'lf_writer_verifier_v7','extensions','USAGE'
     ) or has_schema_privilege(
       'lf_writer_verifier_v7','extensions','CREATE'
     ) then
    raise exception 'writer verifier extensions boundary mismatch';
  end if;

  if exists (
       select 1
       from pg_auth_members m
       where m.member='postgres'::regrole
         and m.grantor='postgres'::regrole
         and m.roleid in (
           'lf_governance_owner_v3'::regrole,
           'lf_writer_verifier_v7'::regrole
         )
     ) then
    raise exception 'temporary postgres-granted memberships remain';
  end if;

  if private.fn_writer_key_separation_v7_valid() is not true then
    raise exception 'writer key separation readback mismatch';
  end if;

  v_key_material := encode(extensions.gen_random_bytes(32),'hex');
  perform private.fn_install_writer_hmac_key_v7(
    'lf-writer-2026-08-r99',
    v_key_material,
    v_execution || '-INSTALL'
  );
  perform private.fn_promote_writer_hmac_key_v7(
    'lf-writer-2026-08-r99',
    v_execution || '-PROMOTE'
  );

  if private.fn_writer_key_rotation_status_v7() <> 'READY' then
    raise exception 'writer key rotation state mismatch';
  end if;

  v_payload_hash := encode(
    extensions.digest(convert_to(v_execution,'UTF8'),'sha256'),
    'hex'
  );
  v_preimage :=
    octet_length(v_scope)::text || '#' || v_scope ||
    octet_length(v_execution)::text || '#' || v_execution ||
    octet_length(v_payload_hash)::text || '#' || v_payload_hash;
  v_nonce :=
    lower(gen_random_uuid()::text) || '.' ||
    floor(extract(epoch from clock_timestamp() + interval '5 minutes'))::bigint::text;
  v_signature := encode(
    extensions.hmac(
      convert_to(v_preimage || ':' || v_nonce,'UTF8'),
      convert_to(v_key_material,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('role','service_role')::text,
    true
  );

  select private.fn_consume_writer_proof_v7(
    v_preimage,
    v_signature,
    v_nonce
  ) into v_consumed;

  if v_consumed is distinct from true then
    raise exception 'valid writer proof was not consumed';
  end if;

  select private.fn_consume_writer_proof_v7(
    v_preimage,
    v_signature,
    v_nonce
  ) into v_replay;

  if v_replay is distinct from false then
    raise exception 'writer proof replay was not rejected';
  end if;

  if (select count(*)
      from private.lf_reconciliation_writer_nonces_v7
      where preimage_sha256=encode(
        extensions.digest(convert_to(v_preimage,'UTF8'),'sha256'),
        'hex'
      )) <> 1 then
    raise exception 'valid writer proof persistence readback mismatch';
  end if;
end
$runtime_readback$;

select jsonb_build_object(
  'server_major', current_setting('server_version_num')::integer / 10000,
  'key_table_owner', pg_get_userbyid(
    (select relowner from pg_class
     where oid='private.lf_writer_hmac_keys_v7'::regclass)
  ),
  'nonce_table_owner', pg_get_userbyid(
    (select relowner from pg_class
     where oid='private.lf_reconciliation_writer_nonces_v7'::regclass)
  ),
  'nonce_policies', (
    select count(*) from pg_policy
    where polrelid='private.lf_reconciliation_writer_nonces_v7'::regclass
  ),
  'valid_proofs_consumed', (
    select count(*) from private.lf_reconciliation_writer_nonces_v7
  ),
  'rotation_state', private.fn_writer_key_rotation_status_v7(),
  'temporary_postgres_grants', (
    select count(*)
    from pg_auth_members m
    where m.member='postgres'::regrole
      and m.grantor='postgres'::regrole
      and m.roleid in (
        'lf_governance_owner_v3'::regrole,
        'lf_writer_verifier_v7'::regrole
      )
  )
) as apply_readback;
