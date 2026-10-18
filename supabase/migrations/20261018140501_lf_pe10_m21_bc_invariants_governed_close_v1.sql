-- PE10 M21: base B + C invariant/metamorphic evidence closure only.
DO $m21_close$
DECLARE
 v_exec text; v_raw text:=$raw${
  "schema": "PE10_METHOD_RAW_V2",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M21",
  "base_code": "B",
  "algorithm_codes": [
    "C"
  ],
  "method_catalog": "PE10_METHOD_V1",
  "source_cutoff": "2026-10-15T00:00:00Z",
  "original_preserved": {
    "ref": "chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M21.json",
    "sha256": "af542c5af8974415367758c6312e860168b34425b49f42f3d073074ea214cf60"
  },
  "role_bound_single_context": true,
  "autonomous_agent_claim": false,
  "cross_method_inputs_used": false,
  "external_evaluation": "NOT_PERFORMED",
  "producer": "B+C: five frozen role-bound metamorphic/invariant investigations followed by synthesis in one coordinated context.",
  "role_reports": [
    {
      "role": "ARCHITECTURE",
      "git_blob_sha": "7f7e2a996262c13287bd8022ecee62da8f144659",
      "query_count": 2,
      "negative_count": 2,
      "invariant_count": 3,
      "role_output_frozen": true
    },
    {
      "role": "PERFORMANCE",
      "git_blob_sha": "e419f7a90d34f184bd2fe1023cbcf268520b02a9",
      "query_count": 2,
      "negative_count": 2,
      "invariant_count": 3,
      "role_output_frozen": true
    },
    {
      "role": "AUTHORITY",
      "git_blob_sha": "71728209d57b811d437ffa4167d3e487c80d2b48",
      "query_count": 2,
      "negative_count": 2,
      "invariant_count": 2,
      "role_output_frozen": true
    },
    {
      "role": "COVERAGE",
      "git_blob_sha": "5c4eb93751391a4ff9299baefa922f646bdf0468",
      "query_count": 2,
      "negative_count": 2,
      "invariant_count": 3,
      "role_output_frozen": true
    },
    {
      "role": "INNOVATION",
      "git_blob_sha": "ba366c522667b3cbf8b742c8a65ad46666a9e945",
      "query_count": 2,
      "negative_count": 2,
      "invariant_count": 3,
      "role_output_frozen": true
    }
  ],
  "synthesis_ref": {
    "path": "docs/profile_updater/experiments/pe10_methods32_p0/M21_SYNTHESIS_V1.json",
    "source_commit": "7e33a9e2a55a375c5a797241b88b56d17057c05c",
    "git_blob_sha": "8b8d113078043369968123fb34eb26db3091d663"
  },
  "synthesis": {
    "schema": "PE10_M21_SYNTHESIS_V1",
    "case_ref": "PE10-IG-M107-M109-P0",
    "method_code": "PE10_M21",
    "base_code": "B",
    "algorithm_codes": [
      "C"
    ],
    "source_cutoff": "2026-10-15T00:00:00Z",
    "role_code": "SYNTHESIZER",
    "role_bound_single_context": true,
    "autonomous_agent_claim": false,
    "source_pieces_frozen_before_synthesis": true,
    "no_new_sql_in_synthesis": true,
    "synthesis_inputs": [
      {
        "role": "ARCHITECTURE",
        "git_blob_sha": "7f7e2a996262c13287bd8022ecee62da8f144659",
        "readbacks": 2,
        "negative_tests": 2,
        "invariants": 3,
        "role_output_frozen": true
      },
      {
        "role": "PERFORMANCE",
        "git_blob_sha": "e419f7a90d34f184bd2fe1023cbcf268520b02a9",
        "readbacks": 2,
        "negative_tests": 2,
        "invariants": 3,
        "role_output_frozen": true
      },
      {
        "role": "AUTHORITY",
        "git_blob_sha": "71728209d57b811d437ffa4167d3e487c80d2b48",
        "readbacks": 2,
        "negative_tests": 2,
        "invariants": 2,
        "role_output_frozen": true
      },
      {
        "role": "COVERAGE",
        "git_blob_sha": "5c4eb93751391a4ff9299baefa922f646bdf0468",
        "readbacks": 2,
        "negative_tests": 2,
        "invariants": 3,
        "role_output_frozen": true
      },
      {
        "role": "INNOVATION",
        "git_blob_sha": "ba366c522667b3cbf8b742c8a65ad46666a9e945",
        "readbacks": 2,
        "negative_tests": 2,
        "invariants": 3,
        "role_output_frozen": true
      }
    ],
    "readbacks_total": 10,
    "negative_tests_total": 10,
    "invariants_total": 14,
    "solver_used": false,
    "findings": [
      {
        "id": "M21_SYN_F1",
        "classification": "MEASURED",
        "finding": "Historical hash comparator reconciles exactly 38=16 TRUE+22 FALSE+0 absent; 38/38 historical hashes are present and syntactically valid, without proving the historical hash recipe."
      },
      {
        "id": "M21_SYN_F2",
        "classification": "MEASURED",
        "finding": "Duration data requires three-valued partitioning: NULL, zero and positive reconcile independently by status; treating NULL as zero is invalid."
      },
      {
        "id": "M21_SYN_F3",
        "classification": "MEASURED",
        "finding": "Authority capabilities are non-monotonic by privilege: EXECUTE=false while SELECT=true, so permission denial cannot be promoted to functional failure or total evidence inaccessibility."
      },
      {
        "id": "M21_SYN_F4",
        "classification": "MEASURED",
        "finding": "All 38 historical caller names resolve currently, but 6/39 callee tokens have multiple current name candidates and therefore fail a uniqueness invariant."
      },
      {
        "id": "M21_SYN_F5",
        "classification": "MEASURED_CANDIDATE_ONLY",
        "finding": "Current pattern population reconciles 95=31 historical-member+64 complement candidates; candidate membership is not omission proof. SQL/external domains remain separate with 0 raw-name overlap."
      }
    ],
    "metamorphic_tests": [
      {
        "id": "C_META_1",
        "transform": "repartition comparator outcomes",
        "expected": "total invariant unchanged",
        "observed": "38=16+22+0",
        "status": "PASS"
      },
      {
        "id": "C_META_2",
        "transform": "separate NULL/zero/positive duration categories",
        "expected": "status totals reconcile",
        "observed": "all status partitions reconcile",
        "status": "PASS"
      },
      {
        "id": "C_META_3",
        "transform": "remove EXECUTE capability while retaining SELECT",
        "expected": "evidence-read capability can remain",
        "observed": "SELECT true with EXECUTE false",
        "status": "PASS"
      },
      {
        "id": "C_META_4",
        "transform": "resolve callee by proname only",
        "expected": "ambiguity must surface when >1 candidate",
        "observed": "6 multiple-candidate tokens",
        "status": "PASS"
      },
      {
        "id": "C_META_5",
        "transform": "partition current pattern names by historical membership",
        "expected": "total=current member+complement",
        "observed": "95=31+64",
        "status": "PASS"
      }
    ],
    "contradictions": [
      {
        "topic": "38 current-present caller names vs 22 comparator-false",
        "resolution": "name presence and definition equality are different invariants"
      },
      {
        "topic": "family_count 47 in both revisions vs cohort equivalence",
        "resolution": "same family count does not preserve sample/duration partition"
      },
      {
        "topic": "EXECUTE denied vs SELECT allowed",
        "resolution": "privileges are distinct capabilities"
      },
      {
        "topic": "0 unresolved callee names vs 6 ambiguous",
        "resolution": "name existence does not imply unique object identity"
      }
    ],
    "decision": {
      "state": "VERIFY_FIRST",
      "implemented_repair": false,
      "reason": "C validates population/invariant boundaries and counterexamples, but no single domain defect or safe repair is established."
    },
    "unresolved": [
      "canonical historical hash method",
      "zero-duration semantics",
      "matched performance effect",
      "six callee object identities",
      "caller classification of current complement"
    ],
    "constraints_preserved": [
      "READ_ONLY",
      "no production edits",
      "P0/current separation",
      "five reports frozen before synthesis",
      "no cross-method inputs",
      "no autonomous-agent claim"
    ],
    "non_isolation_risk": "Five role-bound passes were sequential in one shared model context; reports were frozen before synthesis, but independent autonomous cognition is not claimed.",
    "final_method_status": "B_C_FIVE_ROLE_REPORTS_SYNTHESIZED_MATERIAL_ONLY_NOT_YET_GOVERNED_DONE"
  },
  "source_queries_total": 10,
  "negative_tests_total": 10,
  "invariants_total": 14,
  "metamorphic_tests_total": 5,
  "solver_used": false,
  "final_method_state": "B_C_ROLE_REPORTS_SYNTHESIZED_NO_DOMAIN_REPAIR",
  "causal_defect_proven": false,
  "solution_state": "VERIFY_FIRST",
  "runtime_modified": false,
  "independence_constraint": {
    "frozen_before_synthesis": true,
    "report_results_from_one_model_context": true,
    "independent_agents": false
  },
  "limits": [
    "invariants validate partitions/identity boundaries, not business-rule truth beyond measured evidence",
    "solver result not claimed",
    "P0/current separation preserved"
  ]
}
$raw$; v_doc jsonb; v_spec jsonb:=$spec${"status":"READY","action_kind":"VERIFY_QUERY_ONCE","recipe_mode":"READBACK_EXACT","requires_material_execution":true,"contract_family":"PE10_METHOD_EXECUTION_EVIDENCE","precision":"PE10_METHOD_V1_MATERIAL_EVIDENCE","assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"checkpoint_identity":"PE10_M21","base_code":"B","algorithm_C_executed":true,"role_reports_frozen":5,"synthesis_completed":true,"read_only_sql_queries":10,"role_negative_tests":10,"invariants":14,"metamorphic_tests":5,"solver_used":false,"role_bound_same_context":true,"independent_agents_claimed":false,"source_event_id":20161,"git_raw_source_verified":true,"runtime_modified":false}},"evidence_ref":"https://github.com/cristhianlujan/claude-persona-lf-patch/blob/d9d16a51baa36a7b93bb8f304d36ac87ba81bda5/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M21_RAW_V2.json#git_blob_sha=d99bf47e5c36b41deb0e8af74d6a7b050a75a9f5","forbidden":["PROMOTE_INVARIANT_PARITY_TO_BUSINESS_TRUTH","CLAIM_SOLVER_RESULT","CLAIM_INDEPENDENT_AUTONOMOUS_SESSIONS","SKIP_TRAIN","TOUCH_OTHER_CHECKPOINTS","APPLY_DOMAIN_REPAIR"]}$spec$::jsonb;
 v_ref text:='https://github.com/cristhianlujan/claude-persona-lf-patch/blob/d9d16a51baa36a7b93bb8f304d36ac87ba81bda5/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M21_RAW_V2.json#git_blob_sha=d99bf47e5c36b41deb0e8af74d6a7b050a75a9f5'; v_old text:='chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M21.json#sha256=af542c5af8974415367758c6312e860168b34425b49f42f3d073074ea214cf60';
 v_blob text; v_prior jsonb; v_after jsonb; v_contract jsonb; v_obs jsonb; v_result jsonb; v_assertion jsonb; v_transition jsonb; v_receipt text;
 v_roles int; v_queries int; v_neg int; v_inv int; v_meta int; v_n int; v_msg text; v_ctx text;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION' AND target_code LIKE '%lf_pe10_m21_bc_invariants_governed_close_v1' AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'M21_NOT_TRAIN_EXECUTOR'; END IF;
 IF (SELECT status FROM programacion.engineering_work_items WHERE id=1133)<>'IN_PROGRESS'
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>20
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>12
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M21' AND id=1645 AND status='PENDING' AND evidence_ref=v_old AND assertion_receipt IS NULL AND completed_at IS NULL)<>1
 OR (SELECT count(*) FROM programacion.pe10_method_variants WHERE method_code='PE10_M21' AND base_code='B' AND algorithm_codes=ARRAY['C']::text[])<>1
 THEN RAISE EXCEPTION 'M21_PRESTATE_OR_METHOD_CONTRACT_NOT_QUALIFIED'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND sequence_no<21 AND status='DONE' AND completed_at IS NOT NULL AND assertion_receipt->>'passed'='true' AND assertion_contract_sha256=assertion_receipt->>'contract_sha256')<>20
 THEN RAISE EXCEPTION 'M21_PRIOR_20_RECEIPTS_NOT_QUALIFIED'; END IF;
 SELECT jsonb_agg(jsonb_build_object('checkpoint_code',checkpoint_code,'status',status,'receipt',assertion_receipt_sha256,'completed_at',completed_at) ORDER BY sequence_no) INTO v_prior FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND sequence_no<21;
 v_blob:=encode(extensions.digest(convert_to('blob '||octet_length(convert_to(v_raw,'UTF8'))::text,'UTF8')||decode('00','hex')||convert_to(v_raw,'UTF8'),'sha1'),'hex');
 IF v_blob<>'d99bf47e5c36b41deb0e8af74d6a7b050a75a9f5' THEN RAISE EXCEPTION 'M21_RAW_BLOB_MISMATCH'; END IF;
 v_doc:=v_raw::jsonb;
 IF v_doc->>'method_code'<>'PE10_M21' OR v_doc->>'base_code'<>'B' OR v_doc->'algorithm_codes'<>'["C"]'::jsonb
 OR v_doc#>>'{original_preserved,sha256}'<>'af542c5af8974415367758c6312e860168b34425b49f42f3d073074ea214cf60'
 OR v_doc#>>'{synthesis,source_pieces_frozen_before_synthesis}'<>'true' OR v_doc#>>'{synthesis,no_new_sql_in_synthesis}'<>'true'
 OR v_doc#>>'{synthesis,decision,state}'<>'VERIFY_FIRST' OR v_doc->>'solver_used'<>'false'
 OR v_doc->>'runtime_modified'<>'false' OR v_doc->>'final_method_state'<>'B_C_ROLE_REPORTS_SYNTHESIZED_NO_DOMAIN_REPAIR'
 THEN RAISE EXCEPTION 'M21_C_AUTHENTICITY_FAILED'; END IF;
 SELECT count(*),sum((x->>'query_count')::int),sum((x->>'negative_count')::int),sum((x->>'invariant_count')::int)
 INTO v_roles,v_queries,v_neg,v_inv FROM jsonb_array_elements(v_doc->'role_reports') x WHERE x->>'role_output_frozen'='true';
 v_meta:=jsonb_array_length(v_doc#>'{synthesis,metamorphic_tests}');
 IF v_roles<>5 OR v_queries<>10 OR v_neg<>10 OR v_inv<>14 OR v_meta<>5
 OR v_doc->>'source_queries_total'<>'10' OR v_doc->>'negative_tests_total'<>'10' OR v_doc->>'invariants_total'<>'14' OR v_doc->>'metamorphic_tests_total'<>'5'
 THEN RAISE EXCEPTION 'M21_C_MATERIAL_MANIFEST_FAILED'; END IF;
 IF (SELECT count(*) FROM public.lf_eventos WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z' AND jsonb_array_length(payload->'sql_callers')=38)<>1
 OR (SELECT count(*) FROM transversal.error_knowledge WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001') AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z')<>2
 THEN RAISE EXCEPTION 'M21_P0_SOURCE_DRIFT'; END IF;
 UPDATE programacion.engineering_plan_units SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10_M21}',v_spec,true) WHERE work_item_id=1133 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32';
 GET DIAGNOSTICS v_n=ROW_COUNT; IF v_n<>1 THEN RAISE EXCEPTION 'M21_ACTION_SPEC_UPDATE_FAILED'; END IF;
 v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M21',programacion.fn_engineering_checkpoint_action_spec_v3('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M21'));
 IF v_contract->>'status'<>'READY' OR v_contract->>'mode'<>'EXPLICIT_PASS_WHEN_SUBSET' THEN RAISE EXCEPTION 'M21_CONTRACT_NOT_READY'; END IF;
 v_obs:=jsonb_build_object('checkpoint_identity','PE10_M21','base_code','B','algorithm_C_executed',true,'role_reports_frozen',v_roles,'synthesis_completed',true,'read_only_sql_queries',v_queries,'role_negative_tests',v_neg,'invariants',v_inv,'metamorphic_tests',v_meta,'solver_used',false,'role_bound_same_context',true,'independent_agents_claimed',false,'source_event_id',20161,'git_raw_source_verified',true,'runtime_modified',false);
 v_result:=jsonb_build_object('status','PASS','observed',v_obs,'evidence_ref',v_ref,'validation_kind','M21_B_C_FIVE_ROLE_BOUND_INVARIANT_SYNTHESIS_MATERIAL_ONLY','product_repair_applied',false);
 v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M21',v_result,v_exec);
 IF v_assertion->>'passed'<>'true' THEN RAISE EXCEPTION 'M21_RECEIPT_NOT_PASSED'; END IF; v_receipt:=v_assertion->>'assertion_receipt_sha256';
 v_transition:=programacion.fn_engineering_checkpoint_transition_v1('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M21','DONE',v_ref,v_exec,'M21 B+C invariant/metamorphic evidence verified; no domain repair');
 IF v_transition#>>'{transition,status}'<>'APPLIED' THEN RAISE EXCEPTION 'M21_TRANSITION_FAILED'; END IF;
 SELECT jsonb_agg(jsonb_build_object('checkpoint_code',checkpoint_code,'status',status,'receipt',assertion_receipt_sha256,'completed_at',completed_at) ORDER BY sequence_no) INTO v_after FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND sequence_no<21;
 IF v_after<>v_prior
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M21' AND status='DONE' AND completed_at IS NOT NULL AND evidence_ref=v_ref AND assertion_receipt_sha256=v_receipt AND assertion_receipt->>'passed'='true' AND assertion_contract_sha256=assertion_receipt->>'contract_sha256')<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>21
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>11
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M22' AND status='PENDING')<>1
 THEN RAISE EXCEPTION 'M21_POST_READBACK_FAILED'; END IF;
EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_msg=MESSAGE_TEXT,v_ctx=PG_EXCEPTION_CONTEXT; RAISE EXCEPTION 'M21_TRAIN_ERROR state=% msg=% context=%',SQLSTATE,left(v_msg,290),left(v_ctx,150) USING ERRCODE=SQLSTATE;
END $m21_close$;
