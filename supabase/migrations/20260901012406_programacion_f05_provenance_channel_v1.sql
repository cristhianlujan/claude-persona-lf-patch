-- AUD24-F05 remediation: durable provenance channel + separated signing material.
-- Source-first migration for the Programming Agent sandbox.
--
-- Goals:
-- 1. Admit the exact AUD24_F05_BASELINE_AUTHORIZATION receipt kind.
-- 2. Provision a migration-managed provenance channel whose runtime token is
--    generated with pgcrypto and retained only in Supabase Vault.
-- 3. Provision independent Ed25519 seed material in Vault; the Builder never
--    receives or persists the plaintext seed.
-- 4. Expose only narrow service_role SECURITY DEFINER RPCs: one to obtain the
--    signing seed for the protected issuer and one to persist the signed receipt
--    through the existing canonical issue_provenance_receipt guard.

alter table programacion.provenance_receipts
  drop constraint if exists provenance_receipts_receipt_kind_check;

alter table programacion.provenance_receipts
  add constraint provenance_receipts_receipt_kind_check
  check (receipt_kind in (
    'RETRIEVAL_PASS',
    'TRACEABILITY_GRAPH',
    'PLAYWRIGHT_RUN',
    'EVIDENCE_VERIFICATION',
    'AUDIT_VERDICT',
    'HUMAN_DECISION',
    'AUD24_F05_BASELINE_AUTHORIZATION'
  ));

drop trigger if exists trg_provenance_channels_immutable
  on programacion.provenance_channels;

do $f05_channel$
declare
  v_channel_token text;
  v_channel_token_sha256 text;
  v_existing_channel_sha256 text;
  v_seed_name constant text := 'programming_agent_f05_ed25519_seed_v1';
  v_channel_token_name constant text := 'programming_agent_f05_provenance_token_v1';
begin
  select pc.secret_sha256
    into v_existing_channel_sha256
    from programacion.provenance_channels pc
   where pc.channel_code = 'F05_SUPABASE_PROTECTED_ISSUER_V1';

  if v_existing_channel_sha256 is null then
    select ds.decrypted_secret
      into v_channel_token
      from vault.decrypted_secrets ds
     where ds.name = v_channel_token_name
     order by ds.created_at desc
     limit 1;

    if v_channel_token is null then
      v_channel_token := encode(extensions.gen_random_bytes(32), 'base64');
      perform vault.create_secret(
        v_channel_token,
        v_channel_token_name,
        'Programming Agent F05 provenance channel token; migration-managed, never returned to Builder.'
      );
    end if;

    v_channel_token_sha256 := encode(
      extensions.digest(convert_to(v_channel_token, 'UTF8'), 'sha256'),
      'hex'
    );

    insert into programacion.provenance_channels(
      channel_code, secret_sha256, allowed_kinds, description
    ) values (
      'F05_SUPABASE_PROTECTED_ISSUER_V1',
      v_channel_token_sha256,
      array['AUD24_F05_BASELINE_AUTHORIZATION']::text[],
      'Restricted Supabase protected issuer for exact-head AUD24-F05 Ed25519 receipts.'
    );
  elsif not exists (
    select 1
      from programacion.provenance_channels pc
     where pc.channel_code = 'F05_SUPABASE_PROTECTED_ISSUER_V1'
       and 'AUD24_F05_BASELINE_AUTHORIZATION' = any(pc.allowed_kinds)
  ) then
    raise exception 'existing F05 provenance channel is not authorized for AUD24_F05_BASELINE_AUTHORIZATION';
  end if;

  if not exists (
    select 1 from vault.secrets s where s.name = v_seed_name
  ) then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'base64'),
      v_seed_name,
      'Programming Agent F05 Ed25519 seed; independent from SUPABASE_SERVICE_ROLE_KEY and never returned to Builder.'
    );
  end if;
end;
$f05_channel$;

create trigger trg_provenance_channels_immutable
before insert or update or delete on programacion.provenance_channels
for each row execute function programacion.fn_provenance_channels_immutable();

create or replace function programacion.f05_signing_seed_v1()
returns text
language plpgsql
security definer
set search_path to 'pg_catalog','programacion','vault'
as $function$
declare
  v_seed text;
begin
  select ds.decrypted_secret
    into v_seed
    from vault.decrypted_secrets ds
   where ds.name = 'programming_agent_f05_ed25519_seed_v1'
   order by ds.created_at desc
   limit 1;

  if v_seed is null or length(v_seed) < 32 then
    raise exception 'F05_SIGNING_SEED_NOT_PROVISIONED';
  end if;
  return v_seed;
end;
$function$;

revoke all on function programacion.f05_signing_seed_v1() from public, anon, authenticated;
grant execute on function programacion.f05_signing_seed_v1() to service_role;

create or replace function programacion.issue_f05_provenance_receipt_v1(
  p_head_sha text,
  p_subject_ref text,
  p_subject_sha256 text,
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
begin
  if p_head_sha !~ '^[0-9a-f]{40}$' then
    raise exception 'F05_HEAD_SHA_INVALID';
  end if;
  if p_subject_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'F05_SUBJECT_SHA256_INVALID';
  end if;
  if jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception 'F05_PAYLOAD_INVALID';
  end if;
  if p_payload->>'kind' is distinct from 'AUD24_F05_BASELINE_AUTHORIZATION'
     or p_payload->>'finding_code' is distinct from 'AUD24-F05'
     or p_payload->>'head_sha' is distinct from p_head_sha
     or p_payload->>'subject_type' is distinct from 'f05_authority'
     or p_payload->>'subject_ref' is distinct from p_subject_ref
     or p_payload->>'subject_sha256' is distinct from p_subject_sha256
     or p_payload->>'verdict' is distinct from 'AUTHORIZED'
     or p_payload->'independent' is distinct from 'true'::jsonb
     or length(btrim(coalesce(p_payload->>'auditor_identity',''))) = 0
     or length(btrim(coalesce(p_payload->>'key_id',''))) = 0
     or length(btrim(coalesce(p_payload->>'signature_ed25519_b64',''))) = 0
     or length(btrim(coalesce(p_payload->>'evidence_sha256',''))) = 0 then
    raise exception 'F05_PAYLOAD_CONTRACT_MISMATCH';
  end if;

  select ds.decrypted_secret
    into v_channel_token
    from vault.decrypted_secrets ds
   where ds.name = 'programming_agent_f05_provenance_token_v1'
   order by ds.created_at desc
   limit 1;

  if v_channel_token is null or length(v_channel_token) < 32 then
    raise exception 'F05_PROVENANCE_TOKEN_NOT_PROVISIONED';
  end if;

  return query
  select r.id, r.receipt_sha256
    from programacion.issue_provenance_receipt(
      'F05_SUPABASE_PROTECTED_ISSUER_V1',
      v_channel_token,
      'AUD24_F05_BASELINE_AUTHORIZATION',
      null,
      p_head_sha,
      'f05_authority',
      p_subject_ref,
      p_subject_sha256,
      p_issuer_identity,
      p_verification_ref,
      p_payload
    ) r;
end;
$function$;

revoke all on function programacion.issue_f05_provenance_receipt_v1(
  text,text,text,text,text,jsonb
) from public, anon, authenticated;
grant execute on function programacion.issue_f05_provenance_receipt_v1(
  text,text,text,text,text,jsonb
) to service_role;
