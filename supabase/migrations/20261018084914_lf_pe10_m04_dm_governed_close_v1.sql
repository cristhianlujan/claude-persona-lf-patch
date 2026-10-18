-- LF PE10 M04: certify individual D+M method investigation, NOT a runtime improvement.
-- Only route: PR -> PASE -> LF Migration Merge Train -> assertion -> DONE -> readback.
-- Preserve previous M01..M03 receipts and M05..M32 pending states.
DO $pe10_m04_close$
DECLARE
 v_exec text;v_raw text:=$m04_source${
  "schema": "PE10_METHOD_RAW_V2",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M04",
  "method_base": "A",
  "algorithms": [
    "D",
    "M"
  ],
  "source_cutoff_utc": "2026-10-15T00:00:00Z",
  "original_preserved": {
    "raw_sha256": "4ec684e46bb3b6ed25a0dd18919f632aacca3b2ea5db7dce9dfd120b21941bfd",
    "ref": "chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M04.json",
    "note": "Prior local RAW remains as historical artifact, new material investigation additive."
  },
  "producer": "One GPT-6 role-bound SRCR+GDE+ATMS method-specific execution; cannot claim distinct sessions or independent blind agent",
  "source_mode": "READ_ONLY_HISTORICAL_P0_SOURCE; CURRENT_PRINCIPAL_OBSERVATION_SEPARATE",
  "evaluation": "NOT_PERFORMED",
  "sql_evidence": [
    {
      "id": "M04_Q01",
      "sql_literal": "SELECT id,created_at,payload->>'source_pack_version' source_pack,payload->>'fetch_spec_version' fetch_spec,payload->'historical_provenance_only' provenance,payload->'scope_guards' scope_guards FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "id": 20161,
          "created_at": "2026-10-04 05:14:40.880842+00",
          "source_pack": "SOURCE_PACK_V1",
          "fetch_spec": "SOURCE_PACK_LOOKUP_V2",
          "provenance": {
            "router_note": "Router binding snapshot observes readiness revision 5.12 while governed current readiness snapshot is 5.13; retained as provenance/currentness drift only.",
            "contract_note": "Older input contract rows remain recorded; caller usage is not inferred from their existence."
          },
          "scope_guards": {
            "callers_retired": false,
            "m10_10_executed": false,
            "callers_modified": false,
            "production_change": false,
            "runtime_activation": false,
            "n13_n14_n15_changed": false
          }
        }
      ],
      "rows_returned": 1,
      "readback_type": "HISTORICAL_SOURCE_READ_AT_CURRENT_TOOL_TIME",
      "source": "SUPABASE_READ_ONLY",
      "run_caveat": "Re-query immutable historical source; not a P0 contemporaneous runtime observation"
    },
    {
      "id": "M04_Q02",
      "sql_literal": "SELECT count(*) sql_callers,count(DISTINCT x->>'dedupe_key') distinct_callers,count(*) FILTER (WHERE x->>'operational_class'='ACTIVE') historically_active,count(*) FILTER (WHERE x->>'definition_md5'~'^[a-f0-9]{32}$') valid_md5 FROM public.lf_eventos l CROSS JOIN LATERAL jsonb_array_elements(l.payload->'sql_callers') x WHERE l.id=20161",
      "rows": [
        {
          "sql_callers": 38,
          "distinct_callers": 38,
          "historically_active": 38,
          "valid_md5": 38
        }
      ],
      "rows_returned": 1,
      "readback_type": "HISTORICAL_SOURCE_READ_AT_CURRENT_TOOL_TIME",
      "source": "SUPABASE_READ_ONLY",
      "run_caveat": "Re-query immutable historical source; not a P0 contemporaneous runtime observation"
    },
    {
      "id": "M04_Q03",
      "sql_literal": "SELECT count(*) edges,count(DISTINCT (x->>'caller')||'->'||callee.value) unique_edges,count(DISTINCT callee.value) callee_names,count(*) FILTER(WHERE callee.value ILIKE '%cached%') cached_edges FROM public.lf_eventos l CROSS JOIN LATERAL jsonb_array_elements(l.payload->'sql_callers') x CROSS JOIN LATERAL jsonb_array_elements_text(x->'callees') callee(value) WHERE l.id=20161",
      "rows": [
        {
          "edges": 76,
          "unique_edges": 76,
          "callee_names": 39,
          "cached_edges": 11
        }
      ],
      "rows_returned": 1,
      "readback_type": "HISTORICAL_SOURCE_READ_AT_CURRENT_TOOL_TIME",
      "source": "SUPABASE_READ_ONLY",
      "run_caveat": "Re-query immutable historical source; not a P0 contemporaneous runtime observation"
    },
    {
      "id": "M04_Q04",
      "sql_literal": "SELECT coalesce(x->>'operational_class','UNKNOWN') class,coalesce(x->>'governance_lifecycle','UNKNOWN') lifecycle,count(*) n FROM public.lf_eventos l CROSS JOIN LATERAL jsonb_array_elements(l.payload->'external_inventory') x WHERE l.id=20161 GROUP BY 1,2 ORDER BY 1,2",
      "rows": [
        {
          "class": "ACTIVE",
          "lifecycle": "CANDIDATE_READ_ONLY",
          "n": 2
        },
        {
          "class": "ACTIVE",
          "lifecycle": "RUNTIME_SANDBOX_CANARY",
          "n": 1
        },
        {
          "class": "CANDIDATE",
          "lifecycle": "CANDIDATE_READ_ONLY",
          "n": 1
        },
        {
          "class": "CANDIDATE",
          "lifecycle": "NO_HABILITADO",
          "n": 1
        },
        {
          "class": "CANDIDATE_TEST",
          "lifecycle": "CANDIDATE_READ_ONLY",
          "n": 1
        }
      ],
      "rows_returned": 5,
      "readback_type": "HISTORICAL_SOURCE_READ_AT_CURRENT_TOOL_TIME",
      "source": "SUPABASE_READ_ONLY",
      "run_caveat": "Re-query immutable historical source; not a P0 contemporaneous runtime observation"
    },
    {
      "id": "M04_Q05",
      "sql_literal": "SELECT jsonb_array_length(payload->'trigger_bindings') triggers,jsonb_array_length(payload->'edge_current') edge_entries,jsonb_array_length(payload->'external_inventory') externals,jsonb_array_length(payload->'consumer_relation_snapshot_json_rows') consumer_snapshot_rows,payload->'usage_stats' usage_stats FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "triggers": 21,
          "edge_entries": 4,
          "externals": 6,
          "consumer_snapshot_rows": 27,
          "usage_stats": {
            "ig_stat_rows": 0,
            "interpretation": "track_functions none means zero stat rows cannot prove no usage; static governed graph supplies inventory currentness",
            "track_functions": "none"
          }
        }
      ],
      "rows_returned": 1,
      "readback_type": "HISTORICAL_SOURCE_READ_AT_CURRENT_TOOL_TIME",
      "source": "SUPABASE_READ_ONLY",
      "run_caveat": "Re-query immutable historical source; not a P0 contemporaneous runtime observation"
    },
    {
      "id": "M04_Q06",
      "sql_literal": "SELECT id,created_at,receipt_kind,subject_ref,payload->>'verification_status' verified,payload->>'pass' qualified,payload->>'screens_total' screens,payload->>'families_total' families,payload->>'known_false_pass_signals' false_pass,payload->>'unresolved_d4' d4 FROM programacion.provenance_receipts WHERE id=38",
      "rows": [
        {
          "id": 38,
          "created_at": "2026-10-07 16:01:00.760627+00",
          "receipt_kind": "EVIDENCE_VERIFICATION",
          "subject_ref": "plan://IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.11/SOAK_OBSERVATION_HISTORY_V2",
          "verified": "VERIFIED",
          "qualified": "true",
          "screens": "13",
          "families": "47",
          "false_pass": "0",
          "d4": "0"
        }
      ],
      "rows_returned": 1,
      "readback_type": "HISTORICAL_SOURCE_READ_AT_CURRENT_TOOL_TIME",
      "source": "SUPABASE_READ_ONLY",
      "run_caveat": "Re-query immutable historical source; not a P0 contemporaneous runtime observation"
    },
    {
      "id": "M04_Q07",
      "sql_literal": "SELECT codigo,primera_vez,causa_raiz,validacion FROM transversal.error_knowledge WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001') AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z' ORDER BY codigo",
      "rows": [
        {
          "codigo": "IG-M107-CP2-READ-ROLE-CURRENTNESS-001",
          "primera_vez": "2026-10-14 23:44:24.874586+00",
          "causa_raiz": "Desalineación entre verificación CP2, autoridad histórica M9.11 y privilegios de lectura declarados.",
          "validacion": "2026-10-14: Q1 receipt 38 PASS, Q2 cohort PASS_OBSERVED 13/13 screens, 47 families, 199 completed runs. SQL 42501 reproducido. Migración revierte primer ensayo y lee CP2 DONE, otros tres pendientes sin autorizar producción."
        },
        {
          "codigo": "IG-M107-SOAK-CRITERION-DRIFT-001",
          "primera_vez": "2026-10-14 23:39:14.146551+00",
          "causa_raiz": "Desalineación de proyección textual del contrato M10.7 frente a la autoridad SOAK_OBSERVATION_HISTORY_V2 de M9.11.",
          "validacion": "Read-only 2026-10-14: receipt 38 13/13 screens,47/47 families, zero below-2, false_pass=0,D4=0; tres negativos sintéticos rechazados. Migración prueba rollback y comprueba CP1 DONE/CP2 PENDING, sin activar producción."
        }
      ],
      "rows_returned": 2,
      "readback_type": "HISTORICAL_SOURCE_READ_AT_CURRENT_TOOL_TIME",
      "source": "SUPABASE_READ_ONLY",
      "run_caveat": "Re-query immutable historical source; not a P0 contemporaneous runtime observation"
    },
    {
      "id": "M04_Q08",
      "sql_literal": "SELECT payload->>'historical_callers_confirmed' historically_confirmed,payload->>'unexplained_material_callers' unexplained,payload->'deduplication' dedup,payload->'ambiguous_name_candidates_checked' ambiguous_checked,payload->'excluded_name_candidate' excluded_candidate FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "historically_confirmed": "[]",
          "unexplained": "0",
          "dedup": {
            "rule": "One logical caller identity per source URI/object identity; evidence from multiple governed sources is merged instead of double-counted.",
            "router_identity": "PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1 maps to live SQL lf_ops.fn_lf_router_input_governance_resolve_v1.",
            "profiles_edge_identity": "EDGE_FN_LF_PROFILES_GOVERNANCE_CALLER_V1 maps to live Edge lf-profiles-governance-caller-v1."
          },
          "ambiguous_checked": 1,
          "excluded_candidate": {
            "object": "lf-profile-creator-governance-caller-v1",
            "reason": "Current caller.ts invokes configured LF_PROFILE_CREATOR_RUNTIME_SLUG/default run-creacion-perfil-lf and contains no IG call; name/existence is not usage evidence.",
            "sha256": "27594e559e752587c5644463efc67fb9be245319b856766d85435431325cf6ee",
            "version": 16,
            "edge_marker": "ACTIVE",
            "classification": "NOT_IG_CALLER",
            "verified_target": "run-creacion-perfil-lf"
          }
        }
      ],
      "rows_returned": 1,
      "readback_type": "HISTORICAL_SOURCE_READ_AT_CURRENT_TOOL_TIME",
      "source": "SUPABASE_READ_ONLY",
      "run_caveat": "Re-query immutable historical source; not a P0 contemporaneous runtime observation"
    },
    {
      "id": "M04_Q09",
      "sql_literal": "SELECT jsonb_array_length(payload->'router_binding_snapshot_json_rows') router_snapshots,jsonb_array_length(payload->'contract_snapshot_json_rows') contract_snapshots,jsonb_array_length(payload->'test_suite_snapshot_json_rows') tests FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "router_snapshots": 4,
          "contract_snapshots": 19,
          "tests": 1
        }
      ],
      "rows_returned": 1,
      "readback_type": "HISTORICAL_SOURCE_READ_AT_CURRENT_TOOL_TIME",
      "source": "SUPABASE_READ_ONLY",
      "run_caveat": "Re-query immutable historical source; not a P0 contemporaneous runtime observation"
    },
    {
      "id": "M04_Q10",
      "sql_literal": "SELECT current_user read_role,current_setting('transaction_read_only') read_only,current_setting('request.jwt.claim.role',true) jwt_role",
      "rows": [
        {
          "read_role": "supabase_read_only_user",
          "read_only": "on",
          "jwt_role": null
        }
      ],
      "rows_returned": 1,
      "readback_type": "CURRENT_TOOL_PRINCIPAL_NOT_P0",
      "source": "SUPABASE_READ_ONLY",
      "run_caveat": "Re-query immutable historical source; not a P0 contemporaneous runtime observation"
    }
  ],
  "gde": {
    "conflict_sets": [
      [
        "ASOF_PROMOTION",
        "VERSIONED_CURRENT_READ_GAP"
      ],
      [
        "STATIC_EDGE_AS_EXECUTION",
        "DYNAMIC_CALL_TRACE_GAP"
      ],
      [
        "ZERO_STATS_AS_NO_USE",
        "COMPARABLE_CLOCKS_GAP"
      ]
    ],
    "components": [
      "ASOF_PROMOTION",
      "VERSIONED_CURRENT_READ_GAP",
      "STATIC_EDGE_AS_EXECUTION",
      "DYNAMIC_CALL_TRACE_GAP",
      "ZERO_STATS_AS_NO_USE",
      "COMPARABLE_CLOCKS_GAP"
    ],
    "enumeration": "FULL_2_POWER_6_MINIMAL_HITTING_SET_SEARCH",
    "candidate_hitting_sets_total": 27,
    "minimal_hitting_sets": [
      [
        "ASOF_PROMOTION",
        "STATIC_EDGE_AS_EXECUTION",
        "ZERO_STATS_AS_NO_USE"
      ],
      [
        "VERSIONED_CURRENT_READ_GAP",
        "STATIC_EDGE_AS_EXECUTION",
        "ZERO_STATS_AS_NO_USE"
      ],
      [
        "ASOF_PROMOTION",
        "DYNAMIC_CALL_TRACE_GAP",
        "ZERO_STATS_AS_NO_USE"
      ],
      [
        "VERSIONED_CURRENT_READ_GAP",
        "DYNAMIC_CALL_TRACE_GAP",
        "ZERO_STATS_AS_NO_USE"
      ],
      [
        "ASOF_PROMOTION",
        "STATIC_EDGE_AS_EXECUTION",
        "COMPARABLE_CLOCKS_GAP"
      ],
      [
        "VERSIONED_CURRENT_READ_GAP",
        "STATIC_EDGE_AS_EXECUTION",
        "COMPARABLE_CLOCKS_GAP"
      ],
      [
        "ASOF_PROMOTION",
        "DYNAMIC_CALL_TRACE_GAP",
        "COMPARABLE_CLOCKS_GAP"
      ],
      [
        "VERSIONED_CURRENT_READ_GAP",
        "DYNAMIC_CALL_TRACE_GAP",
        "COMPARABLE_CLOCKS_GAP"
      ]
    ],
    "minimal_count": 8,
    "barinel": "NOT_CALIBRATABLE_NO_EXECUTION_SPECTRA_OR_PRIORS",
    "information_gain": "ORDINAL_DISCRIMINATION_AND_COST_ONLY",
    "causality": "NO_CONFIRMED_ROOT_CAUSE"
  },
  "atms": {
    "facts": [
      "SRC20161",
      "RECEIPT38",
      "EKB2",
      "ASOF_ONLY",
      "TF_NONE"
    ],
    "rules": {
      "HIST_CALLERS": [
        [
          "SRC20161",
          "ASOF_ONLY"
        ]
      ],
      "HIST_SOAK": [
        [
          "RECEIPT38",
          "ASOF_ONLY"
        ]
      ],
      "PRE_CUTOFF_RISK": [
        [
          "EKB2",
          "ASOF_ONLY"
        ]
      ],
      "NEED_VERSIONED_READBACK": [
        [
          "HIST_CALLERS",
          "PRE_CUTOFF_RISK"
        ]
      ],
      "NO_ZERO_USE_INFERENCE": [
        [
          "SRC20161",
          "TF_NONE"
        ]
      ],
      "METHOD_RISK": [
        [
          "NEED_VERSIONED_READBACK"
        ],
        [
          "HIST_SOAK",
          "EKB2"
        ]
      ]
    },
    "nogoods": [
      [
        "ASOF_ONLY",
        "CLAIM_CURRENT"
      ],
      [
        "TF_NONE",
        "CLAIM_NO_USAGE"
      ]
    ],
    "supports": {
      "SRC20161": [
        [
          "SRC20161"
        ]
      ],
      "RECEIPT38": [
        [
          "RECEIPT38"
        ]
      ],
      "EKB2": [
        [
          "EKB2"
        ]
      ],
      "ASOF_ONLY": [
        [
          "ASOF_ONLY"
        ]
      ],
      "TF_NONE": [
        [
          "TF_NONE"
        ]
      ],
      "HIST_CALLERS": [
        [
          "ASOF_ONLY",
          "SRC20161"
        ]
      ],
      "HIST_SOAK": [
        [
          "ASOF_ONLY",
          "RECEIPT38"
        ]
      ],
      "PRE_CUTOFF_RISK": [
        [
          "ASOF_ONLY",
          "EKB2"
        ]
      ],
      "NEED_VERSIONED_READBACK": [
        [
          "ASOF_ONLY",
          "EKB2",
          "SRC20161"
        ]
      ],
      "NO_ZERO_USE_INFERENCE": [
        [
          "SRC20161",
          "TF_NONE"
        ]
      ],
      "METHOD_RISK": [
        [
          "ASOF_ONLY",
          "EKB2",
          "RECEIPT38"
        ],
        [
          "ASOF_ONLY",
          "EKB2",
          "SRC20161"
        ]
      ]
    },
    "counterfactuals": [
      {
        "removed": [
          "SRC20161"
        ],
        "claim": "HIST_CALLERS",
        "expected": false,
        "test": "ATMS_T1",
        "supported": false
      },
      {
        "removed": [
          "RECEIPT38"
        ],
        "claim": "HIST_SOAK",
        "expected": false,
        "test": "ATMS_T2",
        "supported": false
      },
      {
        "removed": [
          "EKB2"
        ],
        "claim": "PRE_CUTOFF_RISK",
        "expected": false,
        "test": "ATMS_T3",
        "supported": false
      },
      {
        "removed": [
          "RECEIPT38"
        ],
        "claim": "METHOD_RISK",
        "expected": true,
        "test": "ATMS_T4",
        "supported": true
      },
      {
        "removed": [
          "EKB2"
        ],
        "claim": "METHOD_RISK",
        "expected": false,
        "test": "ATMS_T5",
        "supported": false
      },
      {
        "removed": [
          "SRC20161"
        ],
        "claim": "NO_ZERO_USE_INFERENCE",
        "expected": false,
        "test": "ATMS_T6",
        "supported": false
      }
    ],
    "counterfactuals_passed": 6
  },
  "negative_tests": [
    {
      "id": "ATMS_T1",
      "pass": true,
      "support": false,
      "expected": false
    },
    {
      "id": "ATMS_T2",
      "pass": true,
      "support": false,
      "expected": false
    },
    {
      "id": "ATMS_T3",
      "pass": true,
      "support": false,
      "expected": false
    },
    {
      "id": "ATMS_T4",
      "pass": true,
      "support": true,
      "expected": true
    },
    {
      "id": "ATMS_T5",
      "pass": true,
      "support": false,
      "expected": false
    },
    {
      "id": "ATMS_T6",
      "pass": true,
      "support": false,
      "expected": false
    },
    {
      "id": "GDE_MINIMAL_ALL_SETS",
      "pass": true
    },
    {
      "id": "NO_BARINEL_NUMERIC_WITHOUT_SPECTRA",
      "pass": true
    },
    {
      "id": "NO_CURRENT_FROM_HISTORICAL",
      "pass": true
    }
  ],
  "findings": [
    {
      "id": "M04-F01",
      "claim": "Historical snapshot: 38 SQL callers and 76 nominal directed edges to 39 callee names; nominal edges do not establish runtime execution",
      "evidence": [
        "M04_Q01",
        "M04_Q02",
        "M04_Q03"
      ],
      "confidence": "MEASURED_ASOF"
    },
    {
      "id": "M04-F02",
      "claim": "Six external inventory entries include ACTIVE/CANDIDATE/CANDIDATE_TEST lifecycle categories. These are not 6 additional unique SQL callers",
      "evidence": [
        "M04_Q04",
        "M04_Q05",
        "M04_Q08"
      ],
      "confidence": "MEASURED_ASOF_WITH_POPULATION_WARNING"
    },
    {
      "id": "M04-F03",
      "claim": "track_functions=none and 0 stats rows cannot prove no usage or efficiency gain",
      "evidence": [
        "M04_Q05"
      ],
      "confidence": "MEASURED_ASOF_TELEMETRY_LIMIT"
    },
    {
      "id": "M04-F04",
      "claim": "Receipt 38 is VERIFIED and qualified for M9.11 SOAK (13 screens,47 families, zero false pass/D4) but it is not a currentness or performance receipt",
      "evidence": [
        "M04_Q06",
        "M04_Q07"
      ],
      "confidence": "MEASURED_ASOF"
    },
    {
      "id": "M04-F05",
      "claim": "ATMS source withdrawal tests invalidate dependent conclusions; GDE yields 8 minimal modeled diagnoses, not identified defects",
      "evidence": [
        "M04_Q01",
        "M04_Q05",
        "M04_Q06",
        "M04_Q07"
      ],
      "confidence": "COMPUTED_WITH_ASSUMPTIONS"
    }
  ],
  "causal_model": {
    "status": "HYPOTHESES_NOT_PROVEN",
    "candidates": [
      "Historical ASOF promoted to CURRENT",
      "Static edges conflated with execution traces",
      "No telemetry misread as no usage"
    ],
    "falsifiers": [
      "version-pinned same-time qualified live source",
      "actual invocation traces across cached/Edge variants",
      "comparable end-to-end durations and cohorts"
    ]
  },
  "candidate_repairs": [
    {
      "action": "Version-scoped snapshot/current comparison",
      "status": "PROPOSED_VERIFY_FIRST"
    },
    {
      "action": "Measure existing E2E timestamps by stage with comparable clocks",
      "status": "PROPOSED_VERIFY_FIRST"
    },
    {
      "action": "Verify consumer identity and reachability before retirement",
      "status": "PROPOSED_VERIFY_FIRST"
    }
  ],
  "chosen_repair": "VERIFY_FIRST_NO_IMPLEMENTATION",
  "rejected_alternatives": [
    "grant EXECUTE to readonly connector",
    "retire cached by name",
    "invent performance improvement from missing stats",
    "apply GDE modeled sets as proven repair"
  ],
  "unresolved": [
    "Canonical historical definition_md5 representation not established",
    "P0 current reachability unknown",
    "E2E denominator clocks unknown",
    "CP2 CURRENT reader authority unknown"
  ],
  "constraints_preserved": [
    "P0 historical",
    "No product runtime or permission changes",
    "No other method RAW supplied as experiment input",
    "No scoring",
    "source-backed statements only"
  ],
  "research_conclusion": "DIAGNOSTIC_MATERIAL_COMPLETE_WITH_OPEN_UNKNOWNS_NOT_IMPLEMENTED_REPAIR",
  "admin_status_at_start": "PENDING"
}
$m04_source$;
 v_doc jsonb;v_blob text;v_count int;v_gde int;v_atms int;v_neg int;v_ekb int;
 v_ref text:='https://github.com/cristhianlujan/claude-persona-lf-patch/blob/58921672c90f0362a6fc4fd6dd86a05719fb1421/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M04_RAW_V2.json#git_blob_sha=88693a382ab276d412cc6dcc6895fa008cd79d37';v_prev text:='chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M04.json#sha256=4ec684e46bb3b6ed25a0dd18919f632aacca3b2ea5db7dce9dfd120b21941bfd';
 v_spec jsonb:=$m04_spec${"status":"READY","action_kind":"VERIFY_QUERY_ONCE","recipe_mode":"READBACK_EXACT","requires_material_execution":true,"contract_family":"PE10_METHOD_EXECUTION_EVIDENCE","precision":"PE10_METHOD_V1_MATERIAL_EVIDENCE","assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"checkpoint_identity":"PE10_M04","method_algorithms":"D+M","literal_sql_count":10,"gde_minimal_hitting_sets":8,"atms_counterfactuals_passed":6,"negative_tests_passed":9,"historical_source_event_id":20161,"git_raw_source_verified":true,"runtime_modified":false}},"evidence_ref":"https://github.com/cristhianlujan/claude-persona-lf-patch/blob/58921672c90f0362a6fc4fd6dd86a05719fb1421/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M04_RAW_V2.json#git_blob_sha=88693a382ab276d412cc6dcc6895fa008cd79d37","verification_queries":["SELECT id,created_at,payload->>'source_pack_version' source_pack,payload->>'fetch_spec_version' fetch_spec,payload->'historical_provenance_only' provenance,payload->'scope_guards' scope_guards FROM public.lf_eventos WHERE id=20161","SELECT count(*) sql_callers,count(DISTINCT x->>'dedupe_key') distinct_callers,count(*) FILTER (WHERE x->>'operational_class'='ACTIVE') historically_active,count(*) FILTER (WHERE x->>'definition_md5'~'^[a-f0-9]{32}$') valid_md5 FROM public.lf_eventos l CROSS JOIN LATERAL jsonb_array_elements(l.payload->'sql_callers') x WHERE l.id=20161","SELECT count(*) edges,count(DISTINCT (x->>'caller')||'->'||callee.value) unique_edges,count(DISTINCT callee.value) callee_names,count(*) FILTER(WHERE callee.value ILIKE '%cached%') cached_edges FROM public.lf_eventos l CROSS JOIN LATERAL jsonb_array_elements(l.payload->'sql_callers') x CROSS JOIN LATERAL jsonb_array_elements_text(x->'callees') callee(value) WHERE l.id=20161","SELECT jsonb_array_length(payload->'trigger_bindings') triggers,jsonb_array_length(payload->'edge_current') edge_entries,jsonb_array_length(payload->'external_inventory') externals,jsonb_array_length(payload->'consumer_relation_snapshot_json_rows') consumer_snapshot_rows,payload->'usage_stats' usage_stats FROM public.lf_eventos WHERE id=20161","SELECT id,created_at,receipt_kind,subject_ref,payload->>'verification_status' verified,payload->>'pass' qualified,payload->>'screens_total' screens,payload->>'families_total' families,payload->>'known_false_pass_signals' false_pass,payload->>'unresolved_d4' d4 FROM programacion.provenance_receipts WHERE id=38","SELECT codigo,primera_vez,causa_raiz,validacion FROM transversal.error_knowledge WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001') AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z' ORDER BY codigo"],"expected":"M04 separately verified original-specific D GDE and M ATMS; 10 literal SQL reads, 8 modeled hitting sets, 6 invalidation tests and 9 negative checks; not an applied repair","forbidden":["TREAT_GDE_SETS_AS_PROVEN_REPAIR","TREAT_HISTORICAL_AS_CURRENT","INVENT_BARINEL_PRIORS","SKIP_ASSERTION_RECEIPT","MODIFY_OTHER_CHECKPOINTS"],"target":{"checkpoint":"PE10_M04","declared_events":[20161],"declared_objects":["public.lf_eventos","programacion.provenance_receipts","transversal.error_knowledge","programacion.engineering_work_checkpoints"],"evidence_artifacts":[{"path":"cristhianlujan/claude-persona-lf-patch:docs/profile_updater/experiments/pe10_methods32_p0/PE10_M04_RAW_V2.json","role":"EVIDENCE","purpose":"PE10_M04_D_M_ORIGINAL_SPECIFIC_RAW","target_kind":"EXACT_EXISTING_FILE"}]}}$m04_spec$::jsonb;
 v_contract jsonb;v_obs jsonb;v_result jsonb;v_assertion jsonb;v_transition jsonb;
 v_receipt text;v_msg text;v_ctx text;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
 AND target_code LIKE '%lf_pe10_m04_dm_governed_close_v1'
 AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'M04_TRAIN_EXECUTOR_ABSENT'; END IF;
 IF (SELECT status FROM programacion.engineering_work_items WHERE id=1133)<>'IN_PROGRESS'
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133)<>32
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>3
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>29
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=1133 AND checkpoint_code='PE10_M04' AND status='PENDING' AND evidence_ref=v_prev
 AND assertion_receipt IS NULL AND completed_at IS NULL)<>1
 OR (SELECT count(*) FROM programacion.engineering_plan_units WHERE work_item_id=1133
 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32'
 AND disposition='ASSIGNED' AND unit_metadata->>'checkpoint_ordering'='INDEPENDENT_METHOD_VARIANTS'
 AND unit_metadata#>>'{action_specs_v1,PE10_M04,status}'='BLOCK_PENDING_MATERIAL_RESEARCH_AND_VALIDATION')<>1
 OR (SELECT count(*) FROM programacion.pe10_method_variants WHERE method_code='PE10_M04'
 AND case_ref='PE10-IG-M107-M109-P0' AND base_code='A'
 AND algorithm_codes=ARRAY['D','M']::text[])<>1
 THEN RAISE EXCEPTION 'M04_PRESTATE_OR_CATALOG_CHANGED'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=1133 AND checkpoint_code IN('PE10_M01','PE10_M02','PE10_M03')
 AND status='DONE' AND assertion_receipt->>'passed'='true'
 AND assertion_contract_sha256=assertion_receipt->>'contract_sha256'
 AND assertion_receipt_sha256 IN ('1c174f3277f9656ffc4146c210ac64cd037fc92d4fb34d7a7959fe826e3f9b01',
 '0079973e1fec8787d2ef45d92131cad58bcb59f3c591aaf2badd8d86fe34c51b',
 '0cbbc9d58552b2c5ea3d2c9bca1b07c6467cd4145720905f38fc5bf07a46e2a1'))<>3
 THEN RAISE EXCEPTION 'M04_PREVIOUS_CLOSURE_RECEIPTS_CHANGED'; END IF;
 v_blob:=encode(extensions.digest(
 convert_to('blob '||octet_length(convert_to(v_raw,'UTF8'))::text,'UTF8')
 ||decode('00','hex')||convert_to(v_raw,'UTF8'),'sha1'),'hex');
 IF v_blob<>'88693a382ab276d412cc6dcc6895fa008cd79d37' THEN RAISE EXCEPTION 'M04_IMMUTABLE_GIT_BLOB_MISMATCH'; END IF;
 v_doc:=v_raw::jsonb;
 IF v_doc->>'schema'<>'PE10_METHOD_RAW_V2'
 OR v_doc->>'case_ref'<>'PE10-IG-M107-M109-P0'
 OR v_doc->>'method_code'<>'PE10_M04'
 OR v_doc->>'method_base'<>'A'
 OR v_doc->'algorithms'<>'["D","M"]'::jsonb
 OR v_doc->>'source_cutoff_utc'<>'2026-10-15T00:00:00Z'
 OR v_doc#>>'{original_preserved,raw_sha256}'<>'4ec684e46bb3b6ed25a0dd18919f632aacca3b2ea5db7dce9dfd120b21941bfd'
 OR v_doc->>'evaluation'<>'NOT_PERFORMED'
 OR v_doc->>'chosen_repair'<>'VERIFY_FIRST_NO_IMPLEMENTATION'
 OR v_doc->>'research_conclusion'<>'DIAGNOSTIC_MATERIAL_COMPLETE_WITH_OPEN_UNKNOWNS_NOT_IMPLEMENTED_REPAIR'
 THEN RAISE EXCEPTION 'M04_RAW_IDENTITY_AND_SCOPE_INVALID'; END IF;
 SELECT count(*) INTO v_count FROM jsonb_array_elements(v_doc->'sql_evidence') e
 WHERE e->>'sql_literal' ~* '^SELECT '
 AND e->>'id' ~ '^M04_Q(0[1-9]|10)$'
 AND e->>'source'='SUPABASE_READ_ONLY'
 AND jsonb_typeof(e->'rows')='array'
 AND (e->>'rows_returned')::int=jsonb_array_length(e->'rows')
 AND jsonb_array_length(e->'rows')>0;
 IF v_count<>10 OR jsonb_array_length(v_doc->'sql_evidence')<>10
 OR (SELECT count(DISTINCT e->>'id') FROM jsonb_array_elements(v_doc->'sql_evidence') e)<>10
 OR v_doc#>>'{sql_evidence,1,rows,0,sql_callers}'<>'38'
 OR v_doc#>>'{sql_evidence,2,rows,0,edges}'<>'76'
 OR v_doc#>>'{sql_evidence,2,rows,0,callee_names}'<>'39'
 OR v_doc#>>'{sql_evidence,4,rows,0,triggers}'<>'21'
 OR v_doc#>>'{sql_evidence,5,rows,0,verified}'<>'VERIFIED'
 OR v_doc#>>'{sql_evidence,5,rows,0,d4}'<>'0'
 OR v_doc#>>'{sql_evidence,9,rows,0,read_only}'<>'on'
 THEN RAISE EXCEPTION 'M04_QUERY_SOURCE_OR_RESULTS_INCOMPLETE'; END IF;

 SELECT count(*) INTO v_gde FROM jsonb_array_elements(v_doc#>'{gde,minimal_hitting_sets}') g
 WHERE jsonb_array_length(g)=3
 AND (g ? 'ASOF_PROMOTION' OR g ? 'VERSIONED_CURRENT_READ_GAP')
 AND (g ? 'STATIC_EDGE_AS_EXECUTION' OR g ? 'DYNAMIC_CALL_TRACE_GAP')
 AND (g ? 'ZERO_STATS_AS_NO_USE' OR g ? 'COMPARABLE_CLOCKS_GAP');
 SELECT count(*) INTO v_atms FROM jsonb_array_elements(v_doc#>'{atms,counterfactuals}') t
 WHERE t->'supported'=t->'expected';
 SELECT count(*) INTO v_neg FROM jsonb_array_elements(v_doc->'negative_tests') n WHERE n->>'pass'='true';
 IF v_gde<>8 OR jsonb_array_length(v_doc#>'{gde,minimal_hitting_sets}')<>8
 OR v_doc#>>'{gde,barinel}'<>'NOT_CALIBRATABLE_NO_EXECUTION_SPECTRA_OR_PRIORS'
 OR v_doc#>>'{gde,information_gain}'<>'ORDINAL_DISCRIMINATION_AND_COST_ONLY'
 OR v_atms<>6 OR jsonb_array_length(v_doc#>'{atms,counterfactuals}')<>6
 OR v_neg<>9 OR jsonb_array_length(v_doc->'negative_tests')<>9
 THEN RAISE EXCEPTION 'M04_GDE_ATMS_OR_NEGATIVE_PROOF_INCOMPLETE'; END IF;

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
 AND payload->>'verification_status'='VERIFIED'
 AND payload->>'false_pass_signals' IS NULL)<>1
 THEN RAISE EXCEPTION 'M04_HISTORICAL_AUTHORITIES_CHANGED'; END IF;

 UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10_M04}',v_spec,true)
 WHERE work_item_id=1133 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32';
 GET DIAGNOSTICS v_count=ROW_COUNT;
 IF v_count<>1 THEN RAISE EXCEPTION 'M04_SPEC_UPDATE_COUNT_NOT_ONE'; END IF;
 v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M04',
 programacion.fn_engineering_checkpoint_action_spec_v3('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M04'));
 IF v_contract->>'status'<>'READY' OR v_contract->>'mode'<>'EXPLICIT_PASS_WHEN_SUBSET'
 THEN RAISE EXCEPTION 'M04_CONTRACT_NOT_READY:%',coalesce(v_contract::text,'null'); END IF;
 v_obs:=jsonb_build_object('checkpoint_identity','PE10_M04','method_algorithms','D+M',
 'literal_sql_count',10,'gde_minimal_hitting_sets',8,'atms_counterfactuals_passed',6,
 'negative_tests_passed',9,'historical_source_event_id',20161,'git_raw_source_verified',true,
 'runtime_modified',false);
 v_result:=jsonb_build_object('status','PASS','observed',v_obs,'evidence_ref',v_ref,
 'validation_kind','METHOD_D_M_MATERIAL_RESEARCH_NOT_APPLIED_REPAIR',
 'external_method_evaluation','NOT_PERFORMED');
 v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M04',v_result,v_exec);
 IF v_assertion->>'passed'<>'true' OR coalesce(v_assertion->>'assertion_receipt_sha256','') !~ '^[a-f0-9]{64}$'
 THEN RAISE EXCEPTION 'M04_CANONICAL_ASSERTION_UNVERIFIED'; END IF;
 v_receipt:=v_assertion->>'assertion_receipt_sha256';
 v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M04','DONE',v_ref,v_exec,
 'GDE D + ATMS M method-specific read-only diagnostic verified, not product implementation');
 IF v_transition#>>'{transition,status}'<>'APPLIED'
 THEN RAISE EXCEPTION 'M04_CANONICAL_DONE_TRANSITION_FAILED'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=1133 AND checkpoint_code='PE10_M04'
 AND status='DONE' AND completed_at IS NOT NULL AND evidence_ref=v_ref
 AND assertion_receipt_sha256=v_receipt
 AND assertion_contract_sha256=assertion_receipt->>'contract_sha256'
 AND assertion_receipt->>'passed'='true')<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>4
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>28
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M05' AND status='PENDING')<>1
 THEN RAISE EXCEPTION 'M04_POSTTRAIN_CHECKPOINT_RECONCILIATION_FAILED'; END IF;
EXCEPTION WHEN OTHERS THEN
 GET STACKED DIAGNOSTICS v_msg=MESSAGE_TEXT,v_ctx=PG_EXCEPTION_CONTEXT;
 RAISE EXCEPTION 'M04_TRAIN_CLOSE_FAILURE sqlstate=% message=% context=%',SQLSTATE,left(v_msg,300),left(v_ctx,140) USING ERRCODE=SQLSTATE;
END $pe10_m04_close$;
