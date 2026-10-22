-- IG M10.13 / GIT_RUNTIME_PARITY CP2: material PASS -> governed canonical DONE.
-- Transport: Git source -> PASE -> LF Migration Merge Train -> Supabase readback.
-- Independent material evidence: Train run 39706754375, job 119588485648,
-- head 8052deeee06d4cc8f3ba31cbd561e3b308047ae7; artifact 12395218172.
-- Edge: Agent v17, Curator v14, Validator v18: six deployed files match Git.
-- Scope: checkpoint 1218 only; no DDL, Edge deploy or production activation.

BEGIN;

DO $ig_m1013_cp2_governed$
DECLARE
  v_plan constant text := 'IG_CURATOR_VALIDATOR_REFACTOR_V2';
  v_unit constant text := 'M10.13';
  v_cp constant text := 'GIT_RUNTIME_PARITY';
  v_work constant bigint := 474;
  v_cp_id constant bigint := 1218;
  v_source_main constant text := '8052deeee06d4cc8f3ba31cbd561e3b308047ae7';
  v_expected_manifest constant text :=
    '39bb96aa3668c9e82af061f80be658c093545c918ee8a18cc24c21c423df257e';
  v_archive_sha constant text :=
    '5828c727632686d67f5fe9a92a07e20dc6d4d7985327b0fa3493e931d0b862e6';
  v_evidence text :=
    'https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/39706754375'
    ||'#job=119588485648;artifact=12395218172;sha256='
    ||'5828c727632686d67f5fe9a92a07e20dc6d4d7985327b0fa3493e931d0b862e6'
    ||';source=8052deeee06d4cc8f3ba31cbd561e3b308047ae7';
  v_proof_path constant text :=
    'docs/input_governance/M10_13_CP2_MATERIAL_CLOSURE_EVIDENCE_V1.md';
  v_proof_blob constant text := 'd11714a3c1b3ede1677ff2eda036a17e6a8ad7e1';
  v_actor text;
  v_row record;
  v_spec jsonb;
  v_ready jsonb;
  v_contract jsonb;
  v_contract_sha text;
  v_result jsonb;
  v_bad_result jsonb;
  v_receipt jsonb;
  v_transition jsonb;
  v_err text;
  v_done integer;
  v_pending integer;
  v_progress numeric;
