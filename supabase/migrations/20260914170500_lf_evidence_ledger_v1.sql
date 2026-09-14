-- LF_EVIDENCE_LEDGER_V1
-- Generic durable evidence anchor for governed LF executions.
-- This migration creates no runtime/current/production/Golden activation.

do $preflight$
begin
  if not exists (
    select 1
    from public.lf_operation_execution
    where execution_id='EXEC-S31-EVIDENCE-LEDGER-V1-20260914-001'
      and operation_code='ACTUALIZACION_DB_LF'
      and target_type='MIGRATION'
      and target_code='S31_EVIDENCE_LEDGER_V1'
      and target_repo='cristhianlujan/claude-persona-lf-patch'
      and target_path='supabase/migrations/20260914170500_lf_evidence_ledger_v1.sql'
      and status='IN_PROGRESS'
  ) then
    raise exception 'BLOCK_S31_EVIDENCE_LEDGER_EXECUTION_BINDING';
  end if;

  if to_regclass('private.lf_evidence_ledger_v1') is not null
     or to_regclass('private.lf_evidence_resolver_registry_v1') is not null
     or to_regprocedure('private.fn_lf_evidence_ledger_guard_v1()') is not null
     or to_regprocedure('private.fn_lf_evidence_resolver_registry_immutable_v1()') is not null
     or to_regprocedure('public.fn_lf_evidence_ledger_anchor_v1(text,text,text,text,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,text)') is not null then
    raise exception 'BLOCK_S31_EVIDENCE_LEDGER_ALREADY_EXISTS';
  end if;
end
$preflight$;

