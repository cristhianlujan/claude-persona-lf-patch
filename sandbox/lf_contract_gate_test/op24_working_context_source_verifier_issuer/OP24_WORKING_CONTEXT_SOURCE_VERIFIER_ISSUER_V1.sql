-- OP24 / Strategy 24 Working Context
-- Candidate only. DO NOT apply durably from this branch.
--
-- Purpose:
-- Close the first-bad-hop found by E2E audit GPT_CP_OP24_E2E_DATAFLOW_AUDIT_001:
-- Context Pack COMPLETE -> Retrieval PASS -> verified RETRIEVAL_PASS receipt -> GREEN budget -> admission.
--
-- Security model:
-- * Never recovers or exposes the legacy SOURCE_VERIFIER_V1 secret.
-- * Provisions a NEW migration-managed channel token in Supabase Vault.
-- * Plaintext token never leaves SECURITY DEFINER execution.
-- * RPC can issue only RETRIEVAL_PASS and requires an independently-produced
--   verification envelope bound to the exact execution/head/request/context digest.
-- * Existing canonical programacion.issue_provenance_receipt and immutable receipt
--   guards remain authoritative.

-- Migration-time provisioning pattern intentionally mirrors the already-proven
-- F05 protected-issuer pattern.
drop trigger if exists trg_provenance_channels_immutable
  on programacion.provenance_channels;

do $op24_source_verifier_channel$
declare
  v_channel_code constant text := 'SOURCE_VERIFIER_PROTECTED_V1';
  v_secret_name constant text := 'op24_source_verifier_protected_token_v1';
  v_channel_token text;
  v_channel_token_sha256 text;
  v_existing_channel_sha256 text;
begin
  select pc.secret_sha256
    into v_existing_channel_sha256
    from programacion.provenance_channels pc
   where pc.channel_code = v_channel_code;

  if v_existing_channel_sha256 is not null and not exists (
    select 1
      from programacion.provenance_channels pc
     where pc.channel_code = v_channel_code
       and 'RETRIEVAL_PASS' = any(pc.allowed_kinds)
  ) then
    raise exception 'SOURCE_VERIFIER_PROTECTED_CHANNEL_KIND_MISMATCH';
  end if;

  select ds.decrypted_secret
    into v_channel_token
    from vault.decrypted_secrets ds
   where ds.name = v_secret_name
   order by ds.created_at desc
   limit 1;

  if v_existing_channel_sha256 is null then
    if v_channel_token is null then
      v_channel_token := encode(extensions.gen_random_bytes(32), 'base64');
      perform vault.create_secret(
        v_channel_token,
        v_secret_name,
        'OP24 protected RETRIEVAL_PASS provenance channel token; migration-managed and never returned to Builder.'
      );
    end if;

    v_channel_token_sha256 := encode(
      extensions.digest(convert_to(v_channel_token, 'UTF8'), 'sha256'),
      'hex'
    );

    insert into programacion.provenance_channels(
      channel_code,
      secret_sha256,
      allowed_kinds,
      description
    ) values (
      v_channel_code,
      v_channel_token_sha256,
      array['RETRIEVAL_PASS']::text[],
      'Protected issuer transport for independently verified Strategy 24 retrieval-context receipts.'
    );
  else
    if v_channel_token is null then
      raise exception 'SOURCE_VERIFIER_PROTECTED_TOKEN_MISSING_FOR_EXISTING_CHANNEL';
    end if;

    v_channel_token_sha256 := encode(
      extensions.digest(convert_to(v_channel_token, 'UTF8'), 'sha256'),
      'hex'
    );

    if v_channel_token_sha256 is distinct from v_existing_channel_sha256 then
      raise exception 'SOURCE_VERIFIER_PROTECTED_TOKEN_HASH_MISMATCH';
    end if;
  end if;
end;
$op24_source_verifier_channel$;

create trigger trg_provenance_channels_immutable
before insert or update or delete on programacion.provenance_channels
for each row execute function programacion.fn_provenance_channels_immutable();

