-- Evidence Ledger cross-binding hardening v1.
-- Same ledger/store and same public anchor entrypoint; no parallel evidence engine.
-- New writes separate producer execution from the EVIDENCE_LEDGER execution that performs the anchor.
-- Existing rows remain readable and untouched.

create unique index if not exists lf_evidence_ledger_v1_composition_sha256_uk
on private.lf_evidence_ledger_v1 ((receipt_payload->>'composition_sha256'))
where receipt_payload ? 'composition_sha256';

create or replace function private.fn_lf_evidence_ledger_guard_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','private','public','extensions'
as $function$
declare
  v_producer_status text;
  v_ledger_status text;
  v_producer_manifest jsonb;
  v_ledger_manifest jsonb;
  v_orchestrator_execution_id text;
  v_plan_digest text;
  v_resolver_id text;
  v_resolver_count integer;
  v_envelope jsonb;
  v_digest text;
  v_composition_preimage jsonb;
  v_composition_sha256 text;
  v_ref_sha text;
  v_subject_ref_sha text;
begin
  if tg_op <> 'INSERT' then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_APPEND_ONLY';
  end if;

  -- Producer execution owns the evidence being anchored.
  select status,manifest into v_producer_status,v_producer_manifest
  from public.lf_operation_execution
  where execution_id=new.execution_id;
  if v_producer_status is null or v_producer_status not in ('IN_PROGRESS','COMPLETED') then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_PRODUCER_EXECUTION_INVALID';
  end if;

  -- created_by_execution_id is the dedicated EVIDENCE_LEDGER capability execution.
  select status,manifest into v_ledger_status,v_ledger_manifest
  from public.lf_operation_execution
  where execution_id=new.created_by_execution_id;
  if v_ledger_status is distinct from 'IN_PROGRESS' then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_EXECUTION_INVALID';
  end if;
  if v_ledger_manifest->>'capability_code' is distinct from 'EVIDENCE_LEDGER' then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_EXECUTION_CAPABILITY_MISMATCH';
  end if;
  v_orchestrator_execution_id:=nullif(v_ledger_manifest->>'orchestrator_execution_id','');
  v_plan_digest:=nullif(v_ledger_manifest->>'plan_digest','');
  if v_orchestrator_execution_id is null or coalesce(v_plan_digest,'') !~ '^[0-9a-f]{64}$' then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_ORCHESTRATOR_CONTEXT_INVALID';
  end if;

  if not exists (
    select 1 from private.lf_orchestrator_dispatch_receipts_v1 d
    where d.orchestrator_execution_id=v_orchestrator_execution_id
      and d.consumer_execution_id=new.created_by_execution_id
      and d.capability_code='EVIDENCE_LEDGER'
      and d.plan_digest=v_plan_digest
  ) then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_DISPATCH_RECEIPT_MISSING';
  end if;

  if not exists (
    select 1
    from public.lf_capability_binding b
    join public.lf_capability_current c
      on c.capability_code=b.capability_code
     and c.version=b.bound_version
     and c.manifest_sha256=b.bound_manifest_sha256
    where b.execution_id=new.created_by_execution_id
      and b.capability_code='EVIDENCE_LEDGER'
      and b.binding_state in ('BOUND','PINNED')
  ) then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_CURRENT_BINDING_MISSING';
  end if;

  -- Producer and Ledger must belong to the exact same orchestrated plan.
  if v_producer_manifest->>'orchestrator_execution_id' is distinct from v_orchestrator_execution_id
     or v_producer_manifest->>'plan_digest' is distinct from v_plan_digest
     or v_producer_manifest->>'capability_code' is distinct from new.capability_code then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_PRODUCER_CROSSBIND_MISMATCH';
  end if;

  if not exists (
    select 1 from public.lf_capability_registry
    where capability_code=new.capability_code and status='ACTIVE'
  ) then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_CAPABILITY_INVALID';
  end if;

  -- Resolver identity is derived from the trusted immutable registry, not from candidate payload.
  select count(*),min(resolver_id)
    into v_resolver_count,v_resolver_id
  from private.lf_evidence_resolver_registry_v1
  where provider=new.provider
    and verification_method=new.verification_method
    and trust_level='TRUSTED_PROVIDER_BOUND'
    and active;
  if v_resolver_count<>1 or v_resolver_id is null then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_TRUSTED_RESOLVER_NOT_UNIQUE';
  end if;
  if new.resolver_id is distinct from v_resolver_id then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_RESOLVER_IDENTITY_MISMATCH';
  end if;

  if new.receipt_payload->>'execution_id' is distinct from new.execution_id
     or new.receipt_payload->>'producer_execution_id' is distinct from new.execution_id
     or new.receipt_payload->>'capability_code' is distinct from new.capability_code
     or new.receipt_payload->>'producer_capability_code' is distinct from new.capability_code
     or new.receipt_payload->>'ledger_execution_id' is distinct from new.created_by_execution_id
     or new.receipt_payload->>'orchestrator_execution_id' is distinct from v_orchestrator_execution_id
     or new.receipt_payload->>'plan_digest' is distinct from v_plan_digest
     or new.receipt_payload->>'gate_code' is distinct from new.gate_code
     or new.receipt_payload->>'receipt_kind' is distinct from new.receipt_kind
     or new.receipt_payload->>'subject_type' is distinct from new.subject_type
     or new.receipt_payload->>'subject_ref' is distinct from new.subject_ref
     or new.receipt_payload->>'subject_sha256' is distinct from new.subject_sha256
     or new.receipt_payload->>'source_head_sha' is distinct from new.source_head_sha
     or new.receipt_payload->>'authority_ref' is distinct from new.authority_ref
     or new.receipt_payload->>'resolver_id' is distinct from v_resolver_id
     or new.receipt_payload->>'provider' is distinct from new.provider
     or new.receipt_payload->>'provider_ref' is distinct from new.provider_ref then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_PAYLOAD_BINDING_MISMATCH';
  end if;

  -- Provider-specific source identity cross-binding. A source revision cannot be re-anchored.
  if new.provider='GITHUB' then
    v_ref_sha:=substring(new.provider_ref from '@([0-9a-f]{40})(/|$)');
    if v_ref_sha is null or v_ref_sha is distinct from new.source_head_sha then
      raise exception 'BLOCK_LF_EVIDENCE_LEDGER_GITHUB_PROVIDER_REF_HEAD_MISMATCH';
    end if;
    if new.subject_ref like 'github://%' then
      v_subject_ref_sha:=substring(new.subject_ref from '@([0-9a-f]{40})(/|#|$)');
      if v_subject_ref_sha is null or v_subject_ref_sha is distinct from new.source_head_sha then
        raise exception 'BLOCK_LF_EVIDENCE_LEDGER_GITHUB_SUBJECT_REF_HEAD_MISMATCH';
      end if;
    end if;
    if new.verification_payload->>'resolved_main_sha' is not null
       and new.verification_payload->>'resolved_main_sha' is distinct from new.source_head_sha then
      raise exception 'BLOCK_LF_EVIDENCE_LEDGER_RESOLVED_MAIN_HEAD_MISMATCH';
    end if;
    if new.receipt_payload#>>'{source_attestation,commit_sha}' is not null
       and new.receipt_payload#>>'{source_attestation,commit_sha}' is distinct from new.source_head_sha then
      raise exception 'BLOCK_LF_EVIDENCE_LEDGER_SOURCE_ATTESTATION_HEAD_MISMATCH';
    end if;
    if new.receipt_payload#>>'{source_attestation,resolved_revision}' is not null
       and new.receipt_payload#>>'{source_attestation,resolved_revision}' is distinct from new.source_head_sha then
      raise exception 'BLOCK_LF_EVIDENCE_LEDGER_SOURCE_ATTESTATION_REVISION_MISMATCH';
    end if;
    if new.receipt_payload#>>'{attestation,commit_sha}' is not null
       and new.receipt_payload#>>'{attestation,commit_sha}' is distinct from new.source_head_sha then
      raise exception 'BLOCK_LF_EVIDENCE_LEDGER_ATTESTATION_HEAD_MISMATCH';
    end if;
    if new.receipt_payload#>>'{attestation,resolved_revision}' is not null
       and new.receipt_payload#>>'{attestation,resolved_revision}' is distinct from new.source_head_sha then
      raise exception 'BLOCK_LF_EVIDENCE_LEDGER_ATTESTATION_REVISION_MISMATCH';
    end if;
    if new.receipt_payload#>>'{hydrated_authority,resolved_revision}' is not null
       and new.receipt_payload#>>'{hydrated_authority,resolved_revision}' is distinct from new.source_head_sha then
      raise exception 'BLOCK_LF_EVIDENCE_LEDGER_HYDRATED_AUTHORITY_REVISION_MISMATCH';
    end if;
    if new.receipt_payload#>>'{hydrated_authority,current_revision}' is not null
       and new.receipt_payload#>>'{hydrated_authority,current_revision}' is distinct from new.source_head_sha then
      raise exception 'BLOCK_LF_EVIDENCE_LEDGER_HYDRATED_AUTHORITY_CURRENT_MISMATCH';
    end if;
  end if;

  v_composition_preimage:=jsonb_build_object(
    'schema_version','LF_EVIDENCE_COMPOSITION_V1',
    'orchestrator_execution_id',v_orchestrator_execution_id,
    'plan_digest',v_plan_digest,
    'ledger_execution_id',new.created_by_execution_id,
    'producer_execution_id',new.execution_id,
    'producer_capability_code',new.capability_code,
    'gate_code',new.gate_code,
    'receipt_kind',new.receipt_kind,
    'subject_type',new.subject_type,
    'subject_ref',new.subject_ref,
    'subject_sha256',new.subject_sha256,
    'source_head_sha',new.source_head_sha,
    'authority_ref',new.authority_ref,
    'resolver_id',v_resolver_id,
    'provider',new.provider,
    'provider_ref',new.provider_ref,
    'verification_method',new.verification_method
  );
  v_composition_sha256:=encode(extensions.digest(convert_to(v_composition_preimage::text,'UTF8'),'sha256'),'hex');
  if new.receipt_payload->>'composition_sha256' is distinct from v_composition_sha256 then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_COMPOSITION_DIGEST_MISMATCH';
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

  v_envelope:=jsonb_build_object(
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
  v_digest:=encode(extensions.digest(convert_to(v_envelope::text,'UTF8'),'sha256'),'hex');
  if new.receipt_sha256 is distinct from v_digest then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_RECEIPT_DIGEST_MISMATCH';
  end if;

  return new;
end
$function$;

create or replace function public.fn_lf_evidence_ledger_anchor_v1(
  p_execution_id text,
  p_capability_code text,
  p_gate_code text,
  p_receipt_kind text,
  p_subject_type text,
  p_subject_ref text,
  p_subject_sha256 text,
  p_source_head_sha text,
  p_authority_ref text,
  p_resolver_id text,
  p_provider text,
  p_provider_ref text,
  p_verification_method text,
  p_verification_state text,
  p_verification_payload jsonb,
  p_receipt_payload jsonb,
  p_actor_execution_id text
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','private','public','extensions'
as $function$
declare
  v_ledger_manifest jsonb;
  v_orchestrator_execution_id text;
  v_plan_digest text;
  v_resolver_id text;
  v_resolver_count integer;
  v_bound_receipt_payload jsonb;
  v_composition_preimage jsonb;
  v_composition_sha256 text;
  v_envelope jsonb;
  v_receipt_sha256 text;
  v_receipt_id uuid;
  v_verified_at timestamptz;
  v_existing private.lf_evidence_ledger_v1%rowtype;
begin
  if p_subject_sha256 !~ '^[0-9a-f]{64}$' or p_source_head_sha !~ '^[0-9a-f]{40}$' then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_HASH_FORMAT';
  end if;
  if p_verification_state not in ('ANCHORED','VERIFIED','REJECTED') then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_VERIFICATION_STATE';
  end if;
  if jsonb_typeof(coalesce(p_verification_payload,'null'::jsonb))<>'object'
     or jsonb_typeof(coalesce(p_receipt_payload,'null'::jsonb))<>'object' then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_PAYLOAD_SHAPE';
  end if;

  select manifest into v_ledger_manifest
  from public.lf_operation_execution
  where execution_id=p_actor_execution_id and status='IN_PROGRESS';
  if v_ledger_manifest is null or v_ledger_manifest->>'capability_code' is distinct from 'EVIDENCE_LEDGER' then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_EXECUTION_INVALID';
  end if;
  v_orchestrator_execution_id:=nullif(v_ledger_manifest->>'orchestrator_execution_id','');
  v_plan_digest:=nullif(v_ledger_manifest->>'plan_digest','');
  if v_orchestrator_execution_id is null or coalesce(v_plan_digest,'') !~ '^[0-9a-f]{64}$' then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_ORCHESTRATOR_CONTEXT_INVALID';
  end if;

  select count(*),min(resolver_id) into v_resolver_count,v_resolver_id
  from private.lf_evidence_resolver_registry_v1
  where provider=p_provider
    and verification_method=p_verification_method
    and trust_level='TRUSTED_PROVIDER_BOUND'
    and active;
  if v_resolver_count<>1 or v_resolver_id is null then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_TRUSTED_RESOLVER_NOT_UNIQUE';
  end if;
  if p_resolver_id is distinct from v_resolver_id then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_RESOLVER_IDENTITY_MISMATCH';
  end if;

  v_composition_preimage:=jsonb_build_object(
    'schema_version','LF_EVIDENCE_COMPOSITION_V1',
    'orchestrator_execution_id',v_orchestrator_execution_id,
    'plan_digest',v_plan_digest,
    'ledger_execution_id',p_actor_execution_id,
    'producer_execution_id',p_execution_id,
    'producer_capability_code',p_capability_code,
    'gate_code',p_gate_code,
    'receipt_kind',p_receipt_kind,
    'subject_type',p_subject_type,
    'subject_ref',p_subject_ref,
    'subject_sha256',p_subject_sha256,
    'source_head_sha',p_source_head_sha,
    'authority_ref',p_authority_ref,
    'resolver_id',v_resolver_id,
    'provider',p_provider,
    'provider_ref',p_provider_ref,
    'verification_method',p_verification_method
  );
  v_composition_sha256:=encode(extensions.digest(convert_to(v_composition_preimage::text,'UTF8'),'sha256'),'hex');

  v_bound_receipt_payload:=coalesce(p_receipt_payload,'{}'::jsonb) || jsonb_build_object(
    'execution_id',p_execution_id,
    'producer_execution_id',p_execution_id,
    'capability_code',p_capability_code,
    'producer_capability_code',p_capability_code,
    'ledger_execution_id',p_actor_execution_id,
    'orchestrator_execution_id',v_orchestrator_execution_id,
    'plan_digest',v_plan_digest,
    'gate_code',p_gate_code,
    'receipt_kind',p_receipt_kind,
    'subject_type',p_subject_type,
    'subject_ref',p_subject_ref,
    'subject_sha256',p_subject_sha256,
    'source_head_sha',p_source_head_sha,
    'authority_ref',p_authority_ref,
    'resolver_id',v_resolver_id,
    'provider',p_provider,
    'provider_ref',p_provider_ref,
    'composition_sha256',v_composition_sha256
  );

  v_verified_at:=case when p_verification_state in ('VERIFIED','REJECTED') then now() else null end;
  v_envelope:=jsonb_build_object(
    'schema_version','LF_EVIDENCE_LEDGER_RECEIPT_V1',
    'execution_id',p_execution_id,
    'capability_code',p_capability_code,
    'gate_code',p_gate_code,
    'receipt_kind',p_receipt_kind,
    'subject_type',p_subject_type,
    'subject_ref',p_subject_ref,
    'subject_sha256',p_subject_sha256,
    'source_head_sha',p_source_head_sha,
    'authority_ref',p_authority_ref,
    'resolver_id',v_resolver_id,
    'provider',p_provider,
    'provider_ref',p_provider_ref,
    'verification_method',p_verification_method,
    'verification_state',p_verification_state,
    'verification_payload',p_verification_payload,
    'receipt_payload',v_bound_receipt_payload,
    'created_by_execution_id',p_actor_execution_id
  );
  v_receipt_sha256:=encode(extensions.digest(convert_to(v_envelope::text,'UTF8'),'sha256'),'hex');

  select * into v_existing
  from private.lf_evidence_ledger_v1
  where receipt_payload->>'composition_sha256'=v_composition_sha256;
  if found then
    if v_existing.receipt_sha256 is distinct from v_receipt_sha256 then
      raise exception 'BLOCK_LF_EVIDENCE_LEDGER_COMPOSITION_REPLAY_CONFLICT';
    end if;
    return jsonb_build_object(
      'schema_version','LF_EVIDENCE_LEDGER_ANCHOR_RESULT_V1',
      'decision','IDEMPOTENT_REPLAY',
      'receipt_id',v_existing.receipt_id,
      'receipt_sha256',v_existing.receipt_sha256,
      'composition_sha256',v_composition_sha256,
      'verification_state',v_existing.verification_state,
      'execution_id',p_execution_id,
      'capability_code',p_capability_code,
      'gate_code',p_gate_code
    );
  end if;

  insert into private.lf_evidence_ledger_v1(
    execution_id,capability_code,gate_code,receipt_kind,subject_type,subject_ref,
    subject_sha256,source_head_sha,authority_ref,resolver_id,provider,provider_ref,
    verification_method,verification_state,verification_payload,receipt_payload,
    receipt_sha256,created_by_execution_id,verified_at
  ) values (
    p_execution_id,p_capability_code,p_gate_code,p_receipt_kind,p_subject_type,p_subject_ref,
    p_subject_sha256,p_source_head_sha,p_authority_ref,v_resolver_id,p_provider,p_provider_ref,
    p_verification_method,p_verification_state,p_verification_payload,v_bound_receipt_payload,
    v_receipt_sha256,p_actor_execution_id,v_verified_at
  ) returning receipt_id into v_receipt_id;

  return jsonb_build_object(
    'schema_version','LF_EVIDENCE_LEDGER_ANCHOR_RESULT_V1',
    'decision','ANCHORED',
    'receipt_id',v_receipt_id,
    'receipt_sha256',v_receipt_sha256,
    'composition_sha256',v_composition_sha256,
    'verification_state',p_verification_state,
    'execution_id',p_execution_id,
    'capability_code',p_capability_code,
    'gate_code',p_gate_code
  );
end
$function$;

revoke all on function public.fn_lf_evidence_ledger_anchor_v1(text,text,text,text,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,text) from public,anon,authenticated;
grant execute on function public.fn_lf_evidence_ledger_anchor_v1(text,text,text,text,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,text) to service_role;
