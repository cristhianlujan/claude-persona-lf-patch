-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M5.9 / PAULO-074 · NEGATIVE_NO_INVOKE repair
-- Adds an inactive-by-default fail-closed Validator handoff boundary. Existing validator_validate_v1 is not modified.

begin;

create or replace function programacion.fn_input_governance_validator_handoff_assert_v1(
  p_run_id bigint,
  p_receipt_id bigint default null
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
  v_receipt_id bigint;
  v_receipt_sha text;
  v_receipt_subject_sha text;
  v_head_sha text;
  v_verification_status text;
begin
  if p_run_id is null or p_run_id < 1 then
    raise exception 'INPUT_GOVERNANCE_VALIDATOR_HANDOFF_RUN_ID_REQUIRED';
  end if;

  select * into v_run
  from programacion.input_readiness_runs
  where id=p_run_id;
  if not found then
    raise exception 'INPUT_GOVERNANCE_VALIDATOR_HANDOFF_RUN_NOT_FOUND:%',p_run_id;
  end if;

  if length(btrim(coalesce(v_run.curator_identity,'')))=0 then
    raise exception 'INPUT_GOVERNANCE_VALIDATOR_HANDOFF_CURATOR_IDENTITY_REQUIRED:%',p_run_id;
  end if;
  if v_run.status not in ('CURATING','VALIDATING','COMPLETED') then
    raise exception 'INPUT_GOVERNANCE_VALIDATOR_HANDOFF_RUN_STATUS_UNSUPPORTED:%:%',p_run_id,v_run.status;
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
    raise exception 'INPUT_GOVERNANCE_VALIDATOR_HANDOFF_UNIVERSE_INCOMPLETE:%:%:%',
      p_run_id,v_run.family_count,v_assessment_count;
  end if;

  -- Reconstruct the immutable pre-Validator handoff subject. It was persisted while the run was CURATING.
  v_subject:=jsonb_build_object(
    'schema_version','INPUT_GOVERNANCE_CURATOR_HANDOFF_V1',
    'run_id',v_run.id,
    'pantalla_id',v_run.pantalla_id,
    'version_id',v_run.version_id,
    'run_status','CURATING',
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

  if p_receipt_id is null then
    select r.id,r.receipt_sha256,r.subject_sha256,r.head_sha,r.payload->>'verification_status'
      into v_receipt_id,v_receipt_sha,v_receipt_subject_sha,v_head_sha,v_verification_status
    from programacion.provenance_receipts r
    where r.receipt_kind='EVIDENCE_VERIFICATION'
      and r.issuer_channel='EVIDENCE_VERIFIER_V1'
      and r.subject_type='input_governance_curator_handoff'
      and r.subject_ref=v_subject_ref
    order by r.id desc
    limit 1;
  else
    select r.id,r.receipt_sha256,r.subject_sha256,r.head_sha,r.payload->>'verification_status'
      into v_receipt_id,v_receipt_sha,v_receipt_subject_sha,v_head_sha,v_verification_status
    from programacion.provenance_receipts r
    where r.id=p_receipt_id;
  end if;

  if v_receipt_id is null then
    raise exception 'INPUT_GOVERNANCE_VALIDATOR_HANDOFF_RECEIPT_REQUIRED:%',p_run_id;
  end if;
  if v_receipt_subject_sha is distinct from v_subject_sha then
    raise exception 'INPUT_GOVERNANCE_VALIDATOR_HANDOFF_SUBJECT_SHA_MISMATCH:%:%:%:%',
      p_run_id,v_receipt_id,v_subject_sha,v_receipt_subject_sha;
  end if;
  if v_verification_status is distinct from 'VERIFIED' then
    raise exception 'INPUT_GOVERNANCE_VALIDATOR_HANDOFF_RECEIPT_NOT_VERIFIED:%:%',p_run_id,v_receipt_id;
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
    'status','VERIFIED',
    'schema_version','INPUT_GOVERNANCE_VALIDATOR_HANDOFF_ASSERT_V1',
    'run_id',p_run_id,
    'receipt_id',v_receipt_id,
    'receipt_sha256',v_receipt_sha,
    'subject_sha256',v_subject_sha,
    'subject_ref',v_subject_ref,
    'head_sha',v_head_sha
  );
end;
$function$;

revoke all on function programacion.fn_input_governance_validator_handoff_assert_v1(bigint,bigint) from public;
grant execute on function programacion.fn_input_governance_validator_handoff_assert_v1(bigint,bigint) to service_role;

comment on function programacion.fn_input_governance_validator_handoff_assert_v1(bigint,bigint) is
  'M5.9 fail-closed assertion of the exact persisted Curator handoff receipt before Validator execution.';

create or replace function programacion.fn_input_governance_validator_validate_handoff_v1(
  p_run_id bigint,
  p_validator_identity text,
  p_receipt_id bigint default null
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,programacion,public
as $function$
declare
  v_handoff jsonb;
  v_result jsonb;
begin
  v_handoff:=programacion.fn_input_governance_validator_handoff_assert_v1(p_run_id,p_receipt_id);
  v_result:=programacion.fn_input_governance_validator_validate_v1(p_run_id,p_validator_identity);
  return coalesce(v_result,'{}'::jsonb) || jsonb_build_object('handoff_receipt',v_handoff);
end;
$function$;

revoke all on function programacion.fn_input_governance_validator_validate_handoff_v1(bigint,text,bigint) from public;
grant execute on function programacion.fn_input_governance_validator_validate_handoff_v1(bigint,text,bigint) to service_role;

comment on function programacion.fn_input_governance_validator_validate_handoff_v1(bigint,text,bigint) is
  'M5.9 Validator entrypoint: verifies exact Curator receipt fail-closed, then delegates to validator_validate_v1. Existing validator_validate_v1 remains unchanged until Edge activation.';

commit;
