-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M3.5 / PAULO-044
-- Resolver-specific evidence receipts reuse the canonical EVIDENCE_LEDGER and
-- TYPED_EVIDENCE_REGISTRY. No parallel evidence store is created.

begin;

-- Fail closed on missing canonical surfaces.
do $preflight$
begin
  if to_regclass('private.lf_evidence_ledger_v1') is null then
    raise exception 'M3_5_EVIDENCE_LEDGER_MISSING';
  end if;
  if to_regclass('private.lf_evidence_resolver_registry_v1') is null then
    raise exception 'M3_5_RESOLVER_REGISTRY_MISSING';
  end if;
  if to_regclass('private.lf_typed_evidence_schema_registry_v3') is null then
    raise exception 'M3_5_TYPED_EVIDENCE_REGISTRY_MISSING';
  end if;
  if to_regprocedure('private.fn_lf_typed_evidence_payload_valid_v3(text,jsonb)') is null then
    raise exception 'M3_5_TYPED_EVIDENCE_VALIDATOR_MISSING';
  end if;
  if to_regprocedure('public.fn_lf_evidence_ledger_anchor_v1(text,text,text,text,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,text)') is null then
    raise exception 'M3_5_EVIDENCE_LEDGER_ANCHOR_MISSING';
  end if;
  if not pg_has_role(current_user,'lf_governance_owner_v3','SET') then
    raise exception 'M3_5_GOVERNANCE_ROLE_SET_MISSING';
  end if;
end
$preflight$;

set local role lf_governance_owner_v3;

-- Register the IG resolver receipt payload in the canonical typed evidence registry.
do $schema$
declare
  v_required_keys text[] := array[
    'evidence_schema_version','resolver_id','resolver_version','sources',
    'subject_sha256','source_head_sha','authority_ref','input_sha256','output_sha256'
  ];
  v_description text := 'IG resolver evidence receipt: exact sources+SHA, authority, subject and input/output digests.';
  v_registry_payload jsonb;
  v_registry_sha256 text;
begin
  v_registry_payload := jsonb_build_object(
    'schema_version','ig-resolver-receipt/v1',
    'validator_version','v3.2',
    'required_keys',to_jsonb(v_required_keys),
    'description',v_description
  );
  v_registry_sha256 := encode(extensions.digest(convert_to(v_registry_payload::text,'UTF8'),'sha256'),'hex');

  insert into private.lf_typed_evidence_schema_registry_v3(
    schema_version,validator_version,required_keys,description,
    registered_by_execution_id,registry_sha256,active
  )
  select
    'ig-resolver-receipt/v1','v3.2',v_required_keys,v_description,
    'PAULO-044',v_registry_sha256,true
  where not exists (
    select 1 from private.lf_typed_evidence_schema_registry_v3
    where schema_version='ig-resolver-receipt/v1'
  );

  if not exists (
    select 1 from private.lf_typed_evidence_schema_registry_v3
    where schema_version='ig-resolver-receipt/v1' and active
  ) then
    raise exception 'M3_5_TYPED_SCHEMA_REGISTRATION_FAILED';
  end if;
end
$schema$;

-- Extend the canonical typed validator. Existing schema behavior is preserved;
-- only the new IG resolver receipt case is added.
create or replace function private.fn_lf_typed_evidence_payload_valid_v3(p_schema text, p_payload jsonb)
returns boolean
language plpgsql
stable
set search_path to 'pg_catalog','private','extensions'
as $function$
declare
  r private.lf_typed_evidence_schema_registry_v3%rowtype;
