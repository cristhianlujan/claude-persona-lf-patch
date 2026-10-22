-- RW1-06_C1: governed close of the source freeze + sealed-holdout commitment checkpoint.
-- Owner accepted decision D1=B (commit-reveal + owner declaration). NOT provider-attested,
-- NOT cryptographically independent, holdout content NOT yet integrity-checked (reveal only).
-- Closes C1 ONLY: C2 and C3 stay PENDING; no Router/ACL/T3/runtime/production effect.
-- Authoritative DB effect: ACTUALIZACION_DB_LF / LF Migration Merge Train ONLY.
BEGIN;
DO $rw106_c1_close$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit constant text := 'RW1-06';
  v_cp constant text := 'RW1-06_C1';
  v_work constant bigint := 1132;
  v_actor constant text := 'MIGRATION_VIA_MERGE_TRAIN_RW1_06_C1_GOVERNED_CLOSE';
  v_prior_md5 constant text := '9bdef81bb0c618e52728ede7729d0458';
  v_evidence constant text :=
    'github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_06_C1_ADMISSION_EVIDENCE_V1.json#blob:9c6a549e937348334eae4444e6c9aea82e8ec275';
  v_artifact_path constant text :=
    'cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_06_C1_ADMISSION_EVIDENCE_V1.json';
  v_pass_when constant jsonb := $pw$
{
  "rw105_done_3_of_3": true,
  "current_source_bound": true,
  "exact_router_sha_verified": true,
  "holdout_valid_minimum_met": true,
  "holdout_invalid_minimum_met": true,
  "holdout_novel_falsifiers_minimum_met": true,
  "holdout_commitment_before_run": true,
  "separate_reviewer_evidence": true,
  "c1_negatives_rejected": 3,
  "no_runtime_activation": true,
  "no_production_activation": true,
  "independent_review_not_inferred_from_prior_c3": true,
  "separate_reviewer_evidence_verified": false,
  "provider_attested": false,
  "independent_review": false,
  "holdout_content_integrity_checked": false
}
$pw$::jsonb;
  v_old jsonb;
  v_new jsonb;
  v_spec jsonb;
  v_contract jsonb;
  v_contract_sha text;
  v_ready jsonb;
  v_bootstrap jsonb;
  v_terminal jsonb;
  v_obs jsonb;
  v_artifact jsonb;
  v_receipt jsonb;
  v_transition jsonb;
  v_err text;
  v_trial integer;
  v_count integer;
  v_functions_ok boolean;
  v_rw105_ok boolean;
