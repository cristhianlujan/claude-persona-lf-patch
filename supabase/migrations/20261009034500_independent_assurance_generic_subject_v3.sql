-- T-INDEP / PAULO-035 — INDEPENDENT_ASSURANCE generic subject extension v3 candidate.
-- Owner: SUPER_ADMIN.
-- Architecture invariant: extend the existing reviewer operation/judges in place.
-- This migration MUST NOT create a second INDEPENDENT_REVIEW operation, Router action or judge set.
--
-- Activation invariant:
--   1) apply this migration only after exact-head R17/preflight;
--   2) requalify REVISION_INDEPENDIENTE_ESTRATEGIA_LF at its new exact revision immediately after APPLY;
--   3) only then promote INDEPENDENT_ASSURANCE 2.0.0 current through fn_lf_capability_promote_v1;
--   4) Story Creator remains fail-closed until that current pointer + provider-bound review receipt exist.
--
-- No production activation, scheduler activation or business write is introduced here.

-- -----------------------------------------------------------------------------
-- 0. Fail-closed preflight: the existing engine must be the only engine.
-- -----------------------------------------------------------------------------
do $pre$
declare
  v_count integer;
  v_revision text;
begin
  select count(*) into v_count
  from public.lf_operation_registry
  where operation_type='INDEPENDENT_REVIEW';
  if v_count <> 1 then
    raise exception 'BLOCK_T_INDEP_INDEPENDENT_REVIEW_OPERATION_COUNT:%',v_count;
  end if;

  if not exists (
    select 1 from public.lf_operation_registry
    where operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
      and operation_type='INDEPENDENT_REVIEW'
      and lifecycle_state_code='OP_OPERATIONAL'
  ) then
    raise exception 'BLOCK_T_INDEP_CANONICAL_OPERATION_NOT_OPERATIONAL';
  end if;

  if not exists (
    select 1 from public.lf_router_action_registry
    where asset_type='STRATEGY'
      and action_code='STRATEGY_INDEPENDENT_REVIEW'
      and operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
      and status='ACTIVE'
  ) then
    raise exception 'BLOCK_T_INDEP_STRATEGY_COMPAT_ROUTE_MISSING';
  end if;

  select count(*) into v_count
  from public.lf_operation_judges
  where operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
    and status='ACTIVE_ENFORCEMENT';
  if v_count <> 6 then
    raise exception 'BLOCK_T_INDEP_CANONICAL_JUDGE_COUNT:%',v_count;
  end if;

  if exists (
    select 1 from public.lf_operation_registry
    where operation_code='REVISION_INDEPENDIENTE_LF'
  ) then
    raise exception 'BLOCK_T_INDEP_PARALLEL_OPERATION_PRESENT';
  end if;

  if exists (
    select 1 from public.lf_router_action_registry
    where asset_type='REVIEW_SUBJECT' and action_code='INDEPENDENT_REVIEW'
  ) then
    raise exception 'BLOCK_T_INDEP_PARALLEL_ROUTE_PRESENT';
  end if;

  if not exists (
    select 1 from public.lf_activos
    where codigo_activo='INDEPENDENT_ASSURANCE'
      and archived_at is null
      and estado_operativo='ACTIVO'
      and owner_name='SUPER_ADMIN'
      and metadata#>>'{transversal_inventory,inventory_status}'='ACTIVE_SHARED_ENFORCEMENT'
  ) then
    raise exception 'BLOCK_T_INDEP_CAPABILITY_INVENTORY_INVALID';
  end if;

  if not exists(
    select 1 from public.lf_capability_current
    where capability_code='INDEPENDENT_ASSURANCE'
      and version='1.0.1'
      and manifest_sha256='b12c44ca0e07d2da4fdcb27f7e8e8da311dfcdaf390e645d45a3cf407a31e6c1'
  ) then
    raise exception 'BLOCK_T_INDEP_PRECHANGE_CURRENT_1_0_1_NOT_EXACT';
  end if;

  v_revision:=public.lf_operation_revision_sha256_v1('REVISION_INDEPENDIENTE_ESTRATEGIA_LF');
  if not public.lf_qualification_current_v1('OPERATION','REVISION_INDEPENDIENTE_ESTRATEGIA_LF',v_revision) then
    raise exception 'BLOCK_T_INDEP_PRECHANGE_OPERATION_QUALIFICATION_NOT_CURRENT:%',v_revision;
  end if;
end
$pre$;

-- -----------------------------------------------------------------------------
-- 1. Capability registry/version projection. No current pointer is promoted here.
-- -----------------------------------------------------------------------------
insert into public.lf_capability_registry(
  capability_code,capability_name,capability_kind,owner_scope,status,description,
  created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code
) values (
  'INDEPENDENT_ASSURANCE','Independent Assurance','TRANSVERSAL','SUPER_ADMIN','ACTIVE',
  'Independent Assurance capability. Current behavior is selected by lf_capability_current; candidate v3 generalizes subject review by contract through the existing REVISION_INDEPENDIENTE_ESTRATEGIA_LF operation and judges without subject-name whitelists.',
  'EXEC-REQUAL-INDEPENDENT-REVIEW-BASELINE-20261003-001','EXEC-REQUAL-INDEPENDENT-REVIEW-BASELINE-20261003-001',true,'ORCHESTRATOR_EXECUTION_GUARD_V1'
)
on conflict(capability_code) do update set
  capability_name=excluded.capability_name,
  capability_kind=excluded.capability_kind,
  owner_scope='SUPER_ADMIN',
  status='ACTIVE',
  description=excluded.description,
  entry_guard_required=true,
  entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1',
  updated_at=clock_timestamp(),
  updated_by_execution_id='EXEC-REQUAL-INDEPENDENT-REVIEW-BASELINE-20261003-001';

do $manifest$
declare
  v_manifest jsonb;
  v_sha text;
  v_existing text;