begin
  select * into r
  from private.lf_typed_evidence_schema_registry_v3
  where schema_version=p_schema and active;

  if not found or jsonb_typeof(p_payload)<>'object' or not (p_payload ?& r.required_keys) then
    return false;
  end if;

  case p_schema
    when 'ig-resolver-receipt/v1' then
      return p_payload->>'evidence_schema_version'='ig-resolver-receipt/v1'
        and nullif(p_payload->>'resolver_id','') is not null
        and coalesce(p_payload->>'resolver_version','') ~ '^v[0-9]+$'
        and jsonb_typeof(p_payload->'sources')='array'
        and jsonb_array_length(p_payload->'sources')>0
        and not exists (
          select 1
          from jsonb_array_elements(p_payload->'sources') s
          where jsonb_typeof(s)<>'object'
             or nullif(s->>'source_ref','') is null
             or coalesce(s->>'source_sha256','') !~ '^[0-9a-f]{64}$'
        )
        and coalesce(p_payload->>'subject_sha256','') ~ '^[0-9a-f]{64}$'
        and coalesce(p_payload->>'source_head_sha','') ~ '^[0-9a-f]{40}$'
        and nullif(p_payload->>'authority_ref','') is not null
        and coalesce(p_payload->>'input_sha256','') ~ '^[0-9a-f]{64}$'
        and coalesce(p_payload->>'output_sha256','') ~ '^[0-9a-f]{64}$';
    when 'architecture-baseline/v1' then
      return jsonb_typeof(p_payload->'blocked')='number'
        and jsonb_typeof(p_payload->'not_validated')='number'
        and jsonb_typeof(p_payload->'pass_with_evidence')='number'
        and private.fn_lf_try_timestamptz(p_payload->>'frozen_at') is not null
        and nullif(p_payload->>'execution_id','') is not null;
    when 'architecture-gate-test/v1' then
      return jsonb_typeof(p_payload->'all_confirmed')='boolean'
        and jsonb_typeof(p_payload->'probe_persistence')='boolean'
        and jsonb_typeof(p_payload->'positive_control_count')='number'
        and jsonb_typeof(p_payload->'negative_rejection_count')='number';
    when 'architecture-program/v2' then
      return jsonb_typeof(p_payload->'gate_tests')='object'
        and jsonb_typeof(p_payload->'capabilities')='object'
        and jsonb_typeof(p_payload->'stored_status')='object'
        and jsonb_typeof(p_payload->'effective_status')='object'
        and private.fn_lf_try_timestamptz(p_payload->>'completed_at') is not null
        and nullif(p_payload->>'execution_id','') is not null;
    when 'architecture-reconciliation/v2' then
      return jsonb_typeof(p_payload->'artifact_count')='number'
        and jsonb_typeof(p_payload->'closure_ready')='boolean'
        and private.fn_lf_try_timestamptz(p_payload->>'reconciled_at') is not null
        and nullif(p_payload->>'skill_code','') is not null
        and nullif(p_payload->>'execution_id','') is not null;
    when 'context-budget/v1' then
      return jsonb_typeof(p_payload->'estimated_tokens')='number'
        and p_payload->>'context_status' in ('GREEN','YELLOW','RED')
        and private.fn_lf_try_timestamptz(p_payload->>'recorded_at') is not null
        and nullif(p_payload->>'execution_id','') is not null;
    when 'dependency-auto-reopen/v2' then
      return jsonb_typeof(p_payload->'artifact_id')='number'
        and jsonb_typeof(p_payload->'root_artifact_id')='number'
        and private.fn_lf_try_timestamptz(p_payload->>'reopened_at') is not null
        and nullif(p_payload->>'execution_id','') is not null;
    when 'event-type-contract-governance/v1' then
      return p_payload->>'decision'='APPROVED'
        and jsonb_typeof(p_payload->'request_id')='number'
        and nullif(p_payload->>'event_type','') is not null
        and coalesce(p_payload->>'proposed_contract_sha256','') ~ '^[0-9a-f]{64}$'
        and private.fn_lf_try_timestamptz(p_payload->>'approved_at') is not null
        and nullif(p_payload->>'execution_id','') is not null;
    when 'gate-test-run/v3' then
      return jsonb_typeof(p_payload->'artifact_id')='number'
        and jsonb_typeof(p_payload->'probe_preimage')='object'
        and p_payload->'probe_preimage'<>'{}'::jsonb
        and jsonb_typeof(p_payload->'expected_outcome')='object'
        and jsonb_typeof(p_payload->'observed_outcome')='object'
        and jsonb_typeof(p_payload->'persisted_effects')='object'
        and jsonb_typeof(p_payload->'passed')='boolean'
        and coalesce(p_payload->>'probe_sha256','') ~ '^[0-9a-f]{64}$'
        and coalesce(p_payload->>'persisted_effects_sha256','') ~ '^[0-9a-f]{64}$'
        and coalesce(p_payload->>'evidence_payload_sha256','') ~ '^[0-9a-f]{64}$'
        and p_payload->>'writer_authentication'='GITHUB_OIDC_HMAC_NONCE_V7'
        and coalesce(p_payload->>'writer_signature_sha256','') ~ '^[0-9a-f]{64}$'
        and coalesce(p_payload->>'writer_nonce_sha256','') ~ '^[0-9a-f]{64}$'
        and private.fn_lf_try_timestamptz(p_payload->>'writer_proof_expires_at') is not null;
    when 'github-reconciliation/v2' then
      return jsonb_typeof(p_payload->'results')='array'
        and jsonb_typeof(p_payload->'result_count')='number'
        and p_payload->>'connector_mode'='CONNECTOR_LIVE_READBACK'
        and private.fn_lf_try_timestamptz(p_payload->>'reconciled_at') is not null
        and nullif(p_payload->>'repository','') is not null
        and nullif(p_payload->>'execution_id','') is not null;
    when 'legacy-reaudit/v2' then
      return jsonb_typeof(p_payload->'legacy_event_id')='number'
        and nullif(p_payload->>'classification','') is not null
        and nullif(p_payload->>'execution_id','') is not null;
    when 'test-evidence/v2' then
      return jsonb_typeof(p_payload->'row_id')='number'
        and jsonb_typeof(p_payload->'test_no')='number'
        and jsonb_typeof(p_payload->'actual')='object'
        and jsonb_typeof(p_payload->'expected')='object'
        and jsonb_typeof(p_payload->'comparison_passed')='boolean'
        and coalesce(p_payload->>'artifact_sha256','') ~ '^[0-9a-f]{64}$'
        and coalesce(p_payload->>'artifact_git_blob','') ~ '^[0-9a-f]{40}$'
        and private.fn_lf_try_timestamptz(p_payload->>'executed_at') is not null;
    when 'validation-exemption-governance/v1' then
      return p_payload->>'decision'='APPROVED'
        and nullif(p_payload->>'event_type','') is not null
        and coalesce(p_payload->>'exemption_sha256','') ~ '^[0-9a-f]{64}$'
        and nullif(p_payload->>'execution_id','') is not null;
    when 'event-contract-baseline/v3' then
      return jsonb_typeof(p_payload->'contract_count')='number'
        and coalesce(p_payload->>'registry_sha256','') ~ '^[0-9a-f]{64}$'
        and jsonb_typeof(p_payload->'contract_versions')='object'
        and private.fn_lf_try_timestamptz(p_payload->>'approved_at') is not null
        and nullif(p_payload->>'execution_id','') is not null;
    when 'artifact-repository-sync/v3' then
      return jsonb_typeof(p_payload->'artifact_id')='number'
        and nullif(p_payload->>'relative_path','') is not null
        and coalesce(p_payload->>'previous_sha256','') ~ '^[0-9a-f]{64}$'
        and coalesce(p_payload->>'repository_sha256','') ~ '^[0-9a-f]{64}$'
        and coalesce(p_payload->>'artifact_git_blob','') ~ '^[0-9a-f]{40}$'
        and coalesce(p_payload->>'merge_commit_sha','') ~ '^[0-9a-f]{40}$'
        and jsonb_typeof(p_payload->'workflow_run_id')='number'
        and jsonb_typeof(p_payload->'repository_sync_run_id')='number'
        and private.fn_lf_try_timestamptz(p_payload->>'synced_at') is not null
        and nullif(p_payload->>'execution_id','') is not null;
    else
      return false;
  end case;
