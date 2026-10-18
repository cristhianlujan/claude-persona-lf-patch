-- PE10 M06: individual D+C evidence-only method closure. No product changes.
DO $m06_governed_close$
DECLARE
 v_exec text; v_raw text:=$m06_raw${
  "schema": "PE10_METHOD_RAW_V2",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M06",
  "base_code": "A",
  "algorithm_codes": [
    "D",
    "C"
  ],
  "source_cutoff": "2026-10-15T00:00:00Z",
  "original_preserved": {
    "ref": "chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M06.json",
    "sha256": "21d4e22c04f2f5b1dee4216807f9466a4a55fbf49d91e174f440d7e76280b5d4"
  },
  "producer": "Single SRCR/GDE+C method-specific investigation, no later method outputs used as source",
  "source_mode": "READ_ONLY_HISTORICAL_AND_SYNTHETIC_CONTRACT_PROBES",
  "external_evaluation": "NOT_PERFORMED",
  "sql_evidence": [
    {
      "id": "M06_Q01",
      "sql_literal": "SELECT id,created_at,payload->>'source_pack_version' source_pack,payload->>'sql_caller_count' declared_sql,payload->>'trigger_binding_count' declared_trigger,payload->'usage_stats' usage_stats FROM public.lf_eventos WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'",
      "rows": [
        {
          "id": 20161,
          "created_at": "2026-10-04 05:14:40.880842+00",
          "source_pack": "SOURCE_PACK_V1",
          "declared_sql": "38",
          "declared_trigger": "21",
          "usage_stats": {
            "ig_stat_rows": 0,
            "interpretation": "track_functions none means zero stat rows cannot prove no usage; static governed graph supplies inventory currentness",
            "track_functions": "none"
          }
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF_PRE_P0"
    },
    {
      "id": "M06_Q02",
      "sql_literal": "SELECT count(*) total,count(*) FILTER(WHERE x->>'operational_class'='ACTIVE') t,count(*) FILTER(WHERE NOT(x->>'operational_class'='ACTIVE')) f,count(*) FILTER(WHERE (x->>'operational_class'='ACTIVE') IS NULL) n,count(DISTINCT x->>'dedupe_key') distinct_callers FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161",
      "rows": [
        {
          "total": 38,
          "t": 38,
          "f": 0,
          "n": 0,
          "distinct_callers": 38
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF_PRE_P0"
    },
    {
      "id": "M06_Q03",
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
      "scope": "HISTORICAL_SOURCE_ASOF_PRE_P0"
    },
    {
      "id": "M06_Q04",
      "sql_literal": "SELECT count(*) total,count(*) FILTER(WHERE x->>'definition_md5' ~ '^[a-f0-9]{32}$') t,count(*) FILTER(WHERE NOT(x->>'definition_md5' ~ '^[a-f0-9]{32}$')) f,count(*) FILTER(WHERE (x->>'definition_md5' ~ '^[a-f0-9]{32}$') IS NULL) n FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161",
      "rows": [
        {
          "total": 38,
          "t": 38,
          "f": 0,
          "n": 0
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF_PRE_P0"
    },
    {
      "id": "M06_Q05",
      "sql_literal": "SELECT count(*) edges,count(DISTINCT (x->>'caller')||'->'||c.name) distinct_edges,count(DISTINCT c.name) target_labels FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x CROSS JOIN LATERAL jsonb_array_elements_text(x->'callees') c(name) WHERE e.id=20161",
      "rows": [
        {
          "edges": 76,
          "distinct_edges": 76,
          "target_labels": 39
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF_PRE_P0"
    },
    {
      "id": "M06_Q06",
      "sql_literal": "SELECT codigo,primera_vez,causa_raiz,prevencion FROM transversal.error_knowledge WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001') AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z' ORDER BY codigo",
      "rows": [
        {
          "codigo": "IG-M107-CP2-READ-ROLE-CURRENTNESS-001",
          "primera_vez": "2026-10-14 23:44:24.874586+00",
          "causa_raiz": "Desalineación entre verificación CP2, autoridad histórica M9.11 y privilegios de lectura declarados.",
          "prevencion": "Leer EKB y action_spec. No elevar EXECUTE ni crear motor. Reusar recibo verificado SOAK_OBSERVATION_HISTORY_V2 y revisar la cohorte mediante tablas con SELECT autorizado. Considerar recuentos brutos como evidencia complementaria, nunca sustituto de as-of. Rectificar únicamente queries CP2."
        },
        {
          "codigo": "IG-M107-SOAK-CRITERION-DRIFT-001",
          "primera_vez": "2026-10-14 23:39:14.146551+00",
          "causa_raiz": "Desalineación de proyección textual del contrato M10.7 frente a la autoridad SOAK_OBSERVATION_HISTORY_V2 de M9.11.",
          "prevencion": "Antes de CP1 leer M9.11 DONE y el recibo VERIFIED; heredar >=2 as-of, 0 falsos PASS y 0 D4. Reusar historia. No convertir 13/47 en obligación de nuevas corridas ni confundir latest CURRENT con validez histórica. Confirmar los checkpoints posteriores por su naturaleza."
        }
      ],
      "rows_returned": 2,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF_PRE_P0"
    },
    {
      "id": "M06_Q07",
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
      "scope": "HISTORICAL_SOURCE_ASOF_PRE_P0"
    },
    {
      "id": "M06_Q08",
      "sql_literal": "WITH v(x) AS(VALUES('ACTIVE'::text),('CANDIDATE'::text),(NULL::text)) SELECT count(*) total,count(*) FILTER(WHERE x='ACTIVE') t,count(*) FILTER(WHERE NOT(x='ACTIVE')) f,count(*) FILTER(WHERE (x='ACTIVE') IS NULL) n FROM v",
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
      "scope": "EXPLICIT_SYNTHETIC_NEGATIVE_TEST"
    },
    {
      "id": "M06_Q09",
      "sql_literal": "WITH cases(declared,observed) AS(VALUES(38,38),(38,39),(38,NULL::int)) SELECT declared,observed, (declared=observed) IS TRUE accepted FROM cases ORDER BY observed NULLS LAST",
      "rows": [
        {
          "declared": 38,
          "observed": 38,
          "accepted": true
        },
        {
          "declared": 38,
          "observed": 39,
          "accepted": false
        },
        {
          "declared": 38,
          "observed": null,
          "accepted": false
        }
      ],
      "rows_returned": 3,
      "source": "SUPABASE_READ_ONLY",
      "scope": "EXPLICIT_SYNTHETIC_NEGATIVE_TEST"
    },
    {
      "id": "M06_Q10",
      "sql_literal": "SELECT payload->'scope_guards' source_guards,payload->'excluded_name_candidate' excluded,payload->'deduplication' deduplication FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "source_guards": {
            "callers_retired": false,
            "m10_10_executed": false,
            "callers_modified": false,
            "production_change": false,
            "runtime_activation": false,
            "n13_n14_n15_changed": false
          },
          "excluded": {
            "object": "lf-profile-creator-governance-caller-v1",
            "reason": "Current caller.ts invokes configured LF_PROFILE_CREATOR_RUNTIME_SLUG/default run-creacion-perfil-lf and contains no IG call; name/existence is not usage evidence.",
            "sha256": "27594e559e752587c5644463efc67fb9be245319b856766d85435431325cf6ee",
            "version": 16,
            "edge_marker": "ACTIVE",
            "classification": "NOT_IG_CALLER",
            "verified_target": "run-creacion-perfil-lf"
          },
          "deduplication": {
            "rule": "One logical caller identity per source URI/object identity; evidence from multiple governed sources is merged instead of double-counted.",
            "router_identity": "PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1 maps to live SQL lf_ops.fn_lf_router_input_governance_resolve_v1.",
            "profiles_edge_identity": "EDGE_FN_LF_PROFILES_GOVERNANCE_CALLER_V1 maps to live Edge lf-profiles-governance-caller-v1."
          }
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF_PRE_P0"
    },
    {
      "id": "M06_Q11",
      "sql_literal": "SELECT jsonb_array_length(payload->'edge_current') edge_entries,jsonb_array_length(payload->'trigger_bindings') triggers,jsonb_array_length(payload->'external_inventory') externals,jsonb_array_length(payload->'consumer_relation_snapshot_json_rows') relations FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "edge_entries": 4,
          "triggers": 21,
          "externals": 6,
          "relations": 27
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF_PRE_P0"
    },
    {
      "id": "M06_Q12",
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
      "scope": "TOOL_PRINCIPAL_ONLY"
    }
  ],
  "algorithm_execution": {
    "D": {
      "conflict_sets": [
        [
          "SOAK_PROJECTION_CONTRACT",
          "SOAK_RECEIPT_CONTEXT"
        ],
        [
          "CP2_PRIVILEGE_ROUTE",
          "CP2_CURRENTNESS_ROUTE"
        ],
        [
          "STATIC_EDGE_INTERPRETATION",
          "RUNTIME_USAGE_STATS_DISABLED"
        ]
      ],
      "minimal_hitting_sets": [
        [
          "SOAK_PROJECTION_CONTRACT",
          "CP2_PRIVILEGE_ROUTE",
          "STATIC_EDGE_INTERPRETATION"
        ],
        [
          "SOAK_RECEIPT_CONTEXT",
          "CP2_PRIVILEGE_ROUTE",
          "STATIC_EDGE_INTERPRETATION"
        ],
        [
          "SOAK_PROJECTION_CONTRACT",
          "CP2_CURRENTNESS_ROUTE",
          "STATIC_EDGE_INTERPRETATION"
        ],
        [
          "SOAK_RECEIPT_CONTEXT",
          "CP2_CURRENTNESS_ROUTE",
          "STATIC_EDGE_INTERPRETATION"
        ],
        [
          "SOAK_PROJECTION_CONTRACT",
          "CP2_PRIVILEGE_ROUTE",
          "RUNTIME_USAGE_STATS_DISABLED"
        ],
        [
          "SOAK_RECEIPT_CONTEXT",
          "CP2_PRIVILEGE_ROUTE",
          "RUNTIME_USAGE_STATS_DISABLED"
        ],
        [
          "SOAK_PROJECTION_CONTRACT",
          "CP2_CURRENTNESS_ROUTE",
          "RUNTIME_USAGE_STATS_DISABLED"
        ],
        [
          "SOAK_RECEIPT_CONTEXT",
          "CP2_CURRENTNESS_ROUTE",
          "RUNTIME_USAGE_STATS_DISABLED"
        ]
      ],
      "enumerated_hitting_sets": 27,
      "scope": "Hypothesis minimal hitting sets, not confirmed causal fixes",
      "barinel": "NOT_CALIBRATABLE_NO_EXECUTION_SPECTRA",
      "information_gain": "ORDINAL_DISCRIMINATION_ONLY"
    },
    "C": {
      "tlp_populations": {
        "callers": {
          "total": 38,
          "t": 38,
          "f": 0,
          "n": 0,
          "distinct_callers": 38
        },
        "external": {
          "total": 6,
          "t": 3,
          "f": 3,
          "n": 0
        },
        "hashes": {
          "total": 38,
          "t": 38,
          "f": 0,
          "n": 0
        },
        "synthetic": {
          "total": 3,
          "t": 1,
          "f": 1,
          "n": 1
        }
      },
      "contract_cases": [
        {
          "declared": 38,
          "observed": 38,
          "accepted": true
        },
        {
          "declared": 38,
          "observed": 39,
          "accepted": false
        },
        {
          "declared": 38,
          "observed": null,
          "accepted": false
        }
      ],
      "invalid_cases_rejected": 2,
      "supports_business_rule_correctness": false,
      "solver": "NOT_RUN_NO_SUPPORTED_SMT_ENGINE"
    }
  },
  "negative_tests": [
    {
      "id": "TLP_38_CALLERS",
      "pass": true
    },
    {
      "id": "TLP_6_EXTERNALS",
      "pass": true
    },
    {
      "id": "TLP_HASH_VALID_NULL_FALSE",
      "pass": true
    },
    {
      "id": "TLP_SYNTHETIC_NULL_EXERCIZED",
      "pass": true
    },
    {
      "id": "CONTRACT_COUNT_VALID_ACCEPT",
      "pass": true
    },
    {
      "id": "CONTRACT_COUNT_MISMATCH_REJECT",
      "pass": true
    },
    {
      "id": "CONTRACT_COUNT_NULL_REJECT",
      "pass": true
    },
    {
      "id": "GDE_EIGHT_MINIMAL_TRIPLETS",
      "pass": true
    },
    {
      "id": "GDE_STRICT_SUBSET_NOT_HITTING",
      "pass": true
    },
    {
      "id": "C_NO_SMT_CLAIM",
      "pass": true
    },
    {
      "id": "D_NO_BARINEL_CALIBRATION_WITHOUT_SPECTRA",
      "pass": true
    },
    {
      "id": "HISTORICAL_RECEIPT_EXISTS",
      "pass": true
    },
    {
      "id": "STATIC_GRAPH_NOT_LIVE_USAGE",
      "pass": true
    }
  ],
  "findings": [
    {
      "id": "M06-F01",
      "claim": "Historical SQL caller identities reconcile 38/38 with an exact 3VL partition and no missing dedup keys",
      "evidence": [
        "M06_Q01",
        "M06_Q02"
      ],
      "scope": "MEASURED_ASOF"
    },
    {
      "id": "M06-F02",
      "claim": "Six external assets partition separately, so they cannot be added to 38 SQL callers without canonical identity mapping",
      "evidence": [
        "M06_Q03",
        "M06_Q11"
      ],
      "scope": "MEASURED_ASOF"
    },
    {
      "id": "M06-F03",
      "claim": "Four diagnostic axes (SOAK, CP2, static edges, usage stats) contain three modeled conflicts yielding eight minimal GDE hitting sets, not a proven repair",
      "evidence": [
        "M06_Q01",
        "M06_Q05",
        "M06_Q06",
        "M06_Q07"
      ],
      "scope": "COMPUTED_HYPOTHESIS"
    },
    {
      "id": "M06-F04",
      "claim": "Positive, mismatch and NULL count checks demonstrate fail-closed guards on synthetic examples; none prove business completeness",
      "evidence": [
        "M06_Q08",
        "M06_Q09"
      ],
      "scope": "MEASURED_SYNTHETIC"
    },
    {
      "id": "M06-F05",
      "claim": "Receipt 38 VERIFIED source P0 and 42501 EKB do not establish performance or functional fail",
      "evidence": [
        "M06_Q06",
        "M06_Q07"
      ],
      "scope": "MEASURED_HISTORICAL"
    }
  ],
  "causal_model": {
    "proven": false,
    "alternatives": [
      "SOAK projection versus qualified historical receipt context",
      "CP2 permission versus currentness drift",
      "Static reference graph versus observed runtime traces"
    ],
    "falsifiers": [
      "Qualified same-clock readback",
      "Source identity route through authorized provider",
      "Actual comparable runtime traces and E2E clocks"
    ]
  },
  "candidate_repairs": [
    {
      "action": "Normalize source-time SQL/external identity and 3VL partitions",
      "status": "PROPOSAL"
    },
    {
      "action": "Use authorized source-pinned SOAK and CP2 receipts before declaring currentness",
      "status": "PROPOSAL"
    }
  ],
  "chosen_repair": "VERIFY_FIRST_NO_RUNTIME_CHANGE",
  "rejected_alternatives": [
    "Treat one GDE candidate set as root cause",
    "Invent BARINEL calibration or SMT solver",
    "Treat null as valid positive",
    "Assume nominal edge means executed"
  ],
  "omissions_searched": [
    "pre-cutoff evidence",
    "duplicate identities",
    "three-valued NULL",
    "valid and invalid count guards",
    "GDE minimality",
    "soak receipt",
    "authority & timing"
  ],
  "unresolved": [
    "No defect root identified",
    "No full canonical MD5 generation method",
    "No runtime performance timing",
    "No authorized current CP2 read at source cutoff"
  ],
  "constraints_preserved": [
    "No prod mutation",
    "No RLS/EXECUTE escalation",
    "P0 source-only",
    "One method per checkpoint",
    "No method score"
  ],
  "conclusion": "D_PLUS_C_RESEARCH_EXECUTED_WITH_MATERIAL_TESTS_AND_UNRESOLVED_CAUSALITY"
}
$m06_raw$;v_doc jsonb;v_blob text;
 v_ref text:='https://github.com/cristhianlujan/claude-persona-lf-patch/blob/794cb73f5adf15113a908b553864b19046ffcd02/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M06_RAW_V2.json#git_blob_sha=671845d5a05321d9effbf0b23b80cce3e2c74104';v_prev text:='chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M06.json#sha256=21d4e22c04f2f5b1dee4216807f9466a4a55fbf49d91e174f440d7e76280b5d4';
 v_spec jsonb:=$m06_spec${"status":"READY","action_kind":"VERIFY_QUERY_ONCE","recipe_mode":"READBACK_EXACT","requires_material_execution":true,"contract_family":"PE10_METHOD_EXECUTION_EVIDENCE","precision":"PE10_METHOD_V1_MATERIAL_EVIDENCE","assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"checkpoint_identity":"PE10_M06","method_algorithms":"D+C","literal_sql_count":12,"gde_minimal_hitting_sets":8,"metamorphic_negative_checks_passed":13,"tlp_total_sql_callers":38,"tlp_total_external":6,"historical_source_event_id":20161,"git_source_verified":true,"runtime_modified":false}},"evidence_ref":"https://github.com/cristhianlujan/claude-persona-lf-patch/blob/794cb73f5adf15113a908b553864b19046ffcd02/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M06_RAW_V2.json#git_blob_sha=671845d5a05321d9effbf0b23b80cce3e2c74104","verification_queries":["SELECT id,created_at,payload->>'source_pack_version' source_pack,payload->>'sql_caller_count' declared_sql,payload->>'trigger_binding_count' declared_trigger,payload->'usage_stats' usage_stats FROM public.lf_eventos WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'","SELECT count(*) total,count(*) FILTER(WHERE x->>'operational_class'='ACTIVE') t,count(*) FILTER(WHERE NOT(x->>'operational_class'='ACTIVE')) f,count(*) FILTER(WHERE (x->>'operational_class'='ACTIVE') IS NULL) n,count(DISTINCT x->>'dedupe_key') distinct_callers FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161","SELECT count(*) total,count(*) FILTER(WHERE x->>'operational_class'='ACTIVE') t,count(*) FILTER(WHERE NOT(x->>'operational_class'='ACTIVE')) f,count(*) FILTER(WHERE (x->>'operational_class'='ACTIVE') IS NULL) n FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'external_inventory') x WHERE e.id=20161","SELECT codigo,primera_vez,causa_raiz,prevencion FROM transversal.error_knowledge WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001') AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z' ORDER BY codigo","WITH v(x) AS(VALUES('ACTIVE'::text),('CANDIDATE'::text),(NULL::text)) SELECT count(*) total,count(*) FILTER(WHERE x='ACTIVE') t,count(*) FILTER(WHERE NOT(x='ACTIVE')) f,count(*) FILTER(WHERE (x='ACTIVE') IS NULL) n FROM v","WITH cases(declared,observed) AS(VALUES(38,38),(38,39),(38,NULL::int)) SELECT declared,observed, (declared=observed) IS TRUE accepted FROM cases ORDER BY observed NULLS LAST"],"expected":"Method-specific combined GDE minimal hypotheses plus C 3VL metamorphic/contract counterexamples; no BARINEL/SMT or operational repair claim","forbidden":["MARK_FROM_HASH_ALONE","TREAT_GDE_AS_PROVEN_PATCH","CLAIM_BARINEL_OR_SMT_EXECUTED","PATCH_OTHER_CHECKPOINTS","PROMOTE_HISTORICAL_TO_CURRENT"],"target":{"checkpoint":"PE10_M06","declared_events":[20161],"declared_objects":["public.lf_eventos","programacion.provenance_receipts","transversal.error_knowledge","programacion.engineering_work_checkpoints"],"evidence_artifacts":[{"path":"cristhianlujan/claude-persona-lf-patch:docs/profile_updater/experiments/pe10_methods32_p0/PE10_M06_RAW_V2.json","role":"EVIDENCE","purpose":"M06_D_C_ALGORITHMS_EXECUTED_RAW","target_kind":"EXACT_EXISTING_FILE"}]}}$m06_spec$::jsonb;
 v_count int;v_test_count int;v_gde_count int;v_ekb_count int;v_receipt text;
 v_contract jsonb;v_obs jsonb;v_result jsonb;v_assertion jsonb;v_transition jsonb;
 v_error text;v_context text;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
 AND target_code LIKE '%lf_pe10_m06_dc_governed_close_v1'
 AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'M06_TRAIN_EXECUTION_NOT_PRESENT'; END IF;
 IF (SELECT status FROM programacion.engineering_work_items WHERE id=1133)<>'IN_PROGRESS'
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>5
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>27
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M06' AND status='PENDING'
 AND evidence_ref=v_prev AND assertion_receipt IS NULL AND completed_at IS NULL)<>1
 OR (SELECT count(*) FROM programacion.pe10_method_variants WHERE method_code='PE10_M06'
 AND base_code='A' AND case_ref='PE10-IG-M107-M109-P0'
 AND algorithm_codes=ARRAY['D','C']::text[])<>1
 OR (SELECT count(*) FROM programacion.engineering_plan_units WHERE work_item_id=1133
 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32'
 AND unit_metadata#>>'{action_specs_v1,PE10_M06,status}'='BLOCK_PENDING_MATERIAL_RESEARCH_AND_VALIDATION')<>1
 THEN RAISE EXCEPTION 'M06_PRESTATE_DRIFT'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133
 AND checkpoint_code IN('PE10_M01','PE10_M02','PE10_M03','PE10_M04','PE10_M05')
 AND status='DONE' AND assertion_receipt->>'passed'='true'
 AND assertion_receipt_sha256 ~ '^[a-f0-9]{64}$'
 AND assertion_contract_sha256=assertion_receipt->>'contract_sha256'
 AND assertion_receipt_sha256 IN (
 '1c174f3277f9656ffc4146c210ac64cd037fc92d4fb34d7a7959fe826e3f9b01',
 '0079973e1fec8787d2ef45d92131cad58bcb59f3c591aaf2badd8d86fe34c51b',
 '0cbbc9d58552b2c5ea3d2c9bca1b07c6467cd4145720905f38fc5bf07a46e2a1',
 '49ff7ae0d5966211ccb5a8caccc5718a61677c375a4a4a35c03e2bd6def7697e',
 '085c478b380e63908672c0382798750a9a075afc9b8fa21d0fa809db0684e90e'))<>5
 THEN RAISE EXCEPTION 'M06_PREVIOUS_RECEIPTS_DRIFT'; END IF;

 v_blob:=encode(extensions.digest(convert_to('blob '||octet_length(convert_to(v_raw,'UTF8'))::text,'UTF8')
 ||decode('00','hex')||convert_to(v_raw,'UTF8'),'sha1'),'hex');
 IF v_blob<>'671845d5a05321d9effbf0b23b80cce3e2c74104' THEN RAISE EXCEPTION 'M06_SOURCE_GIT_BLOB_IDENTITY_FAIL'; END IF;
 v_doc:=v_raw::jsonb;
 IF v_doc->>'schema'<>'PE10_METHOD_RAW_V2'
 OR v_doc->>'method_code'<>'PE10_M06'
 OR v_doc->>'case_ref'<>'PE10-IG-M107-M109-P0'
 OR v_doc->>'base_code'<>'A'
 OR v_doc->'algorithm_codes'<>'["D","C"]'::jsonb
 OR v_doc->>'source_cutoff'<>'2026-10-15T00:00:00Z'
 OR v_doc#>>'{original_preserved,sha256}'<>'21d4e22c04f2f5b1dee4216807f9466a4a55fbf49d91e174f440d7e76280b5d4'
 OR v_doc->>'external_evaluation'<>'NOT_PERFORMED'
 OR v_doc->>'chosen_repair'<>'VERIFY_FIRST_NO_RUNTIME_CHANGE'
 OR v_doc->>'conclusion'<>'D_PLUS_C_RESEARCH_EXECUTED_WITH_MATERIAL_TESTS_AND_UNRESOLVED_CAUSALITY'
 THEN RAISE EXCEPTION 'M06_METHOD_ID_OR_SCOPE_BAD'; END IF;

 SELECT count(*) INTO v_count FROM jsonb_array_elements(v_doc->'sql_evidence') e
 WHERE e->>'sql_literal' ~* '^(SELECT|WITH) ' AND e->>'id' ~ '^M06_Q(0[1-9]|1[0-2])$'
 AND e->>'source'='SUPABASE_READ_ONLY'
 AND jsonb_typeof(e->'rows')='array'
 AND (e->>'rows_returned')::int=jsonb_array_length(e->'rows')
 AND jsonb_array_length(e->'rows')>0;
 IF v_count<>12 OR jsonb_array_length(v_doc->'sql_evidence')<>12
 OR (SELECT count(DISTINCT e->>'id') FROM jsonb_array_elements(v_doc->'sql_evidence') e)<>12
 OR v_doc#>>'{sql_evidence,1,rows,0,total}'<>'38'
 OR v_doc#>>'{sql_evidence,2,rows,0,total}'<>'6'
 OR v_doc#>>'{sql_evidence,4,rows,0,edges}'<>'76'
 OR v_doc#>>'{sql_evidence,7,rows,0,n}'<>'1'
 OR v_doc#>>'{sql_evidence,6,rows,0,verified}'<>'VERIFIED'
 THEN RAISE EXCEPTION 'M06_SQL_READBACK_MISSING_OR_CONTRADICTED'; END IF;
 SELECT count(*) INTO v_gde_count FROM jsonb_array_elements(v_doc#>'{algorithm_execution,D,minimal_hitting_sets}') x
 WHERE jsonb_array_length(x)=3
 AND (x ? 'SOAK_PROJECTION_CONTRACT' OR x ? 'SOAK_RECEIPT_CONTEXT')
 AND (x ? 'CP2_PRIVILEGE_ROUTE' OR x ? 'CP2_CURRENTNESS_ROUTE')
 AND (x ? 'STATIC_EDGE_INTERPRETATION' OR x ? 'RUNTIME_USAGE_STATS_DISABLED');
 SELECT count(*) INTO v_test_count FROM jsonb_array_elements(v_doc->'negative_tests') x
 WHERE x->>'pass'='true';
 IF v_gde_count<>8 OR jsonb_array_length(v_doc#>'{algorithm_execution,D,minimal_hitting_sets}')<>8
 OR v_test_count<>13 OR jsonb_array_length(v_doc->'negative_tests')<>13
 OR v_doc#>>'{algorithm_execution,D,barinel}'<>'NOT_CALIBRATABLE_NO_EXECUTION_SPECTRA'
 OR v_doc#>>'{algorithm_execution,D,information_gain}'<>'ORDINAL_DISCRIMINATION_ONLY'
 OR v_doc#>>'{algorithm_execution,C,solver}'<>'NOT_RUN_NO_SUPPORTED_SMT_ENGINE'
 OR v_doc#>>'{algorithm_execution,C,tlp_populations,callers,total}'<>'38'
 OR v_doc#>>'{algorithm_execution,C,tlp_populations,external,total}'<>'6'
 OR v_doc#>>'{algorithm_execution,C,tlp_populations,synthetic,n}'<>'1'
 OR jsonb_array_length(v_doc#>'{algorithm_execution,C,contract_cases}')<>3
 THEN RAISE EXCEPTION 'M06_GDE_C_INVARIANT_NEGATIVES_INCOMPLETE'; END IF;

 SELECT count(*) INTO v_ekb_count FROM transversal.error_knowledge WHERE codigo IN
 ('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001')
 AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z';
 IF v_ekb_count<>2
 OR (SELECT count(*) FROM public.lf_eventos WHERE id=20161
 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'
 AND jsonb_array_length(payload->'sql_callers')=38
 AND payload->'usage_stats'->>'track_functions'='none')<>1
 OR (SELECT count(*) FROM programacion.provenance_receipts WHERE id=38
 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'
 AND payload->>'verification_status'='VERIFIED')<>1
 THEN RAISE EXCEPTION 'M06_HISTORICAL_SOURCE_AUDIT_FAILED'; END IF;

 UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10_M06}',v_spec,true)
 WHERE work_item_id=1133 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32';
 GET DIAGNOSTICS v_count=ROW_COUNT;
 IF v_count<>1 THEN RAISE EXCEPTION 'M06_CANONICAL_ACTION_UPDATE_NOT_ONE'; END IF;
 v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M06',
 programacion.fn_engineering_checkpoint_action_spec_v3('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M06'));
 IF v_contract->>'status'<>'READY' OR v_contract->>'mode'<>'EXPLICIT_PASS_WHEN_SUBSET'
 THEN RAISE EXCEPTION 'M06_ASSERTION_CONTRACT_NOT_READY:%',coalesce(v_contract::text,'NULL'); END IF;
 v_obs:=jsonb_build_object('checkpoint_identity','PE10_M06','method_algorithms','D+C',
 'literal_sql_count',12,'gde_minimal_hitting_sets',8,'metamorphic_negative_checks_passed',13,
 'tlp_total_sql_callers',38,'tlp_total_external',6,
 'historical_source_event_id',20161,'git_source_verified',true,'runtime_modified',false);
 v_result:=jsonb_build_object('status','PASS','observed',v_obs,'evidence_ref',v_ref,
 'validation_kind','METHOD_D_C_RESEARCH_MATERIALITY_NOT_BUSINESS_REPAIR',
 'method_correctness_evaluated',false);
 v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M06',v_result,v_exec);
 IF v_assertion->>'passed'<>'true' OR coalesce(v_assertion->>'assertion_receipt_sha256','') !~ '^[a-f0-9]{64}$'
 THEN RAISE EXCEPTION 'M06_CANONICAL_ASSERTION_NOT_PASSED'; END IF;
 v_receipt:=v_assertion->>'assertion_receipt_sha256';
 v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M06','DONE',v_ref,v_exec,
 'M06 D+C GDE/TLP research materiality verified; no production repair');
 IF v_transition#>>'{transition,status}'<>'APPLIED'
 THEN RAISE EXCEPTION 'M06_CANONICAL_TRANSITION_FAILED'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133
 AND checkpoint_code='PE10_M06' AND status='DONE' AND completed_at IS NOT NULL
 AND assertion_receipt_sha256=v_receipt
 AND assertion_contract_sha256=assertion_receipt->>'contract_sha256'
 AND assertion_receipt->>'passed'='true' AND evidence_ref=v_ref)<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>6
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>26
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M07' AND status='PENDING')<>1
 THEN RAISE EXCEPTION 'M06_POSTTRAIN_STATUS_INCONSISTENT'; END IF;
EXCEPTION WHEN OTHERS THEN
 GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT,v_context=PG_EXCEPTION_CONTEXT;
 RAISE EXCEPTION 'M06_TRAIN_DIAGNOSTIC state=% msg=% context=%',SQLSTATE,left(v_error,300),left(v_context,160) USING ERRCODE=SQLSTATE;
END $m06_governed_close$;
