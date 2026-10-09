-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M5.9 / PAULO-074 · PERSIST_RECEIPT
-- Curator -> Validator handoff is persisted as a provenance receipt. The Curator does not invoke the Validator.
-- Runtime activation/deployment is intentionally not part of this migration.

begin;

create or replace function programacion.fn_input_governance_curator_handoff_receipt_v1(
  p_run_id bigint,
  p_expected_curator_identity text
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,programacion,public
as $function$
declare
  v_run programacion.input_readiness_runs%rowtype;
  v_assessments jsonb;
  v_assessment_count integer;
  v_subject jsonb;
  v_subject_sha text;
  v_subject_ref text;
  v_head_sha constant text := '42cc13e35a11b9fe7ab711ad2ee666778c765f91';
  v_issuer constant text := 'SUPABASE:INPUT_GOVERNANCE_CURATOR_HANDOFF_V1';
  v_token text;
  v_payload jsonb;
  v_receipt_id bigint;
  v_receipt_sha text;
begin
  if p_run_id is null or p_run_id < 1 then
    raise exception 'CURATOR_HANDOFF_RUN_ID_REQUIRED';
  end if;
  if length(btrim(coalesce(p_expected_curator_identity,'')))=0 then
    raise exception 'CURATOR_HANDOFF_IDENTITY_REQUIRED';
  end if;

  select * into v_run
  from programacion.input_readiness_runs
  where id=p_run_id;
  if not found then
    raise exception 'CURATOR_HANDOFF_RUN_NOT_FOUND:%',p_run_id;
  end if;

  if v_run.curator_identity is distinct from p_expected_curator_identity then
    raise exception 'CURATOR_HANDOFF_CURATOR_IDENTITY_MISMATCH:%',p_run_id;
  end if;
  if v_run.status is distinct from 'CURATING' then
    raise exception 'CURATOR_HANDOFF_PRE_VALIDATOR_STATUS_REQUIRED:%:%',p_run_id,v_run.status;
  end if;
  if v_run.validator_identity is not null then
    raise exception 'CURATOR_HANDOFF_VALIDATOR_ALREADY_INVOKED:%',p_run_id;
  end if;

  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'family_code',a.family_code,
          'severity',a.severity,
          'applicability',a.applicability,
          'coverage_status',a.coverage_status,
          'well_defined_status',a.well_defined_status,
          'story_ready_status',a.story_ready_status,
          'implementation_ready_status',a.implementation_ready_status,
          'qa_ready_status',a.qa_ready_status,
          'production_ready_status',a.production_ready_status,
          'source_refs',a.source_refs,
          'rationale',a.rationale,
          'blockers',a.blockers,
          'negative_requirements',a.negative_requirements,
          'test_obligations',a.test_obligations,
          'freshness',a.freshness,
          'curator_evidence',a.curator_evidence,
          'curator_sha256',a.curator_sha256,
          'subject_coverage',a.subject_coverage,
          'threat_coverage',a.threat_coverage,
          'semantic_depth_sha256',a.semantic_depth_sha256
        )
        order by a.family_code
      ),
      '[]'::jsonb
    ),
    count(*)
  into v_assessments,v_assessment_count
  from programacion.input_family_assessments a
  where a.run_id=p_run_id;

  if v_assessment_count is distinct from v_run.family_count or v_assessment_count<>47 then
    raise exception 'CURATOR_HANDOFF_UNIVERSE_INCOMPLETE:%:%:%',
      p_run_id,v_run.family_count,v_assessment_count;
  end if;

  v_subject:=jsonb_build_object(
    'schema_version','INPUT_GOVERNANCE_CURATOR_HANDOFF_V1',
    'run_id',v_run.id,
    'pantalla_id',v_run.pantalla_id,
    'version_id',v_run.version_id,
    'run_status',v_run.status,
    'curator_identity',v_run.curator_identity,
    'family_count',v_run.family_count,
    'universe_snapshot_sha256',v_run.universe_snapshot_sha256,
    'contract_version',v_run.contract_version,
    'contract_revision',v_run.contract_revision,
    'contract_snapshot_sha256',v_run.contract_snapshot_sha256,
    'assessments_sha256',programacion.fn_v09_sha256_jsonb(v_assessments),
    'required_role','INPUT_VALIDATOR',
    'validator_invoked',false
  );
  v_subject_sha:=programacion.fn_v09_sha256_jsonb(v_subject);
  v_subject_ref:='input-readiness-run:'||p_run_id::text;

  select r.id,r.receipt_sha256
    into v_receipt_id,v_receipt_sha
  from programacion.provenance_receipts r
  where r.receipt_kind='EVIDENCE_VERIFICATION'
    and r.issuer_channel='EVIDENCE_VERIFIER_V1'
    and r.head_sha=v_head_sha
    and r.subject_type='input_governance_curator_handoff'
    and r.subject_ref=v_subject_ref
    and r.subject_sha256=v_subject_sha
  order by r.id desc
  limit 1;

  if v_receipt_id is null then
    select decrypted_secret into v_token
    from vault.decrypted_secrets
    where name='EVIDENCE_VERIFIER_V1_TOKEN'
    order by created_at desc
    limit 1;
    if length(coalesce(v_token,''))<32 then
      raise exception 'CURATOR_HANDOFF_EVIDENCE_VERIFIER_TOKEN_MISSING';
    end if;

    v_payload:=jsonb_build_object(
      'head_sha',v_head_sha,
      'subject_type','input_governance_curator_handoff',
      'subject_ref',v_subject_ref,
      'subject_sha256',v_subject_sha,
      'verification_status','VERIFIED',
      'verifier_identity',v_issuer,
      'verification_method','SUPABASE_CANONICAL_RUN_AND_CURATOR_ASSESSMENT_DIGEST_V1',
      'handoff',v_subject,
      'validator_invoked',false
    );

    select r.id,r.receipt_sha256
      into v_receipt_id,v_receipt_sha
    from programacion.issue_provenance_receipt(
      'EVIDENCE_VERIFIER_V1',
      v_token,
      'EVIDENCE_VERIFICATION',
      null,
      v_head_sha,
      'input_governance_curator_handoff',
      v_subject_ref,
      v_subject_sha,
      v_issuer,
      'supabase://programacion.input_readiness_runs/'||p_run_id::text||'#curator-handoff',
      v_payload
    ) r;
  end if;

  perform programacion.fn_assert_provenance_receipt(
    v_receipt_id,
    'EVIDENCE_VERIFICATION',
    null,
    v_head_sha,
    'input_governance_curator_handoff',
    v_subject_ref,
    v_subject_sha
  );

  return jsonb_build_object(
    'status','PERSISTED',
    'schema_version','INPUT_GOVERNANCE_CURATOR_HANDOFF_RECEIPT_V1',
    'receipt_id',v_receipt_id,
    'receipt_sha256',v_receipt_sha,
    'subject_sha256',v_subject_sha,
    'subject_ref',v_subject_ref,
    'head_sha',v_head_sha,
    'required_role','INPUT_VALIDATOR',
    'validator_invoked',false
  );