create or replace function programacion.issue_retrieval_pass_provenance_receipt_v1(
  p_execution_id bigint,
  p_head_sha text,
  p_request_ref text,
  p_context_sha256 text,
  p_issuer_identity text,
  p_verification_ref text,
  p_payload jsonb
)
returns table(id bigint, receipt_sha256 text)
language plpgsql
security definer
set search_path to 'pg_catalog','programacion','vault'
as $function$
declare
  v_channel_token text;
  v_execution_request_ref text;
  v_subject_ref text;
begin
  if p_execution_id is null then
    raise exception 'RETRIEVAL_PROVENANCE_EXECUTION_REQUIRED';
  end if;
  if p_head_sha !~ '^[0-9a-f]{40}$' then
    raise exception 'RETRIEVAL_PROVENANCE_HEAD_SHA_INVALID';
  end if;
  if p_context_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'RETRIEVAL_PROVENANCE_CONTEXT_SHA256_INVALID';
  end if;
  if length(btrim(coalesce(p_request_ref,''))) = 0 then
    raise exception 'RETRIEVAL_PROVENANCE_REQUEST_REF_REQUIRED';
  end if;
  if length(btrim(coalesce(p_issuer_identity,''))) = 0
     or length(btrim(coalesce(p_verification_ref,''))) = 0 then
    raise exception 'RETRIEVAL_PROVENANCE_VERIFIER_IDENTITY_REQUIRED';
  end if;
  if jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception 'RETRIEVAL_PROVENANCE_PAYLOAD_INVALID';
  end if;

  select e.request_ref
    into v_execution_request_ref
    from programacion.ejecuciones e
   where e.id = p_execution_id
     and e.head_sha = p_head_sha;

  if not found then
    raise exception 'RETRIEVAL_PROVENANCE_EXECUTION_HEAD_NOT_FOUND';
  end if;
  if v_execution_request_ref is distinct from p_request_ref then
    raise exception 'RETRIEVAL_PROVENANCE_REQUEST_REF_MISMATCH';
  end if;

  -- The protected issuer transports an independent verdict; it does not create
  -- semantic authority by self-declaration. The envelope must therefore identify
  -- the external verification evidence and bind the exact subject.
  if p_payload->>'kind' is distinct from 'RETRIEVAL_PASS'
     or p_payload->>'verdict' is distinct from 'PASS'
     or p_payload->'independent' is distinct from 'true'::jsonb
     or p_payload->>'execution_id' is distinct from p_execution_id::text
     or p_payload->>'head_sha' is distinct from p_head_sha
     or p_payload->>'request_ref' is distinct from p_request_ref
     or p_payload->>'context_sha256' is distinct from p_context_sha256
     or p_payload->>'verifier_identity' is distinct from p_issuer_identity
     or p_payload->>'evidence_ref' is distinct from p_verification_ref
     or coalesce(p_payload->>'evidence_sha256','') !~ '^[0-9a-f]{64}$' then
    raise exception 'RETRIEVAL_PROVENANCE_PAYLOAD_CONTRACT_MISMATCH';
  end if;

  select ds.decrypted_secret
    into v_channel_token
    from vault.decrypted_secrets ds
   where ds.name = 'op24_source_verifier_protected_token_v1'
   order by ds.created_at desc
   limit 1;

  if v_channel_token is null or length(v_channel_token) < 32 then
    raise exception 'RETRIEVAL_PROVENANCE_PROTECTED_TOKEN_NOT_PROVISIONED';
  end if;

  v_subject_ref := 'retrieval:' || p_execution_id::text;

  return query
  select r.id, r.receipt_sha256
    from programacion.issue_provenance_receipt(
      'SOURCE_VERIFIER_PROTECTED_V1',
      v_channel_token,
      'RETRIEVAL_PASS',
      p_execution_id,
      p_head_sha,
      'retrieval_context',
      v_subject_ref,
      p_context_sha256,
      p_issuer_identity,
      p_verification_ref,
      p_payload
    ) r;
end;
$function$;

revoke all on function programacion.issue_retrieval_pass_provenance_receipt_v1(
  bigint,text,text,text,text,text,jsonb
) from public, anon, authenticated;
grant execute on function programacion.issue_retrieval_pass_provenance_receipt_v1(
  bigint,text,text,text,text,text,jsonb
) to service_role;
