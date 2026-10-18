-- PE10 M22: B+D+C governed evidence closure.
DO $m22$
DECLARE v_exec text;v_raw text:=$raw${
  "schema": "PE10_METHOD_RAW_V2",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M22",
  "base_code": "B",
  "algorithm_codes": [
    "D",
    "C"
  ],
  "method_catalog": "PE10_METHOD_V1",
  "source_cutoff": "2026-10-15T00:00:00Z",
  "original_preserved": {
    "ref": "chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M22.json",
    "sha256": "bbb21bd84ec17a11326d6555e4b1536936ac159493cf1750916fb5365f3a3ad8"
  },
  "role_bound_single_context": true,
  "autonomous_agent_claim": false,
  "cross_method_inputs_used": false,
  "external_evaluation": "NOT_PERFORMED",
  "role_reports": [
    {
      "role": "ARCHITECTURE",
      "git_blob_sha": "270fec1d5b00b261dd10ca32c9b71ce428df6d65",
      "query_count": 2,
      "negative_count": 2,
      "gde_conflict_sets": 2,
      "invariant_count": 2,
      "role_output_frozen": true
    },
    {
      "role": "PERFORMANCE",
      "git_blob_sha": "b9d5c95432d830c1226a07d6f39d40f77d991a3e",
      "query_count": 2,
      "negative_count": 2,
      "gde_conflict_sets": 2,
      "invariant_count": 2,
      "role_output_frozen": true
    },
    {
      "role": "AUTHORITY",
      "git_blob_sha": "551663b884fc13bb1965f7676ef1c02694175324",
      "query_count": 2,
      "negative_count": 2,
      "gde_conflict_sets": 2,
      "invariant_count": 2,
      "role_output_frozen": true
    },
    {
      "role": "COVERAGE",
      "git_blob_sha": "a4336a35d52ed6bb1ec766f9f744bff5518fa3dc",
      "query_count": 2,
      "negative_count": 2,
      "gde_conflict_sets": 2,
      "invariant_count": 2,
      "role_output_frozen": true
    },
    {
      "role": "INNOVATION",
      "git_blob_sha": "26bfdc0d7447e64ebe956ad7bd0c53cff9a008ef",
      "query_count": 2,
      "negative_count": 2,
      "gde_conflict_sets": 2,
      "invariant_count": 2,
      "role_output_frozen": true
    }
  ],
  "synthesis_ref": {
    "path": "docs/profile_updater/experiments/pe10_methods32_p0/M22_SYNTHESIS_V1.json",
    "source_commit": "7d6da71f1b3ab7a2f045d130130801ed034e7ae9",
    "git_blob_sha": "113f091e7a531d4aa0d18a4f22e230b7e6c05fe1"
  },
  "synthesis": {
    "schema": "PE10_M22_SYNTHESIS_V1",
    "case_ref": "PE10-IG-M107-M109-P0",
    "method_code": "PE10_M22",
    "base_code": "B",
    "algorithm_codes": [
      "D",
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
        "git_blob_sha": "270fec1d5b00b261dd10ca32c9b71ce428df6d65",
        "readbacks": 2,
        "negative_tests": 2,
        "conflict_sets": 2,
        "invariants": 2,
        "role_output_frozen": true
      },
      {
        "role": "PERFORMANCE",
        "git_blob_sha": "b9d5c95432d830c1226a07d6f39d40f77d991a3e",
        "readbacks": 2,
        "negative_tests": 2,
        "conflict_sets": 2,
        "invariants": 2,
        "role_output_frozen": true
      },
      {
        "role": "AUTHORITY",
        "git_blob_sha": "551663b884fc13bb1965f7676ef1c02694175324",
        "readbacks": 2,
        "negative_tests": 2,
        "conflict_sets": 2,
        "invariants": 2,
        "role_output_frozen": true
      },
      {
        "role": "COVERAGE",
        "git_blob_sha": "a4336a35d52ed6bb1ec766f9f744bff5518fa3dc",
        "readbacks": 2,
        "negative_tests": 2,
        "conflict_sets": 2,
        "invariants": 2,
        "role_output_frozen": true
      },
      {
        "role": "INNOVATION",
        "git_blob_sha": "26bfdc0d7447e64ebe956ad7bd0c53cff9a008ef",
        "readbacks": 2,
        "negative_tests": 2,
        "conflict_sets": 2,
        "invariants": 2,
        "role_output_frozen": true
      }
    ],
    "readbacks_total": 10,
    "negative_tests_total": 10,
    "gde_conflict_sets_total": 10,
    "invariants_total": 10,
    "barinel": {
      "status": "NOT_CALIBRATED",
      "roles_not_calibrated": 5
    },
    "information_gain_mode": "ORDINAL_DISCRIMINATION_COST",
    "solver_used": false,
    "findings": [
      {
        "id": "M22_SYN_F1",
        "classification": "MEASURED",
        "finding": "Comparator invariant reconciles 38=16 TRUE+22 FALSE+0 absent; GDE keeps hash-recipe and snapshot-freshness alternatives open."
      },
      {
        "id": "M22_SYN_F2",
        "classification": "MEASURED",
        "finding": "Duration partitions reconcile only with NULL/zero/positive separated; function stats are unavailable under track_functions=none."
      },
      {
        "id": "M22_SYN_F3",
        "classification": "MEASURED",
        "finding": "Authority evidence separates EXECUTE denial from SELECT access; 42501 cannot be promoted to functional failure."
      },
      {
        "id": "M22_SYN_F4",
        "classification": "MEASURED",
        "finding": "Historical callers are unique and hashes present, while 6/39 callee names are currently ambiguous and break name-only identity uniqueness."
      },
      {
        "id": "M22_SYN_F5",
        "classification": "MEASURED_CANDIDATE_ONLY",
        "finding": "95 pattern objects partition 31 historical/64 complement; 23 path-shaped complements are priority candidates, not proven callers."
      }
    ],
    "metamorphic_tests": [
      {
        "id": "DC_META1",
        "transform": "repartition comparator",
        "observed": "38=16+22+0",
        "status": "PASS"
      },
      {
        "id": "DC_META2",
        "transform": "separate duration null/zero/positive",
        "observed": "status totals reconcile",
        "status": "PASS"
      },
      {
        "id": "DC_META3",
        "transform": "deny EXECUTE retain SELECT",
        "observed": "evidence path remains",
        "status": "PASS"
      },
      {
        "id": "DC_META4",
        "transform": "name-only callee resolution",
        "observed": "6 ambiguities surface",
        "status": "PASS"
      },
      {
        "id": "DC_META5",
        "transform": "current-pattern membership partition",
        "observed": "95=31+64",
        "status": "PASS"
      }
    ],
    "decision": {
      "state": "VERIFY_FIRST",
      "implemented_repair": false,
      "reason": "D identifies alternatives and next discriminators; C validates boundaries/counterexamples but no single causal domain defect is proven."
    },
    "unresolved": [
      "canonical historical hash method",
      "runtime materiality of changed definitions",
      "zero-duration semantics",
      "six qualified callee identities",
      "actual caller role of path-shaped candidates"
    ],
    "constraints_preserved": [
      "READ_ONLY",
      "no production repair",
      "P0/current separation",
      "five reports frozen before synthesis",
      "no cross-method inputs",
      "no autonomous-agent claim"
    ],
    "non_isolation_risk": "Five role-bound passes ran sequentially in one shared model context; artifacts froze before synthesis, but autonomous cognitive independence is not claimed.",
    "final_method_status": "B_D_C_FIVE_ROLE_REPORTS_SYNTHESIZED_MATERIAL_ONLY_NOT_YET_GOVERNED_DONE"
  },
  "source_queries_total": 10,
  "negative_tests_total": 10,
  "gde_conflict_sets_total": 10,
  "invariants_total": 10,
  "metamorphic_tests_total": 5,
  "barinel_calibrated": false,
  "information_gain_mode": "ORDINAL_DISCRIMINATION_COST",
  "solver_used": false,
  "final_method_state": "B_D_C_ROLE_REPORTS_SYNTHESIZED_NO_DOMAIN_REPAIR",
  "causal_defect_proven": false,
  "solution_state": "VERIFY_FIRST",
  "runtime_modified": false,
  "independence_constraint": {
    "frozen_before_synthesis": true,
    "report_results_from_one_model_context": true,
    "independent_agents": false
  }
}
$raw$;v_doc jsonb;v_spec jsonb:=$spec${"status":"READY","action_kind":"VERIFY_QUERY_ONCE","recipe_mode":"READBACK_EXACT","requires_material_execution":true,"contract_family":"PE10_METHOD_EXECUTION_EVIDENCE","precision":"PE10_METHOD_V1_MATERIAL_EVIDENCE","assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"checkpoint_identity":"PE10_M22","base_code":"B","algorithm_D_executed":true,"algorithm_C_executed":true,"role_reports_frozen":5,"synthesis_completed":true,"read_only_sql_queries":10,"role_negative_tests":10,"gde_conflict_sets":10,"invariants":10,"metamorphic_tests":5,"barinel_calibrated":false,"solver_used":false,"role_bound_same_context":true,"independent_agents_claimed":false,"git_raw_source_verified":true,"runtime_modified":false}},"evidence_ref":"https://github.com/cristhianlujan/claude-persona-lf-patch/blob/98a2b2ad018b2b21319e6c04102c02a1621c2ba2/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M22_RAW_V2.json#git_blob_sha=9fd094456701b1935e90fb26b61a1ffe877312ee"}$spec$::jsonb;v_ref text:='https://github.com/cristhianlujan/claude-persona-lf-patch/blob/98a2b2ad018b2b21319e6c04102c02a1621c2ba2/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M22_RAW_V2.json#git_blob_sha=9fd094456701b1935e90fb26b61a1ffe877312ee';v_old text:='chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M22.json#sha256=bbb21bd84ec17a11326d6555e4b1536936ac159493cf1750916fb5365f3a3ad8';v_blob text;v_prior jsonb;v_after jsonb;v_contract jsonb;v_obs jsonb;v_result jsonb;v_assertion jsonb;v_transition jsonb;v_receipt text;v_roles int;v_q int;v_neg int;v_gde int;v_inv int;v_meta int;v_n int;v_msg text;v_ctx text;
BEGIN
SELECT execution_id INTO v_exec FROM public.lf_operation_execution WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION' AND target_code LIKE '%lf_pe10_m22_bdc_governed_close_v1' AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
IF v_exec IS NULL THEN RAISE EXCEPTION 'M22_NOT_TRAIN_EXECUTOR';END IF;
IF (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>21 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>11 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M22' AND id=1646 AND status='PENDING' AND evidence_ref=v_old AND assertion_receipt IS NULL)<>1 OR (SELECT count(*) FROM programacion.pe10_method_variants WHERE method_code='PE10_M22' AND base_code='B' AND algorithm_codes=ARRAY['D','C']::text[])<>1 THEN RAISE EXCEPTION 'M22_PRESTATE_FAILED';END IF;
IF (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND sequence_no<22 AND status='DONE' AND assertion_receipt->>'passed'='true' AND assertion_contract_sha256=assertion_receipt->>'contract_sha256')<>21 THEN RAISE EXCEPTION 'M22_PRIOR_RECEIPTS_FAILED';END IF;
SELECT jsonb_agg(jsonb_build_object('c',checkpoint_code,'s',status,'r',assertion_receipt_sha256,'d',completed_at) ORDER BY sequence_no) INTO v_prior FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND sequence_no<22;
v_blob:=encode(extensions.digest(convert_to('blob '||octet_length(convert_to(v_raw,'UTF8'))::text,'UTF8')||decode('00','hex')||convert_to(v_raw,'UTF8'),'sha1'),'hex');IF v_blob<>'9fd094456701b1935e90fb26b61a1ffe877312ee' THEN RAISE EXCEPTION 'M22_BLOB_FAILED';END IF;
v_doc:=v_raw::jsonb;
IF v_doc->>'method_code'<>'PE10_M22' OR v_doc->'algorithm_codes'<>'["D","C"]'::jsonb OR v_doc#>>'{original_preserved,sha256}'<>'bbb21bd84ec17a11326d6555e4b1536936ac159493cf1750916fb5365f3a3ad8' OR v_doc#>>'{synthesis,source_pieces_frozen_before_synthesis}'<>'true' OR v_doc#>>'{synthesis,barinel,status}'<>'NOT_CALIBRATED' OR v_doc#>>'{synthesis,decision,state}'<>'VERIFY_FIRST' OR v_doc->>'runtime_modified'<>'false' THEN RAISE EXCEPTION 'M22_AUTHENTICITY_FAILED';END IF;
SELECT count(*),sum((x->>'query_count')::int),sum((x->>'negative_count')::int),sum((x->>'gde_conflict_sets')::int),sum((x->>'invariant_count')::int) INTO v_roles,v_q,v_neg,v_gde,v_inv FROM jsonb_array_elements(v_doc->'role_reports') x WHERE x->>'role_output_frozen'='true';v_meta:=jsonb_array_length(v_doc#>'{synthesis,metamorphic_tests}');
IF v_roles<>5 OR v_q<>10 OR v_neg<>10 OR v_gde<>10 OR v_inv<>10 OR v_meta<>5 THEN RAISE EXCEPTION 'M22_MANIFEST_FAILED';END IF;
UPDATE programacion.engineering_plan_units SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10_M22}',v_spec,true) WHERE work_item_id=1133 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32';GET DIAGNOSTICS v_n=ROW_COUNT;IF v_n<>1 THEN RAISE EXCEPTION 'M22_SPEC_FAILED';END IF;
v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M22',programacion.fn_engineering_checkpoint_action_spec_v3('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M22'));IF v_contract->>'status'<>'READY' OR v_contract->>'mode'<>'EXPLICIT_PASS_WHEN_SUBSET' THEN RAISE EXCEPTION 'M22_CONTRACT_FAILED';END IF;
v_obs:=jsonb_build_object('checkpoint_identity','PE10_M22','base_code','B','algorithm_D_executed',true,'algorithm_C_executed',true,'role_reports_frozen',v_roles,'synthesis_completed',true,'read_only_sql_queries',v_q,'role_negative_tests',v_neg,'gde_conflict_sets',v_gde,'invariants',v_inv,'metamorphic_tests',v_meta,'barinel_calibrated',false,'solver_used',false,'role_bound_same_context',true,'independent_agents_claimed',false,'git_raw_source_verified',true,'runtime_modified',false);
v_result:=jsonb_build_object('status','PASS','observed',v_obs,'evidence_ref',v_ref,'validation_kind','M22_B_DC_ROLE_SYNTHESIS_MATERIAL_ONLY','product_repair_applied',false);
v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M22',v_result,v_exec);IF v_assertion->>'passed'<>'true' THEN RAISE EXCEPTION 'M22_RECEIPT_FAILED';END IF;v_receipt:=v_assertion->>'assertion_receipt_sha256';
v_transition:=programacion.fn_engineering_checkpoint_transition_v1('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M22','DONE',v_ref,v_exec,'M22 B+D+C GDE/invariant evidence verified; no domain repair');IF v_transition#>>'{transition,status}'<>'APPLIED' THEN RAISE EXCEPTION 'M22_TRANSITION_FAILED';END IF;
SELECT jsonb_agg(jsonb_build_object('c',checkpoint_code,'s',status,'r',assertion_receipt_sha256,'d',completed_at) ORDER BY sequence_no) INTO v_after FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND sequence_no<22;
IF v_after<>v_prior OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M22' AND status='DONE' AND completed_at IS NOT NULL AND evidence_ref=v_ref AND assertion_receipt_sha256=v_receipt AND assertion_receipt->>'passed'='true' AND assertion_contract_sha256=assertion_receipt->>'contract_sha256')<>1 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>22 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>10 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M23' AND status='PENDING')<>1 THEN RAISE EXCEPTION 'M22_POST_FAILED';END IF;
EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_msg=MESSAGE_TEXT,v_ctx=PG_EXCEPTION_CONTEXT;RAISE EXCEPTION 'M22_TRAIN_ERROR state=% msg=% context=%',SQLSTATE,left(v_msg,290),left(v_ctx,150) USING ERRCODE=SQLSTATE;END $m22$;