BEGIN
  -- A real in-progress owner must exist; never fabricate the Train execution.
  SELECT e.execution_id INTO v_actor
  FROM public.lf_operation_execution e
  WHERE e.operation_code='ACTUALIZACION_DB_LF'
    AND e.target_type='MIGRATION'
    AND e.target_code LIKE '%20261022014150_lf_ig_m1013_cp2_governed_canonical_close_v1'
    AND e.status='IN_PROGRESS'
  ORDER BY e.created_at DESC LIMIT 1;
  IF v_actor IS NULL THEN RAISE EXCEPTION 'M1013_CP2_REAL_TRAIN_EXECUTION_REQUIRED'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM programacion.engineering_plan_units p
    JOIN programacion.engineering_work_items w ON w.id=p.work_item_id
    WHERE p.plan_code=v_plan AND p.unit_code=v_unit
      AND p.disposition='ASSIGNED' AND p.work_item_id=v_work
      AND w.status='IN_PROGRESS'
  ) THEN RAISE EXCEPTION 'M1013_CP2_UNIT_PRESTATE_DRIFT'; END IF;

  SELECT id,checkpoint_code,status,evidence_ref,assertion_receipt,
         assertion_contract_sha256,assertion_receipt_sha256
    INTO STRICT v_row
  FROM programacion.engineering_work_checkpoints
  WHERE id=v_cp_id AND work_item_id=v_work AND checkpoint_code=v_cp
  FOR UPDATE;
  IF v_row.status IS DISTINCT FROM 'PENDING'
     OR v_row.evidence_ref IS NOT NULL OR v_row.assertion_receipt IS NOT NULL
     OR v_row.assertion_contract_sha256 IS NOT NULL
     OR v_row.assertion_receipt_sha256 IS NOT NULL
  THEN RAISE EXCEPTION 'M1013_CP2_CHECKPOINT_PRESTATE_DRIFT:%',row_to_json(v_row); END IF;

  IF (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work AND sequence_no=1) IS DISTINCT FROM 'DONE'
  OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work AND status='DONE')<>1
  OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work AND status='PENDING')<>6
  THEN RAISE EXCEPTION 'M1013_CP2_ORDERING_DRIFT'; END IF;

  v_ready := programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);
  v_spec := programacion.fn_engineering_checkpoint_action_spec_v3(v_plan,v_unit,v_cp);
  IF v_ready->>'status' IS DISTINCT FROM 'READY'
     OR v_ready->>'execution_ready' IS DISTINCT FROM 'true'
     OR v_spec->>'status' IS DISTINCT FROM 'READY'
     OR v_spec->>'action_kind' IS DISTINCT FROM 'TRANSVERSAL_REPOSITORY_CAPABILITY_EXECUTION'
     OR v_spec->>'transversal_handler' IS DISTINCT FROM 'REPOSITORY_CAPABILITY_EXECUTOR'
     OR v_spec#>>'{capability_execution,capability_code}' IS DISTINCT FROM 'MIGRATION_SOURCE_PARITY'
  THEN RAISE EXCEPTION 'M1013_CP2_CURRENT_EXECUTION_CONTRACT_DRIFT:%',v_ready; END IF;

  v_contract := programacion.fn_engineering_action_spec_assertion_contract_v1(
    v_plan,v_unit,v_cp,v_spec);
  IF v_contract->>'status' IS DISTINCT FROM 'READY'
     OR v_contract->>'mode' IS DISTINCT FROM 'REPOSITORY_CAPABILITY_VALIDATED_OUTPUT'
     OR v_contract->>'capability_code' IS DISTINCT FROM 'MIGRATION_SOURCE_PARITY'
     OR v_contract->>'version' IS DISTINCT FROM '1.0.0'
     OR v_contract->>'result_schema' IS DISTINCT FROM 'lf-migration-source-parity-result/v1'
     OR v_contract->>'manifest_sha256' IS DISTINCT FROM v_expected_manifest
     OR v_contract->>'expected_validator_status' IS DISTINCT FROM 'PASS'
     OR coalesce(v_contract->>'validator_ref','') !~
        '^github://cristhianlujan/claude-persona-lf-patch@[0-9a-f]{40}/sandbox/lf_contract_gate_test/s30_migration_source_parity/test_migration_source_parity_core.py$'
  THEN RAISE EXCEPTION 'M1013_CP2_ASSERTION_CONTRACT_STALE:%',v_contract; END IF;
  v_contract_sha := programacion.fn_v09_sha256_jsonb(v_contract);

  -- Facts are sourced from the real executed GitHub Actions run and six
  -- independently read-back deployed Edge files; never from a client verdict.
  -- Immutable Git blob of the detailed material evidence:
  -- docs/input_governance/M10_13_CP2_MATERIAL_CLOSURE_EVIDENCE_V1.md
  IF v_source_main !~ '^[0-9a-f]{40}$' OR v_archive_sha !~ '^[0-9a-f]{64}$'
     OR v_proof_blob !~ '^[0-9a-f]{40}$' OR v_proof_path=''
  THEN RAISE EXCEPTION 'M1013_CP2_EVIDENCE_IDENTITY_INVALID'; END IF;

  v_result := jsonb_build_object(
    'status','PASS',
    'validator_status','PASS',
    'capability_code',v_contract->>'capability_code',
    'version',v_contract->>'version',
    'manifest_sha256',v_contract->>'manifest_sha256',
    'result_schema',v_contract->>'result_schema',
    'validator_ref',v_contract->>'validator_ref',
    'validator_evidence_ref',v_evidence,
    'observed',jsonb_build_object(
      'evaluation_scope','FULL_CURRENT_STATE',
      'runner','TRUSTED_READ_ONLY_V1',
      'github_actions_run_id',39706754375,
      'github_actions_job_id',119588485648,
      'source_main_sha',v_source_main,
      'material_log_result','PASS_IG_M1013_CP2_FULL_CURRENT_STATE',
      'git_migrations_checked',828,
      'historical_exceptions_verified',15,
      'pointer_representations_verified',4,
      'edge_files_exact',6,
      'edge_functions_verified',3,
      'artifact_id',12395218172,
      'artifact_archive_sha256',v_archive_sha,
      'proof_git_blob',v_proof_blob,
      'production_activated',false
    )
  );

  -- Negative: a result lacking independent validator PASS MUST be refused.
  BEGIN
    v_bad_result:=jsonb_set(v_result,'{validator_status}','"FAIL"'::jsonb,true);
    PERFORM programacion.fn_engineering_checkpoint_assertion_record_v1(
      v_plan,v_unit,v_cp,v_bad_result,v_actor);
    RAISE EXCEPTION 'M1013_CP2_FORGED_NEGATIVE_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'ENGINEERING_ASSERTION_RESULT_FAILED:%'
    THEN RAISE EXCEPTION 'M1013_CP2_NEGATIVE_UNEXPECTED:%',v_err; END IF;
  END;
  IF EXISTS (SELECT 1 FROM programacion.engineering_work_checkpoints
    WHERE id=v_cp_id AND (assertion_receipt IS NOT NULL OR assertion_receipt_sha256 IS NOT NULL))
  THEN RAISE EXCEPTION 'M1013_CP2_NEGATIVE_RESIDUE'; END IF;

  v_receipt := programacion.fn_engineering_checkpoint_assertion_record_v1(
    v_plan,v_unit,v_cp,v_result,v_actor);
  IF v_receipt->>'passed' IS DISTINCT FROM 'true'
     OR v_receipt->>'contract_sha256' IS DISTINCT FROM v_contract_sha
     OR coalesce(v_receipt->>'assertion_receipt_sha256','') !~ '^[0-9a-f]{64}$'
  THEN RAISE EXCEPTION 'M1013_CP2_CANONICAL_RECEIPT_FAILED:%',v_receipt; END IF;

  v_transition := programacion.fn_engineering_checkpoint_transition_v1(
    v_plan,v_unit,v_cp,'DONE',v_evidence,v_actor,
    'Verified actual FULL_CURRENT_STATE PASS: official run 39706754375, exact current Git and Supabase ledger, 15 historical exceptions, 4 source pointers, independent 6/6 deployed Edge file readback, artifact sha256=' || v_archive_sha || '. No production activation.'
  );
  IF v_transition#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
     OR v_transition#>>'{transition,new_status}' IS DISTINCT FROM 'DONE'
  THEN RAISE EXCEPTION 'M1013_CP2_CANONICAL_TRANSITION_FAILED:%',v_transition; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM programacion.engineering_work_checkpoints
    WHERE id=v_cp_id AND work_item_id=v_work AND status='DONE'
      AND evidence_ref=v_evidence
      AND assertion_contract_sha256=v_contract_sha
      AND assertion_receipt_sha256=v_receipt->>'assertion_receipt_sha256'
      AND assertion_receipt_sha256=programacion.fn_v09_sha256_jsonb(assertion_receipt)
      AND assertion_receipt->>'passed'='true'
  ) THEN RAISE EXCEPTION 'M1013_CP2_RECEIPT_READBACK_MISMATCH'; END IF;

  SELECT count(*) FILTER (WHERE status='DONE'),
         count(*) FILTER (WHERE status='PENDING')
    INTO v_done,v_pending
  FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=v_work;
  SELECT progress_pct INTO v_progress
  FROM programacion.v_engineering_work_progress WHERE id=v_work;

  IF v_done<>2 OR v_pending<>5
     OR (SELECT status FROM programacion.engineering_work_items WHERE id=v_work)<>'IN_PROGRESS'
     OR v_progress<=15 OR v_progress>=100
     OR NOT EXISTS (
       SELECT 1 FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=v_work AND checkpoint_code='ZERO_LEGACY_CALLERS'
         AND sequence_no=3 AND status='PENDING'
     )
  THEN RAISE EXCEPTION 'M1013_CP2_POSTSTATE_FAILED done=% pending=% progress=%',
       v_done,v_pending,v_progress; END IF;
END
$ig_m1013_cp2_governed$;

COMMIT;
