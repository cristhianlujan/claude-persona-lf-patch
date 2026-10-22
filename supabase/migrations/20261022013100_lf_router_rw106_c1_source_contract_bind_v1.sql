-- RW1-06_C1: govern source-policy freeze and prepare independent holdout contract.
-- Bound only through ACTUALIZACION_DB_LF / LF Migration Merge Train.
-- No C1 closure; no inferred independent holdout; no C2 run, Router/ACL/T3/production effects.
BEGIN;
DO $rw106_c1_bind$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit constant text := 'RW1-06';
  v_cp constant text := 'RW1-06_C1';
  v_wi constant bigint := 1132;
  v_prior_md5 constant text := 'a47654d9ed8f680df424f97a93c3f6a4';
  v_spec jsonb := $spec$
{
  "schema_version": "ENGINEERING_ACTION_SPEC_V3",
  "status": "READY",
  "checkpoint_code": "RW1-06_C1",
  "contract_source": "EXPLICIT_ACTION_SPEC",
  "contract_family": "VERIFIED_CURRENT_SOURCE",
  "precision": "EXACT_RW106_C1_SOURCE_POLICY_AND_INDEPENDENT_HOLDOUT_FREEZE_V1",
  "action_kind": "BOUNDED_CHECKPOINT_TEST_AUTHORING",
  "recipe_mode": "AUTHOR_AND_RUN_CHECKPOINT_TEST",
  "mutation_policy": "TEST_ARTIFACT_ONLY",
  "requires_material_execution": true,
  "expected": "Freeze the exact current LF Router source, preregister an independently generated sealed holdout and fail thresholds before any C2 tests or C3 judgement.",
  "target": {
    "checkpoint": "RW1-06_C1",
    "declared_assets": [
      "ACT-0001"
    ],
    "declared_events": [],
    "declared_objects": [
      "public.lf_router_resolve_v1",
      "public.lf_router_intent_handoff_v2",
      "public.lf_router_semantic_resume_validate_v1",
      "public.lf_router_semantic_resume_route_v1",
      "programacion.engineering_plan_units",
      "programacion.engineering_work_items",
      "programacion.engineering_work_checkpoints",
      "public.lf_operation_execution"
    ],
    "declared_artifacts": [
      {
        "path": "cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_06_C1_SOURCE_POLICY_FREEZE_V1.json",
        "role": "EVIDENCE",
        "purpose": "SOURCE_AND_PREREGISTERED_HOLDOUT_POLICY",
        "target_kind": "EXACT_EXISTING_FILE"
      },
      {
        "path": "cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/router_wave/validate_rw106_c1_holdout_commitment_v1.py",
        "role": "EVIDENCE",
        "purpose": "SEALED_HOLDOUT_COMMITMENT_VALIDATOR",
        "target_kind": "EXACT_EXISTING_FILE"
      },
      {
        "path": "cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_06_C1_INDEPENDENT_HOLDOUT_HANDOFF_V1.md",
        "role": "EVIDENCE",
        "purpose": "SEPARATE_REVIEWER_HANDOFF",
        "target_kind": "EXACT_EXISTING_FILE"
      }
    ],
    "evidence_artifacts": [
      {
        "path": "cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_06_C1_SOURCE_POLICY_FREEZE_V1.json",
        "role": "EVIDENCE",
        "purpose": "SOURCE_POLICY_FREEZE",
        "target_kind": "EXACT_EXISTING_FILE"
      },
      {
        "path": "cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/router_wave/validate_rw106_c1_holdout_commitment_v1.py",
        "role": "EVIDENCE",
        "purpose": "SEALED_HOLDOUT_COMMITMENT_VALIDATOR",
        "target_kind": "EXACT_EXISTING_FILE"
      },
      {
        "path": "cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_06_C1_INDEPENDENT_HOLDOUT_HANDOFF_V1.md",
        "role": "EVIDENCE",
        "purpose": "SEPARATE_REVIEWER_HANDOFF",
        "target_kind": "EXACT_EXISTING_FILE"
      }
    ],
    "mutation_artifacts": []
  },
  "forbidden": [
    "DECLARE_C1_DONE_WITHOUT_INDEPENDENT_HOLDOUT",
    "REUSE_BURNED_HOLDOUT",
    "PRODUCER_SELF_JUDGEMENT",
    "DISCLOSE_HOLDOUT_BEFORE_COMMITMENT",
    "TREAT_LOCAL_PREFLIGHT_AS_PROVIDER_RUN",
    "CLAIM_NUMERIC_OVERHEAD_SLO_EXISTS",
    "CLAIM_PREVIOUS_C3_IS_CRYPTOGRAPHICALLY_INDEPENDENT",
    "CREATE_SECOND_ROUTER",
    "WIDEN_SCOPE_OR_ACL",
    "ACTIVATE_RUNTIME_T3_T4",
    "DIRECT_DB_WRITE_OUTSIDE_TRAIN",
    "GOLDEN_PROMOTION"
  ],
  "action_steps": [
    "REVALIDATE_RW105_DEPENDENCY_AND_ASSERTION",
    "RECHECK_FROZEN_GIT_BLOBS_AND_LIVE_DB_SIGNATURES",
    "PRE_REGISTER_13_TEST_FAMILIES_AND_FAIL_GATES",
    "GENERATE_SEALED_HOLDOUT_FROM_MATERIALLY_SEPARATE_REVIEWER",
    "COMMIT_HOLDOUT_MANIFEST_AND_SOURCE_ID_BEFORE_ANY_C2_RUN",
    "EXECUTE_MISSING_STALE_CROSS_PROJECT_NEGATIVES",
    "RECORD_PROVIDER_RUN_AND_C1_READBACK",
    "ONLY_THEN_PROPOSE_GOVERNED_ASSERTION_AND_C1_TRANSITION"
  ],
  "assertion_contract": {
    "mode": "EXPLICIT_PASS_WHEN_SUBSET",
    "pass_when": {
      "rw105_done_3_of_3": true,
      "current_source_bound": true,
      "exact_router_sha_verified": true,
      "holdout_valid_cases": 12,
      "holdout_invalid_cases": 24,
      "holdout_novel_falsifiers": 2,
      "holdout_commitment_before_run": true,
      "separate_reviewer_evidence": true,
      "c1_negatives_rejected": 3,
      "no_runtime_activation": true,
      "no_production_activation": true,
      "independent_review_not_inferred_from_prior_c3": true
    }
  },
  "test_execution_contract": {
    "mode": "AUTHORED_NEGATIVE",
    "test_code": "ENG_RW106_C1_INDEPENDENT_HOLDOUT_FREEZE",
    "authoring_required": true,
    "negative_required": true,
    "synthetic_pass": "FORBIDDEN",
    "semantic_authority": "SEPARATE_REVIEWER_REQUIRES_NEW_INDEPENDENT_INVOCATION",
    "checkpoint_title_context": "RW1-06_C1",
    "canonical_exit_criterion": "Exact sources frozen and sealed new independent holdout committed with predeclared hard fail gates and material readback; no C2 testing or C1 DONE without actual evidence."
  },
  "verification_queries": [
    "SELECT checkpoint_code,status,evidence_ref,assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints WHERE work_item_id=1132 ORDER BY sequence_no",
    "SELECT md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure)) AS router_md5",
    "SELECT public.lf_profile_execution_terminal_authority_receipt_v1('EXEC-RW105-C2-GPT-NATIVE-CANARY-20261021-001')->>'status' AS terminal_status"
  ],
  "evidence_ref": "github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_06_C1_SOURCE_POLICY_FREEZE_V1.json#blob:138efc3285ee5226c107827c66f84ced6be4afcb"
}
$spec$::jsonb;
  v_source jsonb := $source$
{
  "inputs": {
    "assets": [
      "ACT-0001"
    ],
    "events": [],
    "db_objects": [
      "public.lf_router_resolve_v1",
      "public.lf_router_intent_handoff_v1",
      "public.lf_router_intent_handoff_v2",
      "public.lf_router_semantic_resume_validate_v1",
      "public.lf_router_semantic_resume_route_v1",
      "public.lf_profile_execution_terminal_authority_receipt_v1",
      "public.lf_router_action_registry",
      "programacion.engineering_plan_units",
      "programacion.engineering_work_items",
      "programacion.engineering_work_checkpoints"
    ],
    "artifacts": [
      "docs/programming-agent/router_wave/RW1_06_C1_SOURCE_POLICY_FREEZE_V1.json",
      "docs/programming-agent/LF_ROUTER_ARCHITECTURE_WAVE_V1.md",
      "docs/programming-agent/router_wave/RW1_01_C3_NEEDS_ACCEPTANCE_CORPUS_V2.json",
      "docs/programming-agent/router_wave/RW1_03_C2_SEMANTIC_ABI_TRANSITION_V1.json",
      "docs/programming-agent/router_wave/RW1_05_C3_REVIEW_CAPTURE_V1.json",
      "sandbox/lf_contract_gate_test/router_wave/validate_rw106_c1_holdout_commitment_v1.py",
      "docs/programming-agent/router_wave/RW1_06_C1_INDEPENDENT_HOLDOUT_HANDOFF_V1.md"
    ],
    "queries": [
      "SELECT checkpoint_code,status,evidence_ref,assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints WHERE work_item_id=1132 ORDER BY sequence_no",
      "SELECT md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure)) AS router_md5",
      "SELECT public.lf_profile_execution_terminal_authority_receipt_v1('EXEC-RW105-C2-GPT-NATIVE-CANARY-20261021-001')->>'status' AS terminal_status"
    ]
  },
  "residual_gaps": [
    {
      "code": "OVERHEAD_NUMERIC_SLO_UNDEFINED",
      "disposition": "GAP_FOR_C3_DECISION_NOT_C1_HOLDOUT_FREEZE_BLOCKER",
      "pass_claim": false,
      "action": "MEASURE_ACTUAL_OVERHEAD_AND_REPORT_GAP_UNTIL_GOVERNED_SLO_EXISTS"
    }
  ],
  "source_snapshot_commit": "ec5d8ce5637c2d118941cfe4b3c88ae4fd325024",
  "source_git_blobs": {
    "rw106_freeze": "138efc3285ee5226c107827c66f84ced6be4afcb",
    "wave": "4bb64d568c3f005cf454fb223b4a5ed699c34504",
    "rw101_corpus": "55c09eb0fc6ddffa7a41d66eddf9c254e061f566",
    "rw103_abi": "bfd571d5e7c7d1d80c5ed39414a822b4096c20d6",
    "rw105_c3_capture": "da02bc075aa45f0ef5f3c81dfc310c6488b3ab63",
    "sealed_holdout_commitment_validator": "72d3c4f98aeedbf63c21334b06b9c091b0fa9a99",
    "separate_reviewer_handoff": "d0ae33254f875f45081b56cfbe7506bdadfef477"
  },
  "db_source_md5": {
    "lf_router_resolve_v1": "d54120efc72b215ea8c5692fc4efb76a",
    "lf_router_intent_handoff_v2": "e6c5df658f322e0c67ee7a2bb5972410",
    "lf_router_semantic_resume_validate_v1": "42e385535e5a8f32d31cc7447a62b860",
    "lf_router_semantic_resume_route_v1": "461b8f5e0e3f6fabcef5a4786bcf9ba8"
  },
  "missing": [
    "INDEPENDENT_SEALED_HOLDOUT_NOT_COMMITTED",
    "PROVIDER_RUN_NOT_OBSERVED"
  ],
  "missing_typed": [
    "INDEPENDENT_SEALED_HOLDOUT_NOT_COMMITTED",
    "PROVIDER_RUN_NOT_OBSERVED"
  ],
  "observed": {
    "rw105_c3": "DONE",
    "rw106_c1": "PENDING",
    "holdout_independent": false,
    "provider_attested": false,
    "baseline_active_actions": 35,
    "production_activation": false,
    "runtime_activation": false,
    "source_policy_test_family_count": 13,
    "holdout_minimum_valid": 12,
    "holdout_minimum_invalid": 24,
    "holdout_novel_falsifiers": 2
  },
  "verification_boundary": "RW106_C1_CONTRACT_BIND_ONLY_NOT_ADMISSION_NOT_C1_CLOSURE_NOT_C2_TESTING",
  "expected_result": "Contract and exact source frozen in governed plan metadata; checkpoint remains PENDING until independent committed holdouts and evidence.",
  "evidence_ref": "github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_06_C1_SOURCE_POLICY_FREEZE_V1.json#blob:138efc3285ee5226c107827c66f84ced6be4afcb"
}
$source$::jsonb;
  v_old jsonb;
  v_new jsonb;
  v_rows integer;