begin
  v_manifest:=jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1',
    'capability_code','INDEPENDENT_ASSURANCE',
    'version','2.0.0',
    'contract',jsonb_build_object(
      'schema_version','lf-independent-review-subject-contract/v3',
      'subject_contract',jsonb_build_object(
        'mode','CONTRACT_DRIVEN_ANY_SUBJECT',
        'subject_type_policy','OPAQUE_NONEMPTY_IDENTIFIER',
        'subject_type_whitelist',false,
        'required_envelope_fields',jsonb_build_array(
          'subject_type','subject_ref','subject_sha256','source_head_sha','subject_receipt_id',
          'producer_execution_id','reviewer_execution_id','review_required','required_dimensions'
        ),
        'required_dimensions','CALLER_BOUND_NONEMPTY_ARRAY',
        'subject_authority','EVIDENCE_LEDGER + CURRENTNESS_AUTHORITY'
      ),
      'invalid_subject_contract','BLOCK_SUBJECT_CONTRACT_INVALID'
    ),
    'delivery',jsonb_build_object(
      'mode','EXISTING_OPERATION_IN_PLACE_EXTENSION',
      'operation_code','REVISION_INDEPENDIENTE_ESTRATEGIA_LF',
      'reuse_existing_step_judges',true,
      'new_operation',false,
      'new_router_action',false,
      'new_judge_codes',false,
      'review_receipt_store','EVIDENCE_LEDGER'
    ),
    'installation',jsonb_build_object(
      'required',false,
      'package_update_mode','DATABASE_NATIVE_GIT_FIRST_MIGRATION',
      'current_pointer_promoted_by_migration',false,
      'promotion_after_operation_requalification',true
    ),
    'dependencies',jsonb_build_object(
      'capabilities',jsonb_build_array('EVIDENCE_LEDGER','CURRENTNESS_AUTHORITY'),
      'governance',jsonb_build_array('ORCHESTRATOR_EXECUTION_GUARD_V1','OPERATION_STEP_CONTRACT_JUDGE_ENFORCEMENT','QUALIFICATION_FRAMEWORK')
    ),
    'compatibility',jsonb_build_object(
      'strategy_route_preserved',true,
      'strategy_begin_signature_preserved',true,
      'strategy_record_judge_signature_preserved',true,
      'strategy_finalizer_signature_preserved',true,
      'generic_subject_must_not_map_to_strategy',true,
      'unknown_subject','FAIL_CLOSED'
    ),
    'migration',jsonb_build_object(
      'work_code','PAULO-035',
      'mode','IN_PLACE_OPERATION_GENERALIZATION',
      'requires_requalification',true,
      'no_parallel_stack',true
    ),
    'rollback',jsonb_build_object(
      'supported',true,
      'rule','RESTORE_OPERATION_METADATA_STEP_CONTRACTS_JUDGE_ASSERTIONS_AND_STRATEGY_RECORDER;REMOVE_CAPABILITY_CURRENT_IF_PROMOTED;PRESERVE_EVIDENCE_HISTORY'
    ),
    'usage',jsonb_build_object(
      'entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1',
      'generic_begin','public.lf_independent_review_begin_v3',
      'generic_step_recorder','public.lf_record_independent_review_step_v3',
      'legacy_strategy_begin','public.lf_independent_strategy_review_begin_v1',
      'legacy_strategy_route','STRATEGY_INDEPENDENT_REVIEW'
    ),
    'currentness',jsonb_build_object(
      'authority_ref','public.lf_capability_current + EVIDENCE_LEDGER + CURRENTNESS_AUTHORITY',
      'promotion_precondition','OPERATION_REQUALIFIED_AT_EXACT_POST_MIGRATION_REVISION',
      'current_pointer_expected_after_promotion',true
    )
  );
  v_sha:=encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  select manifest_sha256 into v_existing
  from public.lf_capability_version_registry
  where capability_code='INDEPENDENT_ASSURANCE' and version='2.0.0';
  if v_existing is not null and v_existing<>v_sha then
    raise exception 'BLOCK_T_INDEP_CAPABILITY_VERSION_MANIFEST_CONFLICT';
  end if;

  insert into public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,
    supersedes_version,manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
  ) values (
    'INDEPENDENT_ASSURANCE','2.0.0',2,0,0,'RELEASED','1.0.1',
    v_manifest,v_sha,
    'supabase/migrations/20261009034500_independent_assurance_generic_subject_v3.sql',
    'sandbox/lf_contract_gate_test/transversal_assets/independent_assurance/README.md',
    'sandbox/lf_contract_gate_test/transversal_assets/independent_assurance/validate_independent_review_subject_envelope_v3.py',
    'EXEC-REQUAL-INDEPENDENT-REVIEW-BASELINE-20261003-001'
  ) on conflict(capability_code,version) do nothing;

  if not exists(
    select 1 from public.lf_capability_current
    where capability_code='INDEPENDENT_ASSURANCE'
      and version='1.0.1'
      and manifest_sha256='b12c44ca0e07d2da4fdcb27f7e8e8da311dfcdaf390e645d45a3cf407a31e6c1'
  ) then
    raise exception 'BLOCK_T_INDEP_BASE_CURRENT_1_0_1_MISSING_OR_DRIFTED';
  end if;
end
$manifest$;

-- -----------------------------------------------------------------------------
-- 2. Generalize the existing operation in place. No new operation/route/judge row.
-- -----------------------------------------------------------------------------
update public.lf_operation_registry
set applies_to_asset_type=null,
    notes=concat_ws(E'\n',nullif(notes,''),
      'T-INDEP v2: existing operation generalized in place for exact subject-aware review. STRATEGY route remains backward-compatible specialization; new consumers enter through INDEPENDENT_ASSURANCE capability binding.'),
    updated_at=clock_timestamp(),
    updated_by_execution_id='EXEC-REQUAL-INDEPENDENT-REVIEW-BASELINE-20261003-001'
where operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF';

update public.lf_operation_contracts
set required_before_write=jsonb_build_array(
      'exact_subject_identity','exact_subject_revision','producer_reviewer_separation',
      'governed_entry_or_legacy_strategy_route','provider_bound_subject_authority'
    ),
    allowed=jsonb_build_object(
      'review_type',jsonb_build_array('INDEPENDENT_REVIEW','INDEPENDENT_HOLDOUT'),
      'subject_contract_mode','CONTRACT_DRIVEN_ANY_SUBJECT',
      'subject_type_whitelist',false,
      'business_write_allowed',false,
      'runtime_activation',false,
      'production_activation',false,
      'strategy_compatibility_route_preserved',true
    ),
    blocked=jsonb_build_array(
      'producer_equals_reviewer','unsupported_subject','stale_subject','missing_provider_bound_authority',
      'hardcoded_strategy_fallback_for_non_strategy','business_write','runtime_activation','production_activation'
    ),
    required_after_write=jsonb_build_array('durable_review_receipt','evidence_refs','authority_readback','next_gate'),
    updated_at=clock_timestamp(),
    updated_by_execution_id='EXEC-REQUAL-INDEPENDENT-REVIEW-BASELINE-20261003-001'
where operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
  and status='ACTIVE_ENFORCEMENT';

