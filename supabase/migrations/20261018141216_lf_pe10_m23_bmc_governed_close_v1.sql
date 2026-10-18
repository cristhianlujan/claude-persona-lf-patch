-- PE10 M23: B+M+C governed evidence closure.
DO $m23$
DECLARE v_exec text;v_raw text:=$raw${
  "schema": "PE10_METHOD_RAW_V2",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M23",
  "base_code": "B",
  "algorithm_codes": [
    "M",
    "C"
  ],
  "method_catalog": "PE10_METHOD_V1",
  "source_cutoff": "2026-10-15T00:00:00Z",
  "original_preserved": {
    "ref": "chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M23.json",
    "sha256": "bcdc0f50dec580977aeae18ffd3d89a340d57c766fe0059d790e2b62beeae461"
  },
  "role_bound_single_context": true,
  "autonomous_agent_claim": false,
  "cross_method_inputs_used": false,
  "external_evaluation": "NOT_PERFORMED",
  "producer": "B+M+C: five role-bound ATMS plus invariant/metamorphic investigations frozen before synthesis in one coordinated context.",
  "role_reports": [
    {
      "role": "ARCHITECTURE",
      "git_blob_sha": "0155ac7a509f4b4b539af6418e18d930b83754e8",
      "query_count": 2,
      "negative_count": 2,
      "atms_nogoods": 2,
      "invariant_count": 2,
      "role_output_frozen": true
    },
    {
      "role": "PERFORMANCE",
      "git_blob_sha": "4bef43d422ef17278ec00c3bad584204a7a33030",
      "query_count": 2,
      "negative_count": 2,
      "atms_nogoods": 2,
      "invariant_count": 2,
      "role_output_frozen": true
    },
    {
      "role": "AUTHORITY",
      "git_blob_sha": "47052707e66bc0a5ec1ce4e3aea2316292e7bb3a",
      "query_count": 2,
      "negative_count": 2,
      "atms_nogoods": 2,
      "invariant_count": 2,
      "role_output_frozen": true
    },
    {
      "role": "COVERAGE",
      "git_blob_sha": "a079506fdec66638d916e86e854a423495923589",
      "query_count": 2,
      "negative_count": 2,
      "atms_nogoods": 2,
      "invariant_count": 2,
      "role_output_frozen": true
    },
    {
      "role": "INNOVATION",
      "git_blob_sha": "b6d2cce9e6742761d962a9a8ef1251bf0a7618b6",
      "query_count": 2,
      "negative_count": 2,
      "atms_nogoods": 2,
      "invariant_count": 2,
      "role_output_frozen": true
    }
  ],
  "synthesis_ref": {
    "path": "docs/profile_updater/experiments/pe10_methods32_p0/M23_SYNTHESIS_V1.json",
    "source_commit": "5ffcdff72599bb54050fd0dd72cc4008003c29af",
    "git_blob_sha": "4bb4aae4917f8709c3b1870aa3ebcefc62485c70"
  },
  "synthesis": {
    "schema": "PE10_M23_SYNTHESIS_V1",
    "case_ref": "PE10-IG-M107-M109-P0",
    "method_code": "PE10_M23",
    "base_code": "B",
    "algorithm_codes": [
      "M",
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
        "git_blob_sha": "0155ac7a509f4b4b539af6418e18d930b83754e8",
        "readbacks": 2,
        "negative_tests": 2,
        "atms_nogoods": 2,
        "invariants": 2,
        "role_output_frozen": true
      },
      {
        "role": "PERFORMANCE",
        "git_blob_sha": "4bef43d422ef17278ec00c3bad584204a7a33030",
        "readbacks": 2,
        "negative_tests": 2,
        "atms_nogoods": 2,
        "invariants": 2,
        "role_output_frozen": true
      },
      {
        "role": "AUTHORITY",
        "git_blob_sha": "47052707e66bc0a5ec1ce4e3aea2316292e7bb3a",
        "readbacks": 2,
        "negative_tests": 2,
        "atms_nogoods": 2,
        "invariants": 2,
        "role_output_frozen": true
      },
      {
        "role": "COVERAGE",
        "git_blob_sha": "a079506fdec66638d916e86e854a423495923589",
        "readbacks": 2,
        "negative_tests": 2,
        "atms_nogoods": 2,
        "invariants": 2,
        "role_output_frozen": true
      },
      {
        "role": "INNOVATION",
        "git_blob_sha": "b6d2cce9e6742761d962a9a8ef1251bf0a7618b6",
        "readbacks": 2,
        "negative_tests": 2,
        "atms_nogoods": 2,
        "invariants": 2,
        "role_output_frozen": true
      }
    ],
    "readbacks_total": 10,
    "negative_tests_total": 10,
    "atms_nogoods_total": 10,
    "invariants_total": 10,
    "atms_propagation_tests": 5,
    "metamorphic_tests_total": 5,
    "solver_used": false,
    "atms_cross_role": {
      "evidence_identity_preserved": true,
      "propagation_tests": [
        {
          "withdraw": "ARQ current comparator",
          "invalidates": [
            "current definition drift"
          ],
          "preserves": [
            "P0 snapshot scope"
          ]
        },
        {
          "withdraw": "performance runs",
          "invalidates": [
            "duration partitions"
          ],
          "preserves": [
            "SOAK quality receipt"
          ]
        },
        {
          "withdraw": "current privileges",
          "invalidates": [
            "current authority boundary"
          ],
          "preserves": [
            "historical EKB authority evidence"
          ]
        },
        {
          "withdraw": "current callee resolution",
          "invalidates": [
            "current callee ambiguity"
          ],
          "preserves": [
            "historical caller integrity"
          ]
        },
        {
          "withdraw": "current complement discovery",
          "invalidates": [
            "complement candidates"
          ],
          "preserves": [
            "evidence chronology"
          ]
        }
      ]
    },
    "findings": [
      {
        "id": "M23_SYN_F1",
        "classification": "MEASURED",
        "finding": "Historical/current comparator reconciles 38=16 empirical equal+22 changed+0 absent; P0 remains as-of evidence, not live certification."
      },
      {
        "id": "M23_SYN_F2",
        "classification": "MEASURED",
        "finding": "Performance evidence partitions NULL/zero/positive independently; receipt38 verifies SOAK quality, not latency."
      },
      {
        "id": "M23_SYN_F3",
        "classification": "MEASURED",
        "finding": "Authority evidence keeps EXECUTE denial separate from SELECT access; permission failure is not functional-failure proof."
      },
      {
        "id": "M23_SYN_F4",
        "classification": "MEASURED_RISK",
        "finding": "Historical callers are unique with hashes present, but 6/39 callee tokens are currently ambiguous by name."
      },
      {
        "id": "M23_SYN_F5",
        "classification": "MEASURED_CANDIDATE_ONLY",
        "finding": "Current pattern set partitions 95=31 historical+64 complement; 23 path-shaped candidates require reference/lifecycle proof."
      }
    ],
    "metamorphic_tests": [
      {
        "id": "MC_META1",
        "transform": "withdraw current comparator evidence",
        "expected": "P0 scope remains while current-drift claim disappears",
        "status": "PASS"
      },
      {
        "id": "MC_META2",
        "transform": "separate NULL/zero/positive durations",
        "expected": "status totals reconcile",
        "status": "PASS"
      },
      {
        "id": "MC_META3",
        "transform": "deny EXECUTE while retaining SELECT",
        "expected": "evidence read path remains",
        "status": "PASS"
      },
      {
        "id": "MC_META4",
        "transform": "resolve callee tokens by name only",
        "expected": "ambiguities surface instead of forced uniqueness",
        "status": "PASS"
      },
      {
        "id": "MC_META5",
        "transform": "partition current pattern by historical membership",
        "expected": "95=31+64",
        "status": "PASS"
      }
    ],
    "contradictions": [
      {
        "topic": "historical integrity vs current drift",
        "resolution": "distinct evidence identities/times"
      },
      {
        "topic": "SOAK VERIFIED vs performance unresolved",
        "resolution": "different dependent claims"
      },
      {
        "topic": "EXECUTE denied vs SELECT allowed",
        "resolution": "distinct capabilities"
      },
      {
        "topic": "0 unresolved callee names vs 6 ambiguous",
        "resolution": "existence is not uniqueness"
      },
      {
        "topic": "later evidence vs P0",
        "resolution": "chronology preserved; no temporal rewriting"
      }
    ],
    "decision": {
      "state": "VERIFY_FIRST",
      "implemented_repair": false,
      "reason": "M+C establishes assumption dependencies and invariants/counterexamples, but no single causal domain defect or safe repair is proven."
    },
    "unresolved": [
      "canonical historical definition_md5 method",
      "zero-duration semantics",
      "matched performance effect",
      "qualified identity of six callees",
      "actual caller role of complement candidates"
    ],
    "constraints_preserved": [
      "READ_ONLY",
      "no production/runtime edits",
      "P0/current separation",
      "five reports frozen before synthesis",
      "no cross-method inputs",
      "no autonomous-agent claim"
    ],
    "non_isolation_risk": "Five role-bound passes ran sequentially in one shared model context; each artifact was frozen before synthesis, but autonomous cognitive independence is not demonstrated.",
    "final_method_status": "B_M_C_FIVE_ROLE_REPORTS_SYNTHESIZED_MATERIAL_ONLY_NOT_YET_GOVERNED_DONE"
  },
  "source_queries_total": 10,
  "negative_tests_total": 10,
  "atms_nogoods_total": 10,
  "invariants_total": 10,
  "atms_propagation_tests": 5,
  "metamorphic_tests_total": 5,
  "solver_used": false,
  "final_method_state": "B_M_C_ROLE_REPORTS_SYNTHESIZED_NO_DOMAIN_REPAIR",
  "causal_defect_proven": false,
  "solution_state": "VERIFY_FIRST",
  "runtime_modified": false,
  "independence_constraint": {
    "frozen_before_synthesis": true,
    "report_results_from_one_model_context": true,
    "independent_agents": false
  }
}
$raw$;v_doc jsonb;v_spec jsonb:=$spec${"status":"READY","action_kind":"VERIFY_QUERY_ONCE","recipe_mode":"READBACK_EXACT","requires_material_execution":true,"contract_family":"PE10_METHOD_EXECUTION_EVIDENCE","precision":"PE10_METHOD_V1_MATERIAL_EVIDENCE","assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"checkpoint_identity":"PE10_M23","base_code":"B","algorithm_M_executed":true,"algorithm_C_executed":true,"role_reports_frozen":5,"synthesis_completed":true,"read_only_sql_queries":10,"role_negative_tests":10,"atms_nogoods":10,"invariants":10,"atms_propagation_tests":5,"metamorphic_tests":5,"solver_used":false,"role_bound_same_context":true,"independent_agents_claimed":false,"git_raw_source_verified":true,"runtime_modified":false}},"evidence_ref":"https://github.com/cristhianlujan/claude-persona-lf-patch/blob/b74acf17143caab664769c045d698cb7f053ada9/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M23_RAW_V2.json#git_blob_sha=aa3bd83a8b98c26c7ab29c14f5c8ddd155bb3531"}$spec$::jsonb;v_ref text:='https://github.com/cristhianlujan/claude-persona-lf-patch/blob/b74acf17143caab664769c045d698cb7f053ada9/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M23_RAW_V2.json#git_blob_sha=aa3bd83a8b98c26c7ab29c14f5c8ddd155bb3531';v_old text:='chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M23.json#sha256=bcdc0f50dec580977aeae18ffd3d89a340d57c766fe0059d790e2b62beeae461';v_blob text;v_prior jsonb;v_after jsonb;v_contract jsonb;v_obs jsonb;v_result jsonb;v_assertion jsonb;v_transition jsonb;v_receipt text;v_roles int;v_q int;v_neg int;v_ng int;v_inv int;v_prop int;v_meta int;v_n int;v_msg text;v_ctx text;
BEGIN
SELECT execution_id INTO v_exec FROM public.lf_operation_execution WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION' AND target_code LIKE '%lf_pe10_m23_bmc_governed_close_v1' AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
IF v_exec IS NULL THEN RAISE EXCEPTION 'M23_NOT_TRAIN_EXECUTOR';END IF;
IF (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>22 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>10 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M23' AND id=1647 AND status='PENDING' AND evidence_ref=v_old AND assertion_receipt IS NULL)<>1 OR (SELECT count(*) FROM programacion.pe10_method_variants WHERE method_code='PE10_M23' AND base_code='B' AND algorithm_codes=ARRAY['M','C']::text[])<>1 THEN RAISE EXCEPTION 'M23_PRESTATE_FAILED';END IF;
IF (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND sequence_no<23 AND status='DONE' AND assertion_receipt->>'passed'='true' AND assertion_contract_sha256=assertion_receipt->>'contract_sha256')<>22 THEN RAISE EXCEPTION 'M23_PRIOR_RECEIPTS_FAILED';END IF;
SELECT jsonb_agg(jsonb_build_object('c',checkpoint_code,'s',status,'r',assertion_receipt_sha256,'d',completed_at) ORDER BY sequence_no) INTO v_prior FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND sequence_no<23;
v_blob:=encode(extensions.digest(convert_to('blob '||octet_length(convert_to(v_raw,'UTF8'))::text,'UTF8')||decode('00','hex')||convert_to(v_raw,'UTF8'),'sha1'),'hex');IF v_blob<>'aa3bd83a8b98c26c7ab29c14f5c8ddd155bb3531' THEN RAISE EXCEPTION 'M23_BLOB_FAILED';END IF;
v_doc:=v_raw::jsonb;
IF v_doc->>'method_code'<>'PE10_M23' OR v_doc->'algorithm_codes'<>'["M","C"]'::jsonb OR v_doc#>>'{original_preserved,sha256}'<>'bcdc0f50dec580977aeae18ffd3d89a340d57c766fe0059d790e2b62beeae461' OR v_doc#>>'{synthesis,source_pieces_frozen_before_synthesis}'<>'true' OR v_doc#>>'{synthesis,decision,state}'<>'VERIFY_FIRST' OR v_doc->>'solver_used'<>'false' OR v_doc->>'runtime_modified'<>'false' THEN RAISE EXCEPTION 'M23_AUTHENTICITY_FAILED';END IF;
SELECT count(*),sum((x->>'query_count')::int),sum((x->>'negative_count')::int),sum((x->>'atms_nogoods')::int),sum((x->>'invariant_count')::int) INTO v_roles,v_q,v_neg,v_ng,v_inv FROM jsonb_array_elements(v_doc->'role_reports') x WHERE x->>'role_output_frozen'='true';
v_prop:=jsonb_array_length(v_doc#>'{synthesis,atms_cross_role,propagation_tests}');v_meta:=jsonb_array_length(v_doc#>'{synthesis,metamorphic_tests}');
IF v_roles<>5 OR v_q<>10 OR v_neg<>10 OR v_ng<>10 OR v_inv<>10 OR v_prop<>5 OR v_meta<>5 THEN RAISE EXCEPTION 'M23_MANIFEST_FAILED';END IF;
UPDATE programacion.engineering_plan_units SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10_M23}',v_spec,true) WHERE work_item_id=1133 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32';GET DIAGNOSTICS v_n=ROW_COUNT;IF v_n<>1 THEN RAISE EXCEPTION 'M23_SPEC_FAILED';END IF;
v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M23',programacion.fn_engineering_checkpoint_action_spec_v3('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M23'));IF v_contract->>'status'<>'READY' OR v_contract->>'mode'<>'EXPLICIT_PASS_WHEN_SUBSET' THEN RAISE EXCEPTION 'M23_CONTRACT_FAILED';END IF;
v_obs:=jsonb_build_object('checkpoint_identity','PE10_M23','base_code','B','algorithm_M_executed',true,'algorithm_C_executed',true,'role_reports_frozen',v_roles,'synthesis_completed',true,'read_only_sql_queries',v_q,'role_negative_tests',v_neg,'atms_nogoods',v_ng,'invariants',v_inv,'atms_propagation_tests',v_prop,'metamorphic_tests',v_meta,'solver_used',false,'role_bound_same_context',true,'independent_agents_claimed',false,'git_raw_source_verified',true,'runtime_modified',false);
v_result:=jsonb_build_object('status','PASS','observed',v_obs,'evidence_ref',v_ref,'validation_kind','M23_B_MC_ROLE_SYNTHESIS_MATERIAL_ONLY','product_repair_applied',false);
v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M23',v_result,v_exec);IF v_assertion->>'passed'<>'true' THEN RAISE EXCEPTION 'M23_RECEIPT_FAILED';END IF;v_receipt:=v_assertion->>'assertion_receipt_sha256';
v_transition:=programacion.fn_engineering_checkpoint_transition_v1('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M23','DONE',v_ref,v_exec,'M23 B+M+C ATMS/invariant evidence verified; no domain repair');IF v_transition#>>'{transition,status}'<>'APPLIED' THEN RAISE EXCEPTION 'M23_TRANSITION_FAILED';END IF;
SELECT jsonb_agg(jsonb_build_object('c',checkpoint_code,'s',status,'r',assertion_receipt_sha256,'d',completed_at) ORDER BY sequence_no) INTO v_after FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND sequence_no<23;
IF v_after<>v_prior OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M23' AND status='DONE' AND completed_at IS NOT NULL AND evidence_ref=v_ref AND assertion_receipt_sha256=v_receipt AND assertion_receipt->>'passed'='true' AND assertion_contract_sha256=assertion_receipt->>'contract_sha256')<>1 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>23 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>9 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M24' AND status='PENDING')<>1 THEN RAISE EXCEPTION 'M23_POST_FAILED';END IF;
EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_msg=MESSAGE_TEXT,v_ctx=PG_EXCEPTION_CONTEXT;RAISE EXCEPTION 'M23_TRAIN_ERROR state=% msg=% context=%',SQLSTATE,left(v_msg,290),left(v_ctx,150) USING ERRCODE=SQLSTATE;END $m23$;