BEGIN
  IF (SELECT count(*) FROM programacion.engineering_work_items
      WHERE id=1131 AND status='DONE')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=1131 AND status='DONE')<>3
     OR (SELECT assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=1131 AND checkpoint_code='RW1-05_C3')
        IS DISTINCT FROM 'e102a097ac005f598f572ced6b60c0dc92e306e4eeb30a24cb9d7535def5b393'
  THEN RAISE EXCEPTION 'RW106_C1_RW105_DEPENDENCY_OR_ASSERTION_DRIFT'; END IF;

  SELECT unit_metadata INTO STRICT v_old
    FROM programacion.engineering_plan_units
    WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi
      AND disposition='ASSIGNED' AND md5(unit_metadata::text)=v_prior_md5
    FOR UPDATE;

  IF (SELECT count(*) FROM programacion.engineering_work_items
      WHERE id=v_wi AND work_code='ROUTER-W1-06' AND status='BACKLOG')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_wi AND status='PENDING' AND evidence_ref IS NULL)<>3
     OR v_old#>'{action_specs_v1,RW1-06_C1}' IS NOT NULL
     OR v_old#>'{source_pack_v2,checkpoint_inputs,RW1-06_C1}' IS NOT NULL
  THEN RAISE EXCEPTION 'RW106_C1_CONTRACT_PRESTATE_DRIFT'; END IF;

  IF md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure))
       IS DISTINCT FROM 'd54120efc72b215ea8c5692fc4efb76a'
     OR md5(pg_get_functiondef('public.lf_router_intent_handoff_v2(text,jsonb,text,jsonb,jsonb)'::regprocedure))
       IS DISTINCT FROM 'e6c5df658f322e0c67ee7a2bb5972410'
     OR md5(pg_get_functiondef('public.lf_router_semantic_resume_validate_v1(jsonb,jsonb)'::regprocedure))
       IS DISTINCT FROM '42e385535e5a8f32d31cc7447a62b860'
     OR md5(pg_get_functiondef('public.lf_router_semantic_resume_route_v1(jsonb,jsonb)'::regprocedure))
       IS DISTINCT FROM '461b8f5e0e3f6fabcef5a4786bcf9ba8'
     OR (SELECT count(*) FROM public.lf_router_action_registry WHERE status='ACTIVE')<>35
  THEN RAISE EXCEPTION 'RW106_C1_CURRENT_ROUTER_SOURCE_DRIFT'; END IF;

  IF (SELECT public.lf_profile_execution_terminal_authority_receipt_v1(
       'EXEC-RW105-C2-GPT-NATIVE-CANARY-20261021-001')->>'status')
        IS DISTINCT FROM 'READY'
  THEN RAISE EXCEPTION 'RW106_C1_RW105_CANARY_TERMINAL_NOT_READY'; END IF;

  -- This step binds the test contract but deliberately CANNOT close C1.
  -- Missing independent holdout and provider receipt remain typed blockers.
  v_new:=jsonb_set(
    v_old,'{action_specs_v1}',
    coalesce(v_old->'action_specs_v1','{}'::jsonb)||jsonb_build_object(v_cp,v_spec),true
  );
  v_new:=jsonb_set(
    v_new,'{source_pack_v2}',
    coalesce(v_new->'source_pack_v2','{}'::jsonb)||jsonb_build_object(
      'checkpoint_inputs',
      coalesce(v_new#>'{source_pack_v2,checkpoint_inputs}','{}'::jsonb)
        ||jsonb_build_object(v_cp,v_source)
    ),true
  );

  UPDATE programacion.engineering_plan_units SET unit_metadata=v_new
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi
    AND md5(unit_metadata::text)=v_prior_md5;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows<>1 THEN RAISE EXCEPTION 'RW106_C1_BIND_ROWCOUNT_%',v_rows; END IF;

  IF (SELECT unit_metadata#>>'{action_specs_v1,RW1-06_C1,schema_version}'
      FROM programacion.engineering_plan_units
      WHERE plan_code=v_plan AND unit_code=v_unit) IS DISTINCT FROM 'ENGINEERING_ACTION_SPEC_V3'
     OR (SELECT unit_metadata#>>'{source_pack_v2,checkpoint_inputs,RW1-06_C1,source_snapshot_commit}'
      FROM programacion.engineering_plan_units
      WHERE plan_code=v_plan AND unit_code=v_unit) IS DISTINCT FROM 'ec5d8ce5637c2d118941cfe4b3c88ae4fd325024'
     OR (SELECT status FROM programacion.engineering_work_items WHERE id=v_wi) IS DISTINCT FROM 'BACKLOG'
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_wi AND status='PENDING' AND evidence_ref IS NULL)<>3
  THEN RAISE EXCEPTION 'RW106_C1_POST_READBACK_OR_LIFECYCLE_DRIFT'; END IF;
END
$rw106_c1_bind$;
COMMIT;