-- Generic evidence keys; legacy Strategy wrapper below maps its existing evidence into these keys.
update public.lf_operation_step_contracts
set purpose=case step_id
    when 'route_bind' then 'Bind governed entry to the existing independent-review operation; Strategy may use its legacy compatibility route.'
    when 'target_currentness' then 'Bind exact subject identity/revision to current provider-bound authority and prove review is required.'
    when 'semantic_review' then 'Persist independent semantic verdict, rationale and exact evidence references for the bound subject.'
    when 'judge_record' then 'Persist or bind the governed review decision record for the exact subject.'
    when 'reviewer_readback' then 'Read back review record and exact subject/currentness before completion.'
    when 'report_output' then 'Emit durable provider-bound review receipt, evidence refs, authority readback and next gate.'
    else purpose end,
  required_evidence_keys=case step_id
    when 'route_bind' then jsonb_build_array('entry_receipt','operation_code')
    when 'target_currentness' then jsonb_build_array('subject_type','subject_ref','subject_sha256','authority_ref','currentness_ref')
    when 'semantic_review' then jsonb_build_array('verdict','review_type','review_context','rationale_summary','evidence_refs')
    when 'judge_record' then jsonb_build_array('review_record_ref','verdict','subject_sha256')
    when 'reviewer_readback' then jsonb_build_array('review_record_ref','subject_sha256','authority_readback_ref')
    when 'report_output' then jsonb_build_array('review_receipt','evidence_refs','authority_readback','next_gate')
    else required_evidence_keys end,
  output_payload=case step_id
    when 'route_bind' then jsonb_build_array('entry_receipt','operation_code')
    when 'target_currentness' then jsonb_build_array('subject_type','subject_ref','subject_sha256','authority_ref','currentness_ref')
    when 'semantic_review' then jsonb_build_array('verdict','review_type','review_context','rationale_summary','evidence_refs')
    when 'judge_record' then jsonb_build_array('review_record_ref','verdict','subject_sha256')
    when 'reviewer_readback' then jsonb_build_array('review_record_ref','subject_sha256','authority_readback_ref')
    when 'report_output' then jsonb_build_array('review_receipt','evidence_refs','authority_readback','next_gate')
    else output_payload end,
  updated_at=clock_timestamp(),
  updated_by_execution_id='EXEC-REQUAL-INDEPENDENT-REVIEW-BASELINE-20261003-001'
where operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
  and step_id in ('route_bind','target_currentness','semantic_review','judge_record','reviewer_readback','report_output')
  and status='ACTIVE_ENFORCEMENT';

update public.lf_operation_step_judge_bindings
set required_evidence_keys=case step_id
    when 'route_bind' then jsonb_build_array('entry_receipt','operation_code')
    when 'target_currentness' then jsonb_build_array('subject_type','subject_ref','subject_sha256','authority_ref','currentness_ref')
    when 'semantic_review' then jsonb_build_array('verdict','review_type','review_context','rationale_summary','evidence_refs')
    when 'judge_record' then jsonb_build_array('review_record_ref','verdict','subject_sha256')
    when 'reviewer_readback' then jsonb_build_array('review_record_ref','subject_sha256','authority_readback_ref')
    when 'report_output' then jsonb_build_array('review_receipt','evidence_refs','authority_readback','next_gate')
    else required_evidence_keys end,
  updated_at=clock_timestamp(),
  updated_by_execution_id='EXEC-REQUAL-INDEPENDENT-REVIEW-BASELINE-20261003-001'
where operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
  and step_id in ('route_bind','target_currentness','semantic_review','judge_record','reviewer_readback','report_output')
  and status='ACTIVE_ENFORCEMENT';

-- Reuse the six existing judge rows; only their assertion vocabulary becomes subject-neutral.
update public.lf_operation_judges
set pass_if=case judge_code
    when 'JUDGE-INDEPENDENT-STRATEGY-REVIEW-ROUTE-v1' then jsonb_build_array('entry_ready','operation_exact')
    when 'JUDGE-INDEPENDENT-STRATEGY-REVIEW-CURRENTNESS-v1' then jsonb_build_array('subject_bound','subject_revision_current','authority_current','review_required')
    when 'JUDGE-INDEPENDENT-STRATEGY-REVIEW-SEMANTIC-v1' then jsonb_build_array('review_receipt_shape_valid','review_context_independent','evidence_refs_present','verdict_allowed')
    when 'JUDGE-INDEPENDENT-STRATEGY-REVIEW-JUDGE-v1' then jsonb_build_array('review_record_persisted','review_record_bound','review_verdict_matches')
    when 'JUDGE-INDEPENDENT-STRATEGY-REVIEW-READBACK-v1' then jsonb_build_array('review_record_readback','subject_still_current','review_still_required')
    when 'JUDGE-INDEPENDENT-STRATEGY-REVIEW-REPORT-v1' then jsonb_build_array('all_prior_clean','reviewer_ready_to_complete','subject_still_current','authority_readback_present')
    else pass_if end,
  fail_if=case judge_code
    when 'JUDGE-INDEPENDENT-STRATEGY-REVIEW-ROUTE-v1' then jsonb_build_array('entry_invalid')
    when 'JUDGE-INDEPENDENT-STRATEGY-REVIEW-CURRENTNESS-v1' then jsonb_build_array('subject_stale')
    when 'JUDGE-INDEPENDENT-STRATEGY-REVIEW-SEMANTIC-v1' then jsonb_build_array('review_receipt_invalid')
    when 'JUDGE-INDEPENDENT-STRATEGY-REVIEW-JUDGE-v1' then jsonb_build_array('review_record_invalid')
    when 'JUDGE-INDEPENDENT-STRATEGY-REVIEW-READBACK-v1' then jsonb_build_array('readback_invalid')
    when 'JUDGE-INDEPENDENT-STRATEGY-REVIEW-REPORT-v1' then jsonb_build_array('completion_invalid')
    else fail_if end,
  updated_at=clock_timestamp(),
  updated_by_execution_id='EXEC-REQUAL-INDEPENDENT-REVIEW-BASELINE-20261003-001'
where operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
  and judge_code in (
    'JUDGE-INDEPENDENT-STRATEGY-REVIEW-ROUTE-v1',
    'JUDGE-INDEPENDENT-STRATEGY-REVIEW-CURRENTNESS-v1',
    'JUDGE-INDEPENDENT-STRATEGY-REVIEW-SEMANTIC-v1',
    'JUDGE-INDEPENDENT-STRATEGY-REVIEW-JUDGE-v1',
    'JUDGE-INDEPENDENT-STRATEGY-REVIEW-READBACK-v1',
    'JUDGE-INDEPENDENT-STRATEGY-REVIEW-REPORT-v1'
  ) and status='ACTIVE_ENFORCEMENT';