exception when others then
  return false;
end
$function$;

-- Canonical resolver receipt emitter. It owns no store; it validates a typed
-- payload and delegates persistence/idempotence/anti-replay to EVIDENCE_LEDGER.
create or replace function public.fn_ig_resolver_receipt_emit_v1(
  p_execution_id text,
  p_capability_code text,
  p_gate_code text,
  p_subject_type text,
  p_subject_ref text,
  p_subject_sha256 text,
  p_source_head_sha text,
  p_authority_ref text,
  p_resolver_id text,
  p_provider_ref text,
  p_sources jsonb,
  p_input_sha256 text,
  p_output_sha256 text,
  p_actor_execution_id text,
  p_verification_state text default 'ANCHORED',
  p_verification_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path to 'pg_catalog','private','public'
as $function$
declare
  v_provider text;
  v_verification_method text;
  v_trust_level text;
  v_active boolean;
  v_resolver_version text;
  v_payload jsonb;
  v_result jsonb;
begin
  select provider,verification_method,trust_level,active
    into v_provider,v_verification_method,v_trust_level,v_active
  from private.lf_evidence_resolver_registry_v1
  where resolver_id=p_resolver_id;

  if v_provider is null
     or v_active is distinct from true
     or v_trust_level is distinct from 'TRUSTED_PROVIDER_BOUND' then
    raise exception 'M3_5_RESOLVER_NOT_TRUSTED_OR_ACTIVE';
  end if;

  v_resolver_version := 'v'||coalesce(substring(p_resolver_id from '_V([0-9]+)$'),'');
  if v_resolver_version !~ '^v[0-9]+$' then
    raise exception 'M3_5_RESOLVER_VERSION_UNRESOLVED';
  end if;

  v_payload := jsonb_build_object(
    'evidence_schema_version','ig-resolver-receipt/v1',
    'resolver_id',p_resolver_id,
    'resolver_version',v_resolver_version,
    'sources',p_sources,
    'subject_sha256',p_subject_sha256,
    'source_head_sha',p_source_head_sha,
    'authority_ref',p_authority_ref,
    'input_sha256',p_input_sha256,
    'output_sha256',p_output_sha256
  );

  if not private.fn_lf_typed_evidence_payload_valid_v3('ig-resolver-receipt/v1',v_payload) then
    raise exception 'M3_5_RESOLVER_RECEIPT_TYPED_PAYLOAD_INVALID';
  end if;

  v_result := public.fn_lf_evidence_ledger_anchor_v1(
    p_execution_id,
    p_capability_code,
    p_gate_code,
    'RESOLVER_EVIDENCE',
    p_subject_type,
    p_subject_ref,
    p_subject_sha256,
    p_source_head_sha,
    p_authority_ref,
    p_resolver_id,
    v_provider,
    p_provider_ref,
    v_verification_method,
    p_verification_state,
    coalesce(p_verification_payload,'{}'::jsonb),
    v_payload,
    p_actor_execution_id
  );

  return v_result || jsonb_build_object(
    'evidence_schema_version','ig-resolver-receipt/v1',
    'resolver_id',p_resolver_id,
    'resolver_version',v_resolver_version
  );
end
$function$;

revoke all on function public.fn_ig_resolver_receipt_emit_v1(
  text,text,text,text,text,text,text,text,text,text,jsonb,text,text,text,text,jsonb
) from public,anon,authenticated;
grant execute on function public.fn_ig_resolver_receipt_emit_v1(
  text,text,text,text,text,text,text,text,text,text,jsonb,text,text,text,text,jsonb
) to service_role;

comment on function public.fn_ig_resolver_receipt_emit_v1(
  text,text,text,text,text,text,text,text,text,text,jsonb,text,text,text,text,jsonb
) is 'M3.5 canonical resolver evidence receipt emitter. Validates ig-resolver-receipt/v1 and persists only through EVIDENCE_LEDGER.';

reset role;
commit;