create table private.lf_evidence_resolver_registry_v1 (
  resolver_id text primary key,
  provider text not null check (provider in ('GITHUB','SUPABASE','GOVERNED_EXTERNAL')),
  verification_method text not null,
  trust_level text not null check (trust_level in ('TRUSTED_PROVIDER_BOUND')),
  active boolean not null default true,
  description text not null,
  created_by_execution_id text not null references public.lf_operation_execution(execution_id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint lf_evidence_resolver_registry_v1_nonblank check (
    btrim(resolver_id)<>'' and btrim(verification_method)<>'' and btrim(description)<>''
  )
);

alter table private.lf_evidence_resolver_registry_v1 enable row level security;

insert into private.lf_evidence_resolver_registry_v1(
  resolver_id,provider,verification_method,trust_level,active,description,created_by_execution_id
) values
(
  'LF_GITHUB_SOURCE_READBACK_V1','GITHUB','GITHUB_API_READBACK_PLUS_OFFLINE_HASH','TRUSTED_PROVIDER_BOUND',true,
  'GitHub provider-bound source readback with independently recomputed local/offline material digest.',
  'EXEC-S31-EVIDENCE-LEDGER-V1-20260914-001'
),
(
  'LF_SUPABASE_READBACK_V1','SUPABASE','SUPABASE_SQL_READBACK_PLUS_DB_DIGEST','TRUSTED_PROVIDER_BOUND',true,
  'Supabase SQL readback with database-side digest recomputation for durable LF evidence.',
  'EXEC-S31-EVIDENCE-LEDGER-V1-20260914-001'
);

create or replace function private.fn_lf_evidence_resolver_registry_immutable_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','private'
as $fn$
begin
  raise exception 'BLOCK_LF_EVIDENCE_RESOLVER_REGISTRY_IMMUTABLE';
end
$fn$;

create trigger trg_lf_evidence_resolver_registry_immutable_v1
before update or delete on private.lf_evidence_resolver_registry_v1
for each row execute function private.fn_lf_evidence_resolver_registry_immutable_v1();

create table private.lf_evidence_ledger_v1 (
  receipt_id uuid primary key default gen_random_uuid(),
  execution_id text not null references public.lf_operation_execution(execution_id) on delete restrict,
  capability_code text not null references public.lf_capability_registry(capability_code) on delete restrict,
  gate_code text not null,
  receipt_kind text not null,
  subject_type text not null,
  subject_ref text not null,
  subject_sha256 text not null check (subject_sha256 ~ '^[0-9a-f]{64}$'),
  source_head_sha text not null check (source_head_sha ~ '^[0-9a-f]{40}$'),
  authority_ref text not null,
  resolver_id text not null references private.lf_evidence_resolver_registry_v1(resolver_id) on delete restrict,
  provider text not null check (provider in ('GITHUB','SUPABASE','GOVERNED_EXTERNAL')),
  provider_ref text not null,
  verification_method text not null,
  verification_state text not null check (verification_state in ('ANCHORED','VERIFIED','REJECTED')),
  verification_payload jsonb not null default '{}'::jsonb check (jsonb_typeof(verification_payload)='object'),
  receipt_payload jsonb not null check (jsonb_typeof(receipt_payload)='object'),
  receipt_sha256 text not null check (receipt_sha256 ~ '^[0-9a-f]{64}$'),
  created_by_execution_id text not null references public.lf_operation_execution(execution_id) on delete restrict,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  constraint lf_evidence_ledger_v1_receipt_sha256_key unique(receipt_sha256),
  constraint lf_evidence_ledger_v1_subject_binding_key unique(
    execution_id, capability_code, gate_code, receipt_kind, subject_ref, subject_sha256, source_head_sha
  ),
  constraint lf_evidence_ledger_v1_identity_nonblank check (
    btrim(gate_code)<>'' and btrim(receipt_kind)<>'' and btrim(subject_type)<>'' and btrim(subject_ref)<>''
    and btrim(authority_ref)<>'' and btrim(resolver_id)<>'' and btrim(provider_ref)<>'' and btrim(verification_method)<>''
  )
);

alter table private.lf_evidence_ledger_v1 enable row level security;

create index lf_evidence_ledger_v1_execution_idx
  on private.lf_evidence_ledger_v1(execution_id,created_at);
create index lf_evidence_ledger_v1_capability_gate_idx
  on private.lf_evidence_ledger_v1(capability_code,gate_code,created_at);
create index lf_evidence_ledger_v1_source_head_idx
  on private.lf_evidence_ledger_v1(source_head_sha);

create or replace function private.fn_lf_evidence_ledger_guard_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','private','public','extensions'
as $fn$
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
$fn$;

create trigger trg_lf_evidence_ledger_guard_v1
before insert or update or delete on private.lf_evidence_ledger_v1
for each row execute function private.fn_lf_evidence_ledger_guard_v1();

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
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','private','public','extensions'
as $fn$
declare
  v_envelope jsonb;
  v_receipt_sha256 text;
  v_receipt_id uuid;
  v_verified_at timestamptz;
begin
  if p_subject_sha256 !~ '^[0-9a-f]{64}$'
     or p_source_head_sha !~ '^[0-9a-f]{40}$' then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_HASH_FORMAT';
  end if;
  if p_verification_state not in ('ANCHORED','VERIFIED','REJECTED') then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_VERIFICATION_STATE';
  end if;
  if jsonb_typeof(coalesce(p_verification_payload,'null'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_receipt_payload,'null'::jsonb)) <> 'object' then
    raise exception 'BLOCK_LF_EVIDENCE_LEDGER_PAYLOAD_SHAPE';
  end if;

  v_verified_at := case when p_verification_state in ('VERIFIED','REJECTED') then now() else null end;
  v_envelope := jsonb_build_object(
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
    'resolver_id',p_resolver_id,
    'provider',p_provider,
    'provider_ref',p_provider_ref,
    'verification_method',p_verification_method,
    'verification_state',p_verification_state,
    'verification_payload',p_verification_payload,
    'receipt_payload',p_receipt_payload,
    'created_by_execution_id',p_actor_execution_id
  );
  v_receipt_sha256 := encode(extensions.digest(convert_to(v_envelope::text,'UTF8'),'sha256'),'hex');

  insert into private.lf_evidence_ledger_v1(
    execution_id,capability_code,gate_code,receipt_kind,subject_type,subject_ref,
    subject_sha256,source_head_sha,authority_ref,resolver_id,provider,provider_ref,
    verification_method,verification_state,verification_payload,receipt_payload,
    receipt_sha256,created_by_execution_id,verified_at
  ) values (
    p_execution_id,p_capability_code,p_gate_code,p_receipt_kind,p_subject_type,p_subject_ref,
    p_subject_sha256,p_source_head_sha,p_authority_ref,p_resolver_id,p_provider,p_provider_ref,
    p_verification_method,p_verification_state,p_verification_payload,p_receipt_payload,
    v_receipt_sha256,p_actor_execution_id,v_verified_at
  ) returning receipt_id into v_receipt_id;

  return jsonb_build_object(
    'schema_version','LF_EVIDENCE_LEDGER_ANCHOR_RESULT_V1',
    'receipt_id',v_receipt_id,
    'receipt_sha256',v_receipt_sha256,
    'verification_state',p_verification_state,
    'execution_id',p_execution_id,
    'capability_code',p_capability_code,
    'gate_code',p_gate_code
  );
end
$fn$;

revoke all on table private.lf_evidence_resolver_registry_v1 from public, anon, authenticated;
revoke all on table private.lf_evidence_ledger_v1 from public, anon, authenticated;
revoke all on function public.fn_lf_evidence_ledger_anchor_v1(text,text,text,text,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,text) from public, anon, authenticated;
grant execute on function public.fn_lf_evidence_ledger_anchor_v1(text,text,text,text,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,text) to service_role;

comment on table private.lf_evidence_resolver_registry_v1 is
'Immutable trusted resolver registry for LF durable evidence. Resolver trust is derived here, never caller-self-certified.';
comment on table private.lf_evidence_ledger_v1 is
'Append-only LF evidence ledger. VERIFIED requires a registered trusted resolver plus provider readback and digest recomputation proof. No row here authorizes runtime, production or Golden by itself.';