BEGIN
  -- Dependency and current-source guards (all fail closed).
  v_rw105_ok := (SELECT count(*) FROM programacion.engineering_work_items
                  WHERE id=1131 AND status='DONE')=1
    AND (SELECT count(*) FROM programacion.engineering_work_checkpoints
          WHERE work_item_id=1131 AND status='DONE')=3
    AND (SELECT assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints
          WHERE work_item_id=1131 AND checkpoint_code='RW1-05_C3')
        IS NOT DISTINCT FROM 'e102a097ac005f598f572ced6b60c0dc92e306e4eeb30a24cb9d7535def5b393';
  IF NOT v_rw105_ok THEN RAISE EXCEPTION 'RW106_C1_CLOSE_RW105_DEPENDENCY_DRIFT'; END IF;

  SELECT unit_metadata INTO STRICT v_old
    FROM programacion.engineering_plan_units
   WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_work
     AND disposition='ASSIGNED' AND md5(unit_metadata::text)=v_prior_md5
   FOR UPDATE;

  IF (SELECT count(*) FROM programacion.engineering_work_items
       WHERE id=v_work AND work_code='ROUTER-W1-06' AND status='BACKLOG')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
          WHERE work_item_id=v_work AND status='PENDING'
            AND evidence_ref IS NULL AND assertion_receipt_sha256 IS NULL)<>3
     OR v_old#>>'{action_specs_v1,RW1-06_C1,schema_version}' IS DISTINCT FROM 'ENGINEERING_ACTION_SPEC_V3'
     OR v_old#>>'{source_pack_v2,checkpoint_inputs,RW1-06_C1,source_snapshot_commit}'
          IS DISTINCT FROM 'ec5d8ce5637c2d118941cfe4b3c88ae4fd325024'
     OR (v_old->>'runtime_activation')::boolean IS DISTINCT FROM false
     OR (v_old->>'production_activation')::boolean IS DISTINCT FROM false
  THEN RAISE EXCEPTION 'RW106_C1_CLOSE_PRESTATE_DRIFT'; END IF;

  v_functions_ok :=
    md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure))
      = 'd54120efc72b215ea8c5692fc4efb76a'
    AND md5(pg_get_functiondef('public.lf_router_intent_handoff_v2(text,jsonb,text,jsonb,jsonb)'::regprocedure))
      = 'e6c5df658f322e0c67ee7a2bb5972410'
    AND md5(pg_get_functiondef('public.lf_router_semantic_resume_validate_v1(jsonb,jsonb)'::regprocedure))
      = '42e385535e5a8f32d31cc7447a62b860'
    AND md5(pg_get_functiondef('public.lf_router_semantic_resume_route_v1(jsonb,jsonb)'::regprocedure))
      = '461b8f5e0e3f6fabcef5a4786bcf9ba8'
    AND (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
          WHERE n.nspname='public' AND (
            (p.proname='lf_router_intent_handoff_v1'
              AND md5(pg_get_functiondef(p.oid))='540bc1b60caf2e3f9d81461f99c509ef')
         OR (p.proname='lf_profile_execution_terminal_authority_receipt_v1'
              AND md5(pg_get_functiondef(p.oid))='6e81929dad0b0952d7ae94a80738a5ff')
         OR (p.proname='lf_profile_execution_executor_admission_v1'
              AND md5(pg_get_functiondef(p.oid))='e584b781c5df3fd58983706830f491f4')))=3
    AND (SELECT count(*) FROM public.lf_router_action_registry WHERE status='ACTIVE')=35;
  IF NOT v_functions_ok THEN RAISE EXCEPTION 'RW106_C1_CLOSE_ROUTER_SOURCE_DRIFT'; END IF;

  v_terminal:=public.lf_profile_execution_terminal_authority_receipt_v1(
    'EXEC-RW105-C2-GPT-NATIVE-CANARY-20261021-001');
  IF v_terminal->>'status' IS DISTINCT FROM 'READY'
  THEN RAISE EXCEPTION 'RW106_C1_CLOSE_RW105_TERMINAL_NOT_READY'; END IF;

  -- The generic checkpoint close stays a read-only candidate: this migration is the route.
  IF NOT EXISTS (
       SELECT 1 FROM public.lf_operation_registry
        WHERE operation_code='CIERRE_CHECKPOINT_INGENIERIA_LF'
          AND status='CANDIDATO_READ_ONLY' AND lifecycle_state_code='OP_CANDIDATE')
     OR NOT EXISTS (
       SELECT 1 FROM public.lf_router_action_registry
        WHERE operation_code='CIERRE_CHECKPOINT_INGENIERIA_LF'
          AND action_code='CHECKPOINT_CLOSE' AND status='CANDIDATO_READ_ONLY'
          AND write_allowed=false)
  THEN RAISE EXCEPTION 'RW106_C1_CLOSE_GENERIC_PROVIDER_AUTHORITY_DRIFT'; END IF;

  -- Contract amendment: the original pass_when mirrored policy minima as equalities
  -- (12/24/2), which @> containment can only satisfy with exactly those counts. The
  -- committed holdout has 13/26/2, so the minima become explicit booleans and the
  -- honest negative claims are pinned (provider_attested/independent_review stay false).
  v_artifact := jsonb_build_object(
    'path',v_artifact_path,'role','MUTATION_TARGET',
    'purpose','C1_ADMISSION_EVIDENCE','target_kind','EXACT_FILE');
  IF v_old#>'{action_specs_v1,RW1-06_C1,target,mutation_artifacts}' IS DISTINCT FROM '[]'::jsonb
  THEN RAISE EXCEPTION 'RW106_C1_CLOSE_MUTATION_ARTIFACTS_NOT_EMPTY'; END IF;

  v_new := jsonb_set(v_old,'{action_specs_v1,RW1-06_C1,assertion_contract,pass_when}',v_pass_when,false);
  v_new := jsonb_set(v_new,'{action_specs_v1,RW1-06_C1,target,mutation_artifacts}',
                     jsonb_build_array(v_artifact),false);
  v_new := jsonb_set(v_new,'{action_specs_v1,RW1-06_C1,target,declared_artifacts}',
                     (v_new#>'{action_specs_v1,RW1-06_C1,target,declared_artifacts}')
                       || jsonb_build_array(v_artifact),false);
  v_new := jsonb_set(v_new,'{action_specs_v1,RW1-06_C1,test_execution_contract}',
    (v_new#>'{action_specs_v1,RW1-06_C1,test_execution_contract}') || $tec$
{
  "test_code": "ENG_RW106_C1_COMMIT_REVEAL_ADMISSION",
  "test_path": "cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/router_wave/verify_rw106_c1_commit_reveal_v1.py",
  "execution_route": {
    "role": "DETERMINISTIC_VERIFIER_ONLY",
    "job_name": "router-level2-advisory-contract",
    "provider": "GITHUB_ACTIONS",
    "check_name": "router-level2-advisory-contract",
    "workflow_path": ".github/workflows/lf-router-level2-advisory-tests.yml"
  }
}
$tec$::jsonb,false);
  v_new := jsonb_set(v_new,'{source_pack_v2,checkpoint_inputs,RW1-06_C1,missing}',
                     '["PROVIDER_RUN_NOT_OBSERVED"]'::jsonb,false);
  v_new := jsonb_set(v_new,'{source_pack_v2,checkpoint_inputs,RW1-06_C1,missing_typed}',
                     '["PROVIDER_RUN_NOT_OBSERVED"]'::jsonb,false);
  v_new := jsonb_set(v_new,'{source_pack_v2,checkpoint_inputs,RW1-06_C1,observed,holdout_committed_before_run}',
                     'true'::jsonb,true);
  v_new := jsonb_set(v_new,'{source_pack_v2,checkpoint_inputs,RW1-06_C1,contract_amendment}',
    $amend$
{
  "reason": "pass_when numeric minima (12/24/2) were equalities under jsonb containment; committed holdout is 13/26/2",
  "replaced": ["holdout_valid_cases", "holdout_invalid_cases", "holdout_novel_falsifiers"],
  "by": ["holdout_valid_minimum_met", "holdout_invalid_minimum_met", "holdout_novel_falsifiers_minimum_met"],
  "pinned_negative_claims": ["separate_reviewer_evidence_verified", "provider_attested", "independent_review", "holdout_content_integrity_checked"],
  "owner_decision": "D1_B",
  "residual": "PROVIDER_RUN_NOT_OBSERVED stays typed missing; no provider attestation exists"
}
$amend$::jsonb,true);

  UPDATE programacion.engineering_plan_units SET unit_metadata=v_new
   WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_work
     AND md5(unit_metadata::text)=v_prior_md5;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>1 THEN RAISE EXCEPTION 'RW106_C1_CLOSE_METADATA_CAS_FAILED'; END IF;

  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(v_plan,v_unit,v_cp);
  v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(v_plan,v_unit,v_cp,v_spec);
  v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);
  IF v_spec->>'status' IS DISTINCT FROM 'READY'
     OR v_contract->>'status' IS DISTINCT FROM 'READY'
     OR v_contract->>'mode' IS DISTINCT FROM 'EXPLICIT_PASS_WHEN_SUBSET'
     OR (v_contract->'pass_when') IS DISTINCT FROM v_pass_when
     OR v_ready->>'status' IS DISTINCT FROM 'READY'
     OR v_ready->>'execution_capability' IS DISTINCT FROM 'WRITE_GIT'
  THEN RAISE EXCEPTION 'RW106_C1_CLOSE_CONTRACT_OR_READINESS_NOT_READY: %',v_ready::text; END IF;
  v_contract_sha:=programacion.fn_v09_sha256_jsonb(v_contract);

  v_bootstrap:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
  IF v_bootstrap#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM v_cp
     OR v_bootstrap#>>'{execution_readiness,status}' IS DISTINCT FROM 'READY'
     OR v_bootstrap#>>'{state,open_blockers}' IS DISTINCT FROM '0'
     OR v_bootstrap#>>'{state,unmet_deps}' IS DISTINCT FROM '0'
  THEN RAISE EXCEPTION 'RW106_C1_CLOSE_BOOTSTRAP_NOT_READY: %',v_bootstrap->>'terminal_action'; END IF;

  -- Observed facts: live-computed where the database can prove them; the rest is the
  -- Git-recorded evidence document (commitment before any producer RAW; 3 named negatives).
  v_obs := jsonb_build_object(
    'rw105_done_3_of_3',v_rw105_ok,
    'current_source_bound',v_functions_ok,
    'exact_router_sha_verified',v_functions_ok,
    'holdout_valid_minimum_met',true,
    'holdout_invalid_minimum_met',true,
    'holdout_novel_falsifiers_minimum_met',true,
    'holdout_commitment_before_run',true,
    'separate_reviewer_evidence',true,
    'c1_negatives_rejected',3,
    'no_runtime_activation',(v_old->>'runtime_activation')::boolean=false,
    'no_production_activation',(v_old->>'production_activation')::boolean=false,
    'independent_review_not_inferred_from_prior_c3',true,
    'separate_reviewer_evidence_verified',false,
    'separate_reviewer_evidence_kind','OWNER_DECLARATION_COMMIT_REVEAL_D1_B',
    'provider_attested',false,
    'independent_review',false,
    'isolation_provable',false,
    'chronology_authenticated',false,
    'holdout_content_integrity_checked',false,
    'holdout_counts_reported_by_reviewer',jsonb_build_object('valid',13,'invalid',26,'novel_falsifiers',2),
    'commitment_git_blob','f26d3001b42a86e5617b915f24e0e07a405b920c',
    'commitment_commit','bc77301d419be28df99230f7f591be357c5cb38c',
    'verifier_git_blob','a3f973de0f70d348170cf386537f8dce324b8062',
    'c2_started',false,
    'c3_full_required',true
  );
  IF (v_obs @> (v_contract->'pass_when')) IS DISTINCT FROM true
  THEN RAISE EXCEPTION 'RW106_C1_CLOSE_OBSERVED_NOT_MATCHING_CONTRACT'; END IF;

  -- Forged observations must be rejected and leave no residue.
  FOR v_trial IN 1..3 LOOP
    BEGIN
      PERFORM programacion.fn_engineering_checkpoint_assertion_record_v1(
        v_plan,v_unit,v_cp,
        jsonb_build_object('status','PASS','evidence_ref',v_evidence,'observed',
          CASE v_trial
            WHEN 1 THEN jsonb_set(v_obs,'{holdout_commitment_before_run}','false'::jsonb,true)
            WHEN 2 THEN jsonb_set(v_obs,'{c1_negatives_rejected}','2'::jsonb,true)
            ELSE jsonb_set(v_obs,'{provider_attested}','true'::jsonb,true)
          END),
        v_actor||'_NEGATIVE');
      RAISE EXCEPTION 'RW106_C1_CLOSE_FORGED_OBSERVATION_ACCEPTED:%',v_trial;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
      IF v_err NOT LIKE 'ENGINEERING_ASSERTION_RESULT_FAILED:%'
      THEN RAISE EXCEPTION 'RW106_C1_CLOSE_NEGATIVE_UNEXPECTED:%',v_err; END IF;
    END;
  END LOOP;
  IF EXISTS (SELECT 1 FROM programacion.engineering_work_checkpoints
              WHERE work_item_id=v_work AND checkpoint_code=v_cp
                AND assertion_receipt_sha256 IS NOT NULL)
  THEN RAISE EXCEPTION 'RW106_C1_CLOSE_NEGATIVE_LEFT_RESIDUE'; END IF;

  -- Positive rehearsal with guaranteed rollback, then the authoritative apply.
  FOR v_trial IN 1..2 LOOP
    BEGIN
      v_receipt:=programacion.fn_engineering_checkpoint_assertion_record_v1(
        v_plan,v_unit,v_cp,
        jsonb_build_object('status','PASS','test_code','ENG_RW106_C1_COMMIT_REVEAL_ADMISSION',
          'evidence_ref',v_evidence,'observed',v_obs),
        v_actor);
      IF v_receipt->>'passed' IS DISTINCT FROM 'true'
         OR v_receipt->>'contract_sha256' IS DISTINCT FROM v_contract_sha
         OR coalesce(v_receipt->>'assertion_receipt_sha256','') !~ '^[0-9a-f]{64}$'
      THEN RAISE EXCEPTION 'RW106_C1_CLOSE_ASSERTION_RECEIPT_INVALID'; END IF;

      v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
        v_plan,v_unit,v_cp,'DONE',v_evidence,v_actor,
        'RW1-06_C1: source freeze and sealed-holdout commitment (13/26/2) registered in Git before any producer RAW; three named negatives rejected; owner accepted D1=B. NOT provider-attested, NOT independent by proof, holdout content integrity checked only at reveal. C2 and C3 remain PENDING; C3 stays FULL.');
      IF v_transition#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
      THEN RAISE EXCEPTION 'RW106_C1_CLOSE_TRANSITION_NOT_APPLIED'; END IF;

      IF NOT EXISTS (
           SELECT 1 FROM programacion.engineering_work_checkpoints
            WHERE work_item_id=v_work AND checkpoint_code=v_cp
              AND status='DONE' AND evidence_ref=v_evidence AND completed_at IS NOT NULL
              AND assertion_contract_sha256=v_contract_sha
              AND assertion_receipt_sha256=v_receipt->>'assertion_receipt_sha256'
              AND assertion_receipt_sha256=programacion.fn_v09_sha256_jsonb(assertion_receipt))
         OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
              WHERE work_item_id=v_work AND checkpoint_code IN ('RW1-06_C2','RW1-06_C3')
                AND status='PENDING' AND evidence_ref IS NULL
                AND assertion_receipt_sha256 IS NULL)<>2
         OR (SELECT status FROM programacion.engineering_work_items WHERE id=v_work)
              IS DISTINCT FROM 'IN_PROGRESS'
      THEN RAISE EXCEPTION 'RW106_C1_CLOSE_TRIAL_READBACK_FAILED'; END IF;

      IF v_trial=1 THEN
        RAISE EXCEPTION 'RW106_C1_CLOSE_POSITIVE_ROLLBACK_SENTINEL' USING ERRCODE='PZ089';
      END IF;
    EXCEPTION WHEN SQLSTATE 'PZ089' THEN
      IF v_trial<>1 THEN
        RAISE EXCEPTION 'RW106_C1_CLOSE_UNEXPECTED_ROLLBACK_SENTINEL'; END IF;
    END;
    IF v_trial=1 THEN
      IF (SELECT status FROM programacion.engineering_work_checkpoints
           WHERE work_item_id=v_work AND checkpoint_code=v_cp) IS DISTINCT FROM 'PENDING'
         OR EXISTS (SELECT 1 FROM programacion.engineering_work_checkpoints
                     WHERE work_item_id=v_work AND checkpoint_code=v_cp
                       AND assertion_receipt_sha256 IS NOT NULL)
         OR (SELECT status FROM programacion.engineering_work_items WHERE id=v_work)
              IS DISTINCT FROM 'BACKLOG'
      THEN RAISE EXCEPTION 'RW106_C1_CLOSE_ROLLBACK_LEFT_RESIDUE'; END IF;
    END IF;
  END LOOP;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=v_work AND checkpoint_code=v_cp AND status='DONE')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
          WHERE work_item_id=v_work AND status='PENDING')<>2
     OR (SELECT status FROM programacion.engineering_work_items WHERE id=v_work)
          IS DISTINCT FROM 'IN_PROGRESS'
  THEN RAISE EXCEPTION 'RW106_C1_CLOSE_FINAL_STATE_INCONSISTENT'; END IF;
END
$rw106_c1_close$;
COMMIT;
