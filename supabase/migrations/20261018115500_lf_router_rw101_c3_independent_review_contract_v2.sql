-- RW1-01_C3: bind explicit independent-review contract and V2 source pack only.
-- No checkpoint closure in this migration. C3 must remain PENDING until an
-- independently attested GPT Native judge result is merged and asserted.
BEGIN;
DO $rw101_c3_bind$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit constant text := 'RW1-01';
  v_cp constant text := 'RW1-01_C3';
  v_work_item constant bigint := 1127;
  v_prior_md5 constant text := '0f6627aa6eabbbd4c20a2b0ae51853cf';
  v_spec jsonb := $json$
{
  "status":"READY",
  "schema_version":"ENGINEERING_ACTION_SPEC_V3",
  "checkpoint_code":"RW1-01_C3",
  "contract_source":"EXPLICIT_ACTION_SPEC",
  "contract_family":"INDEPENDENT_ADVERSARIAL_REVIEW",
  "precision":"EXACT_RW101_C3_INDEPENDENT_V2",
  "action_kind":"MATERIALIZE_DECLARED_DELIVERABLE",
  "recipe_mode":"EXECUTE_DECLARED_DELIVERABLE",
  "mutation_policy":"TEST_ARTIFACT_ONLY",
  "requires_material_execution":true,
  "expected":"A materially separate GPT Native judge freezes RAW1 before prior critiques, evaluates V2 plus a fresh secret-seed holdout, and returns PASS only with zero material blockers. No Router runtime or production claim.",
  "target":{
    "checkpoint":"RW1-01_C3",
    "declared_assets":["ACT-0001"],
    "declared_events":[21263],
    "declared_objects":[
      "programacion.engineering_plan_units",
      "programacion.engineering_work_checkpoints",
      "public.lf_error_knowledge",
      "supabase_migrations.schema_migrations"
    ],
    "declared_artifacts":[
      {"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_01_C3_NEEDS_ACCEPTANCE_CORPUS_V2.json","role":"EVIDENCE","purpose":"V2_PUBLIC_ORACLE","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/router_wave/validate_rw101_needs_corpus_v2.py","role":"EVIDENCE","purpose":"V2_FAIL_CLOSED_CHECKER","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/router_wave/generate_rw101_c3_holdout_v2.py","role":"EVIDENCE","purpose":"SECRET_SEED_HOLDOUT_GENERATOR","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_01_C3_BLIND_JUDGE_HANDOFF_V2.md","role":"EVIDENCE","purpose":"INDEPENDENT_JUDGE_PROTOCOL","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_01_C3_INDEPENDENT_VERDICT_V2.json","role":"MUTATION_TARGET","purpose":"INDEPENDENT_VERDICT","target_kind":"EXACT_FILE"}
    ],
    "evidence_artifacts":[
      {"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_01_C3_NEEDS_ACCEPTANCE_CORPUS_V2.json","role":"EVIDENCE","purpose":"V2_PUBLIC_ORACLE","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/router_wave/validate_rw101_needs_corpus_v2.py","role":"EVIDENCE","purpose":"V2_FAIL_CLOSED_CHECKER","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/router_wave/generate_rw101_c3_holdout_v2.py","role":"EVIDENCE","purpose":"SECRET_SEED_HOLDOUT_GENERATOR","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_01_C3_BLIND_JUDGE_HANDOFF_V2.md","role":"EVIDENCE","purpose":"INDEPENDENT_JUDGE_PROTOCOL","target_kind":"EXACT_EXISTING_FILE"}
    ],
    "mutation_artifacts":[
      {"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_01_C3_INDEPENDENT_VERDICT_V2.json","role":"MUTATION_TARGET","purpose":"INDEPENDENT_VERDICT","target_kind":"EXACT_FILE"}
    ]
  },
  "forbidden":[
    "SAME_PRODUCER_REVIEW",
    "REUSE_BURNED_H01_H12",
    "OPEN_PRIOR_C3_CRITIQUES_BEFORE_RAW1",
    "SELF_ATTEST_INDEPENDENCE",
    "CLAIM_ROUTER_RUNTIME_PASS",
    "CLAIM_PRODUCTION_EFFECT",
    "SYNTHETIC_HOLDOUT_PASS",
    "DIRECT_DB_MUTATION_OUTSIDE_TRAIN",
    "MERGE_WITHOUT_CI_PASE_TRAIN",
    "REOPEN_C1_OR_C2"
  ],
  "assertion_contract":{
    "mode":"EXPLICIT_PASS_WHEN_SUBSET",
    "pass_when":{
      "blind_verdict":"PASS",
      "independent_judge_attested":true,
      "judge_identity_ref_present":true,
      "source_freeze_verified":true,
      "holdout_commitment_verified":true,
      "holdout_revealed_after_raw1":true,
      "public_v2_all_42_good_accepted":true,
      "holdout_12_good_accepted":true,
      "holdout_at_least_24_bad_rejected":true,
      "novel_falsifiers_at_least_2":true,
      "material_blockers":0,
      "no_router_runtime_claim":true,
      "no_production_mutation":true
    }
  },
  "verification_queries":[
    "SELECT c.checkpoint_code,c.status,c.evidence_ref,c.assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints c WHERE c.work_item_id=1127 ORDER BY c.sequence_no",
    "SELECT md5(unit_metadata::text) unit_metadata_md5, unit_metadata#>'{action_specs_v1,RW1-01_C3}' c3_spec FROM programacion.engineering_plan_units WHERE plan_code='LF_ROUTER_ARCHITECTURE_WAVE_V1' AND unit_code='RW1-01'"
  ],
  "action_steps":[
    "FREEZE_EXACT_MAIN_AND_V2_SOURCE_BLOBS",
    "START_MATERIALLY_SEPARATE_GPT_NATIVE_JUDGE",
    "GENERATE_SECRET_SEED_HOLDOUT_AFTER_SOURCE_FREEZE",
    "ANNOUNCE_HOLDOUT_COMMITMENT_BEFORE_RESULTS",
    "FREEZE_RAW1_BEFORE_PRIOR_CRITIQUES",
    "REVEAL_AND_VERIFY_HOLDOUT_AFTER_RAW1",
    "CONTRAST_PRIOR_CRITIQUES_WITHOUT_REWRITING_RAW1",
    "MERGE_INDEPENDENT_VERDICT_ARTIFACT",
    "PERSIST_ASSERTION_RECEIPT_ONLY_FROM_REAL_INDEPENDENT_PASS",
    "PERSIST_C3_DONE_ONLY_AFTER_ASSERTION_AND_READBACK"
  ],
  "evidence_ref":"github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_01_C3_INDEPENDENT_VERDICT_V2.json"
}
$json$::jsonb;
  v_source jsonb := $json$
{
  "inputs":{
    "assets":["ACT-0001"],
    "events":[21263],
    "queries":[
      "SELECT c.checkpoint_code,c.status,c.evidence_ref FROM programacion.engineering_work_checkpoints c WHERE c.work_item_id=1127 ORDER BY c.sequence_no",
      "SELECT codigo,titulo,causa_raiz,prevencion FROM public.lf_error_knowledge WHERE codigo IN ('LF-ROUTER-ACT0001-LEXICAL-MISROUTE-20261015-001','LF-ROUTER-ACT0001-PREWRITE-INTENT-GATE-20261015-002','LF-ROUTER-ACT0001-UNSTRUCTURED-MUTATION-FALSE-READY-20261017-002','LF-ROUTER-ACT0001-TYPED-TARGET-AUTHORITY-BYPASS-20261017-003','CIERRE_PREMATURO_POR_CONFUNDIR_READ_ONLY_CON_BLOQUEO_GLOBAL') ORDER BY codigo"
    ],
    "db_objects":[
      "programacion.engineering_plan_units",
      "programacion.engineering_work_checkpoints",
      "public.lf_error_knowledge",
      "supabase_migrations.schema_migrations"
    ],
    "artifacts":[
      "docs/programming-agent/router_wave/RW1_01_C1_NEEDS_SOURCES_AND_BIASES_V1.md",
      "docs/programming-agent/router_wave/RW1_01_C3_NEEDS_ACCEPTANCE_CORPUS_V2.json",
      "sandbox/lf_contract_gate_test/router_wave/validate_rw101_needs_corpus_v2.py",
      "sandbox/lf_contract_gate_test/router_wave/generate_rw101_c3_holdout_v2.py",
      "docs/programming-agent/router_wave/RW1_01_C3_BLIND_JUDGE_HANDOFF_V2.md"
    ]
  },
  "missing":[],
  "missing_typed":[],
  "expected_result":"Independent adversarial review of V2 with a fresh secret-seed holdout and frozen RAW1. PASS requires zero material blockers; no Router runtime claim.",
  "verification_boundary":"RW101_C3_INDEPENDENT_CONTRACT_ONLY_NOT_ROUTER_RUNTIME_OR_PRODUCTION"
}
$json$::jsonb;
  v_new jsonb;
  v_count integer;
  v_compiled jsonb;
  v_contract jsonb;
  v_ready jsonb;
