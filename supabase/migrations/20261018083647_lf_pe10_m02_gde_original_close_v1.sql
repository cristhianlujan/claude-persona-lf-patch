-- PE10 M02: certify one GDE method proof, original RAW preserved.
-- Scope research material only, no product repair claim. Train-only apply and exact receipt.
DO $m02_close$
DECLARE
 v_exec text;v_raw text:=$m02_doc${
  "schema": "PE10_METHOD_RAW_V2",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M02",
  "base_code": "A",
  "algorithm_codes": [
    "D"
  ],
  "source_cutoff": "2026-10-15T00:00:00Z",
  "mode": "REVERIFY_ORIGINAL_GDE_CANDIDATES",
  "original_raw": {
    "ref": "chatgpt-file://file_000000004e48820e8414025654581746/prior_originals/PE10_M02_RAW.json",
    "sha256": "34cdfe2c2d3619495122092934d2db7719a312d620094b97463d1c41866c54e7"
  },
  "readbacks": [
    {
      "id": "M02-Q1",
      "sql_literal": "SELECT codigo,categoria,severidad,primera_vez,causa_raiz,prevencion,validacion FROM transversal.error_knowledge WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001') AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z' ORDER BY codigo",
      "rows": [
        {
          "codigo": "IG-M107-CP2-READ-ROLE-CURRENTNESS-001"
        },
        {
          "codigo": "IG-M107-SOAK-CRITERION-DRIFT-001"
        }
      ],
      "readback_scope": "PROJECTED_OUTPUT_NOT_FULL_ROW",
      "observed_count": 2
    },
    {
      "id": "M02-Q2",
      "sql_literal": "SELECT id,created_at,payload->>'source_pack_version' source_pack,payload->>'test_case_count' test_count,payload->>'trigger_binding_count' trigger_bindings,payload->>'acceptance_declared' acceptance,payload->'historical_provenance_only' provenance FROM public.lf_eventos WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'",
      "rows": [
        {
          "test_count": "77",
          "trigger_bindings": "21",
          "source_pack": "SOURCE_PACK_V1",
          "acceptance": "false"
        }
      ],
      "readback_scope": "PROJECTED_OUTPUT_NOT_FULL_ROW",
      "observed_count": 1
    },
    {
      "id": "M02-Q3",
      "sql_literal": "SELECT evento_tipo,entidad_codigo,count(*) n,min(created_at) min_at,max(created_at) max_at FROM public.lf_eventos WHERE created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z' AND (entidad_codigo ILIKE '%M9.11%' OR descripcion ILIKE '%SOAK_OBSERVATION_HISTORY_V2%') GROUP BY 1,2 ORDER BY max(created_at) DESC LIMIT 15",
      "rows": [],
      "readback_scope": "PROJECTED_OUTPUT_NOT_FULL_ROW",
      "observed_count": 0
    },
    {
      "id": "M02-Q4",
      "sql_literal": "SELECT id,created_at,receipt_kind,subject_ref,verification_ref,receipt_sha256,payload->>'verification_status' verification_status,payload->>'pass' historical_pass,payload->>'screens_total' screens,payload->>'families_total' families,payload->>'screens_below_2' screens_below,payload->>'families_below_2' families_below,payload->>'known_false_pass_signals' false_pass,payload->>'unresolved_d4' d4 FROM programacion.provenance_receipts WHERE id=38 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'",
      "rows": [
        {
          "id": 38,
          "receipt_kind": "EVIDENCE_VERIFICATION",
          "verification_status": "VERIFIED",
          "screens": "13",
          "families": "47",
          "false_pass": "0",
          "d4": "0"
        }
      ],
      "readback_scope": "PROJECTED_OUTPUT_NOT_FULL_ROW",
      "observed_count": 1
    },
    {
      "id": "M02-Q5",
      "sql_literal": "SELECT payload->'usage_stats' usage_stats,payload->'historical_provenance_only' provenance,payload->'scope_guards' scope_guards FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "usage_stats": {
            "track_functions": "none",
            "ig_stat_rows": 0
          }
        }
      ],
      "readback_scope": "PROJECTED_OUTPUT_NOT_FULL_ROW",
      "observed_count": 1
    },
    {
      "id": "M02-Q6",
      "sql_literal": "SELECT current_user principal,current_setting('transaction_read_only') read_only,current_setting('request.jwt.claim.role',true) jwt_role",
      "rows": [
        {
          "principal": "supabase_read_only_user",
          "read_only": "on",
          "jwt_role": null
        }
      ],
      "readback_scope": "PROJECTED_FROM_ROLE_QUERY_EXECUTION",
      "observed_count": 1
    },
    {
      "id": "M02-Q7",
      "sql_literal": "SELECT count(*) n,count(*) FILTER(WHERE (x->>'definition_md5') ~ '^[a-f0-9]{32}$') md5_format_valid,count(*) FILTER(WHERE x->>'currentness_source'='LIVE_PG_PROC') historical_currentness_labels FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161",
      "rows": [
        {
          "n": 38,
          "md5_format_valid": 38,
          "historical_currentness_labels": 38
        }
      ],
      "readback_scope": "PROJECTED_OUTPUT_NOT_FULL_ROW",
      "observed_count": 1
    }
  ],
  "algorithm_execution": {
    "GDE": {
      "conflict_sets": [
        [
          "soak_projection",
          "historical_soak_binding"
        ],
        [
          "cp2_current_reader",
          "cp2_privilege_contract"
        ]
      ],
      "minimal_hitting_sets": [
        [
          "soak_projection",
          "cp2_current_reader"
        ],
        [
          "soak_projection",
          "cp2_privilege_contract"
        ],
        [
          "historical_soak_binding",
          "cp2_current_reader"
        ],
        [
          "historical_soak_binding",
          "cp2_privilege_contract"
        ]
      ],
      "enumeration": "4 minimal two-component hitting sets computed; open-world alternatives remain; not a confirmed fault repair"
    },
    "BARINEL": {
      "status": "NOT_CALIBRATABLE",
      "reason": "No component execution spectra or priors; numeric likelihood/health not computed"
    },
    "INFORMATION_GAIN": {
      "mode": "ORDINAL_ONLY",
      "ranking": [
        "Read qualified historical M9.11 receipt",
        "Check historical CP2 privilege/equivalent SELECT",
        "Check source-pinned caller identities"
      ],
      "numeric_entropy": "NOT_JUSTIFIED"
    }
  },
  "negative_tests": [
    {
      "id": "GDE_MINIMALITY",
      "pass": true,
      "proof": "Every set hits both conflicts; removing either element misses one conflict"
    },
    {
      "id": "GDE_EMPTY_SET_REJECT",
      "pass": true
    },
    {
      "id": "BARINEL_NO_INVENTED_NUMERICS",
      "pass": true
    },
    {
      "id": "ZERO_EVENT_MATCH_NOT_ZERO_HISTORICAL_RECEIPTS",
      "pass": true,
      "proof": "id38 VERIFIED in provenance_receipts"
    },
    {
      "id": "CP2_PERMISSION_NOT_FUNCTIONAL_FAILURE",
      "pass": true
    }
  ],
  "findings": [
    {
      "code": "M02-F1",
      "claim": "Historical SOAK and CP2 risk families are separate; candidate hitting sets are not confirmed causal repairs.",
      "evidence": [
        "M02-Q1"
      ]
    },
    {
      "code": "M02-F2",
      "claim": "Zero matches in a narrow event text search does not establish absence of verified historical receipt 38.",
      "evidence": [
        "M02-Q3",
        "M02-Q4"
      ]
    },
    {
      "code": "M02-F3",
      "claim": "Numeric BARINEL and expected information gain cannot be calibrated from P0; ordinal questions retained.",
      "evidence": [
        "M02-Q1",
        "M02-Q4"
      ]
    }
  ],
  "causal_model": "Competing source-restricted hypotheses, no proven production defect.",
  "chosen_repair": "VERIFY_FIRST",
  "constraints_preserved": [
    "P0 cutoff",
    "Read only",
    "Original unchanged",
    "No method quality scoring",
    "No runtime changes"
  ],
  "result": "GDE_MATERIAL_RESEARCH_VERIFIED_CAUSAL_UNKNOWN"
}
$m02_doc$;v_doc jsonb;v_blob text;
 v_ref text:='https://github.com/cristhianlujan/claude-persona-lf-patch/blob/b3ce6a436016737190407dc0932fba317a04c244/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M02_RAW_V2.json#git_blob_sha=e3a99ebf7730eb09096f76876ee2e287970dee43';v_prev text:='chatgpt-file://file_000000004e48820e8414025654581746/prior_originals/PE10_M02_RAW.json#sha256=34cdfe2c2d3619495122092934d2db7719a312d620094b97463d1c41866c54e7';
 v_spec jsonb:=$m02_spec${"status":"READY","action_kind":"VERIFY_QUERY_ONCE","recipe_mode":"READBACK_EXACT","requires_material_execution":true,"contract_family":"PE10_METHOD_EXECUTION_EVIDENCE","precision":"PE10_METHOD_V1_MATERIAL_EVIDENCE","assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"checkpoint_identity":"PE10_M02","method_algorithm":"D","literal_sql_count":7,"gde_minimal_hitting_sets":4,"negative_tests_passed":5,"historical_source_event_id":20161,"original_sha256_preserved":true,"barinel_not_calibrated":true,"runtime_modified":false}},"evidence_ref":"https://github.com/cristhianlujan/claude-persona-lf-patch/blob/b3ce6a436016737190407dc0932fba317a04c244/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M02_RAW_V2.json#git_blob_sha=e3a99ebf7730eb09096f76876ee2e287970dee43","verification_queries":["SELECT codigo,categoria,severidad,primera_vez,causa_raiz,prevencion,validacion FROM transversal.error_knowledge WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001') AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z' ORDER BY codigo","SELECT id,created_at,payload->>'source_pack_version' source_pack,payload->>'test_case_count' test_count,payload->>'trigger_binding_count' trigger_bindings,payload->>'acceptance_declared' acceptance,payload->'historical_provenance_only' provenance FROM public.lf_eventos WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'","SELECT evento_tipo,entidad_codigo,count(*) n,min(created_at) min_at,max(created_at) max_at FROM public.lf_eventos WHERE created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z' AND (entidad_codigo ILIKE '%M9.11%' OR descripcion ILIKE '%SOAK_OBSERVATION_HISTORY_V2%') GROUP BY 1,2 ORDER BY max(created_at) DESC LIMIT 15","SELECT id,created_at,receipt_kind,subject_ref,verification_ref,receipt_sha256,payload->>'verification_status' verification_status,payload->>'pass' historical_pass,payload->>'screens_total' screens,payload->>'families_total' families,payload->>'screens_below_2' screens_below,payload->>'families_below_2' families_below,payload->>'known_false_pass_signals' false_pass,payload->>'unresolved_d4' d4 FROM programacion.provenance_receipts WHERE id=38 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'","SELECT payload->'usage_stats' usage_stats,payload->'historical_provenance_only' provenance,payload->'scope_guards' scope_guards FROM public.lf_eventos WHERE id=20161","SELECT count(*) n,count(*) FILTER(WHERE (x->>'definition_md5') ~ '^[a-f0-9]{32}$') md5_format_valid,count(*) FILTER(WHERE x->>'currentness_source'='LIVE_PG_PROC') historical_currentness_labels FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161"],"expected":"Original-preserving D algorithm GDE research with four verifiable minimal hypothetical diagnosis sets; evidence is historical, no repair implementation or quantitative BARINEL","forbidden":["TREAT_DIAGNOSIS_AS_APPLIED_REPAIR","INVENT_BARINEL_PRIORS","SKIP_CANONICAL_RECEIPT","MODIFY_PREVIOUS_METHODS"],"target":{"checkpoint":"PE10_M02","declared_events":[20161],"declared_objects":["public.lf_eventos","programacion.provenance_receipts","transversal.error_knowledge","programacion.engineering_work_checkpoints"],"evidence_artifacts":[{"path":"cristhianlujan/claude-persona-lf-patch:docs/profile_updater/experiments/pe10_methods32_p0/PE10_M02_RAW_V2.json","role":"EVIDENCE","purpose":"M02_ORIGINAL_PRESERVED_D_MODULE_EXECUTED","target_kind":"EXACT_EXISTING_FILE"}]}}$m02_spec$::jsonb;
 v_contract jsonb;v_assertion jsonb;v_transition jsonb;
 v_r integer;v_neg integer;v_min integer;v_ekb integer;v_currentness integer;v_n integer;v_receipt text;
 v_observed jsonb;v_result jsonb;v_code text;v_a jsonb;v_components jsonb;
 v_dbg_msg text;v_dbg_context text;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
 AND target_code LIKE '%lf_pe10_m02_gde_original_close_v1' AND status='IN_PROGRESS'
 ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'M02_EXECUTION_NOT_TRAIN'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>2
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>30
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M02'
 AND status='PENDING' AND evidence_ref=v_prev AND assertion_receipt IS NULL)<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M01'
 AND status='DONE' AND assertion_receipt_sha256='1c174f3277f9656ffc4146c210ac64cd037fc92d4fb34d7a7959fe826e3f9b01')<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M03'
 AND status='DONE' AND assertion_receipt_sha256='0cbbc9d58552b2c5ea3d2c9bca1b07c6467cd4145720905f38fc5bf07a46e2a1')<>1
 OR (SELECT unit_metadata#>>'{action_specs_v1,PE10_M02,status}' FROM programacion.engineering_plan_units WHERE work_item_id=1133)<>'BLOCK_PENDING_MATERIAL_RESEARCH_AND_VALIDATION'
 THEN RAISE EXCEPTION 'M02_PRESTATE_CONTRACT_DRIFT'; END IF;

 v_blob:=encode(extensions.digest(convert_to('blob '||octet_length(convert_to(v_raw,'UTF8'))::text,'UTF8')
 ||decode('00','hex')||convert_to(v_raw,'UTF8'),'sha1'),'hex');
 IF v_blob<>'e3a99ebf7730eb09096f76876ee2e287970dee43' THEN RAISE EXCEPTION 'M02_GIT_BLOB_MISMATCH'; END IF;
 v_doc:=v_raw::jsonb;
 IF v_doc->>'schema'<>'PE10_METHOD_RAW_V2'
 OR v_doc->>'case_ref'<>'PE10-IG-M107-M109-P0'
 OR v_doc->>'method_code'<>'PE10_M02'
 OR v_doc->>'base_code'<>'A'
 OR v_doc->'algorithm_codes'<>'["D"]'::jsonb
 OR v_doc#>>'{original_raw,sha256}'<>'34cdfe2c2d3619495122092934d2db7719a312d620094b97463d1c41866c54e7'
 OR v_doc->>'chosen_repair'<>'VERIFY_FIRST'
 OR v_doc->>'source_cutoff'<>'2026-10-15T00:00:00Z'
 THEN RAISE EXCEPTION 'M02_RAW_IDENTITY_INVALID'; END IF;

 SELECT count(*) INTO v_r FROM jsonb_array_elements(v_doc->'readbacks') e
 WHERE e->>'sql_literal' ~* '^SELECT ' AND e->>'id' ~ '^M02-Q[1-7]$'
 AND jsonb_typeof(e->'rows')='array'
 AND (e->>'observed_count')::int=jsonb_array_length(e->'rows');
 IF v_r<>7 OR jsonb_array_length(v_doc->'readbacks')<>7
 OR (SELECT count(DISTINCT e->>'id') FROM jsonb_array_elements(v_doc->'readbacks') e)<>7
 THEN RAISE EXCEPTION 'M02_SQL_READBACKS_NOT_COMPLETE'; END IF;
 SELECT count(*) INTO v_neg FROM jsonb_array_elements(v_doc->'negative_tests') x
 WHERE x->>'pass'='true';
 IF v_neg<>5 OR jsonb_array_length(v_doc->'negative_tests')<>5
 OR v_doc#>>'{readbacks,1,rows,0,test_count}'<>'77'
 OR v_doc#>>'{readbacks,1,rows,0,trigger_bindings}'<>'21'
 OR jsonb_array_length(v_doc#>'{readbacks,2,rows}')<>0
 OR v_doc#>>'{readbacks,3,rows,0,verification_status}'<>'VERIFIED'
 OR v_doc#>>'{readbacks,6,rows,0,n}'<>'38'
 THEN RAISE EXCEPTION 'M02_READBACK_EVIDENCE_OR_FALSIFIERS_BAD'; END IF;

 SELECT count(*) INTO v_min FROM jsonb_array_elements(v_doc#>'{algorithm_execution,GDE,minimal_hitting_sets}') x
 WHERE jsonb_array_length(x)=2 AND
 (x ? 'soak_projection' OR x ? 'historical_soak_binding') AND
 (x ? 'cp2_current_reader' OR x ? 'cp2_privilege_contract');
 IF v_min<>4 OR jsonb_array_length(v_doc#>'{algorithm_execution,GDE,minimal_hitting_sets}')<>4
 OR v_doc#>>'{algorithm_execution,BARINEL,status}'<>'NOT_CALIBRATABLE'
 OR v_doc#>>'{algorithm_execution,INFORMATION_GAIN,mode}'<>'ORDINAL_ONLY'
 THEN RAISE EXCEPTION 'M02_GDE_BARENL_OR_IG_EVIDENCE_INVALID'; END IF;

 SELECT count(*) INTO v_ekb FROM transversal.error_knowledge WHERE codigo IN
 ('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001')
 AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z';
 SELECT count(*) INTO v_currentness FROM public.lf_eventos
 WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'
 AND payload->>'test_case_count'='77'
 AND payload->>'trigger_binding_count'='21';
 IF v_ekb<>2 OR v_currentness<>1
 OR (SELECT count(*) FROM programacion.provenance_receipts
 WHERE id=38 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'
 AND payload->>'verification_status'='VERIFIED')<>1
 THEN RAISE EXCEPTION 'M02_P0_SOURCE_READBACK_DIFFERENT'; END IF;

 UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10_M02}',v_spec,true)
 WHERE work_item_id=1133 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32';
 GET DIAGNOSTICS v_n=ROW_COUNT;
 IF v_n<>1 THEN RAISE EXCEPTION 'M02_UNIT_SPEC_UPDATE_NOT_SINGLE'; END IF;
 v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M02',
 programacion.fn_engineering_checkpoint_action_spec_v3('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M02'));
 IF v_contract->>'status'<>'READY' OR v_contract->>'mode'<>'EXPLICIT_PASS_WHEN_SUBSET'
 THEN RAISE EXCEPTION 'M02_ASSERTION_CONTRACT_NOT_READY:%',coalesce(v_contract::text,'NULL'); END IF;
 v_observed:=jsonb_build_object('checkpoint_identity','PE10_M02','method_algorithm','D',
 'literal_sql_count',v_r,'gde_minimal_hitting_sets',v_min,'negative_tests_passed',v_neg,
 'historical_source_event_id',20161,'original_sha256_preserved',true,'barinel_not_calibrated',true,
 'runtime_modified',false);
 v_result:=jsonb_build_object('status','PASS','observed',v_observed,'evidence_ref',v_ref,
 'validation_kind','METHOD_GDE_DIAGNOSTIC_MATERIALITY_NOT_CAUSAL_REPAIR',
 'independent_method_score','NOT_PERFORMED');
 v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M02',v_result,v_exec);
 IF v_assertion->>'passed'<>'true' OR coalesce(v_assertion->>'assertion_receipt_sha256','') !~ '^[a-f0-9]{64}$'
 THEN RAISE EXCEPTION 'M02_GOVERNED_ASSERTION_NOT_PASSED'; END IF;
 v_receipt:=v_assertion->>'assertion_receipt_sha256';
 v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M02','DONE',v_ref,v_exec,
 'M02 method GDE evidence verified, no BARINEL calibration claimed, no production repair');
 IF v_transition#>>'{transition,status}'<>'APPLIED' THEN RAISE EXCEPTION 'M02_GOVERNED_TRANSITION_FAIL'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=1133 AND checkpoint_code='PE10_M02' AND status='DONE'
 AND evidence_ref=v_ref AND completed_at IS NOT NULL AND assertion_receipt_sha256=v_receipt
 AND assertion_contract_sha256=assertion_receipt->>'contract_sha256'
 AND assertion_receipt->>'passed'='true')<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>3
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>29
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M03' AND status='DONE' AND assertion_receipt_sha256='0cbbc9d58552b2c5ea3d2c9bca1b07c6467cd4145720905f38fc5bf07a46e2a1')<>1
 THEN RAISE EXCEPTION 'M02_FINAL_STATES_INCORRECT'; END IF;
EXCEPTION WHEN OTHERS THEN
 GET STACKED DIAGNOSTICS v_dbg_msg=MESSAGE_TEXT,v_dbg_context=PG_EXCEPTION_CONTEXT;
 RAISE EXCEPTION 'M02_CLOSE_ROOT_CAUSE state=% msg=% context=%',SQLSTATE,left(v_dbg_msg,300),left(v_dbg_context,140) USING ERRCODE=SQLSTATE;
END $m02_close$;
