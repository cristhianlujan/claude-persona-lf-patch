-- S31 CURRENTNESS_AUTHORITY / Evidence Ledger source-head anti-replay hardening v1.
-- Source-first only. No live apply, runtime, production or Golden activation in this commit.
-- Finding: a VERIFIED GitHub Evidence Ledger row could be re-anchored to a different
-- source_head_sha if the caller recomputed only the outer ledger digest while preserving
-- the old provider_ref/provider readback. That violates Currentness exact-revision evidence binding.

do $pre$
declare
  v_actual_sha text;
  v_bad integer;
begin
  select encode(
           extensions.digest(
             convert_to(pg_get_functiondef('private.fn_lf_evidence_ledger_guard_v1()'::regprocedure),'UTF8'),
             'sha256'
           ),
           'hex'
         )
    into v_actual_sha;

  if v_actual_sha is distinct from 'c5ba19d81030868b95bc0ee2f2e9180653d0c540d31a6ed5c89c4e45e979a598' then
    raise exception 'S31_EVIDENCE_SOURCE_HEAD_GUARD_FINGERPRINT_MISMATCH expected=% actual=%',
      'c5ba19d81030868b95bc0ee2f2e9180653d0c540d31a6ed5c89c4e45e979a598',
      v_actual_sha;
  end if;

  select count(*) into v_bad
  from private.lf_evidence_ledger_v1
  where provider='GITHUB'
    and (
      source_head_sha !~ '^[0-9a-f]{40}$'
      or provider_ref not like '%@' || source_head_sha
    );

  if v_bad<>0 then
    raise exception 'S31_EVIDENCE_SOURCE_HEAD_PREEXISTING_INCONSISTENCY:%',v_bad;
  end if;
end
$pre$;

create or replace function private.fn_lf_evidence_ledger_guard_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'private', 'public', 'extensions'
as $function$
declare
  v_execution_status text;
  v_resolver_provider text;
  v_resolver_method text;
  v_resolver_trust text;
  v_resolver_active boolean;
  v_envelope jsonb;
  v_digest text;
