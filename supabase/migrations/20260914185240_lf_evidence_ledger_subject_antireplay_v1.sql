-- S31 Evidence Ledger subject anti-replay v1
DO $pre$
DECLARE v_dups integer;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_execution
    WHERE execution_id='EXEC-S31-EVIDENCE-ANTIREPLAY-V1-20260914-001'
      AND operation_code='ACTUALIZACION_DB_LF'
      AND target_type='MIGRATION'
      AND target_code='S31_EVIDENCE_LEDGER_ANTIREPLAY_V1'
      AND target_path='supabase/migrations/20260914185240_lf_evidence_ledger_subject_antireplay_v1.sql'
      AND status='IN_PROGRESS'
  ) THEN
    RAISE EXCEPTION 'S31_EVIDENCE_ANTIREPLAY_EXECUTION_BINDING_INVALID';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_constraint c
    JOIN pg_class t ON t.oid=c.conrelid
    JOIN pg_namespace n ON n.oid=t.relnamespace
    WHERE n.nspname='private' AND t.relname='lf_evidence_ledger_v1'
      AND c.conname='lf_evidence_ledger_v1_global_subject_key'
  ) THEN
    RAISE EXCEPTION 'S31_EVIDENCE_ANTIREPLAY_ALREADY_APPLIED';
  END IF;

  SELECT count(*) INTO v_dups
  FROM (
    SELECT capability_code,gate_code,receipt_kind,subject_ref,subject_sha256,source_head_sha
    FROM private.lf_evidence_ledger_v1
    GROUP BY capability_code,gate_code,receipt_kind,subject_ref,subject_sha256,source_head_sha
    HAVING count(*)>1
  ) d;
  IF v_dups<>0 THEN
    RAISE EXCEPTION 'S31_EVIDENCE_ANTIREPLAY_PREEXISTING_DUPLICATES:%',v_dups;
  END IF;
END
$pre$;

ALTER TABLE private.lf_evidence_ledger_v1
  ADD CONSTRAINT lf_evidence_ledger_v1_global_subject_key
  UNIQUE (capability_code,gate_code,receipt_kind,subject_ref,subject_sha256,source_head_sha);

CREATE OR REPLACE FUNCTION private.fn_lf_evidence_ledger_guard_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog', 'private', 'public', 'extensions'
AS $function$
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

DO $post$
DECLARE v_def text;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c
    JOIN pg_class t ON t.oid=c.conrelid
    JOIN pg_namespace n ON n.oid=t.relnamespace
    WHERE n.nspname='private' AND t.relname='lf_evidence_ledger_v1'
      AND c.conname='lf_evidence_ledger_v1_global_subject_key'
  ) THEN
    RAISE EXCEPTION 'S31_EVIDENCE_ANTIREPLAY_GLOBAL_UNIQUE_MISSING';
  END IF;

  SELECT pg_get_functiondef(p.oid) INTO v_def
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='private' AND p.proname='fn_lf_evidence_ledger_guard_v1';
  IF position('BLOCK_LF_EVIDENCE_LEDGER_SUBJECT_REPLAY' in coalesce(v_def,''))=0 THEN
    RAISE EXCEPTION 'S31_EVIDENCE_ANTIREPLAY_GUARD_MISSING';
  END IF;
END
$post$;