BEGIN
  IF (SELECT count(*) FROM programacion.engineering_plan_units u
      JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
      WHERE u.plan_code=v_plan AND u.unit_code=v_unit
        AND u.work_item_id=v_work_item AND u.plan_event_id=21263
        AND u.disposition='ASSIGNED'
        AND w.status='IN_PROGRESS'
        AND md5(u.unit_metadata::text)=v_prior_md5
        AND u.unit_metadata#>'{action_specs_v1,RW1-01_C3}' IS NULL
        AND u.unit_metadata#>'{source_pack_v2,checkpoint_inputs,RW1-01_C3}' IS NULL)<>1
  THEN RAISE EXCEPTION 'RW101_C3_BIND_PREREQUISITE_OR_SOURCE_DRIFT'; END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work_item
        AND ((checkpoint_code='RW1-01_C1' AND status='DONE')
          OR (checkpoint_code='RW1-01_C2' AND status='DONE')
          OR (checkpoint_code='RW1-01_C3' AND status='PENDING')))<>3
  THEN RAISE EXCEPTION 'RW101_C3_BIND_LIFECYCLE_DRIFT'; END IF;

  v_new := (
    SELECT jsonb_set(
      jsonb_set(u.unit_metadata,'{action_specs_v1,RW1-01_C3}',v_spec,true),
      '{source_pack_v2,checkpoint_inputs,RW1-01_C3}',v_source,true)
    FROM programacion.engineering_plan_units u
    WHERE u.plan_code=v_plan AND u.unit_code=v_unit
  );

  UPDATE programacion.engineering_plan_units
     SET unit_metadata=v_new,
         updated_at=now(),
         updated_by_execution_id='LF_ROUTER_RW101_C3_V2_BIND_TRAIN_20261018'
   WHERE plan_code=v_plan AND unit_code=v_unit
     AND md5(unit_metadata::text)=v_prior_md5;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>1 THEN RAISE EXCEPTION 'RW101_C3_BIND_ROW_COUNT:%',v_count; END IF;

  v_compiled:=programacion.fn_engineering_checkpoint_action_spec_v3(v_plan,v_unit,v_cp);
  v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(v_plan,v_unit,v_cp,v_compiled);
  v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);

  IF v_compiled->>'status' IS DISTINCT FROM 'READY'
     OR v_compiled->>'contract_source' IS DISTINCT FROM 'EXPLICIT_ACTION_SPEC'
     OR v_contract->>'status' IS DISTINCT FROM 'READY'
     OR v_contract->>'mode' IS DISTINCT FROM 'EXPLICIT_PASS_WHEN_SUBSET'
     OR v_ready->>'status' IS DISTINCT FROM 'READY'
     OR coalesce((v_ready->>'execution_ready')::boolean,false) IS NOT TRUE
  THEN RAISE EXCEPTION 'RW101_C3_BIND_COMPILED_CONTRACT_NOT_READY: spec=% contract=% ready=%',
       v_compiled::text,v_contract::text,v_ready::text; END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work_item AND checkpoint_code=v_cp
        AND status='PENDING' AND evidence_ref IS NULL AND assertion_receipt IS NULL)<>1
  THEN RAISE EXCEPTION 'RW101_C3_BIND_MUST_PRESERVE_PENDING'; END IF;
END
$rw101_c3_bind$;
COMMIT;
