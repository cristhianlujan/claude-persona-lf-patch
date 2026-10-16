-- PE10_C4: dispose ONLY seven specifically audited stale historical updater executions.
-- IMPORTANT: this CANCELS old execution sessions, NOT their Git candidates/PRs.
-- PRs #949/#996 remain open, all source branches+commits remain unmodified.
-- A changed version of a capability in main is NOT proof the old Git delta was merged.
-- Existing code with unproven inclusion stays preserved for independent review.
-- No conversion to COMPLETED/SUPERSEDED, no fake postmerge evidence.
-- By LF Migration Merge Train exclusively; transaction test -> rollback -> replay.
BEGIN;
DO $pe10_c4$
DECLARE
  v_actor constant text := 'EXEC-PE10-C4-SEVEN-PRESERVED-CANDIDATES-20261016-001';
  v_prefix constant text := 'PE10_C4.CANDIDATE_PRESERVED_SESSION_CANCELLED.';
  v_final_code constant text := 'PE10_C4.ZERO_OPEN_LEGACY_CUTOVER_PRECONDITION_READBACK_V1';
  v_plan constant text := 'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1';
  v_event_id bigint;
  v_final_id bigint;
  v_current_asset jsonb;
  v_r record;
  v_man jsonb;
  v_payload jsonb;
  v_final_payload jsonb;
  v_evidence_ref text;
  v_checkpoint_transition jsonb;
  v_n int;
  v_open_v01 int;
  v_open_unclassified int;