-- -----------------------------------------------------------------------------
-- 3. Generic subject begin. It uses the same operation; no Router action is added.
--    The operation execution is reserved first only inside this transaction; a failed
--    capability bind raises and rolls back the reservation.
-- -----------------------------------------------------------------------------
create or replace function public.lf_independent_review_begin_v3(
  p_execution_id text,
  p_subject_type text,
  p_subject_ref text,
  p_subject_sha256 text,
  p_source_head_sha text,
  p_subject_receipt_id uuid,
  p_producer_execution_id text,
  p_expected_capability_manifest_sha256 text,
  p_plan_digest text,
  p_dispatch_receipt_id uuid,
  p_request_sha256 text,
  p_idempotency_key text,
  p_actor_execution_id text,
  p_manifest jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,private,extensions
as $fn$
declare
  v_subject private.lf_evidence_ledger_v1%rowtype;
  v_current public.lf_capability_current%rowtype;
  v_version public.lf_capability_version_registry%rowtype;
  v_reserve jsonb;
  v_bind jsonb;
  v_manifest jsonb;
begin
  if nullif(btrim(coalesce(p_subject_type,'')),'') is null then
    return jsonb_build_object('result','BLOCKED','code','SUBJECT_TYPE_MISSING');
  end if;
  if jsonb_typeof(coalesce(p_manifest->'required_dimensions','null'::jsonb))<>'array'
     or jsonb_array_length(p_manifest->'required_dimensions')=0 then
    return jsonb_build_object('result','BLOCKED','code','REQUIRED_DIMENSIONS_MISSING');
  end if;
  if coalesce((p_manifest->>'review_required')::boolean,true) is not true then
    return jsonb_build_object('result','BLOCKED','code','REVIEW_NOT_REQUIRED');
  end if;
  if coalesce(p_subject_sha256,'') !~ '^[0-9a-f]{64}$' or coalesce(p_source_head_sha,'') !~ '^[0-9a-f]{40}$' then
    return jsonb_build_object('result','BLOCKED','code','SUBJECT_HASH_INVALID');
  end if;
  if nullif(btrim(p_subject_ref),'') is null or nullif(btrim(p_producer_execution_id),'') is null then
    return jsonb_build_object('result','BLOCKED','code','SUBJECT_OR_PRODUCER_IDENTITY_MISSING');
  end if;
  if p_execution_id=p_producer_execution_id then
    return jsonb_build_object('result','BLOCKED','code','BUILDER_REVIEWER_NOT_INDEPENDENT');
  end if;

  select * into v_subject from private.lf_evidence_ledger_v1 where receipt_id=p_subject_receipt_id;
  if not found or v_subject.verification_state<>'VERIFIED'
     or v_subject.subject_type<>p_subject_type
     or v_subject.subject_ref<>p_subject_ref
     or v_subject.subject_sha256<>p_subject_sha256
     or v_subject.source_head_sha<>p_source_head_sha then
    return jsonb_build_object('result','BLOCKED','code','SUBJECT_PROVIDER_BOUND_RECEIPT_INVALID');
  end if;

  select * into v_current from public.lf_capability_current where capability_code='INDEPENDENT_ASSURANCE';
  if not found then return jsonb_build_object('result','BLOCKED','code','BLOCK_NO_CURRENT_CAPABILITY'); end if;
  if v_current.manifest_sha256<>p_expected_capability_manifest_sha256 then
    return jsonb_build_object('result','BLOCKED','code','BLOCK_CURRENTNESS_MISMATCH');
  end if;
  select * into v_version from public.lf_capability_version_registry
  where capability_code='INDEPENDENT_ASSURANCE' and version=v_current.version;
  if not found
     or coalesce(v_version.manifest#>>'{contract,subject_contract,mode}','')<>'CONTRACT_DRIVEN_ANY_SUBJECT'
     or coalesce((v_version.manifest#>>'{contract,subject_contract,subject_type_whitelist}')::boolean,true) is not false then
    return jsonb_build_object('result','BLOCKED','code','GENERIC_SUBJECT_CONTRACT_NOT_CURRENT');
  end if;

  v_manifest:=p_manifest||jsonb_build_object(
    'capability_code','INDEPENDENT_ASSURANCE',
    'capability_manifest_sha256',v_current.manifest_sha256,
    'subject_type',p_subject_type,
    'subject_ref',p_subject_ref,
    'subject_sha256',p_subject_sha256,
    'source_head_sha',p_source_head_sha,
    'subject_receipt_id',p_subject_receipt_id::text,
    'producer_execution_id',p_producer_execution_id,
    'review_required',true,
    'required_dimensions',p_manifest->'required_dimensions',
    'runtime_activation',false,
    'production_activation',false,
    'business_effect_allowed',false
  );

  v_reserve:=public.fn_lf_operation_reserve_execution_v1(
    p_execution_id,'REVISION_INDEPENDIENTE_ESTRATEGIA_LF',p_subject_type,p_subject_ref,
    p_idempotency_key,p_request_sha256,p_actor_execution_id,null,null,v_manifest
  );
  if v_reserve->>'status'<>'IN_PROGRESS' then
    raise exception 'BLOCK_T_INDEP_REVIEW_RESERVATION:%',v_reserve;
  end if;

  v_bind:=public.fn_lf_capability_bind_from_orchestrator_v1(
    p_execution_id,'INDEPENDENT_ASSURANCE',p_expected_capability_manifest_sha256,
    p_plan_digest,p_dispatch_receipt_id,p_actor_execution_id
  );
  if coalesce((v_bind->>'ready')::boolean,false) is not true then
    raise exception 'BLOCK_T_INDEP_CAPABILITY_BIND:%',v_bind;
  end if;

  update public.lf_operation_execution
  set manifest=manifest||jsonb_build_object('capability_binding_receipt',v_bind),
      updated_at=clock_timestamp(),updated_by_execution_id=p_actor_execution_id
  where execution_id=p_execution_id;

  return v_reserve||jsonb_build_object(
    'capability_binding_receipt',v_bind,
    'subject_receipt_id',p_subject_receipt_id::text,
    'next_step','route_bind'
  );
end
$fn$;

-- -----------------------------------------------------------------------------
-- 4. Subject-aware recorder. Same six step IDs + same six judge rows.
--    For every non-Strategy subject, the existing EVIDENCE_LEDGER is the review-record/receipt store.
-- -----------------------------------------------------------------------------
create or replace function public.lf_record_independent_review_step_v3(
  p_execution_id text,
  p_step_id text,
  p_evidence_ref text,
  p_evidence_payload jsonb,
  p_actor_execution_id text,
  p_evidence_ledger_execution_id text default null
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,private,extensions
as $fn$
declare
  x public.lf_operation_execution%rowtype;
  q public.lf_qualification_receipts%rowtype;
  tr public.lf_test_runs%rowtype;
  jr public.lf_test_judge_results%rowtype;
  subject_receipt private.lf_evidence_ledger_v1%rowtype;
  review_receipt private.lf_evidence_ledger_v1%rowtype;
  route jsonb;
  rev text;
  fp text;
  qid uuid;
  trid uuid;
  jrid uuid;
  sid bigint;
  review_receipt_id uuid;
  assertions jsonb:='[]'::jsonb;
  hard_fails jsonb:='[]'::jsonb;
  valid boolean:=true;
  code text:='OK';
  trust jsonb;
  payload jsonb;
  verdict text;
  anchor jsonb;
  step_digest text;
  required_dims jsonb;
  observed_dims jsonb;
  prior_bad integer:=0;
begin
  if p_evidence_payload is null or jsonb_typeof(p_evidence_payload)<>'object' then
    return jsonb_build_object('outcome','BLOCKED','code','EVIDENCE_PAYLOAD_INVALID','durable',false);
  end if;
  select * into x from public.lf_operation_execution where execution_id=p_execution_id for update;
  if not found or x.operation_code<>'REVISION_INDEPENDIENTE_ESTRATEGIA_LF' or x.status<>'IN_PROGRESS' then
    return jsonb_build_object('outcome','BLOCKED','code','EXECUTION_IDENTITY_INVALID','durable',false);
  end if;
  if nullif(btrim(coalesce(x.target_type,'')),'') is null then
    return jsonb_build_object('outcome','BLOCKED','code','SUBJECT_TYPE_MISSING','durable',false);
  end if;
  if x.manifest->>'producer_execution_id'=p_execution_id then
    return jsonb_build_object('outcome','BLOCKED','code','BUILDER_REVIEWER_NOT_INDEPENDENT','durable',false);
  end if;

  payload:=p_evidence_payload;

  if x.target_type='STRATEGY' then
    begin
      qid:=(x.manifest->>'qualification_id')::uuid;
      trid:=(x.manifest->>'test_run_id')::uuid;
      sid:=(x.manifest->>'snapshot_id')::bigint;
    exception when others then
      return jsonb_build_object('outcome','BLOCKED','code','EXECUTION_MANIFEST_BINDING_INVALID','durable',false);
    end;
    rev:=public.lf_strategy_revision_sha256_v1(sid);
    fp:=public.lf_required_test_suite_fingerprint_v1('STRATEGY',x.target_code);
    select * into q from public.lf_qualification_receipts where qualification_id=qid;
    select * into tr from public.lf_test_runs where test_run_id=trid;
  else
    begin review_receipt_id:=nullif(x.manifest->>'review_receipt_id','')::uuid; exception when others then review_receipt_id:=null; end;
    select * into subject_receipt from private.lf_evidence_ledger_v1
    where receipt_id=(x.manifest->>'subject_receipt_id')::uuid;
    if not found or subject_receipt.verification_state<>'VERIFIED'
       or subject_receipt.subject_type<>x.target_type
       or subject_receipt.subject_ref<>x.target_code
       or subject_receipt.subject_sha256<>x.manifest->>'subject_sha256'
       or subject_receipt.source_head_sha<>x.manifest->>'source_head_sha' then
      valid:=false; code:='SUBJECT_PROVIDER_BOUND_RECEIPT_INVALID'; hard_fails:=hard_fails||'"subject_stale"'::jsonb;
    end if;
  end if;

  if p_step_id='route_bind' then
    if x.target_type='STRATEGY' then
      route:=public.lf_router_resolve_v1('revision independiente de qualification de estrategia',null,'STRATEGY_INDEPENDENT_REVIEW','STRATEGY','ROUTER');
      if route->>'status'='READY_TO_EXECUTE' then assertions:=assertions||'"entry_ready"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"entry_invalid"'::jsonb; code:='ROUTE_INVALID'; end if;
      if route->>'operation_code'='REVISION_INDEPENDIENTE_ESTRATEGIA_LF' then assertions:=assertions||'"operation_exact"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"entry_invalid"'::jsonb; code:='OPERATION_MISMATCH'; end if;
      payload:=payload||jsonb_build_object('entry_receipt',route,'operation_code','REVISION_INDEPENDIENTE_ESTRATEGIA_LF');
    else
      if exists (
        select 1 from public.lf_capability_binding b
        join public.lf_capability_current c on c.capability_code=b.capability_code
        where b.execution_id=p_execution_id and b.capability_code='INDEPENDENT_ASSURANCE'
          and b.bound_manifest_sha256=c.manifest_sha256 and b.binding_state in ('BOUND','PINNED')
      ) then assertions:=assertions||'"entry_ready"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"entry_invalid"'::jsonb; code:='CAPABILITY_BINDING_NOT_CURRENT'; end if;
      assertions:=assertions||'"operation_exact"'::jsonb;
      payload:=payload||jsonb_build_object('entry_receipt',x.manifest->'capability_binding_receipt','operation_code','REVISION_INDEPENDIENTE_ESTRATEGIA_LF');
    end if;

  elsif p_step_id='target_currentness' then
    if x.target_type='STRATEGY' then
      if q.qualification_id=qid and q.subject_code=x.target_code and q.lifecycle_state_code='QUAL_QUALIFYING' then assertions:=assertions||'"subject_bound"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"subject_stale"'::jsonb; code:='QUALIFICATION_NOT_BOUND'; end if;
      if rev=x.manifest->>'revision_sha256' and q.revision_sha256=rev then assertions:=assertions||'"subject_revision_current"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"subject_stale"'::jsonb; code:='REVISION_STALE'; end if;
      if fp=x.manifest->>'suite_set_fingerprint' and q.suite_set_fingerprint=fp then assertions:=assertions||'"authority_current"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"subject_stale"'::jsonb; code:='SUITE_FINGERPRINT_STALE'; end if;
      if tr.test_run_id=trid and tr.status='REVIEW_REQUIRED' and tr.test_code='A03' and tr.input_payload->>'probe_code'='INDEPENDENT_REVIEW' and tr.suite_run_id=any(q.suite_run_ids) then assertions:=assertions||'"review_required"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"subject_stale"'::jsonb; code:='TEST_NOT_REVIEW_REQUIRED'; end if;
      payload:=payload||jsonb_build_object('subject_type','STRATEGY','subject_ref',x.target_code,'subject_sha256',rev,'authority_ref','supabase://public/lf_qualification_receipts/'||qid::text,'currentness_ref','supabase://public/lf_test_runs/'||trid::text);
    else
      if valid then assertions:=assertions||'"subject_bound"'::jsonb||'"subject_revision_current"'::jsonb||'"authority_current"'::jsonb; end if;
      if coalesce((x.manifest->>'review_required')::boolean,false) then assertions:=assertions||'"review_required"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"subject_stale"'::jsonb; code:='REVIEW_NOT_REQUIRED_BY_CONTRACT'; end if;
      payload:=payload||jsonb_build_object('subject_type',x.target_type,'subject_ref',x.target_code,'subject_sha256',x.manifest->>'subject_sha256','authority_ref',subject_receipt.authority_ref,'currentness_ref','supabase://private/lf_evidence_ledger_v1/'||subject_receipt.receipt_id::text);
    end if;

  elsif p_step_id='semantic_review' then
    verdict:=upper(coalesce(payload->>'verdict',''));
    if verdict in ('PASS','FAIL') and nullif(btrim(coalesce(payload->>'rationale_summary','')),'') is not null
       and payload->>'review_type' in ('INDEPENDENT_REVIEW','INDEPENDENT_HOLDOUT') then assertions:=assertions||'"review_receipt_shape_valid"'::jsonb||'"verdict_allowed"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"review_receipt_invalid"'::jsonb; code:='REVIEW_RECEIPT_INVALID'; end if;
    if payload->>'review_context'='INDEPENDENT_OPERATION_CONTEXT' then assertions:=assertions||'"review_context_independent"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"review_receipt_invalid"'::jsonb; code:='REVIEW_CONTEXT_INVALID'; end if;
    if jsonb_typeof(payload->'evidence_refs')='array' and jsonb_array_length(payload->'evidence_refs')>0 then assertions:=assertions||'"evidence_refs_present"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"review_receipt_invalid"'::jsonb; code:='REVIEW_EVIDENCE_MISSING'; end if;
    if x.target_type<>'STRATEGY' then
      required_dims:=coalesce(x.manifest->'required_dimensions','[]'::jsonb);
      observed_dims:=coalesce(payload->'utility_dimensions_checked','[]'::jsonb);
      if jsonb_typeof(observed_dims)<>'array' or not (observed_dims @> required_dims and required_dims @> observed_dims) then
        valid:=false; hard_fails:=hard_fails||'"review_receipt_invalid"'::jsonb; code:='UTILITY_DIMENSIONS_INCOMPLETE';
      end if;
    end if;

  elsif p_step_id='judge_record' then
    if x.target_type='STRATEGY' then
      begin jrid:=coalesce(nullif(payload->>'judge_result_id',''),x.checkpoint_payload->>'judge_result_id')::uuid; exception when others then jrid:=null; end;
      if jrid is not null then select * into jr from public.lf_test_judge_results where judge_result_id=jrid; end if;
      if jr.judge_result_id=jrid then assertions:=assertions||'"review_record_persisted"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"review_record_invalid"'::jsonb; code:='JUDGE_NOT_FOUND'; end if;
      if jr.test_run_id=trid and jr.created_by_execution_id=p_execution_id and jr.metadata->>'reviewer_execution_id'=p_execution_id then assertions:=assertions||'"review_record_bound"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"review_record_invalid"'::jsonb; code:='JUDGE_BINDING_INVALID'; end if;
      if jr.verdict=upper(coalesce(x.checkpoint_payload->>'verdict','')) then assertions:=assertions||'"review_verdict_matches"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"review_record_invalid"'::jsonb; code:='JUDGE_VERDICT_MISMATCH'; end if;
      payload:=payload||jsonb_build_object('review_record_ref','supabase://public/lf_test_judge_results/'||jrid::text,'verdict',jr.verdict,'subject_sha256',rev);
    else
      if nullif(btrim(coalesce(p_evidence_ledger_execution_id,'')),'') is null then return jsonb_build_object('outcome','BLOCKED','code','EVIDENCE_LEDGER_EXECUTION_REQUIRED','durable',false); end if;
      select encode(extensions.digest(convert_to(jsonb_build_object('execution_id',p_execution_id,'semantic_step',evidence_payload)::text,'UTF8'),'sha256'),'hex') into step_digest
      from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='semantic_review' and status='STEP_PASS_WITH_EVIDENCE';
      if step_digest is null then return jsonb_build_object('outcome','BLOCKED','code','SEMANTIC_REVIEW_STEP_NOT_CLEAN','durable',false); end if;
      verdict:=upper(coalesce((select evidence_payload->>'verdict' from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='semantic_review'),''));
      anchor:=public.fn_lf_evidence_ledger_anchor_v1(
        p_execution_id,'INDEPENDENT_ASSURANCE','INDEPENDENT_REVIEW','REVIEW_DECISION',
        x.target_type,x.target_code,x.manifest->>'subject_sha256',x.manifest->>'source_head_sha',
        subject_receipt.authority_ref,'LF_SUPABASE_READBACK_V1','SUPABASE',
        'supabase://public/lf_operation_execution/'||p_execution_id,
        'SUPABASE_SQL_READBACK_PLUS_DB_DIGEST','VERIFIED',
        jsonb_build_object('operation_code',x.operation_code,'semantic_step_sha256',step_digest,'reviewer_execution_id',p_execution_id,'producer_execution_id',x.manifest->>'producer_execution_id'),
        jsonb_build_object('verdict',verdict,'semantic_step_sha256',step_digest,'evidence_refs',(select evidence_payload->'evidence_refs' from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='semantic_review')),
        p_evidence_ledger_execution_id
      );
      review_receipt_id:=(anchor->>'receipt_id')::uuid;
      if coalesce(anchor->>'verification_state','')<>'VERIFIED' then valid:=false; hard_fails:=hard_fails||'"review_record_invalid"'::jsonb; code:='REVIEW_RECORD_NOT_VERIFIED'; else assertions:=assertions||'"review_record_persisted"'::jsonb||'"review_record_bound"'::jsonb||'"review_verdict_matches"'::jsonb; end if;
      update public.lf_operation_execution set checkpoint_payload=coalesce(checkpoint_payload,'{}'::jsonb)||jsonb_build_object('review_record_receipt_id',review_receipt_id::text,'verdict',verdict),updated_at=clock_timestamp(),updated_by_execution_id=p_actor_execution_id where execution_id=p_execution_id;
      payload:=payload||jsonb_build_object('review_record_ref','supabase://private/lf_evidence_ledger_v1/'||review_receipt_id::text,'verdict',verdict,'subject_sha256',x.manifest->>'subject_sha256');
    end if;

  elsif p_step_id='reviewer_readback' then
    if x.target_type='STRATEGY' then
      begin jrid:=coalesce(nullif(payload->>'judge_result_id',''),x.checkpoint_payload->>'judge_result_id')::uuid; exception when others then jrid:=null; end;
      if jrid is not null then select * into jr from public.lf_test_judge_results where judge_result_id=jrid; end if;
      if jr.judge_result_id=jrid and jr.test_run_id=trid and jr.created_by_execution_id=p_execution_id then assertions:=assertions||'"review_record_readback"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"readback_invalid"'::jsonb; code:='JUDGE_READBACK_INVALID'; end if;
      if rev=x.manifest->>'revision_sha256' and fp=x.manifest->>'suite_set_fingerprint' and q.lifecycle_state_code='QUAL_QUALIFYING' then assertions:=assertions||'"subject_still_current"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"readback_invalid"'::jsonb; code:='TARGET_STALE_AT_READBACK'; end if;
      if tr.status='REVIEW_REQUIRED' then assertions:=assertions||'"review_still_required"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"readback_invalid"'::jsonb; code:='TEST_STATE_CHANGED_BEFORE_FINALIZE'; end if;
      payload:=payload||jsonb_build_object('review_record_ref','supabase://public/lf_test_judge_results/'||jrid::text,'subject_sha256',rev,'authority_readback_ref','supabase://public/lf_qualification_receipts/'||qid::text);
    else
      begin review_receipt_id:=(x.checkpoint_payload->>'review_record_receipt_id')::uuid; exception when others then review_receipt_id:=null; end;
      if review_receipt_id is not null then select * into review_receipt from private.lf_evidence_ledger_v1 where receipt_id=review_receipt_id; end if;
      if review_receipt.receipt_id=review_receipt_id and review_receipt.verification_state='VERIFIED' and review_receipt.execution_id=p_execution_id then assertions:=assertions||'"review_record_readback"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"readback_invalid"'::jsonb; code:='REVIEW_RECORD_READBACK_INVALID'; end if;
      if subject_receipt.verification_state='VERIFIED' and subject_receipt.subject_sha256=x.manifest->>'subject_sha256' and subject_receipt.source_head_sha=x.manifest->>'source_head_sha' then assertions:=assertions||'"subject_still_current"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"readback_invalid"'::jsonb; code:='SUBJECT_STALE_AT_READBACK'; end if;
      if coalesce((x.manifest->>'review_required')::boolean,false) then assertions:=assertions||'"review_still_required"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"readback_invalid"'::jsonb; code:='REVIEW_REQUIREMENT_CHANGED'; end if;
      payload:=payload||jsonb_build_object('review_record_ref','supabase://private/lf_evidence_ledger_v1/'||review_receipt_id::text,'subject_sha256',x.manifest->>'subject_sha256','authority_readback_ref','supabase://private/lf_evidence_ledger_v1/'||subject_receipt.receipt_id::text);
    end if;

  elsif p_step_id='report_output' then
    select count(*) into prior_bad
    from public.lf_operation_steps s
    left join public.lf_operation_execution_steps es on es.execution_id=p_execution_id and es.step_order=s.step_order and es.step_id=s.step_id
    left join public.lf_operation_step_judge_bindings b on b.operation_code=s.operation_code and b.step_order=s.step_order and b.step_id=s.step_id and b.status='ACTIVE_ENFORCEMENT'
    where s.operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF' and s.required and s.active and s.step_id<>'report_output'
      and (es.step_id is null or b.clean_result_value is null or es.status<>b.clean_result_value);
    if prior_bad=0 then assertions:=assertions||'"all_prior_clean"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"completion_invalid"'::jsonb; code:='PRIOR_STEPS_NOT_CLEAN'; end if;

    if x.target_type='STRATEGY' then
      begin jrid:=coalesce(nullif(payload->>'judge_result_id',''),x.checkpoint_payload->>'judge_result_id')::uuid; exception when others then jrid:=null; end;
      if jrid is not null then select * into jr from public.lf_test_judge_results where judge_result_id=jrid; end if;
      if jr.judge_result_id=jrid and jr.created_by_execution_id=p_execution_id then assertions:=assertions||'"reviewer_ready_to_complete"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"completion_invalid"'::jsonb; code:='JUDGE_NOT_BOUND_AT_COMPLETION'; end if;
      if rev=x.manifest->>'revision_sha256' and fp=x.manifest->>'suite_set_fingerprint' and q.lifecycle_state_code='QUAL_QUALIFYING' and tr.status='REVIEW_REQUIRED' then assertions:=assertions||'"subject_still_current"'::jsonb||'"authority_readback_present"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"completion_invalid"'::jsonb; code:='TARGET_STALE_AT_COMPLETION'; end if;
      payload:=payload||jsonb_build_object('review_receipt',coalesce(payload->'review_receipt',jsonb_build_object('judge_result_id',jrid::text,'verdict',jr.verdict)),'authority_readback',jsonb_build_object('qualification_id',qid::text,'test_run_id',trid::text,'revision_sha256',rev,'suite_set_fingerprint',fp),'next_gate',coalesce(payload->'next_gate','QUALIFICATION_FRAMEWORK'));
    else
      if nullif(btrim(coalesce(p_evidence_ledger_execution_id,'')),'') is null then return jsonb_build_object('outcome','BLOCKED','code','EVIDENCE_LEDGER_EXECUTION_REQUIRED','durable',false); end if;
      begin review_receipt_id:=(x.checkpoint_payload->>'review_record_receipt_id')::uuid; exception when others then review_receipt_id:=null; end;
      if review_receipt_id is not null then select * into review_receipt from private.lf_evidence_ledger_v1 where receipt_id=review_receipt_id; end if;
      if review_receipt.receipt_id=review_receipt_id and review_receipt.verification_state='VERIFIED' then assertions:=assertions||'"reviewer_ready_to_complete"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"completion_invalid"'::jsonb; code:='REVIEW_RECORD_NOT_READY'; end if;
      if subject_receipt.verification_state='VERIFIED' and subject_receipt.subject_sha256=x.manifest->>'subject_sha256' and subject_receipt.source_head_sha=x.manifest->>'source_head_sha' then assertions:=assertions||'"subject_still_current"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"completion_invalid"'::jsonb; code:='SUBJECT_STALE_AT_COMPLETION'; end if;
      if valid then
        anchor:=public.fn_lf_evidence_ledger_anchor_v1(
          p_execution_id,'INDEPENDENT_ASSURANCE','INDEPENDENT_REVIEW','INDEPENDENT_REVIEW_RECEIPT',
          x.target_type,x.target_code,x.manifest->>'subject_sha256',x.manifest->>'source_head_sha',
          subject_receipt.authority_ref,'LF_SUPABASE_READBACK_V1','SUPABASE',
          'supabase://public/lf_operation_execution/'||p_execution_id,
          'SUPABASE_SQL_READBACK_PLUS_DB_DIGEST','VERIFIED',
          jsonb_build_object('operation_code',x.operation_code,'review_record_receipt_id',review_receipt_id::text,'reviewer_execution_id',p_execution_id,'producer_execution_id',x.manifest->>'producer_execution_id'),
          jsonb_build_object('verdict',review_receipt.receipt_payload->>'verdict','review_record_receipt_id',review_receipt_id::text,'evidence_refs',review_receipt.receipt_payload->'evidence_refs','next_gate','AUTHORITY_READBACK'),
          p_evidence_ledger_execution_id
        );
        if coalesce(anchor->>'verification_state','')='VERIFIED' then assertions:=assertions||'"authority_readback_present"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"completion_invalid"'::jsonb; code:='FINAL_REVIEW_RECEIPT_NOT_VERIFIED'; end if;
        payload:=payload||jsonb_build_object('review_receipt',anchor,'evidence_refs',review_receipt.receipt_payload->'evidence_refs','authority_readback',jsonb_build_object('subject_receipt_id',subject_receipt.receipt_id::text,'review_record_receipt_id',review_receipt_id::text,'final_receipt_id',anchor->>'receipt_id','verification_state',anchor->>'verification_state'),'next_gate','AUTHORITY_READBACK');
      end if;
    end if;
  else
    return jsonb_build_object('outcome','BLOCKED','code','STEP_NOT_SUPPORTED','durable',false);
  end if;

  trust:=jsonb_build_object(
    'valid',valid,'code',code,'server_assertions',assertions,'server_hard_fails',hard_fails,
    'details',jsonb_build_object('subject_type',x.target_type,'subject_ref',x.target_code,'subject_sha256',coalesce(x.manifest->>'subject_sha256',rev))
  );

  return public.lf_record_operation_step_core_v1(
    p_execution_id,p_step_id,p_evidence_ref,payload,p_actor_execution_id,
    'REVISION_INDEPENDIENTE_ESTRATEGIA_LF',x.target_type,
    'ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT',trust,true,'lf_record_independent_review_step_v3'
  );
end
$fn$;

-- -----------------------------------------------------------------------------
-- 5. Backward-compatible Strategy recorder signature. Existing begin/judge/finalize
--    RPCs remain unchanged and now flow through the subject-aware recorder.
-- -----------------------------------------------------------------------------
create or replace function public.lf_record_independent_strategy_review_step_v1(
  p_execution_id text,
  p_step_id text,
  p_evidence_ref text,
  p_evidence_payload jsonb,
  p_actor_execution_id text
) returns jsonb
language sql
set search_path=pg_catalog,public
as $fn$
  select public.lf_record_independent_review_step_v3(
    p_execution_id,p_step_id,p_evidence_ref,p_evidence_payload,p_actor_execution_id,null
  );
$fn$;

-- Restricted generic RPCs follow the same service-role boundary as Evidence Ledger.
revoke all on function public.lf_independent_review_begin_v3(text,text,text,text,text,uuid,text,text,text,uuid,text,text,text,jsonb) from public,anon,authenticated;
revoke all on function public.lf_record_independent_review_step_v3(text,text,text,jsonb,text,text) from public,anon,authenticated;
grant execute on function public.lf_independent_review_begin_v3(text,text,text,text,text,uuid,text,text,text,uuid,text,text,text,jsonb) to service_role;
grant execute on function public.lf_record_independent_review_step_v3(text,text,text,jsonb,text,text) to service_role;

-- -----------------------------------------------------------------------------
-- 6. Post-DDL invariants. Qualification MUST be stale now; current pointer MUST
--    still be absent. This is intentional and forces the governed requalification
--    before capability promotion.
-- -----------------------------------------------------------------------------
do $post$
declare
  v_count integer;
  v_revision text;
begin
  select count(*) into v_count from public.lf_operation_registry where operation_type='INDEPENDENT_REVIEW';
  if v_count<>1 then raise exception 'BLOCK_T_INDEP_POST_PARALLEL_OPERATION_COUNT:%',v_count; end if;

  if exists(select 1 from public.lf_operation_registry where operation_code='REVISION_INDEPENDIENTE_LF') then
    raise exception 'BLOCK_T_INDEP_POST_PARALLEL_OPERATION';
  end if;
  if exists(select 1 from public.lf_router_action_registry where asset_type='REVIEW_SUBJECT' and action_code='INDEPENDENT_REVIEW') then
    raise exception 'BLOCK_T_INDEP_POST_PARALLEL_ROUTE';
  end if;
  select count(*) into v_count from public.lf_operation_judges where operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF' and status='ACTIVE_ENFORCEMENT';
  if v_count<>6 then raise exception 'BLOCK_T_INDEP_POST_JUDGE_COUNT:%',v_count; end if;
  if not exists(select 1 from public.lf_capability_version_registry where capability_code='INDEPENDENT_ASSURANCE' and version='2.0.0') then
    raise exception 'BLOCK_T_INDEP_CAPABILITY_VERSION_MISSING';
  end if;
  if not exists(
    select 1 from public.lf_capability_current
    where capability_code='INDEPENDENT_ASSURANCE'
      and version='1.0.1'
      and manifest_sha256='b12c44ca0e07d2da4fdcb27f7e8e8da311dfcdaf390e645d45a3cf407a31e6c1'
  ) then
    raise exception 'BLOCK_T_INDEP_BASE_CURRENT_1_0_1_POINTER_CHANGED_BEFORE_PROMOTION';
  end if;

  v_revision:=public.lf_operation_revision_sha256_v1('REVISION_INDEPENDIENTE_ESTRATEGIA_LF');
  if public.lf_qualification_current_v1('OPERATION','REVISION_INDEPENDIENTE_ESTRATEGIA_LF',v_revision) then
    raise exception 'BLOCK_T_INDEP_EXPECTED_REQUALIFICATION_GATE_NOT_OBSERVED:%',v_revision;
  end if;
end
$post$;


-- V3 static postcondition: generic core may not whitelist named subjects.
do $v3_static$
declare
  v_begin text:=pg_get_functiondef('public.lf_independent_review_begin_v3(text,text,text,text,text,uuid,text,text,text,uuid,text,text,text,jsonb)'::regprocedure);
  v_record text:=pg_get_functiondef('public.lf_record_independent_review_step_v3(text,text,text,jsonb,text,text)'::regprocedure);
begin
  if v_begin ~ $$p_subject_type\s*<>$$ or v_begin like '%STORY_IMPLEMENTATION_PACKAGE%' then
    raise exception 'BLOCK_T_INDEP_V3_BEGIN_SUBJECT_NAME_BRANCH_PRESENT';
  end if;
  if v_record like '%target_type not in (%' or v_record like '%STORY_IMPLEMENTATION_PACKAGE%' then
    raise exception 'BLOCK_T_INDEP_V3_RECORDER_SUBJECT_NAME_BRANCH_PRESENT';
  end if;
  if not (v_begin like '%CONTRACT_DRIVEN_ANY_SUBJECT%' and v_begin like '%required_dimensions%') then
    raise exception 'BLOCK_T_INDEP_V3_GENERIC_CONTRACT_MARKERS_MISSING';
  end if;
end
$v3_static$;
