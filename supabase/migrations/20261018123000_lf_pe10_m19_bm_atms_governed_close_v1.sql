-- PE10 M19: base B + algorithm M (ATMS assumptions/evidence), five frozen role-bound passes + synthesis.
-- Governed Train only. Administrative evidence closure; no product/runtime repair.
DO $m19_close$
DECLARE
 v_exec text;
 v_raw text:=$m19_raw${
  "schema": "PE10_METHOD_RAW_V2",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M19",
  "base_code": "B",
  "algorithm_codes": [
    "M"
  ],
  "method_catalog": "PE10_METHOD_V1",
  "source_cutoff": "2026-10-15T00:00:00Z",
  "original_preserved": {
    "ref": "chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M19.json",
    "sha256": "13a3c0278e78c8ffe8b4ebbd44c084c972277ac3d8fe06a6fb5c027e0fa80ce1"
  },
  "role_bound_single_context": true,
  "autonomous_agent_claim": false,
  "cross_method_inputs_used": false,
  "external_evaluation": "NOT_PERFORMED",
  "producer": "B+M: five specialized role-bound ATMS investigations frozen before synthesis; one shared coordinated model context, no autonomous independence claim",
  "role_reports": [
    {
      "role": "ARCHITECTURE",
      "git_blob_sha": "ba05e006182fa20aac4c5c507631c0429963e3f3",
      "query_count": 2,
      "negative_count": 2,
      "atms_nogoods": 2,
      "role_output_frozen": true
    },
    {
      "role": "PERFORMANCE",
      "git_blob_sha": "289f09b402c67c18eb32aa7c8d92b15b4344352d",
      "query_count": 2,
      "negative_count": 2,
      "atms_nogoods": 2,
      "role_output_frozen": true
    },
    {
      "role": "AUTHORITY",
      "git_blob_sha": "b6c2c8bd79d397f66629b0179d65217e2c446802",
      "query_count": 2,
      "negative_count": 2,
      "atms_nogoods": 2,
      "role_output_frozen": true
    },
    {
      "role": "COVERAGE",
      "git_blob_sha": "fa04b993165ba0b2ede0a861108990ef07186886",
      "query_count": 2,
      "negative_count": 2,
      "atms_nogoods": 2,
      "role_output_frozen": true
    },
    {
      "role": "INNOVATION",
      "git_blob_sha": "a4268ca674e0f46529dfb206965656b038b72241",
      "query_count": 2,
      "negative_count": 2,
      "atms_nogoods": 2,
      "role_output_frozen": true
    }
  ],
  "synthesis_ref": {
    "path": "docs/profile_updater/experiments/pe10_methods32_p0/M19_SYNTHESIS_V1.json",
    "source_commit": "bd4d03eef7662b36a2f25c642f1de11ba73b3505",
    "git_blob_sha": "b33d2304534ab3a233453da09b0d972bf8f879d4"
  },
  "synthesis": {
    "schema": "PE10_M19_SYNTHESIS_V1",
    "case_ref": "PE10-IG-M107-M109-P0",
    "method_code": "PE10_M19",
    "base_code": "B",
    "algorithm_codes": [
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
        "git_blob_sha": "ba05e006182fa20aac4c5c507631c0429963e3f3",
        "source_commit": "3f49eae1ce28575715f8dc38e7abdd2249cfd539",
        "readbacks": 2,
        "negative_tests": 2,
        "atms_nogoods": 2,
        "role_output_frozen": true
      },
      {
        "role": "PERFORMANCE",
        "git_blob_sha": "289f09b402c67c18eb32aa7c8d92b15b4344352d",
        "source_commit": "e5613702c88394f88e58e914a9bd43c9f261d2d8",
        "readbacks": 2,
        "negative_tests": 2,
        "atms_nogoods": 2,
        "role_output_frozen": true
      },
      {
        "role": "AUTHORITY",
        "git_blob_sha": "b6c2c8bd79d397f66629b0179d65217e2c446802",
        "source_commit": "4bd7c55cf3878547b6e9f918650d2a2cf2070673",
        "readbacks": 2,
        "negative_tests": 2,
        "atms_nogoods": 2,
        "role_output_frozen": true
      },
      {
        "role": "COVERAGE",
        "git_blob_sha": "fa04b993165ba0b2ede0a861108990ef07186886",
        "source_commit": "af9f1135a2b35dadbba2914ab64ad0d5b3b03053",
        "readbacks": 2,
        "negative_tests": 2,
        "atms_nogoods": 2,
        "role_output_frozen": true
      },
      {
        "role": "INNOVATION",
        "git_blob_sha": "a4268ca674e0f46529dfb206965656b038b72241",
        "source_commit": "63549e69f713d81dc10fef262b0853619b841f90",
        "readbacks": 2,
        "negative_tests": 2,
        "atms_nogoods": 2,
        "role_output_frozen": true
      }
    ],
    "readbacks_total": 10,
    "negative_tests_total": 10,
    "atms_nogoods_total": 10,
    "atms_synthesis": {
      "evidence_identity_preserved": true,
      "temporal_equivalence_required": true,
      "cross_role_claims": [
        {
          "claim": "P0 is historical, not live certification",
          "supports": [
            "E_ARQ_HIST",
            "E_INNOV_TIME"
          ],
          "status": "SUPPORTED"
        },
        {
          "claim": "Current architecture differs from some historical definitions",
          "supports": [
            "E_ARQ_HIST",
            "E_ARQ_CURR"
          ],
          "status": "SUPPORTED_WITH_HASH_RECIPE_LIMIT"
        },
        {
          "claim": "SOAK receipt proves performance improvement",
          "supports": [],
          "status": "UNSUPPORTED",
          "nogoods": [
            "N_PERF_1"
          ]
        },
        {
          "claim": "42501 is functional failure",
          "supports": [],
          "status": "UNSUPPORTED",
          "nogoods": [
            "N_AUTH_1"
          ]
        },
        {
          "claim": "Historical declared inventory is internally reconciled",
          "supports": [
            "E_COVER_INV",
            "E_COVER_SCOPE"
          ],
          "status": "SUPPORTED_HISTORICAL_ONLY"
        },
        {
          "claim": "64 current complement names are 64 missing callers",
          "supports": [],
          "status": "UNSUPPORTED",
          "nogoods": [
            "N_INNOV_2"
          ]
        }
      ],
      "propagation_tests": [
        {
          "remove": "E_ARQ_CURR",
          "effect": "withdraw current-definition drift claim but keep historical snapshot integrity",
          "result": "PASS"
        },
        {
          "remove": "E_PERF_RUNS",
          "effect": "withdraw revision timing variation while preserving SOAK quality receipt claim",
          "result": "PASS"
        },
        {
          "remove": "E_AUTH_PRIV",
          "effect": "withdraw current privilege-boundary claim while historical EKB 42501 observation remains",
          "result": "PASS"
        },
        {
          "remove": "E_COVER_SCOPE",
          "effect": "withdraw dedupe/exclusion scope claim while 38-row internal count claim remains",
          "result": "PASS"
        },
        {
          "remove": "E_INNOV_COMP",
          "effect": "withdraw complement-candidate claim while temporal layering remains",
          "result": "PASS"
        }
      ]
    },
    "findings": [
      {
        "id": "M19_SYN_F1",
        "classification": "MEASURED",
        "finding": "ATMS separation of historical and current evidence prevents P0 from being promoted to live certification; 22/38 empirical definition changes remain a current comparison with unknown historical hash recipe."
      },
      {
        "id": "M19_SYN_F2",
        "classification": "MEASURED",
        "finding": "SOAK quality evidence and performance evidence are separate supports; removing performance-run evidence does not invalidate receipt-38 quality history."
      },
      {
        "id": "M19_SYN_F3",
        "classification": "MEASURED",
        "finding": "Authority evidence supports 42501 as a readback-path condition, and current SELECT evidence remains available without EXECUTE elevation."
      },
      {
        "id": "M19_SYN_F4",
        "classification": "MEASURED_HISTORICAL",
        "finding": "The declared 38-caller/76-edge snapshot is internally reconciled under its own dedupe/exclusion rules, but ATMS blocks reuse as live completeness without temporal/source equivalence."
      },
      {
        "id": "M19_SYN_F5",
        "classification": "MEASURED_CANDIDATE_ONLY",
        "finding": "Current complement/path-shaped objects are candidate evidence only; ATMS blocks name-pattern membership from supporting caller-omission claims."
      }
    ],
    "contradictions": [
      {
        "topic": "historical integrity vs current drift",
        "resolution": "different evidence time/identity; both can hold"
      },
      {
        "topic": "SOAK pass vs performance unresolved",
        "resolution": "different dependent claims and evidence scope"
      },
      {
        "topic": "42501 vs readable evidence",
        "resolution": "EXECUTE and SELECT are separate authority supports"
      }
    ],
    "decision": {
      "state": "VERIFY_FIRST",
      "implemented_repair": false,
      "reason": "ATMS shows material claims depend on non-equivalent evidence classes; structural/performance uncertainties remain."
    },
    "unresolved": [
      "canonical historical definition_md5 method",
      "runtime impact of changed definitions",
      "matched performance effect",
      "current caller classification of complement candidates"
    ],
    "constraints_preserved": [
      "READ_ONLY",
      "no production mutation",
      "historical/current separation",
      "five role reports frozen before synthesis",
      "no cross-method inputs",
      "no independent-agent claim"
    ],
    "non_isolation_risk": "Five role-bound passes ran sequentially in one shared model context. Their artifacts were frozen before synthesis and did not consume peer role reports, but autonomous cognitive independence is not demonstrated.",
    "final_method_status": "B_M_ATMS_FIVE_ROLE_REPORTS_SYNTHESIZED_MATERIAL_ONLY_NOT_YET_GOVERNED_DONE"
  },
  "source_queries_total": 10,
  "negative_tests_total": 10,
  "atms_nogoods_total": 10,
  "atms_propagation_tests": 5,
  "final_method_state": "B_M_ATMS_ROLE_REPORTS_SYNTHESIZED_NO_DOMAIN_REPAIR",
  "causal_defect_proven": false,
  "solution_state": "VERIFY_FIRST",
  "runtime_modified": false,
  "independence_constraint": {
    "frozen_before_synthesis": true,
    "report_results_from_one_model_context": true,
    "independent_agents": false
  },
  "limits": [
    "P0 historical and current observations are separate ATMS evidence identities",
    "Historical hash recipe remains unknown",
    "SOAK receipt is not performance proof",
    "42501 is authority-path evidence, not functional failure",
    "Name-pattern complement is candidate discovery only"
  ]
}
$m19_raw$;
 v_doc jsonb;
 v_spec jsonb:=$m19_spec${"status":"READY","action_kind":"VERIFY_QUERY_ONCE","recipe_mode":"READBACK_EXACT","requires_material_execution":true,"contract_family":"PE10_METHOD_EXECUTION_EVIDENCE","precision":"PE10_METHOD_V1_MATERIAL_EVIDENCE","assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"checkpoint_identity":"PE10_M19","base_code":"B","algorithm_M_executed":true,"role_reports_frozen":5,"synthesis_completed":true,"read_only_sql_queries":10,"role_negative_tests":10,"atms_nogoods":10,"atms_propagation_tests":5,"role_bound_same_context":true,"independent_agents_claimed":false,"source_event_id":20161,"git_raw_source_verified":true,"runtime_modified":false}},"evidence_ref":"https://github.com/cristhianlujan/claude-persona-lf-patch/blob/9e4fbdadfe890341d739e3cdb50e5f7ee368fcee/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M19_RAW_V2.json#git_blob_sha=e0246057d861707223f4d02dca679929fbc74bf8","verification_queries":["SELECT id,created_at,payload->>'sql_caller_count' FROM public.lf_eventos WHERE id=20161","SELECT id,created_at,payload->>'verification_status' FROM programacion.provenance_receipts WHERE id=38","SELECT codigo,primera_vez FROM transversal.error_knowledge WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001')"],"expected":"B+M method with five frozen role-bound ATMS reports, 10 read-only observations, 10 negative checks, 10 nogoods, five invalidation-propagation tests, synthesis after freeze, no domain repair.","forbidden":["CLAIM_INDEPENDENT_AUTONOMOUS_SESSIONS","USE_NARRATIVE_LIST_AS_ATMS","PROMOTE_P0_TO_CURRENT","SKIP_TRAIN","TOUCH_OTHER_CHECKPOINTS","APPLY_DOMAIN_REPAIR"],"target":{"checkpoint":"PE10_M19","declared_events":[20161],"declared_objects":["public.lf_eventos","programacion.provenance_receipts","transversal.error_knowledge","programacion.input_readiness_runs","programacion.engineering_work_checkpoints"]}}$m19_spec$::jsonb;
 v_ref text:='https://github.com/cristhianlujan/claude-persona-lf-patch/blob/9e4fbdadfe890341d739e3cdb50e5f7ee368fcee/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M19_RAW_V2.json#git_blob_sha=e0246057d861707223f4d02dca679929fbc74bf8';
 v_old text:='chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M19.json#sha256=13a3c0278e78c8ffe8b4ebbd44c084c972277ac3d8fe06a6fb5c027e0fa80ce1';
 v_blob text;
 v_prior jsonb;
 v_after jsonb;
 v_contract jsonb;
 v_obs jsonb;
 v_result jsonb;
 v_assertion jsonb;
 v_transition jsonb;
 v_receipt text;
 v_roles int;
 v_queries int;
 v_neg int;
 v_nogoods int;
 v_prop int;
 v_n int;
 v_msg text;
 v_ctx text;
BEGIN
 SELECT execution_id INTO v_exec
 FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF'
   AND target_type='MIGRATION'
   AND target_code LIKE '%lf_pe10_m19_bm_atms_governed_close_v1'
   AND status='IN_PROGRESS'
 ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'M19_NOT_TRAIN_EXECUTOR'; END IF;

 IF (SELECT status FROM programacion.engineering_work_items WHERE id=1133)<>'IN_PROGRESS'
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>18
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>14
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1133 AND checkpoint_code='PE10_M19' AND id=1643
       AND status='PENDING' AND evidence_ref=v_old
       AND assertion_receipt IS NULL AND completed_at IS NULL)<>1
 OR (SELECT count(*) FROM programacion.pe10_method_variants
     WHERE method_code='PE10_M19' AND base_code='B'
       AND case_ref='PE10-IG-M107-M109-P0'
       AND algorithm_codes=ARRAY['M']::text[])<>1
 OR (SELECT count(*) FROM programacion.engineering_plan_units
     WHERE work_item_id=1133 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32'
       AND unit_metadata#>>'{action_specs_v1,PE10_M19,status}'='BLOCK_PENDING_MATERIAL_RESEARCH_AND_VALIDATION')<>1
 THEN RAISE EXCEPTION 'M19_PRESTATE_OR_METHOD_CONTRACT_NOT_QUALIFIED'; END IF;

 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1133 AND sequence_no<19
       AND status='DONE' AND completed_at IS NOT NULL
       AND assertion_receipt->>'passed'='true'
       AND assertion_contract_sha256=assertion_receipt->>'contract_sha256')<>18
 THEN RAISE EXCEPTION 'M19_PRIOR_18_CANONICAL_RECEIPTS_NOT_QUALIFIED'; END IF;

 SELECT jsonb_agg(jsonb_build_object('checkpoint_code',checkpoint_code,'status',status,'evidence_ref',evidence_ref,'assertion_receipt_sha256',assertion_receipt_sha256,'completed_at',completed_at) ORDER BY sequence_no)
 INTO v_prior
 FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=1133 AND sequence_no<19;

 v_blob:=encode(extensions.digest(convert_to('blob '||octet_length(convert_to(v_raw,'UTF8'))::text,'UTF8')||decode('00','hex')||convert_to(v_raw,'UTF8'),'sha1'),'hex');
 IF v_blob<>'e0246057d861707223f4d02dca679929fbc74bf8' THEN RAISE EXCEPTION 'M19_RAW_GIT_BLOB_NOT_VERIFIED expected=e0246057d861707223f4d02dca679929fbc74bf8 observed=%',v_blob; END IF;

 v_doc:=v_raw::jsonb;
 IF v_doc->>'schema'<>'PE10_METHOD_RAW_V2'
 OR v_doc->>'case_ref'<>'PE10-IG-M107-M109-P0'
 OR v_doc->>'method_code'<>'PE10_M19'
 OR v_doc->>'base_code'<>'B'
 OR v_doc->'algorithm_codes'<>'["M"]'::jsonb
 OR v_doc->>'source_cutoff'<>'2026-10-15T00:00:00Z'
 OR v_doc#>>'{original_preserved,sha256}'<>'13a3c0278e78c8ffe8b4ebbd44c084c972277ac3d8fe06a6fb5c027e0fa80ce1'
 OR v_doc->>'autonomous_agent_claim'<>'false'
 OR v_doc->>'cross_method_inputs_used'<>'false'
 OR v_doc->>'role_bound_single_context'<>'true'
 OR v_doc#>>'{independence_constraint,independent_agents}'<>'false'
 OR v_doc#>>'{synthesis,source_pieces_frozen_before_synthesis}'<>'true'
 OR v_doc#>>'{synthesis,no_new_sql_in_synthesis}'<>'true'
 OR v_doc#>>'{synthesis,decision,state}'<>'VERIFY_FIRST'
 OR v_doc->>'runtime_modified'<>'false'
 OR v_doc->>'final_method_state'<>'B_M_ATMS_ROLE_REPORTS_SYNTHESIZED_NO_DOMAIN_REPAIR'
 THEN RAISE EXCEPTION 'M19_ATMS_AUTHENTICITY_OR_SYNTHESIS_NOT_QUALIFIED'; END IF;

 SELECT count(*),coalesce(sum((x->>'query_count')::int),0),coalesce(sum((x->>'negative_count')::int),0),coalesce(sum((x->>'atms_nogoods')::int),0)
 INTO v_roles,v_queries,v_neg,v_nogoods
 FROM jsonb_array_elements(v_doc->'role_reports') x
 WHERE x->>'role_output_frozen'='true';
 v_prop:=jsonb_array_length(v_doc#>'{synthesis,atms_synthesis,propagation_tests}');
 IF v_roles<>5 OR v_queries<>10 OR v_neg<>10 OR v_nogoods<>10 OR v_prop<>5
 OR v_doc->>'source_queries_total'<>'10'
 OR v_doc->>'negative_tests_total'<>'10'
 OR v_doc->>'atms_nogoods_total'<>'10'
 OR v_doc->>'atms_propagation_tests'<>'5'
 OR jsonb_array_length(v_doc#>'{synthesis,synthesis_inputs}')<>5
 THEN RAISE EXCEPTION 'M19_ATMS_MATERIAL_MANIFEST_FAILED'; END IF;

 IF (SELECT count(*) FROM public.lf_eventos
     WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'
       AND jsonb_array_length(payload->'sql_callers')=38)<>1
 OR (SELECT count(*) FROM programacion.provenance_receipts
     WHERE id=38 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'
       AND payload->>'verification_status'='VERIFIED')<>1
 OR (SELECT count(*) FROM transversal.error_knowledge
     WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001')
       AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z')<>2
 THEN RAISE EXCEPTION 'M19_P0_SOURCE_DRIFT'; END IF;

 UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10_M19}',v_spec,true)
 WHERE work_item_id=1133 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32';
 GET DIAGNOSTICS v_n=ROW_COUNT;
 IF v_n<>1 THEN RAISE EXCEPTION 'M19_ACTION_SPEC_UPDATE_COUNT_FAILED'; END IF;

 v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
  'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M19',
  programacion.fn_engineering_checkpoint_action_spec_v3('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M19')
 );
 IF v_contract->>'status'<>'READY' OR v_contract->>'mode'<>'EXPLICIT_PASS_WHEN_SUBSET'
 THEN RAISE EXCEPTION 'M19_ASSERTION_CONTRACT_NOT_READY:%',coalesce(v_contract::text,'NULL'); END IF;

 v_obs:=jsonb_build_object(
  'checkpoint_identity','PE10_M19','base_code','B','algorithm_M_executed',true,
  'role_reports_frozen',v_roles,'synthesis_completed',true,'read_only_sql_queries',v_queries,
  'role_negative_tests',v_neg,'atms_nogoods',v_nogoods,'atms_propagation_tests',v_prop,
  'role_bound_same_context',true,'independent_agents_claimed',false,'source_event_id',20161,
  'git_raw_source_verified',true,'runtime_modified',false
 );
 v_result:=jsonb_build_object('status','PASS','observed',v_obs,'evidence_ref',v_ref,
   'validation_kind','M19_B_M_ATMS_FIVE_ROLE_BOUND_REPORTS_SYNTHESIS_MATERIAL_ONLY',
   'independent_autonomous_agents',false,'product_repair_applied',false);

 v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
  'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M19',v_result,v_exec
 );
 IF v_assertion->>'passed'<>'true'
 OR coalesce(v_assertion->>'assertion_receipt_sha256','') !~ '^[a-f0-9]{64}$'
 THEN RAISE EXCEPTION 'M19_CANONICAL_RECEIPT_NOT_PASSED'; END IF;
 v_receipt:=v_assertion->>'assertion_receipt_sha256';

 v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
  'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M19','DONE',v_ref,v_exec,
  'M19 B+M: five frozen role-bound ATMS reports with assumptions, minimal supports, nogoods and invalidation propagation; no domain repair'
 );
 IF v_transition#>>'{transition,status}'<>'APPLIED' THEN RAISE EXCEPTION 'M19_STATUS_TRANSITION_NOT_CANONICAL'; END IF;

 SELECT jsonb_agg(jsonb_build_object('checkpoint_code',checkpoint_code,'status',status,'evidence_ref',evidence_ref,'assertion_receipt_sha256',assertion_receipt_sha256,'completed_at',completed_at) ORDER BY sequence_no)
 INTO v_after
 FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=1133 AND sequence_no<19;

 IF v_after<>v_prior
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1133 AND checkpoint_code='PE10_M19'
       AND status='DONE' AND completed_at IS NOT NULL AND evidence_ref=v_ref
       AND assertion_receipt_sha256=v_receipt
       AND assertion_receipt->>'passed'='true'
       AND assertion_contract_sha256=assertion_receipt->>'contract_sha256')<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>19
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>13
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M20' AND status='PENDING')<>1
 THEN RAISE EXCEPTION 'M19_POST_TRAIN_GOVERNED_READBACK_FAILED'; END IF;
EXCEPTION WHEN OTHERS THEN
 GET STACKED DIAGNOSTICS v_msg=MESSAGE_TEXT,v_ctx=PG_EXCEPTION_CONTEXT;
 RAISE EXCEPTION 'M19_TRAIN_ERROR state=% msg=% context=%',SQLSTATE,left(v_msg,290),left(v_ctx,150) USING ERRCODE=SQLSTATE;
END $m19_close$;