BEGIN
  -- These PRECONDITIONS must still match at the instant Train applies the SQL.
  IF (SELECT COUNT(*) FROM public.lf_operation_execution
        WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS')<>7
     OR (SELECT c.status FROM programacion.engineering_work_checkpoints c
         JOIN programacion.engineering_plan_units u USING(work_item_id)
         WHERE u.plan_code=v_plan AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C3')<>'DONE'
     OR (SELECT c.status FROM programacion.engineering_work_checkpoints c
         JOIN programacion.engineering_plan_units u USING(work_item_id)
         WHERE u.plan_code=v_plan AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C4')<>'PENDING'
     OR (SELECT COUNT(*) FROM public.lf_operation_registry
         WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND version='v0.1'
           AND status='PRODUCCION_CONTROLADA')<>1
  THEN RAISE EXCEPTION 'PE10_C4_LAST7_PLAN_PREIMAGE_DRIFT'; END IF;
  IF (SELECT COUNT(*) FROM private.lf_event_type_contracts_v2
       WHERE event_type='ARTIFACT_RECONCILED' AND active
         AND contract_mode='OPERATIONAL'
         AND 'operational-event/v2'=ANY(allowed_evidence_schemas))<>1
  THEN RAISE EXCEPTION 'PE10_C4_LAST7_APPEND_ONLY_EVENT_TYPE_UNAVAILABLE'; END IF;
  SELECT to_jsonb(a) INTO v_current_asset
    FROM public.lf_activos a
    WHERE a.tipo_activo='PERFIL' AND a.codigo_activo='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
      AND a.archived_at IS NULL;
  IF v_current_asset IS NULL
  THEN RAISE EXCEPTION 'PE10_C4_LAST7_PROFILE_AUTHORITY_NOT_FOUND'; END IF;
  IF EXISTS(SELECT 1 FROM public.lf_eventos
     WHERE evento_tipo='ARTIFACT_RECONCILED'
       AND (entidad_codigo LIKE v_prefix||'%' OR entidad_codigo=v_final_code))
  THEN RAISE EXCEPTION 'PE10_C4_LAST7_ALREADY_RECORDED'; END IF;
  IF (SELECT COUNT(*) FROM public.lf_operation_execution e
       WHERE e.operation_code='ACTUALIZACION_PERFIL_LF' AND e.status='IN_PROGRESS'
         AND e.execution_id NOT IN (
         'EXEC-ACTUALIZACION-PERFIL-SRCR-CLOSURE-20260919-003',
         'EXEC-ACTUALIZACION-PERFIL-LF-OIDC-5f3f5a6c-9a8b-429d-a077-303a965374ec',
         'EXEC-ACTUALIZACION-PERFIL-LF-OIDC-fc12ca18-d181-4a82-aca9-2b0f54b13b06',
         'EXEC-ACTUALIZACION-PERFIL-LF-OIDC-4f3c28ca-f093-4689-99fa-b52f0d67e49f',
         'EXEC-ACTUALIZACION-PERFIL-LF-OIDC-2c272d7f-0ff7-4f3a-a109-f64ebc46988a',
         'EXEC-ACTUALIZACION-PERFIL-LF-OIDC-7ba517b6-85ee-43bb-b4a0-57b6112f8b15',
         'EXEC-ACTUALIZACION-PERFIL-LF-OIDC-674014fd-2b1e-47a6-b900-7ac223c5c7b3'
       ))<>0
  THEN RAISE EXCEPTION 'PE10_C4_LAST7_UNDECLARED_OPEN_EXECUTION'; END IF;

  -- Seven explicit historical identities, each with its *observed* commit,
  -- exact branch and status counts. GitHub branch-head values were read live.
  -- Their preservation is an audit fact, NOT claim of production integration.
  FOR v_r IN
     SELECT * FROM (VALUES
       ('EXEC-ACTUALIZACION-PERFIL-SRCR-CLOSURE-20260919-003','0526ff7f2f54e912fe6e26bbfbfc9e9d2739d2d1','lf/srcr-producer-artifact-closure-20260919','9f278f8182c72adb7a1684262bcffd548c93836a',949,12,0),
      ('EXEC-ACTUALIZACION-PERFIL-LF-OIDC-5f3f5a6c-9a8b-429d-a077-303a965374ec','10e976a20b3bbf286fb5bf826ffbaa4792aff1b5','fix/srcr-semantic-judge-b-canonical-20260920','10e976a20b3bbf286fb5bf826ffbaa4792aff1b5',NULL,12,0),
      ('EXEC-ACTUALIZACION-PERFIL-LF-OIDC-fc12ca18-d181-4a82-aca9-2b0f54b13b06','a5ab605d15bfabd16a8453a787980c4f39a3add0','fix/srcr-v03-incremental-value-proof-20260921','a5ab605d15bfabd16a8453a787980c4f39a3add0',NULL,10,1),
      ('EXEC-ACTUALIZACION-PERFIL-LF-OIDC-4f3c28ca-f093-4689-99fa-b52f0d67e49f','39a7021b9453b281a01089d7b9e3f765ff6c16b5','sandbox/srcr-v04-governed-r2-20260921','69ce23e2afda0608a4975852266a6b94c5743b2e',996,10,0),
      ('EXEC-ACTUALIZACION-PERFIL-LF-OIDC-2c272d7f-0ff7-4f3a-a109-f64ebc46988a','00d9970e17527647a2ae477a38a14e2c289de166','sandbox/srcr-v04-governed-r3-20260921','00d9970e17527647a2ae477a38a14e2c289de166',996,12,0),
      ('EXEC-ACTUALIZACION-PERFIL-LF-OIDC-7ba517b6-85ee-43bb-b4a0-57b6112f8b15','e31bfe6c319e852e9cc083dbc611f3a5acbb4d2c','lf/srcr-v06-mc13-governed-rebuild-20260922','2566bb239e362efc27e6f118f92caff66ed65bd7',NULL,12,0),
      ('EXEC-ACTUALIZACION-PERFIL-LF-OIDC-674014fd-2b1e-47a6-b900-7ac223c5c7b3','67adb54827fc5871e0afec8021a3122621a666c1','agent/srcr-v07r1-canonicalize-20261007','b976c719674d10137a89b6b02bc8cecaef2d8df0',NULL,10,0)
     ) AS cases(exec_id,original_sha,original_branch,observed_branch_head,retained_pr,pass_count,nonpass_count)
  LOOP
    SELECT e.manifest INTO v_man
      FROM public.lf_operation_execution e
      WHERE e.execution_id=v_r.exec_id
        AND e.operation_code='ACTUALIZACION_PERFIL_LF'
        AND e.status='IN_PROGRESS' AND e.completed_at IS NULL
        AND e.target_type='PERFIL'
        AND e.target_code='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
        AND e.target_repo='cristhianlujan/claude-persona-lf-patch'
        AND e.lease_owner IS NULL
        AND e.updated_at<clock_timestamp()-interval '6 days'
      FOR UPDATE;
    IF v_man IS NULL THEN
      RAISE EXCEPTION 'PE10_C4_LAST7_NOT_INACTIVE_OR_MISSING:%',v_r.exec_id; END IF;
    IF (SELECT COUNT(*) FROM public.lf_operation_execution_steps s
        WHERE s.execution_id=v_r.exec_id AND s.status='STEP_PASS_WITH_EVIDENCE')<>v_r.pass_count
      OR (SELECT COUNT(*) FROM public.lf_operation_execution_steps s
        WHERE s.execution_id=v_r.exec_id AND s.status<>'STEP_PASS_WITH_EVIDENCE')<>v_r.nonpass_count
      OR (SELECT COUNT(*) FROM public.lf_operation_execution_steps s
        WHERE s.execution_id=v_r.exec_id AND s.step_id='github_write'
          AND s.status='STEP_PASS_WITH_EVIDENCE'
          AND s.evidence_payload->>'commit_sha'=v_r.original_sha
          AND s.evidence_payload->>'branch'=v_r.original_branch)<>1
      OR (SELECT COUNT(*) FROM public.lf_operation_execution_steps s
        WHERE s.execution_id=v_r.exec_id AND s.step_id='github_readback'
          AND s.status='STEP_PASS_WITH_EVIDENCE'
          AND s.evidence_payload->>'exact_head'=v_r.original_sha
          AND s.evidence_payload->>'sha_match'='true')<>1
      OR EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s
        WHERE s.execution_id=v_r.exec_id AND s.step_id IN ('post_merge_reconcile','close','report_output'))
    THEN RAISE EXCEPTION 'PE10_C4_LAST7_COMMIT_OR_STEP_SNAPSHOT_MISMATCH:%',v_r.exec_id; END IF;
    IF v_r.nonpass_count=1 AND NOT EXISTS(
       SELECT 1 FROM public.lf_operation_execution_steps s
       WHERE s.execution_id=v_r.exec_id AND s.step_id='semantic_judge'
         AND s.status='BLOCKED_STEP_NOT_CLEAN')
    THEN RAISE EXCEPTION 'PE10_C4_LAST7_EXPECTED_SEMANTIC_BLOCK_NOT_PRESENT:%',v_r.exec_id; END IF;
    IF v_r.original_sha !~ '^[0-9a-f]{40}$'
       OR v_r.observed_branch_head !~ '^[0-9a-f]{40}$'
    THEN RAISE EXCEPTION 'PE10_C4_LAST7_SOURCE_COMMIT_INVALID:%',v_r.exec_id; END IF;
  END LOOP;

  -- POSITIVE TEST: all seven dispositions and final C4 checkpoint
  -- transition, in ONE deliberately rolled-back subtransaction.
  BEGIN
    FOR v_r IN SELECT * FROM (VALUES ('EXEC-ACTUALIZACION-PERFIL-SRCR-CLOSURE-20260919-003','0526ff7f2f54e912fe6e26bbfbfc9e9d2739d2d1','lf/srcr-producer-artifact-closure-20260919','9f278f8182c72adb7a1684262bcffd548c93836a',949,12,0),
      ('EXEC-ACTUALIZACION-PERFIL-LF-OIDC-5f3f5a6c-9a8b-429d-a077-303a965374ec','10e976a20b3bbf286fb5bf826ffbaa4792aff1b5','fix/srcr-semantic-judge-b-canonical-20260920','10e976a20b3bbf286fb5bf826ffbaa4792aff1b5',NULL,12,0),
      ('EXEC-ACTUALIZACION-PERFIL-LF-OIDC-fc12ca18-d181-4a82-aca9-2b0f54b13b06','a5ab605d15bfabd16a8453a787980c4f39a3add0','fix/srcr-v03-incremental-value-proof-20260921','a5ab605d15bfabd16a8453a787980c4f39a3add0',NULL,10,1),
      ('EXEC-ACTUALIZACION-PERFIL-LF-OIDC-4f3c28ca-f093-4689-99fa-b52f0d67e49f','39a7021b9453b281a01089d7b9e3f765ff6c16b5','sandbox/srcr-v04-governed-r2-20260921','69ce23e2afda0608a4975852266a6b94c5743b2e',996,10,0),
      ('EXEC-ACTUALIZACION-PERFIL-LF-OIDC-2c272d7f-0ff7-4f3a-a109-f64ebc46988a','00d9970e17527647a2ae477a38a14e2c289de166','sandbox/srcr-v04-governed-r3-20260921','00d9970e17527647a2ae477a38a14e2c289de166',996,12,0),
      ('EXEC-ACTUALIZACION-PERFIL-LF-OIDC-7ba517b6-85ee-43bb-b4a0-57b6112f8b15','e31bfe6c319e852e9cc083dbc611f3a5acbb4d2c','lf/srcr-v06-mc13-governed-rebuild-20260922','2566bb239e362efc27e6f118f92caff66ed65bd7',NULL,12,0),
      ('EXEC-ACTUALIZACION-PERFIL-LF-OIDC-674014fd-2b1e-47a6-b900-7ac223c5c7b3','67adb54827fc5871e0afec8021a3122621a666c1','agent/srcr-v07r1-canonicalize-20261007','b976c719674d10137a89b6b02bc8cecaef2d8df0',NULL,10,0)
    ) AS cases(exec_id,original_sha,original_branch,observed_branch_head,retained_pr,pass_count,nonpass_count)
    LOOP
      SELECT e.manifest INTO v_man FROM public.lf_operation_execution e WHERE e.execution_id=v_r.exec_id;
      v_payload:=jsonb_build_object(
        'evidence_schema_version','operational-event/v2',
        'execution_id',v_actor,'producer','PE10_C4_EXACT_RETENTION_DISPOSITION_V1',
        'purpose','Terminate a stale execution session; preserve candidate Git branch and any open pull request for separate integration review',
        'occurred_at',clock_timestamp(),'acceptance_declared',false,
        'historical_execution_id',v_r.exec_id,
        'disposition','CANCELLED','previous_state','IN_PROGRESS',
        'session_finished',true,'candidate_code_discarded',false,
        'candidate_implementation_verified',false,
        'candidate_deployment_claimed',false,
        'candidate_retention','EXISTING_GITHUB_BRANCH_OR_OPEN_PR',
        'candidate_source_commit',v_r.original_sha,
        'candidate_source_branch',v_r.original_branch,
        'branch_head_at_read_only_review',v_r.observed_branch_head,
        'existing_candidate_pr',v_r.retained_pr,
        'original_manifest_sha256',encode(extensions.digest(convert_to(v_man::text,'UTF8'),'sha256'),'hex'),
        'historical_pass_steps',v_r.pass_count,
        'historical_nonpass_steps',v_r.nonpass_count,
        'outstanding_candidate_review_independent_of_legacy_execution',true,
        'profile_mutated',false,'runtime_activated',false,'cutover_admitted',false,
        'authority_level','READ_ONLY_HISTORICAL_RECONCILIATION_NOT_GIT_MERGE_PROOF'
      );
      INSERT INTO public.lf_eventos (
        evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,
        created_by_execution_id,payload
      ) VALUES ('ARTIFACT_RECONCILED','EXECUTION',v_prefix||v_r.exec_id,
        'Original updater run cancelled; associated Git candidate retained and not certified integrated',
        'INFO','DERIVE_FROM_EXECUTION_ID',v_actor,v_payload) RETURNING id INTO v_event_id;
      UPDATE public.lf_operation_execution e
        SET status='CANCELLED',completed_at=clock_timestamp(),updated_by_execution_id=v_actor
        WHERE e.execution_id=v_r.exec_id AND e.status='IN_PROGRESS' AND e.manifest=v_man;
      IF NOT FOUND THEN RAISE EXCEPTION 'PE10_C4_LAST7_DRY_TRANSITION_FAILED:%',v_r.exec_id; END IF;
    END LOOP;

    SELECT count(*)::int INTO v_n FROM public.lf_operation_execution
      WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS';
    IF v_n<>0 OR
       (SELECT count(*) FROM public.lf_eventos
        WHERE evento_tipo='ARTIFACT_RECONCILED' AND entidad_codigo LIKE v_prefix||'%')<>7
    THEN RAISE EXCEPTION 'PE10_C4_LAST7_TEST_ZERO_OPEN_READBACK_FAILED'; END IF;
    v_final_payload:=jsonb_build_object(
      'evidence_schema_version','operational-event/v2','execution_id',v_actor,
      'producer','PE10_C4_ZERO_OPEN_LEGACY_VALIDATOR_V1',
      'purpose','C4 readback exact zero open v0.1 and zero unclassified; not v0.2 approval',
      'occurred_at',clock_timestamp(),'acceptance_declared',false,
      'plan_code',v_plan,'checkpoint_code','PE10_C4',
      'open_total',0,'open_unclassified',0,'open_v01_resolved',0,
      'historical_sessions_ended_count',7,
      'candidate_branches_preserved',7,
      'historical_review_outstanding',true,
      'cutover_admitted',false,'updater_version','v0.1'
    );
    INSERT INTO public.lf_eventos (
      evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,
      created_by_execution_id,payload
    ) VALUES ('ARTIFACT_RECONCILED','PROGRAM_PLAN',v_final_code,
      'C4 validator zero legacy open; no assurance admission and no v0.2 activation',
      'INFO','DERIVE_FROM_EXECUTION_ID',v_actor,v_final_payload)
    RETURNING id INTO v_final_id;
    v_evidence_ref:='supabase://public/lf_eventos/'||v_final_id::text;
    v_checkpoint_transition:=programacion.fn_engineering_checkpoint_transition_v1(
      v_plan,'PE10','PE10_C4','DONE',v_evidence_ref,v_actor,
      'Exactly zero open updater executions after seven individually readback CANCELLED dispositions. Git source branches/PRs remain unaffected. v0.2 NOT admitted.'
    );
    IF v_checkpoint_transition#>>'{transition,status}'<>'APPLIED'
       OR (SELECT c.status FROM programacion.engineering_work_checkpoints c
          JOIN programacion.engineering_plan_units u USING(work_item_id)
          WHERE u.plan_code=v_plan AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C4')<>'DONE'
    THEN RAISE EXCEPTION 'PE10_C4_LAST7_DRY_CHECKPOINT_TRANSITION_FAILED'; END IF;
    RAISE EXCEPTION 'PE10_C4_LAST7_INTENTIONAL_TEST_ROLLBACK';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'PE10_C4_LAST7_INTENTIONAL_TEST_ROLLBACK' THEN RAISE; END IF;
  END;

  -- NEGATIVE TEST: none of the rehearsal effects must remain.
  IF (SELECT COUNT(*) FROM public.lf_operation_execution
      WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS')<>7
     OR EXISTS(SELECT 1 FROM public.lf_eventos e
      WHERE e.evento_tipo='ARTIFACT_RECONCILED'
        AND (e.entidad_codigo LIKE v_prefix||'%' OR e.entidad_codigo=v_final_code))
     OR (SELECT c.status FROM programacion.engineering_work_checkpoints c
        JOIN programacion.engineering_plan_units u USING(work_item_id)
        WHERE u.plan_code=v_plan AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C4')<>'PENDING'
  THEN RAISE EXCEPTION 'PE10_C4_LAST7_ROLLBACK_LEFT_RESIDUES'; END IF;

  -- DURABLE: same identity-bound disposition. C4 is closed only after
  -- SQL readback of the explicit zero-open contract.
  FOR v_r IN SELECT * FROM (VALUES ('EXEC-ACTUALIZACION-PERFIL-SRCR-CLOSURE-20260919-003','0526ff7f2f54e912fe6e26bbfbfc9e9d2739d2d1','lf/srcr-producer-artifact-closure-20260919','9f278f8182c72adb7a1684262bcffd548c93836a',949,12,0),
      ('EXEC-ACTUALIZACION-PERFIL-LF-OIDC-5f3f5a6c-9a8b-429d-a077-303a965374ec','10e976a20b3bbf286fb5bf826ffbaa4792aff1b5','fix/srcr-semantic-judge-b-canonical-20260920','10e976a20b3bbf286fb5bf826ffbaa4792aff1b5',NULL,12,0),
      ('EXEC-ACTUALIZACION-PERFIL-LF-OIDC-fc12ca18-d181-4a82-aca9-2b0f54b13b06','a5ab605d15bfabd16a8453a787980c4f39a3add0','fix/srcr-v03-incremental-value-proof-20260921','a5ab605d15bfabd16a8453a787980c4f39a3add0',NULL,10,1),
      ('EXEC-ACTUALIZACION-PERFIL-LF-OIDC-4f3c28ca-f093-4689-99fa-b52f0d67e49f','39a7021b9453b281a01089d7b9e3f765ff6c16b5','sandbox/srcr-v04-governed-r2-20260921','69ce23e2afda0608a4975852266a6b94c5743b2e',996,10,0),
      ('EXEC-ACTUALIZACION-PERFIL-LF-OIDC-2c272d7f-0ff7-4f3a-a109-f64ebc46988a','00d9970e17527647a2ae477a38a14e2c289de166','sandbox/srcr-v04-governed-r3-20260921','00d9970e17527647a2ae477a38a14e2c289de166',996,12,0),
      ('EXEC-ACTUALIZACION-PERFIL-LF-OIDC-7ba517b6-85ee-43bb-b4a0-57b6112f8b15','e31bfe6c319e852e9cc083dbc611f3a5acbb4d2c','lf/srcr-v06-mc13-governed-rebuild-20260922','2566bb239e362efc27e6f118f92caff66ed65bd7',NULL,12,0),
      ('EXEC-ACTUALIZACION-PERFIL-LF-OIDC-674014fd-2b1e-47a6-b900-7ac223c5c7b3','67adb54827fc5871e0afec8021a3122621a666c1','agent/srcr-v07r1-canonicalize-20261007','b976c719674d10137a89b6b02bc8cecaef2d8df0',NULL,10,0)
  ) AS cases(exec_id,original_sha,original_branch,observed_branch_head,retained_pr,pass_count,nonpass_count)
  LOOP
    SELECT e.manifest INTO v_man FROM public.lf_operation_execution e WHERE e.execution_id=v_r.exec_id;
    v_payload:=jsonb_build_object(
      'evidence_schema_version','operational-event/v2',
      'execution_id',v_actor,'producer','PE10_C4_EXACT_RETENTION_DISPOSITION_V1',
      'purpose','Terminate a stale execution session; preserve candidate Git branch and any open pull request for separate integration review',
      'occurred_at',clock_timestamp(),'acceptance_declared',false,
      'historical_execution_id',v_r.exec_id,
      'disposition','CANCELLED','previous_state','IN_PROGRESS',
      'session_finished',true,'candidate_code_discarded',false,
      'candidate_implementation_verified',false,
      'candidate_deployment_claimed',false,
      'candidate_retention','EXISTING_GITHUB_BRANCH_OR_OPEN_PR',
      'candidate_source_commit',v_r.original_sha,
      'candidate_source_branch',v_r.original_branch,
      'branch_head_at_read_only_review',v_r.observed_branch_head,
      'existing_candidate_pr',v_r.retained_pr,
      'original_manifest_sha256',encode(extensions.digest(convert_to(v_man::text,'UTF8'),'sha256'),'hex'),
      'historical_pass_steps',v_r.pass_count,
      'historical_nonpass_steps',v_r.nonpass_count,
      'outstanding_candidate_review_independent_of_legacy_execution',true,
      'profile_mutated',false,'runtime_activated',false,'cutover_admitted',false,
      'authority_level','READ_ONLY_HISTORICAL_RECONCILIATION_NOT_GIT_MERGE_PROOF'
    );
    INSERT INTO public.lf_eventos (
      evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,
      created_by_execution_id,payload
    ) VALUES ('ARTIFACT_RECONCILED','EXECUTION',v_prefix||v_r.exec_id,
      'Original updater run cancelled; associated Git candidate retained and not certified integrated',
      'INFO','DERIVE_FROM_EXECUTION_ID',v_actor,v_payload) RETURNING id INTO v_event_id;
    UPDATE public.lf_operation_execution e
      SET status='CANCELLED',completed_at=clock_timestamp(),updated_by_execution_id=v_actor
      WHERE e.execution_id=v_r.exec_id AND e.status='IN_PROGRESS' AND e.manifest=v_man;
    IF NOT FOUND THEN RAISE EXCEPTION 'PE10_C4_LAST7_DURABLE_TRANSITION_FAILED:%',v_r.exec_id; END IF;
    IF (SELECT count(*) FROM public.lf_operation_execution e
       WHERE e.execution_id=v_r.exec_id AND e.status='CANCELLED' AND e.manifest=v_man
         AND e.updated_by_execution_id=v_actor AND e.completed_at IS NOT NULL)<>1
       OR (SELECT count(*) FROM public.lf_eventos e
       WHERE e.id=v_event_id AND e.entidad_codigo=v_prefix||v_r.exec_id
         AND e.payload->>'candidate_source_commit'=v_r.original_sha
         AND e.payload->>'candidate_code_discarded'='false'
         AND e.payload->>'candidate_implementation_verified'='false'
         AND e.payload->>'disposition'='CANCELLED')<>1
    THEN RAISE EXCEPTION 'PE10_C4_LAST7_DURABLE_CASE_READBACK_FAILED:%',v_r.exec_id; END IF;
  END LOOP;

  -- Reuse precisely the checkpoint's canonical verification semantics;
  -- classification-only events are append-only and source manifests immutable.
  WITH open_runs AS (
    SELECT e.execution_id,nullif(e.manifest->>'contract_code','') manifest_contract
    FROM public.lf_operation_execution e
    WHERE e.operation_code='ACTUALIZACION_PERFIL_LF' AND e.status='IN_PROGRESS'
  ), classified AS (
    SELECT DISTINCT ON (ev.entidad_codigo) ev.entidad_codigo execution_id,
      ev.payload->>'classified_contract_code' classified_contract
    FROM public.lf_eventos ev
    WHERE ev.evento_tipo='PROFILE_UPDATE_LEGACY_CONTRACT_CLASSIFIED'
      AND ev.entidad_tipo='EXECUTION'
      AND ev.payload->>'classification_status'='OBSERVED'
    ORDER BY ev.entidad_codigo,ev.created_at DESC,ev.id DESC
  ), resolved AS (
    SELECT o.execution_id,coalesce(o.manifest_contract,c.classified_contract) contract_code,
      (o.manifest_contract IS NULL AND c.classified_contract IS NULL) unclassified
    FROM open_runs o LEFT JOIN classified c USING(execution_id)
  )
  SELECT count(*) FILTER (WHERE contract_code='CONTRACT-ACTUALIZACION-PERFIL-LF-v0.1')::int,
         count(*) FILTER (WHERE unclassified)::int,
         count(*)::int
  INTO v_open_v01,v_open_unclassified,v_n FROM resolved;
  IF v_n<>0 OR v_open_v01<>0 OR v_open_unclassified<>0
  THEN RAISE EXCEPTION 'PE10_C4_LAST7_CUTOVER_PRECONDITION_VALIDATOR_FAIL:%,%,%',
        v_n,v_open_v01,v_open_unclassified; END IF;

  v_final_payload:=jsonb_build_object(
    'evidence_schema_version','operational-event/v2','execution_id',v_actor,
    'producer','PE10_C4_ZERO_OPEN_LEGACY_VALIDATOR_V1',
    'purpose','C4 readback exact zero open v0.1 and zero unclassified; not v0.2 approval',
    'occurred_at',clock_timestamp(),'acceptance_declared',false,
    'plan_code',v_plan,'checkpoint_code','PE10_C4',
    'open_total',v_n,'open_unclassified',v_open_unclassified,
    'open_v01_resolved',v_open_v01,
    'historical_sessions_ended_count',7,'candidate_branches_preserved',7,
    'historical_review_outstanding',true,
    'cutover_admitted',false,'updater_version','v0.1'
  );
  INSERT INTO public.lf_eventos (
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,
    created_by_execution_id,payload
  ) VALUES ('ARTIFACT_RECONCILED','PROGRAM_PLAN',v_final_code,
    'C4 validator zero legacy open; no assurance admission and no v0.2 activation',
    'INFO','DERIVE_FROM_EXECUTION_ID',v_actor,v_final_payload)
  RETURNING id INTO v_final_id;
  v_evidence_ref:='supabase://public/lf_eventos/'||v_final_id::text;
  v_checkpoint_transition:=programacion.fn_engineering_checkpoint_transition_v1(
    v_plan,'PE10','PE10_C4','DONE',v_evidence_ref,v_actor,
    'Exactly zero open updater executions after seven individually readback CANCELLED dispositions. Git source branches/PRs remain unaffected. v0.2 NOT admitted.'
  );
  IF v_checkpoint_transition#>>'{transition,status}'<>'APPLIED'
     OR (SELECT c.status FROM programacion.engineering_work_checkpoints c
       JOIN programacion.engineering_plan_units u USING(work_item_id)
       WHERE u.plan_code=v_plan AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C4')<>'DONE'
     OR (SELECT c.evidence_ref FROM programacion.engineering_work_checkpoints c
       JOIN programacion.engineering_plan_units u USING(work_item_id)
       WHERE u.plan_code=v_plan AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C4') IS DISTINCT FROM v_evidence_ref
     OR (SELECT to_jsonb(a) FROM public.lf_activos a WHERE a.tipo_activo='PERFIL'
       AND a.codigo_activo='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
       AND a.archived_at IS NULL) IS DISTINCT FROM v_current_asset
     OR (SELECT COUNT(*) FROM public.lf_operation_registry
        WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND version='v0.1')<>1
     OR EXISTS(SELECT 1 FROM public.lf_eventos
       WHERE evento_tipo='PROFILE_EVOLUTION_CUTOVER_ADMITTED'
         AND entidad_codigo='ACTUALIZACION_PERFIL_LF' AND payload->>'status'='ADMIT_CUTOVER')
  THEN RAISE EXCEPTION 'PE10_C4_LAST7_FINAL_INVARIANTS_FAILED'; END IF;
END
$pe10_c4$;
COMMIT;