end;
$function$;

revoke all on function programacion.fn_input_governance_curator_handoff_receipt_v1(bigint,text) from public;
grant execute on function programacion.fn_input_governance_curator_handoff_receipt_v1(bigint,text) to service_role;

comment on function programacion.fn_input_governance_curator_handoff_receipt_v1(bigint,text) is
  'M5.9: persists an idempotent, exact-subject Curator handoff receipt before Validator invocation; source head 42cc13e35a11b9fe7ab711ad2ee666778c765f91.';

do $block$
declare
  v_head_sha constant text := '42cc13e35a11b9fe7ab711ad2ee666778c765f91';
  v_issuer constant text := 'SUPABASE:INPUT_GOVERNANCE_CURATOR_HANDOFF_V1';
  v_contract jsonb;
  v_subject_sha text;
  v_subject_ref constant text := 'plan://IG_CURATOR_VALIDATOR_REFACTOR_V2/M5.9/PERSIST_RECEIPT';
  v_token text;
  v_payload jsonb;
  v_receipt_id bigint;
  v_receipt_sha text;
begin
  if not exists(
    select 1 from programacion.provenance_channels
    where channel_code='EVIDENCE_VERIFIER_V1'
      and 'EVIDENCE_VERIFICATION'=any(allowed_kinds)
  ) then
    raise exception 'M5_9_EVIDENCE_VERIFIER_CHANNEL_NOT_READY';
  end if;

  if to_regprocedure('programacion.fn_assert_provenance_receipt(bigint,text,bigint,text,text,text,text)') is null
     or to_regprocedure('programacion.issue_provenance_receipt(text,text,text,bigint,text,text,text,text,text,text,jsonb)') is null then
    raise exception 'M5_9_PROVENANCE_PRIMITIVES_MISSING';
  end if;

  v_contract:=jsonb_build_object(
    'schema_version','IG_M5_9_PERSIST_RECEIPT_CONTRACT_V1',
    'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'unit_code','M5.9',
    'work_code','PAULO-074',
    'edge_path','supabase/functions/input-governance-curator-v1/index.ts',
    'edge_blob_sha1','527c840df9102d7e9c751dd0f3f4d2c92afb4e17',
    'edge_source_head_sha',v_head_sha,
    'receipt_model','programacion.provenance_receipts',
    'receipt_function','programacion.fn_input_governance_curator_handoff_receipt_v1',
    'receipt_kind','EVIDENCE_VERIFICATION',
    'subject_type','input_governance_curator_handoff',
    'required_role','INPUT_VALIDATOR',
    'validator_invocation',false,
    'idempotent',true,
    'parallel_receipt_store',false
  );
  v_subject_sha:=programacion.fn_v09_sha256_jsonb(v_contract);

  select r.id,r.receipt_sha256
    into v_receipt_id,v_receipt_sha
  from programacion.provenance_receipts r
  where r.receipt_kind='EVIDENCE_VERIFICATION'
    and r.issuer_channel='EVIDENCE_VERIFIER_V1'
    and r.head_sha=v_head_sha
    and r.subject_type='input_governance_curator_handoff_contract'
    and r.subject_ref=v_subject_ref
    and r.subject_sha256=v_subject_sha
  order by r.id desc
  limit 1;

  if v_receipt_id is null then
    select decrypted_secret into v_token
    from vault.decrypted_secrets
    where name='EVIDENCE_VERIFIER_V1_TOKEN'
    order by created_at desc
    limit 1;
    if length(coalesce(v_token,''))<32 then
      raise exception 'M5_9_EVIDENCE_VERIFIER_TOKEN_MISSING';
    end if;

    v_payload:=jsonb_build_object(
      'head_sha',v_head_sha,
      'subject_type','input_governance_curator_handoff_contract',
      'subject_ref',v_subject_ref,
      'subject_sha256',v_subject_sha,
      'verification_status','VERIFIED',
      'verifier_identity',v_issuer,
      'verification_method','SUPABASE_CONTRACT_READBACK_V1',
      'contract',v_contract,
      'validator_invoked',false
    );

    select r.id,r.receipt_sha256
      into v_receipt_id,v_receipt_sha
    from programacion.issue_provenance_receipt(
      'EVIDENCE_VERIFIER_V1',
      v_token,
      'EVIDENCE_VERIFICATION',
      null,
      v_head_sha,
      'input_governance_curator_handoff_contract',
      v_subject_ref,
      v_subject_sha,
      v_issuer,
      'github://cristhianlujan/claude-persona-lf-patch@'||v_head_sha||'/supabase/functions/input-governance-curator-v1/index.ts',
      v_payload
    ) r;
  end if;

  perform programacion.fn_assert_provenance_receipt(
    v_receipt_id,
    'EVIDENCE_VERIFICATION',
    null,
    v_head_sha,
    'input_governance_curator_handoff_contract',
    v_subject_ref,
    v_subject_sha
  );
end;
$block$;

commit;