begin
  if tg_op <> 'INSERT' then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_APPEND_ONLY';
  end if;

  select status into v_execution_status
  from public.lf_operation_execution
  where execution_id=new.execution_id;
  if v_execution_status is null or v_execution_status not in ('IN_PROGRESS','COMPLETED') then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_EXECUTION_INVALID';
  end if;

  if not exists (
    select 1 from public.lf_operation_execution
    where execution_id=new.created_by_execution_id
  ) then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_ACTOR_EXECUTION_INVALID';
  end if;

  if not exists (
    select 1 from public.lf_capability_registry
    where capability_code=new.capability_code and status='ACTIVE'
  ) then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_CAPABILITY_INVALID';
  end if;

  select provider,verification_method,trust_level,active
    into v_resolver_provider,v_resolver_method,v_resolver_trust,v_resolver_active
  from private.lf_evidence_resolver_registry_v1
  where resolver_id=new.resolver_id;
  if v_resolver_provider is null
     or v_resolver_active is distinct from true
     or v_resolver_trust is distinct from 'TRUSTED_PROVIDER_BOUND'
     or v_resolver_provider is distinct from new.provider
     or v_resolver_method is distinct from new.verification_method then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_RESOLVER_TRUST_MISMATCH';
  end if;

  if new.receipt_payload->>'execution_id' is distinct from new.execution_id
     or new.receipt_payload->>'capability_code' is distinct from new.capability_code
     or new.receipt_payload->>'gate_code' is distinct from new.gate_code
     or new.receipt_payload->>'receipt_kind' is distinct from new.receipt_kind
     or new.receipt_payload->>'subject_type' is distinct from new.subject_type
     or new.receipt_payload->>'subject_ref' is distinct from new.subject_ref
     or new.receipt_payload->>'subject_sha256' is distinct from new.subject_sha256
     or new.receipt_payload->>'source_head_sha' is distinct from new.source_head_sha
     or new.receipt_payload->>'authority_ref' is distinct from new.authority_ref
     or new.receipt_payload->>'resolver_id' is distinct from new.resolver_id
     or new.receipt_payload->>'provider' is distinct from new.provider
     or new.receipt_payload->>'provider_ref' is distinct from new.provider_ref then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_PAYLOAD_BINDING_MISMATCH';
  end if;

  -- GitHub evidence must bind the provider readback to the exact source head.
  -- Recomputing only the outer Evidence Ledger digest must never turn old provider
  -- evidence into VERIFIED evidence for a different Git revision.
  if new.provider='GITHUB' then
    if new.source_head_sha !~ '^[0-9a-f]{40}$'
       or new.provider_ref not like '%@' || new.source_head_sha then
      raise exception 'BLOCK_LF_EVIDENCE_LEDGER_SOURCE_HEAD_PROVIDER_MISMATCH';
    end if;

    if jsonb_typeof(new.receipt_payload->'attestation')='object'
       and new.receipt_payload #>> '{attestation,commit_sha}' is distinct from new.source_head_sha then
      raise exception 'BLOCK_LF_EVIDENCE_LEDGER_SOURCE_HEAD_ATTESTATION_MISMATCH';
    end if;

    if jsonb_typeof(new.receipt_payload->'source_attestation')='object' then
      if new.receipt_payload #>> '{source_attestation,commit_sha}' is distinct from new.source_head_sha
         or new.receipt_payload #>> '{source_attestation,resolved_revision}' is distinct from new.source_head_sha then
        raise exception 'BLOCK_LF_EVIDENCE_LEDGER_SOURCE_HEAD_ATTESTATION_MISMATCH';
      end if;
    end if;

    if nullif(new.verification_payload->>'resolved_main_sha','') is not null
       and new.verification_payload->>'resolved_main_sha' is distinct from new.source_head_sha then
      raise exception 'BLOCK_LF_EVIDENCE_LEDGER_SOURCE_HEAD_READBACK_MISMATCH';
    end if;
  end if;

  if exists (
    select 1
    from private.lf_evidence_ledger_v1 prior
    where prior.capability_code=new.capability_code
      and prior.gate_code=new.gate_code
      and prior.receipt_kind=new.receipt_kind
      and prior.subject_ref=new.subject_ref
      and prior.subject_sha256=new.subject_sha256
      and prior.source_head_sha=new.source_head_sha
      and prior.execution_id is distinct from new.execution_id
  ) then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_SUBJECT_REPLAY';
  end if;

  if new.verification_state='ANCHORED' and new.verified_at is not null then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_PREMATURE_VERIFIED_AT';
  end if;

  if new.verification_state='VERIFIED' then
    if new.verified_at is null
       or new.verification_payload->'provider_readback_verified' is distinct from 'true'::jsonb
       or new.verification_payload->'digest_recomputed' is distinct from 'true'::jsonb then
      raise exception 'BLOCK_LF_EVIDENCE_LEDGER_VERIFICATION_PROOF_INCOMPLETE';
    end if;
  end if;

  v_envelope := jsonb_build_object(
    'schema_version','LF_EVIDENCE_LEDGER_RECEIPT_V1',
    'execution_id',new.execution_id,
    'capability_code',new.capability_code,
    'gate_code',new.gate_code,
    'receipt_kind',new.receipt_kind,
    'subject_type',new.subject_type,
    'subject_ref',new.subject_ref,
    'subject_sha256',new.subject_sha256,
    'source_head_sha',new.source_head_sha,
    'authority_ref',new.authority_ref,
    'resolver_id',new.resolver_id,
    'provider',new.provider,
    'provider_ref',new.provider_ref,
    'verification_method',new.verification_method,
    'verification_state',new.verification_state,
    'verification_payload',new.verification_payload,
    'receipt_payload',new.receipt_payload,
    'created_by_execution_id',new.created_by_execution_id
  );
  v_digest := encode(extensions.digest(convert_to(v_envelope::text,'UTF8'),'sha256'),'hex');
  if new.receipt_sha256 is distinct from v_digest then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_RECEIPT_DIGEST_MISMATCH';
  end if;

  return new;
end
$function$;

do $post$
declare
  v_def text;
begin
  select pg_get_functiondef('private.fn_lf_evidence_ledger_guard_v1()'::regprocedure)
    into v_def;

  if position('BLOCK_LF_EVIDENCE_LEDGER_SOURCE_HEAD_PROVIDER_MISMATCH' in coalesce(v_def,''))=0
     or position('BLOCK_LF_EVIDENCE_LEDGER_SOURCE_HEAD_ATTESTATION_MISMATCH' in coalesce(v_def,''))=0
     or position('BLOCK_LF_EVIDENCE_LEDGER_SOURCE_HEAD_READBACK_MISMATCH' in coalesce(v_def,''))=0 then
    raise exception 'S31_EVIDENCE_SOURCE_HEAD_GUARD_POSTCHECK_MISSING';
  end if;
end
$post$;
