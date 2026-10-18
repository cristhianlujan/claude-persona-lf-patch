-- PE10 M20: base B + D+M; governed evidence closure only.
DO $m20_close$
DECLARE
 v_exec text; v_raw text:=$m20_raw${
  "schema": "PE10_METHOD_RAW_V2",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M20",
  "base_code": "B",
  "algorithm_codes": [
    "D",
    "M"
  ],
  "method_catalog": "PE10_METHOD_V1",
  "source_cutoff": "2026-10-15T00:00:00Z",
  "original_preserved": {
    "ref": "chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M20.json",
    "sha256": "5fdb1e282b3ff7e425b29c89440ac3ee5bffaa390930e0202775e1c77918cc63"
  },
  "role_bound_single_context": true,
  "autonomous_agent_claim": false,
  "cross_method_inputs_used": false,
  "external_evaluation": "NOT_PERFORMED",
  "producer": "B+D+M: five role-bound research passes executing GDE/BARINEL/information-gain constraints plus ATMS assumptions/evidence; frozen before synthesis in one coordinated context.",
  "role_reports": [
    {
      "role": "ARCHITECTURE",
      "git_blob_sha": "55f2770cdf9289e83e0a24ea214bdddf086ad020",
      "query_count": 2,
      "negative_count": 2,
      "gde_conflict_sets": 2,
      "atms_nogoods": 2,
      "role_output_frozen": true
    },
    {
      "role": "PERFORMANCE",
      "git_blob_sha": "22f5e3453ca9f7277c71d903670efbf0933945c1",
      "query_count": 2,
      "negative_count": 2,
      "gde_conflict_sets": 2,
      "atms_nogoods": 2,
      "role_output_frozen": true
    },
    {
      "role": "AUTHORITY",
      "git_blob_sha": "3b314ea00e1753bbdb0231e984e6c7123ed93a66",
      "query_count": 2,
      "negative_count": 2,
      "gde_conflict_sets": 2,
      "atms_nogoods": 2,
      "role_output_frozen": true
    },
    {
      "role": "COVERAGE",
      "git_blob_sha": "0a0039999e951bb60921d4acae8a1c65819df611",
      "query_count": 2,
      "negative_count": 2,
      "gde_conflict_sets": 2,
      "atms_nogoods": 2,
      "role_output_frozen": true
    },
    {
      "role": "INNOVATION",
      "git_blob_sha": "2f1cd81eea23e2f6a0106c92a6ae2ee649dcc217",
      "query_count": 2,
      "negative_count": 2,
      "gde_conflict_sets": 2,
      "atms_nogoods": 2,
      "role_output_frozen": true
    }
  ],
  "synthesis_ref": {
    "path": "docs/profile_updater/experiments/pe10_methods32_p0/M20_SYNTHESIS_V1.json",
    "source_commit": "3caae51cc002b98ba5e68e15b85a18fad0c84663",
    "git_blob_sha": "e7e57974678097a640303d74514e45df1a295a97"
  },
  "synthesis": {
    "schema": "PE10_M20_SYNTHESIS_V1",
    "case_ref": "PE10-IG-M107-M109-P0",
    "method_code": "PE10_M20",
    "base_code": "B",
    "algorithm_codes": [
      "D",
      "M"
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
        "path": "docs/profile_updater/experiments/pe10_methods32_p0/M20_roles/ARCHITECTURE_RAW_V1.json",
        "git_blob_sha": "55f2770cdf9289e83e0a24ea214bdddf086ad020",
        "readbacks": 2,
        "negative_tests": 2,
        "conflict_sets": 2,
        "atms_nogoods": 2,
        "role_output_frozen": true
      },
      {
        "role": "PERFORMANCE",
        "path": "docs/profile_updater/experiments/pe10_methods32_p0/M20_roles/PERFORMANCE_RAW_V1.json",
        "git_blob_sha": "22f5e3453ca9f7277c71d903670efbf0933945c1",
        "readbacks": 2,
        "negative_tests": 2,
        "conflict_sets": 2,
        "atms_nogoods": 2,
        "role_output_frozen": true
      },
      {
        "role": "AUTHORITY",
        "path": "docs/profile_updater/experiments/pe10_methods32_p0/M20_roles/AUTHORITY_RAW_V1.json",
        "git_blob_sha": "3b314ea00e1753bbdb0231e984e6c7123ed93a66",
        "readbacks": 2,
        "negative_tests": 2,
        "conflict_sets": 2,
        "atms_nogoods": 2,
        "role_output_frozen": true
      },
      {
        "role": "COVERAGE",
        "path": "docs/profile_updater/experiments/pe10_methods32_p0/M20_roles/COVERAGE_RAW_V1.json",
        "git_blob_sha": "0a0039999e951bb60921d4acae8a1c65819df611",
        "readbacks": 2,
        "negative_tests": 2,
        "conflict_sets": 2,
        "atms_nogoods": 2,
        "role_output_frozen": true
      },
      {
        "role": "INNOVATION",
        "path": "docs/profile_updater/experiments/pe10_methods32_p0/M20_roles/INNOVATION_RAW_V1.json",
        "git_blob_sha": "2f1cd81eea23e2f6a0106c92a6ae2ee649dcc217",
        "readbacks": 2,
        "negative_tests": 2,
        "conflict_sets": 2,
        "atms_nogoods": 2,
        "role_output_frozen": true
      }
    ],
    "readbacks_total": 10,
    "negative_tests_total": 10,
    "gde_conflict_sets_total": 10,
    "atms_nogoods_total": 10,
    "barinel": {
      "status": "NOT_CALIBRATED",
      "roles_not_calibrated": 5,
      "reason": "No role had a justified pass/fail component spectrum with priors; numeric BARINEL probabilities would be fabricated."
    },
    "information_gain_mode": "ORDINAL_DISCRIMINATION_COST",
    "atms_cross_role": {
      "evidence_identity_preserved": true,
      "propagation_tests": [
        {
          "withdraw": "architecture-current-readback",
          "invalidates": [
            "current-definition-drift"
          ],
          "preserves": [
            "historical-snapshot-scope"
          ]
        },
        {
          "withdraw": "performance-runs",
          "invalidates": [
            "revision-timing-variation"
          ],
          "preserves": [
            "stats-unavailable-under-track_functions-none"
          ]
        },
        {
          "withdraw": "authority-current-privileges",
          "invalidates": [
            "current-privilege-boundary"
          ],
          "preserves": [
            "historical-EKB-42501-observation"
          ]
        },
        {
          "withdraw": "coverage-current-resolution",
          "invalidates": [
            "callee-ambiguity-current"
          ],
          "preserves": [
            "historical-inventory-integrity"
          ]
        },
        {
          "withdraw": "innovation-current-complement",
          "invalidates": [
            "complement-candidate-signal"
          ],
          "preserves": [
            "temporal-layering"
          ]
        }
      ]
    },
    "findings": [
      {
        "id": "M20_SYN_F1",
        "classification": "MEASURED",
        "finding": "Historical P0 remains internally scoped but not live-certified: 22/38 caller definitions differ by empirical current md5(prosrc), while no current caller name is absent."
      },
      {
        "id": "M20_SYN_F2",
        "classification": "MEASURED_PERFORMANCE_LIMIT",
        "finding": "track_functions=none prevents function-stat inference; 5.13.1 positive stage medians are larger than 5.13 but cohort/zero semantics block causal regression or improvement claims."
      },
      {
        "id": "M20_SYN_F3",
        "classification": "MEASURED_AUTHORITY",
        "finding": "42501 remains an authority/readback-path condition; SELECT evidence is available while EXECUTE is denied."
      },
      {
        "id": "M20_SYN_F4",
        "classification": "MEASURED_COVERAGE_RISK",
        "finding": "Historical 38/76 inventory is internally reconciled, but 6/39 callee tokens are currently ambiguous by name and require schema identity."
      },
      {
        "id": "M20_SYN_F5",
        "classification": "MEASURED_CANDIDATE_ONLY",
        "finding": "64 current complement names including 23 path-shaped candidates are discovery signals, not proven callers or omissions."
      },
      {
        "id": "M20_SYN_F6",
        "classification": "METHOD_RESULT",
        "finding": "GDE narrows alternatives to temporal equivalence, post-snapshot definition/path evolution, identity qualification, authority path and cohort equivalence; ATMS prevents unsupported evidence substitution and propagates withdrawals."
      }
    ],
    "contradictions": [
      {
        "topic": "historical integrity vs current drift",
        "resolution": "different evidence time and claim scope; both supported"
      },
      {
        "topic": "larger 5.13.1 timings vs causal regression",
        "resolution": "direction measured, cause unresolved"
      },
      {
        "topic": "42501 vs readable tables",
        "resolution": "EXECUTE denial and SELECT access are different privileges"
      },
      {
        "topic": "39 callee tokens vs six ambiguous current names",
        "resolution": "historical token identity lacks sufficient current schema qualification"
      }
    ],
    "causal_model": {
      "proven_root_cause": false,
      "supported_risk_families": [
        "snapshot currentness promotion",
        "post-snapshot definition/path evolution",
        "callee identity ambiguity",
        "wrong authority readback path",
        "performance cohort mismatch"
      ],
      "not_proven": [
        "single Curator defect",
        "single Validator defect",
        "causal 5.13.1 regression",
        "64 caller omissions",
        "canonical historical hash recipe"
      ]
    },
    "decision": {
      "state": "VERIFY_FIRST",
      "implemented_repair": false,
      "reason": "D+M identifies discriminating risks and assumption dependencies but no single causal defect or safe product repair is proven."
    },
    "next_safe_step": "Qualify changed call paths and ambiguous callees, classify path-shaped complement candidates, and build matched performance/authorized CP2 evidence before repair.",
    "unresolved": [
      "canonical historical hash recipe",
      "runtime materiality of changed definitions",
      "zero-duration semantics",
      "matched performance effect",
      "current complement caller classification"
    ],
    "constraints_preserved": [
      "READ_ONLY",
      "no production/runtime edits",
      "P0/current separation",
      "five reports frozen before synthesis",
      "no cross-method inputs",
      "no autonomous-agent claim"
    ],
    "non_isolation_risk": "Five role-bound passes ran sequentially in one shared model context. Artifacts were frozen before synthesis and no peer report was consumed before freeze; autonomous cognitive independence is not demonstrated.",
    "final_method_status": "B_D_M_FIVE_ROLE_REPORTS_SYNTHESIZED_MATERIAL_ONLY_NOT_YET_GOVERNED_DONE"
  },
  "source_queries_total": 10,
  "negative_tests_total": 10,
  "gde_conflict_sets_total": 10,
  "atms_nogoods_total": 10,
  "atms_propagation_tests": 5,
  "barinel_calibrated": false,
  "information_gain_mode": "ORDINAL_DISCRIMINATION_COST",
  "final_method_state": "B_D_M_ROLE_REPORTS_SYNTHESIZED_NO_DOMAIN_REPAIR",
  "causal_defect_proven": false,
  "solution_state": "VERIFY_FIRST",
  "runtime_modified": false,
  "independence_constraint": {
    "frozen_before_synthesis": true,
    "report_results_from_one_model_context": true,
    "independent_agents": false
  },
  "limits": [
    "BARINEL numeric health not calibrated",
    "ATMS evidence identities preserve time/source assumptions",
    "P0/current separation",
    "lexical/name candidate evidence not runtime proof",
    "performance cohorts not causally equivalent"
  ]
}
$m20_raw$; v_doc jsonb;
 v_spec jsonb:=$m20_spec${"status":"READY","action_kind":"VERIFY_QUERY_ONCE","recipe_mode":"READBACK_EXACT","requires_material_execution":true,"contract_family":"PE10_METHOD_EXECUTION_EVIDENCE","precision":"PE10_METHOD_V1_MATERIAL_EVIDENCE","assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"checkpoint_identity":"PE10_M20","base_code":"B","algorithm_D_executed":true,"algorithm_M_executed":true,"role_reports_frozen":5,"synthesis_completed":true,"read_only_sql_queries":10,"role_negative_tests":10,"gde_conflict_sets":10,"atms_nogoods":10,"atms_propagation_tests":5,"barinel_calibrated":false,"information_gain_mode":"ORDINAL_DISCRIMINATION_COST","role_bound_same_context":true,"independent_agents_claimed":false,"source_event_id":20161,"git_raw_source_verified":true,"runtime_modified":false}},"evidence_ref":"https://github.com/cristhianlujan/claude-persona-lf-patch/blob/f0c63cf37a3a722791a5c528df6a7d3c79711bff/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M20_RAW_V2.json#git_blob_sha=d08e4c49463ac6c1b0fe7dcbd3dd1157c948a7f1","verification_queries":["SELECT id,created_at,payload->>'sql_caller_count',jsonb_array_length(payload->'trigger_bindings') FROM public.lf_eventos WHERE id=20161","SELECT current_setting('track_functions')","SELECT codigo,primera_vez FROM transversal.error_knowledge WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001')"],"expected":"B+D+M with five frozen role-bound reports, 10 read-only observations, 10 negatives, 10 GDE conflict sets, 10 ATMS nogoods, five propagation tests, BARINEL correctly not calibrated and ordinal IG.","forbidden":["CLAIM_INDEPENDENT_AUTONOMOUS_SESSIONS","FABRICATE_BARINEL_PROBABILITIES","USE_NARRATIVE_LIST_AS_ATMS","PROMOTE_P0_TO_CURRENT","SKIP_TRAIN","TOUCH_OTHER_CHECKPOINTS","APPLY_DOMAIN_REPAIR"],"target":{"checkpoint":"PE10_M20","declared_events":[20161]}}$m20_spec$::jsonb;
 v_ref text:='https://github.com/cristhianlujan/claude-persona-lf-patch/blob/f0c63cf37a3a722791a5c528df6a7d3c79711bff/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M20_RAW_V2.json#git_blob_sha=d08e4c49463ac6c1b0fe7dcbd3dd1157c948a7f1';
 v_old text:='chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M20.json#sha256=5fdb1e282b3ff7e425b29c89440ac3ee5bffaa390930e0202775e1c77918cc63';
 v_blob text; v_prior jsonb; v_after jsonb; v_contract jsonb; v_obs jsonb; v_result jsonb; v_assertion jsonb; v_transition jsonb; v_receipt text;
 v_roles int; v_queries int; v_neg int; v_gde int; v_nogoods int; v_prop int; v_n int; v_msg text; v_ctx text;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
   AND target_code LIKE '%lf_pe10_m20_bdm_governed_close_v1' AND status='IN_PROGRESS'
 ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'M20_NOT_TRAIN_EXECUTOR'; END IF;

 IF (SELECT status FROM programacion.engineering_work_items WHERE id=1133)<>'IN_PROGRESS'
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>19
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>13
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M20' AND id=1644 AND status='PENDING' AND evidence_ref=v_old AND assertion_receipt IS NULL AND completed_at IS NULL)<>1
 OR (SELECT count(*) FROM programacion.pe10_method_variants WHERE method_code='PE10_M20' AND base_code='B' AND case_ref='PE10-IG-M107-M109-P0' AND algorithm_codes=ARRAY['D','M']::text[])<>1
 OR (SELECT count(*) FROM programacion.engineering_plan_units WHERE work_item_id=1133 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32' AND unit_metadata#>>'{action_specs_v1,PE10_M20,status}'='BLOCK_PENDING_MATERIAL_RESEARCH_AND_VALIDATION')<>1
 THEN RAISE EXCEPTION 'M20_PRESTATE_OR_METHOD_CONTRACT_NOT_QUALIFIED'; END IF;

 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND sequence_no<20 AND status='DONE' AND completed_at IS NOT NULL AND assertion_receipt->>'passed'='true' AND assertion_contract_sha256=assertion_receipt->>'contract_sha256')<>19
 THEN RAISE EXCEPTION 'M20_PRIOR_19_CANONICAL_RECEIPTS_NOT_QUALIFIED'; END IF;

 SELECT jsonb_agg(jsonb_build_object('checkpoint_code',checkpoint_code,'status',status,'evidence_ref',evidence_ref,'assertion_receipt_sha256',assertion_receipt_sha256,'completed_at',completed_at) ORDER BY sequence_no)
 INTO v_prior FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND sequence_no<20;

 v_blob:=encode(extensions.digest(convert_to('blob '||octet_length(convert_to(v_raw,'UTF8'))::text,'UTF8')||decode('00','hex')||convert_to(v_raw,'UTF8'),'sha1'),'hex');
 IF v_blob<>'d08e4c49463ac6c1b0fe7dcbd3dd1157c948a7f1' THEN RAISE EXCEPTION 'M20_RAW_GIT_BLOB_NOT_VERIFIED expected=d08e4c49463ac6c1b0fe7dcbd3dd1157c948a7f1 observed=%',v_blob; END IF;

 v_doc:=v_raw::jsonb;
 IF v_doc->>'schema'<>'PE10_METHOD_RAW_V2' OR v_doc->>'case_ref'<>'PE10-IG-M107-M109-P0' OR v_doc->>'method_code'<>'PE10_M20' OR v_doc->>'base_code'<>'B'
 OR v_doc->'algorithm_codes'<>'["D","M"]'::jsonb OR v_doc->>'source_cutoff'<>'2026-10-15T00:00:00Z'
 OR v_doc#>>'{original_preserved,sha256}'<>'5fdb1e282b3ff7e425b29c89440ac3ee5bffaa390930e0202775e1c77918cc63'
 OR v_doc->>'autonomous_agent_claim'<>'false' OR v_doc->>'cross_method_inputs_used'<>'false' OR v_doc->>'role_bound_single_context'<>'true'
 OR v_doc#>>'{independence_constraint,independent_agents}'<>'false'
 OR v_doc#>>'{synthesis,source_pieces_frozen_before_synthesis}'<>'true'
 OR v_doc#>>'{synthesis,no_new_sql_in_synthesis}'<>'true'
 OR v_doc#>>'{synthesis,barinel,status}'<>'NOT_CALIBRATED'
 OR v_doc#>>'{synthesis,information_gain_mode}'<>'ORDINAL_DISCRIMINATION_COST'
 OR v_doc#>>'{synthesis,decision,state}'<>'VERIFY_FIRST'
 OR v_doc->>'barinel_calibrated'<>'false' OR v_doc->>'runtime_modified'<>'false'
 OR v_doc->>'final_method_state'<>'B_D_M_ROLE_REPORTS_SYNTHESIZED_NO_DOMAIN_REPAIR'
 THEN RAISE EXCEPTION 'M20_DM_AUTHENTICITY_OR_SYNTHESIS_NOT_QUALIFIED'; END IF;

 SELECT count(*),coalesce(sum((x->>'query_count')::int),0),coalesce(sum((x->>'negative_count')::int),0),coalesce(sum((x->>'gde_conflict_sets')::int),0),coalesce(sum((x->>'atms_nogoods')::int),0)
 INTO v_roles,v_queries,v_neg,v_gde,v_nogoods FROM jsonb_array_elements(v_doc->'role_reports') x WHERE x->>'role_output_frozen'='true';
 v_prop:=jsonb_array_length(v_doc#>'{synthesis,atms_cross_role,propagation_tests}');
 IF v_roles<>5 OR v_queries<>10 OR v_neg<>10 OR v_gde<>10 OR v_nogoods<>10 OR v_prop<>5
 OR v_doc->>'source_queries_total'<>'10' OR v_doc->>'negative_tests_total'<>'10' OR v_doc->>'gde_conflict_sets_total'<>'10' OR v_doc->>'atms_nogoods_total'<>'10' OR v_doc->>'atms_propagation_tests'<>'5'
 OR jsonb_array_length(v_doc#>'{synthesis,synthesis_inputs}')<>5
 THEN RAISE EXCEPTION 'M20_DM_MATERIAL_MANIFEST_FAILED'; END IF;

 IF (SELECT count(*) FROM public.lf_eventos WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z' AND jsonb_array_length(payload->'sql_callers')=38 AND jsonb_array_length(payload->'trigger_bindings')=21)<>1
 OR current_setting('track_functions')<>'none'
 OR (SELECT count(*) FROM transversal.error_knowledge WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001') AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z')<>2
 THEN RAISE EXCEPTION 'M20_P0_SOURCE_DRIFT'; END IF;

 UPDATE programacion.engineering_plan_units SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10_M20}',v_spec,true)
 WHERE work_item_id=1133 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32';
 GET DIAGNOSTICS v_n=ROW_COUNT; IF v_n<>1 THEN RAISE EXCEPTION 'M20_ACTION_SPEC_UPDATE_COUNT_FAILED'; END IF;

 v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M20',programacion.fn_engineering_checkpoint_action_spec_v3('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M20'));
 IF v_contract->>'status'<>'READY' OR v_contract->>'mode'<>'EXPLICIT_PASS_WHEN_SUBSET' THEN RAISE EXCEPTION 'M20_ASSERTION_CONTRACT_NOT_READY:%',coalesce(v_contract::text,'NULL'); END IF;

 v_obs:=jsonb_build_object('checkpoint_identity','PE10_M20','base_code','B','algorithm_D_executed',true,'algorithm_M_executed',true,'role_reports_frozen',v_roles,'synthesis_completed',true,'read_only_sql_queries',v_queries,'role_negative_tests',v_neg,'gde_conflict_sets',v_gde,'atms_nogoods',v_nogoods,'atms_propagation_tests',v_prop,'barinel_calibrated',false,'information_gain_mode','ORDINAL_DISCRIMINATION_COST','role_bound_same_context',true,'independent_agents_claimed',false,'source_event_id',20161,'git_raw_source_verified',true,'runtime_modified',false);
 v_result:=jsonb_build_object('status','PASS','observed',v_obs,'evidence_ref',v_ref,'validation_kind','M20_B_DM_FIVE_ROLE_BOUND_REPORTS_SYNTHESIS_MATERIAL_ONLY','independent_autonomous_agents',false,'product_repair_applied',false);
 v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M20',v_result,v_exec);
 IF v_assertion->>'passed'<>'true' OR coalesce(v_assertion->>'assertion_receipt_sha256','') !~ '^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'M20_CANONICAL_RECEIPT_NOT_PASSED'; END IF;
 v_receipt:=v_assertion->>'assertion_receipt_sha256';
 v_transition:=programacion.fn_engineering_checkpoint_transition_v1('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M20','DONE',v_ref,v_exec,'M20 B+D+M: five frozen role-bound reports with GDE/ordinal IG plus ATMS propagation; no domain repair');
 IF v_transition#>>'{transition,status}'<>'APPLIED' THEN RAISE EXCEPTION 'M20_STATUS_TRANSITION_NOT_CANONICAL'; END IF;

 SELECT jsonb_agg(jsonb_build_object('checkpoint_code',checkpoint_code,'status',status,'evidence_ref',evidence_ref,'assertion_receipt_sha256',assertion_receipt_sha256,'completed_at',completed_at) ORDER BY sequence_no)
 INTO v_after FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND sequence_no<20;
 IF v_after<>v_prior
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M20' AND status='DONE' AND completed_at IS NOT NULL AND evidence_ref=v_ref AND assertion_receipt_sha256=v_receipt AND assertion_receipt->>'passed'='true' AND assertion_contract_sha256=assertion_receipt->>'contract_sha256')<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>20
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>12
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M21' AND status='PENDING')<>1
 THEN RAISE EXCEPTION 'M20_POST_TRAIN_GOVERNED_READBACK_FAILED'; END IF;
EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_msg=MESSAGE_TEXT,v_ctx=PG_EXCEPTION_CONTEXT; RAISE EXCEPTION 'M20_TRAIN_ERROR state=% msg=% context=%',SQLSTATE,left(v_msg,290),left(v_ctx,150) USING ERRCODE=SQLSTATE;
END $m20_close$;
