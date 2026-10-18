-- PE10 M07 independent M+C method research. One checkpoint only, Train exact version.
DO $m07_train$
DECLARE
 v_exec text;v_raw text:=$m07_raw${
  "schema": "PE10_METHOD_RAW_V2",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M07",
  "base_code": "A",
  "algorithm_codes": [
    "M",
    "C"
  ],
  "source_cutoff": "2026-10-15T00:00:00Z",
  "original_preserved": {
    "ref": "chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M07.json",
    "sha256": "518a7e53245608950e5681a5cca655998ac8913dcec718918bf490495d8ea421"
  },
  "producer": "Single role-bound M+C SRCR investigator; source P0 only; no separate agent claims",
  "external_method_score": "NOT_PERFORMED",
  "sql_evidence": [
    {
      "id": "M07_Q01",
      "sql_literal": "SELECT id,created_at,payload->>'source_pack_version' source_pack,payload->>'sql_caller_count' declared_sql,payload->'historical_provenance_only' historical_notes FROM public.lf_eventos WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'",
      "rows": [
        {
          "id": 20161,
          "created_at": "2026-10-04 05:14:40.880842+00",
          "source_pack": "SOURCE_PACK_V1",
          "declared_sql": "38",
          "historical_notes": {
            "router_note": "Router binding snapshot observes readiness revision 5.12 while governed current readiness snapshot is 5.13; retained as provenance/currentness drift only.",
            "contract_note": "Older input contract rows remain recorded; caller usage is not inferred from their existence."
          }
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF"
    },
    {
      "id": "M07_Q02",
      "sql_literal": "SELECT count(*) total,count(*) FILTER(WHERE x->>'operational_class'='ACTIVE') t,count(*) FILTER(WHERE NOT(x->>'operational_class'='ACTIVE')) f,count(*) FILTER(WHERE (x->>'operational_class'='ACTIVE') IS NULL) n,count(DISTINCT x->>'dedupe_key') unique_callers FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161",
      "rows": [
        {
          "total": 38,
          "t": 38,
          "f": 0,
          "n": 0,
          "unique_callers": 38
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF"
    },
    {
      "id": "M07_Q03",
      "sql_literal": "SELECT count(*) total,count(*) FILTER(WHERE x->>'operational_class'='ACTIVE') t,count(*) FILTER(WHERE NOT(x->>'operational_class'='ACTIVE')) f,count(*) FILTER(WHERE (x->>'operational_class'='ACTIVE') IS NULL) n FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'external_inventory') x WHERE e.id=20161",
      "rows": [
        {
          "total": 6,
          "t": 3,
          "f": 3,
          "n": 0
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF"
    },
    {
      "id": "M07_Q04",
      "sql_literal": "SELECT count(*) total,count(*) FILTER(WHERE x->>'definition_md5'~'^[a-f0-9]{32}$') valid,count(*) FILTER(WHERE NOT(x->>'definition_md5'~'^[a-f0-9]{32}$')) invalid,count(*) FILTER(WHERE (x->>'definition_md5'~'^[a-f0-9]{32}$') IS NULL) unknown FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161",
      "rows": [
        {
          "total": 38,
          "valid": 38,
          "invalid": 0,
          "unknown": 0
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF"
    },
    {
      "id": "M07_Q05",
      "sql_literal": "SELECT count(*) edges,count(DISTINCT (x->>'caller')||'->'||c.name) distinct_edges,count(DISTINCT c.name) callee_names FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x CROSS JOIN LATERAL jsonb_array_elements_text(x->'callees') c(name) WHERE e.id=20161",
      "rows": [
        {
          "edges": 76,
          "distinct_edges": 76,
          "callee_names": 39
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF"
    },
    {
      "id": "M07_Q06",
      "sql_literal": "SELECT codigo,primera_vez,causa_raiz FROM transversal.error_knowledge WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001') AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z' ORDER BY codigo",
      "rows": [
        {
          "codigo": "IG-M107-CP2-READ-ROLE-CURRENTNESS-001",
          "primera_vez": "2026-10-14 23:44:24.874586+00",
          "causa_raiz": "Desalineación entre verificación CP2, autoridad histórica M9.11 y privilegios de lectura declarados."
        },
        {
          "codigo": "IG-M107-SOAK-CRITERION-DRIFT-001",
          "primera_vez": "2026-10-14 23:39:14.146551+00",
          "causa_raiz": "Desalineación de proyección textual del contrato M10.7 frente a la autoridad SOAK_OBSERVATION_HISTORY_V2 de M9.11."
        }
      ],
      "rows_returned": 2,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF"
    },
    {
      "id": "M07_Q07",
      "sql_literal": "SELECT id,created_at,receipt_kind,subject_ref,payload->>'verification_status' verified,payload->>'screens_total' screens,payload->>'families_total' families,payload->>'known_false_pass_signals' false_pass,payload->>'unresolved_d4' d4 FROM programacion.provenance_receipts WHERE id=38 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'",
      "rows": [
        {
          "id": 38,
          "created_at": "2026-10-07 16:01:00.760627+00",
          "receipt_kind": "EVIDENCE_VERIFICATION",
          "subject_ref": "plan://IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.11/SOAK_OBSERVATION_HISTORY_V2",
          "verified": "VERIFIED",
          "screens": "13",
          "families": "47",
          "false_pass": "0",
          "d4": "0"
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF"
    },
    {
      "id": "M07_Q08",
      "sql_literal": "WITH val(v) AS(VALUES('ACTIVE'::text),('OTHER'::text),(NULL::text)) SELECT count(*) total,count(*) FILTER(WHERE v='ACTIVE') t,count(*) FILTER(WHERE NOT(v='ACTIVE')) f,count(*) FILTER(WHERE (v='ACTIVE') IS NULL) n FROM val",
      "rows": [
        {
          "total": 3,
          "t": 1,
          "f": 1,
          "n": 1
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "SYNTHETIC_CONTRACT_NEGATIVE"
    },
    {
      "id": "M07_Q09",
      "sql_literal": "WITH tested(expected,observed) AS(VALUES(38,38),(38,40),(38,NULL::int)) SELECT expected,observed,(expected=observed) IS TRUE accepted FROM tested ORDER BY observed NULLS LAST",
      "rows": [
        {
          "expected": 38,
          "observed": 38,
          "accepted": true
        },
        {
          "expected": 38,
          "observed": 40,
          "accepted": false
        },
        {
          "expected": 38,
          "observed": null,
          "accepted": false
        }
      ],
      "rows_returned": 3,
      "source": "SUPABASE_READ_ONLY",
      "scope": "SYNTHETIC_CONTRACT_NEGATIVE"
    },
    {
      "id": "M07_Q10",
      "sql_literal": "SELECT jsonb_array_length(payload->'trigger_bindings') triggers,jsonb_array_length(payload->'edge_current') edge_snapshots,jsonb_array_length(payload->'external_inventory') external_assets,payload->'usage_stats' usage_stats FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "triggers": 21,
          "edge_snapshots": 4,
          "external_assets": 6,
          "usage_stats": {
            "ig_stat_rows": 0,
            "interpretation": "track_functions none means zero stat rows cannot prove no usage; static governed graph supplies inventory currentness",
            "track_functions": "none"
          }
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF"
    },
    {
      "id": "M07_Q11",
      "sql_literal": "SELECT count(*) FILTER(WHERE created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z') before_cutoff,count(*) FILTER(WHERE created_at>=TIMESTAMPTZ '2026-10-15T00:00:00Z') after_cutoff FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "before_cutoff": 1,
          "after_cutoff": 0
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF"
    },
    {
      "id": "M07_Q12",
      "sql_literal": "SELECT current_user principal,current_setting('transaction_read_only') read_only,current_setting('request.jwt.claim.role',true) jwt_role",
      "rows": [
        {
          "principal": "supabase_read_only_user",
          "read_only": "on",
          "jwt_role": null
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "QUERY_ROLE_ONLY"
    }
  ],
  "algorithm_execution": {
    "M": {
      "facts": [
        "EVENT20161",
        "SOAK38",
        "EKB2",
        "ASOF",
        "STATS_NONE"
      ],
      "rules": {
        "HIST_CALLERS": [
          [
            "EVENT20161",
            "ASOF"
          ]
        ],
        "HIST_SOAK": [
          [
            "SOAK38",
            "ASOF"
          ]
        ],
        "PRE_CUTOFF_RISKS": [
          [
            "EKB2",
            "ASOF"
          ]
        ],
        "NEED_CURRENT_READER": [
          [
            "HIST_CALLERS",
            "PRE_CUTOFF_RISKS"
          ]
        ],
        "NO_ZERO_USAGE": [
          [
            "EVENT20161",
            "STATS_NONE"
          ]
        ],
        "METHOD_RISK": [
          [
            "NEED_CURRENT_READER"
          ],
          [
            "HIST_SOAK",
            "EKB2"
          ]
        ]
      },
      "nogoods": [
        [
          "ASOF",
          "CLAIM_CURRENT"
        ],
        [
          "STATS_NONE",
          "CLAIM_ZERO_USAGE"
        ]
      ],
      "minimal_justifications": {
        "EVENT20161": [
          [
            "EVENT20161"
          ]
        ],
        "SOAK38": [
          [
            "SOAK38"
          ]
        ],
        "EKB2": [
          [
            "EKB2"
          ]
        ],
        "ASOF": [
          [
            "ASOF"
          ]
        ],
        "STATS_NONE": [
          [
            "STATS_NONE"
          ]
        ],
        "HIST_CALLERS": [
          [
            "ASOF",
            "EVENT20161"
          ]
        ],
        "HIST_SOAK": [
          [
            "ASOF",
            "SOAK38"
          ]
        ],
        "PRE_CUTOFF_RISKS": [
          [
            "ASOF",
            "EKB2"
          ]
        ],
        "NEED_CURRENT_READER": [
          [
            "ASOF",
            "EKB2",
            "EVENT20161"
          ]
        ],
        "NO_ZERO_USAGE": [
          [
            "EVENT20161",
            "STATS_NONE"
          ]
        ],
        "METHOD_RISK": [
          [
            "ASOF",
            "EKB2",
            "EVENT20161"
          ],
          [
            "ASOF",
            "EKB2",
            "SOAK38"
          ]
        ]
      },
      "counterfactuals": [
        {
          "removed": [
            "EVENT20161"
          ],
          "claim": "HIST_CALLERS",
          "expected": false,
          "test": "ATMS_1",
          "supported": false
        },
        {
          "removed": [
            "SOAK38"
          ],
          "claim": "HIST_SOAK",
          "expected": false,
          "test": "ATMS_2",
          "supported": false
        },
        {
          "removed": [
            "EKB2"
          ],
          "claim": "PRE_CUTOFF_RISKS",
          "expected": false,
          "test": "ATMS_3",
          "supported": false
        },
        {
          "removed": [
            "SOAK38"
          ],
          "claim": "METHOD_RISK",
          "expected": true,
          "test": "ATMS_4",
          "supported": true
        },
        {
          "removed": [
            "EVENT20161"
          ],
          "claim": "METHOD_RISK",
          "expected": true,
          "test": "ATMS_5",
          "supported": true
        },
        {
          "removed": [
            "EKB2"
          ],
          "claim": "METHOD_RISK",
          "expected": false,
          "test": "ATMS_6",
          "supported": false
        }
      ],
      "passed": 6
    },
    "C": {
      "three_valued_partitions": {
        "callers": {
          "total": 38,
          "t": 38,
          "f": 0,
          "n": 0,
          "unique_callers": 38
        },
        "external": {
          "total": 6,
          "t": 3,
          "f": 3,
          "n": 0
        },
        "hash": {
          "total": 38,
          "valid": 38,
          "invalid": 0,
          "unknown": 0
        },
        "synthetic": {
          "total": 3,
          "t": 1,
          "f": 1,
          "n": 1
        }
      },
      "positive_negative_contract_cases": [
        {
          "expected": 38,
          "observed": 38,
          "accepted": true
        },
        {
          "expected": 38,
          "observed": 40,
          "accepted": false
        },
        {
          "expected": 38,
          "observed": null,
          "accepted": false
        }
      ],
      "test_results": [
        {
          "id": "TLP_CALLERS",
          "pass": true
        },
        {
          "id": "TLP_EXTERNAL",
          "pass": true
        },
        {
          "id": "TLP_HASH",
          "pass": true
        },
        {
          "id": "TLP_SYNTHETIC_NULL",
          "pass": true
        },
        {
          "id": "VALID_CASE_ACCEPTED",
          "pass": true
        },
        {
          "id": "BAD_COUNT_REJECTED",
          "pass": true
        },
        {
          "id": "NULL_DENOMINATOR_REJECTED",
          "pass": true
        },
        {
          "id": "HIST_CUTOFF_RESTRICTED",
          "pass": true
        },
        {
          "id": "STATIC_GRAPH_NOT_RUNTIME",
          "pass": true
        },
        {
          "id": "ATMS_ALL_INVALS_PASS",
          "pass": true
        }
      ],
      "solver": "NOT_USED_NO_COMPATIBLE_SMT_AVAILABLE",
      "business_correctness": "NOT_PROVEN_BY_TLP"
    }
  },
  "findings": [
    {
      "id": "M07-F1",
      "claim": "ATMS P0 evidence removal changes historically supported claims; independent alternatives preserve METHOD_RISK without a single receipt or inventory",
      "evidence": [
        "M07_Q01",
        "M07_Q06",
        "M07_Q07"
      ],
      "type": "COMPUTED_EVIDENCE_DEPENDENCY"
    },
    {
      "id": "M07-F2",
      "claim": "Caller 38/38 and external 6/6 each reconcile with 3VL partitions; populations are not additive to unique consumer count",
      "evidence": [
        "M07_Q02",
        "M07_Q03"
      ],
      "type": "MEASURED_HISTORICAL"
    },
    {
      "id": "M07-F3",
      "claim": "Synthetic TRUE/FALSE/NULL and count invalidators exercise negative controls; this does not prove business policy",
      "evidence": [
        "M07_Q08",
        "M07_Q09"
      ],
      "type": "MEASURED_SYNTHETIC"
    },
    {
      "id": "M07-F4",
      "claim": "Nominal 76 directed edges and zero usage stats under track_functions none cannot certify executed calls or speed",
      "evidence": [
        "M07_Q05",
        "M07_Q10"
      ],
      "type": "MEASURED_LIMIT"
    },
    {
      "id": "M07-F5",
      "claim": "M9.11 receipt verified SOAK at source time, but no CP2 current reader status inferred",
      "evidence": [
        "M07_Q06",
        "M07_Q07"
      ],
      "type": "MEASURED_HISTORICAL"
    }
  ],
  "causal_model": {
    "status": "UNKNOWN",
    "hypotheses": [
      "Static/ASOF evidence promoted to live state",
      "Null/missing partitions masked during coverage",
      "Missing trace context mistaken for zero usage"
    ],
    "falsifiers": [
      "replay with time-qualified current source",
      "three-valued population reconciliation outside snapshot",
      "same-clock runtime traces"
    ]
  },
  "candidate_repairs": [
    {
      "action": "Maintain ATMS support invalidation for versioned evidence",
      "status": "PROPOSED"
    },
    {
      "action": "TLP contract partition gate before completeness claims",
      "status": "PROPOSED"
    }
  ],
  "chosen_repair": "VERIFY_FIRST_NO_PRODUCT_PATCH",
  "rejected_alternatives": [
    "Assume TLP engine equality proves business acceptance",
    "Invent solver proof",
    "Claim ATMS without actual withdrawal propagation"
  ],
  "unresolved": [
    "Canonical MD5 construction unknown",
    "Runtime call targets not measured",
    "Exact P0 CP2 permission state not re-executed"
  ],
  "constraints_preserved": [
    "read-only source",
    "as-of cutoff",
    "no runtime or grants",
    "no other methods as evidence"
  ],
  "conclusion": "M_PLUS_C_EXECUTED_EVIDENCE_DEPENDENCY_AND_METAMORPHIC_TESTS"
}
$m07_raw$;v_doc jsonb;v_blob text;
 v_ref text:='https://github.com/cristhianlujan/claude-persona-lf-patch/blob/aac9768b173aab7db21091685ee4b565821410b3/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M07_RAW_V2.json#git_blob_sha=000c1aebd6153c590f59b20ba59d1964f1c47ab1';v_prev text:='chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M07.json#sha256=518a7e53245608950e5681a5cca655998ac8913dcec718918bf490495d8ea421';
 v_spec jsonb:=$m07_spec${"status":"READY","action_kind":"VERIFY_QUERY_ONCE","recipe_mode":"READBACK_EXACT","requires_material_execution":true,"contract_family":"PE10_METHOD_EXECUTION_EVIDENCE","precision":"PE10_METHOD_V1_MATERIAL_EVIDENCE","assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"checkpoint_identity":"PE10_M07","method_algorithms":"M+C","literal_sql_count":12,"atms_counterfactuals_passed":6,"c_invariants_passed":10,"sql_caller_partition_total":38,"external_partition_total":6,"historical_source_event_id":20161,"git_source_verified":true,"runtime_modified":false}},"evidence_ref":"https://github.com/cristhianlujan/claude-persona-lf-patch/blob/aac9768b173aab7db21091685ee4b565821410b3/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M07_RAW_V2.json#git_blob_sha=000c1aebd6153c590f59b20ba59d1964f1c47ab1","verification_queries":["SELECT id,created_at,payload->>'source_pack_version' source_pack,payload->>'sql_caller_count' declared_sql,payload->'historical_provenance_only' historical_notes FROM public.lf_eventos WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'","SELECT count(*) total,count(*) FILTER(WHERE x->>'operational_class'='ACTIVE') t,count(*) FILTER(WHERE NOT(x->>'operational_class'='ACTIVE')) f,count(*) FILTER(WHERE (x->>'operational_class'='ACTIVE') IS NULL) n,count(DISTINCT x->>'dedupe_key') unique_callers FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161","SELECT count(*) total,count(*) FILTER(WHERE x->>'operational_class'='ACTIVE') t,count(*) FILTER(WHERE NOT(x->>'operational_class'='ACTIVE')) f,count(*) FILTER(WHERE (x->>'operational_class'='ACTIVE') IS NULL) n FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'external_inventory') x WHERE e.id=20161","SELECT codigo,primera_vez,causa_raiz FROM transversal.error_knowledge WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001') AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z' ORDER BY codigo","WITH val(v) AS(VALUES('ACTIVE'::text),('OTHER'::text),(NULL::text)) SELECT count(*) total,count(*) FILTER(WHERE v='ACTIVE') t,count(*) FILTER(WHERE NOT(v='ACTIVE')) f,count(*) FILTER(WHERE (v='ACTIVE') IS NULL) n FROM val","WITH tested(expected,observed) AS(VALUES(38,38),(38,40),(38,NULL::int)) SELECT expected,observed,(expected=observed) IS TRUE accepted FROM tested ORDER BY observed NULLS LAST"],"expected":"Executed ATMS withdrawal propagation and C TLP positive/negative/null checks, not business correction","forbidden":["TREAT_SOURCE_AS_CURRENT","SYNTHETIC_ATMS_NOT_EXECUTED","CLAIM_SMT","BYPASS_TRAIN","TOUCH_ADJACENT_METHODS"],"target":{"checkpoint":"PE10_M07","declared_events":[20161],"declared_objects":["public.lf_eventos","programacion.provenance_receipts","transversal.error_knowledge","programacion.engineering_work_checkpoints"],"evidence_artifacts":[{"path":"cristhianlujan/claude-persona-lf-patch:docs/profile_updater/experiments/pe10_methods32_p0/PE10_M07_RAW_V2.json","role":"EVIDENCE","purpose":"PE10_M07_M_C_REAL_METHOD_EXECUTION_RAW","target_kind":"EXACT_EXISTING_FILE"}]}}$m07_spec$::jsonb;
 v_q int;v_m int;v_c int;v_count int;v_ekb int;v_contract jsonb;
 v_obs jsonb;v_result jsonb;v_assertion jsonb;v_transition jsonb;v_receipt text;
 v_error text;v_context text;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
 AND target_code LIKE '%lf_pe10_m07_mc_governed_close_v1'
 AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'M07_TRAIN_EXECUTION_NOT_FOUND'; END IF;
 IF (SELECT status FROM programacion.engineering_work_items WHERE id=1133)<>'IN_PROGRESS'
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>6
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>26
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M07'
 AND status='PENDING' AND evidence_ref=v_prev AND assertion_receipt IS NULL AND completed_at IS NULL)<>1
 OR (SELECT count(*) FROM programacion.pe10_method_variants WHERE method_code='PE10_M07'
 AND case_ref='PE10-IG-M107-M109-P0' AND base_code='A'
 AND algorithm_codes=ARRAY['M','C']::text[])<>1
 OR (SELECT count(*) FROM programacion.engineering_plan_units WHERE work_item_id=1133
 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32'
 AND unit_metadata#>>'{action_specs_v1,PE10_M07,status}'='BLOCK_PENDING_MATERIAL_RESEARCH_AND_VALIDATION')<>1
 THEN RAISE EXCEPTION 'M07_PRESTATE_DRIFT'; END IF;

 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133
 AND checkpoint_code IN('PE10_M01','PE10_M02','PE10_M03','PE10_M04','PE10_M05','PE10_M06')
 AND status='DONE' AND assertion_receipt->>'passed'='true'
 AND assertion_contract_sha256=assertion_receipt->>'contract_sha256'
 AND assertion_receipt_sha256 IN(
 '1c174f3277f9656ffc4146c210ac64cd037fc92d4fb34d7a7959fe826e3f9b01',
 '0079973e1fec8787d2ef45d92131cad58bcb59f3c591aaf2badd8d86fe34c51b',
 '0cbbc9d58552b2c5ea3d2c9bca1b07c6467cd4145720905f38fc5bf07a46e2a1',
 '49ff7ae0d5966211ccb5a8caccc5718a61677c375a4a4a35c03e2bd6def7697e',
 '085c478b380e63908672c0382798750a9a075afc9b8fa21d0fa809db0684e90e',
 '4d5a9c761bc0171efa908e97d471cb1d372046b235274f141695d4665f1cc4cb'))<>6
 THEN RAISE EXCEPTION 'M07_PREDECESSOR_RECEIPTS_CHANGED'; END IF;

 v_blob:=encode(extensions.digest(convert_to('blob '||octet_length(convert_to(v_raw,'UTF8'))::text,'UTF8')
 ||decode('00','hex')||convert_to(v_raw,'UTF8'),'sha1'),'hex');
 IF v_blob<>'000c1aebd6153c590f59b20ba59d1964f1c47ab1' THEN RAISE EXCEPTION 'M07_RAW_BLOB_IDENTITY_FAILED'; END IF;
 v_doc:=v_raw::jsonb;
 IF v_doc->>'schema'<>'PE10_METHOD_RAW_V2'
 OR v_doc->>'case_ref'<>'PE10-IG-M107-M109-P0'
 OR v_doc->>'method_code'<>'PE10_M07'
 OR v_doc->>'base_code'<>'A'
 OR v_doc->'algorithm_codes'<>'["M","C"]'::jsonb
 OR v_doc->>'source_cutoff'<>'2026-10-15T00:00:00Z'
 OR v_doc#>>'{original_preserved,sha256}'<>'518a7e53245608950e5681a5cca655998ac8913dcec718918bf490495d8ea421'
 OR v_doc->>'external_method_score'<>'NOT_PERFORMED'
 OR v_doc->>'chosen_repair'<>'VERIFY_FIRST_NO_PRODUCT_PATCH'
 OR v_doc->>'conclusion'<>'M_PLUS_C_EXECUTED_EVIDENCE_DEPENDENCY_AND_METAMORPHIC_TESTS'
 THEN RAISE EXCEPTION 'M07_RAW_CONTRACT_IDENTITY_FAILED'; END IF;

 SELECT count(*) INTO v_q FROM jsonb_array_elements(v_doc->'sql_evidence') e
 WHERE e->>'id' ~ '^M07_Q(0[1-9]|1[0-2])$'
 AND e->>'sql_literal' ~* '^(SELECT|WITH) '
 AND e->>'source'='SUPABASE_READ_ONLY'
 AND jsonb_typeof(e->'rows')='array'
 AND (e->>'rows_returned')::int=jsonb_array_length(e->'rows')
 AND jsonb_array_length(e->'rows')>0;
 IF v_q<>12 OR jsonb_array_length(v_doc->'sql_evidence')<>12
 OR (SELECT count(DISTINCT e->>'id') FROM jsonb_array_elements(v_doc->'sql_evidence') e)<>12
 OR v_doc#>>'{sql_evidence,1,rows,0,total}'<>'38'
 OR v_doc#>>'{sql_evidence,2,rows,0,total}'<>'6'
 OR v_doc#>>'{sql_evidence,4,rows,0,edges}'<>'76'
 OR v_doc#>>'{sql_evidence,6,rows,0,verified}'<>'VERIFIED'
 OR v_doc#>>'{sql_evidence,7,rows,0,n}'<>'1'
 THEN RAISE EXCEPTION 'M07_SQL_READBACK_EVIDENCE_FAIL'; END IF;

 SELECT count(*) INTO v_m FROM jsonb_array_elements(v_doc#>'{algorithm_execution,M,counterfactuals}') c
 WHERE c->'expected'=c->'supported';
 SELECT count(*) INTO v_c FROM jsonb_array_elements(v_doc#>'{algorithm_execution,C,test_results}') t
 WHERE t->>'pass'='true';
 IF v_m<>6 OR jsonb_array_length(v_doc#>'{algorithm_execution,M,counterfactuals}')<>6
 OR v_c<>10 OR jsonb_array_length(v_doc#>'{algorithm_execution,C,test_results}')<>10
 OR v_doc#>>'{algorithm_execution,M,passed}'<>'6'
 OR v_doc#>>'{algorithm_execution,C,three_valued_partitions,callers,total}'<>'38'
 OR v_doc#>>'{algorithm_execution,C,three_valued_partitions,external,total}'<>'6'
 OR v_doc#>>'{algorithm_execution,C,three_valued_partitions,synthetic,n}'<>'1'
 OR v_doc#>>'{algorithm_execution,C,solver}'<>'NOT_USED_NO_COMPATIBLE_SMT_AVAILABLE'
 OR jsonb_array_length(v_doc#>'{algorithm_execution,C,positive_negative_contract_cases}')<>3
 THEN RAISE EXCEPTION 'M07_ATMS_OR_C_NEGATIVES_NOT_ATTESTED'; END IF;

 SELECT count(*) INTO v_ekb FROM transversal.error_knowledge
 WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001')
 AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z';
 IF v_ekb<>2
 OR (SELECT count(*) FROM public.lf_eventos WHERE id=20161
 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'
 AND jsonb_array_length(payload->'sql_callers')=38
 AND payload->'usage_stats'->>'track_functions'='none')<>1
 OR (SELECT count(*) FROM programacion.provenance_receipts WHERE id=38
 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'
 AND payload->>'verification_status'='VERIFIED')<>1
 THEN RAISE EXCEPTION 'M07_SOURCE_P0_READBACK_CHANGED'; END IF;

 UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10_M07}',v_spec,true)
 WHERE work_item_id=1133 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32';
 GET DIAGNOSTICS v_count=ROW_COUNT;
 IF v_count<>1 THEN RAISE EXCEPTION 'M07_UNIT_SPEC_UPDATE_COUNT'; END IF;
 v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M07',
 programacion.fn_engineering_checkpoint_action_spec_v3('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M07'));
 IF v_contract->>'status'<>'READY' OR v_contract->>'mode'<>'EXPLICIT_PASS_WHEN_SUBSET'
 THEN RAISE EXCEPTION 'M07_ASSERTION_SPEC_NOT_READY:%',coalesce(v_contract::text,'null'); END IF;
 v_obs:=jsonb_build_object('checkpoint_identity','PE10_M07','method_algorithms','M+C',
 'literal_sql_count',12,'atms_counterfactuals_passed',6,'c_invariants_passed',10,
 'sql_caller_partition_total',38,'external_partition_total',6,
 'historical_source_event_id',20161,'git_source_verified',true,'runtime_modified',false);
 v_result:=jsonb_build_object('status','PASS','observed',v_obs,'evidence_ref',v_ref,
 'validation_kind','METHOD_M_C_MATERIAL_EVIDENCE_NO_PRODUCT_REPAIR',
 'external_scoring','NOT_PERFORMED');
 v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M07',v_result,v_exec);
 IF v_assertion->>'passed'<>'true'
 OR coalesce(v_assertion->>'assertion_receipt_sha256','') !~ '^[a-f0-9]{64}$'
 THEN RAISE EXCEPTION 'M07_CANONICAL_ASSERTION_NOT_PASSED'; END IF;
 v_receipt:=v_assertion->>'assertion_receipt_sha256';
 v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M07','DONE',v_ref,v_exec,
 'M07 ATMS M+C three-valued counterexamples verified; original case untouched');
 IF v_transition#>>'{transition,status}'<>'APPLIED'
 THEN RAISE EXCEPTION 'M07_DONE_CANONICAL_TRANSITION_FAILED'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=1133 AND checkpoint_code='PE10_M07'
 AND status='DONE' AND completed_at IS NOT NULL AND evidence_ref=v_ref
 AND assertion_receipt_sha256=v_receipt
 AND assertion_contract_sha256=assertion_receipt->>'contract_sha256'
 AND assertion_receipt->>'passed'='true')<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>7
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>25
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M08' AND status='PENDING')<>1
 THEN RAISE EXCEPTION 'M07_POSTTRAIN_RECONCILIATION_BAD'; END IF;
EXCEPTION WHEN OTHERS THEN
 GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT,v_context=PG_EXCEPTION_CONTEXT;
 RAISE EXCEPTION 'M07_TRAIN_CLOSE_ROOT state=% msg=% context=%',SQLSTATE,left(v_error,300),left(v_context,160) USING ERRCODE=SQLSTATE;
END $m07_train$;
