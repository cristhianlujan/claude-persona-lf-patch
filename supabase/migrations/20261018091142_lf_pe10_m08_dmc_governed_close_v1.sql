-- PE10 M08 governed D+M+C research-only checkpoint closure through Train; no production repair.
DO $m08_close$
DECLARE
 v_exec text;v_raw text:=$m08_raw${
  "schema": "PE10_METHOD_RAW_V2",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M08",
  "base_code": "A",
  "algorithm_codes": [
    "D",
    "M",
    "C"
  ],
  "source_cutoff": "2026-10-15T00:00:00Z",
  "original_preserved": {
    "path": "chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M08.json",
    "sha256": "197bba20c5ac02a7bc0a70e43246499798af8fcca068c091eda6f9df165befd1"
  },
  "producer": "One M08 single integrated SRCR investigation applying D,M,C; no separately isolated session claim",
  "external_method_scoring": "NOT_PERFORMED",
  "sql_evidence": [
    {
      "id": "M08_Q01",
      "sql_literal": "SELECT id,created_at,payload->>'source_pack_version' source_pack,payload->>'sql_caller_count' declared_sql,payload->'scope_guards' scope_guards FROM public.lf_eventos WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'",
      "rows": [
        {
          "id": 20161,
          "created_at": "2026-10-04 05:14:40.880842+00",
          "source_pack": "SOURCE_PACK_V1",
          "declared_sql": "38",
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
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF"
    },
    {
      "id": "M08_Q02",
      "sql_literal": "SELECT count(*) total,count(*) FILTER(WHERE x->>'operational_class'='ACTIVE') t,count(*) FILTER(WHERE NOT(x->>'operational_class'='ACTIVE')) f,count(*) FILTER(WHERE (x->>'operational_class'='ACTIVE') IS NULL) n,count(DISTINCT x->>'dedupe_key') unique_caller FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161",
      "rows": [
        {
          "total": 38,
          "t": 38,
          "f": 0,
          "n": 0,
          "unique_caller": 38
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF"
    },
    {
      "id": "M08_Q03",
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
      "id": "M08_Q04",
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
      "id": "M08_Q05",
      "sql_literal": "SELECT count(*) edges,count(DISTINCT (x->>'caller')||'->'||c.name) unique_edges,count(DISTINCT c.name) distinct_callees,count(*) FILTER(WHERE c.name ILIKE '%cached%') cached_edges FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x CROSS JOIN LATERAL jsonb_array_elements_text(x->'callees') c(name) WHERE e.id=20161",
      "rows": [
        {
          "edges": 76,
          "unique_edges": 76,
          "distinct_callees": 39,
          "cached_edges": 11
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF"
    },
    {
      "id": "M08_Q06",
      "sql_literal": "SELECT jsonb_array_length(payload->'trigger_bindings') triggers,jsonb_array_length(payload->'external_inventory') external_assets,jsonb_array_length(payload->'consumer_relation_snapshot_json_rows') relation_rows,jsonb_array_length(payload->'edge_current') edge_rows FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "triggers": 21,
          "external_assets": 6,
          "relation_rows": 27,
          "edge_rows": 4
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF"
    },
    {
      "id": "M08_Q07",
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
      "id": "M08_Q08",
      "sql_literal": "SELECT codigo,primera_vez,causa_raiz,prevencion,validacion FROM transversal.error_knowledge WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001') AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z' ORDER BY codigo",
      "rows": [
        {
          "codigo": "IG-M107-CP2-READ-ROLE-CURRENTNESS-001",
          "primera_vez": "2026-10-14 23:44:24.874586+00",
          "causa_raiz": "Desalineación entre verificación CP2, autoridad histórica M9.11 y privilegios de lectura declarados.",
          "prevencion": "Leer EKB y action_spec. No elevar EXECUTE ni crear motor. Reusar recibo verificado SOAK_OBSERVATION_HISTORY_V2 y revisar la cohorte mediante tablas con SELECT autorizado. Considerar recuentos brutos como evidencia complementaria, nunca sustituto de as-of. Rectificar únicamente queries CP2.",
          "validacion": "2026-10-14: Q1 receipt 38 PASS, Q2 cohort PASS_OBSERVED 13/13 screens, 47 families, 199 completed runs. SQL 42501 reproducido. Migración revierte primer ensayo y lee CP2 DONE, otros tres pendientes sin autorizar producción."
        },
        {
          "codigo": "IG-M107-SOAK-CRITERION-DRIFT-001",
          "primera_vez": "2026-10-14 23:39:14.146551+00",
          "causa_raiz": "Desalineación de proyección textual del contrato M10.7 frente a la autoridad SOAK_OBSERVATION_HISTORY_V2 de M9.11.",
          "prevencion": "Antes de CP1 leer M9.11 DONE y el recibo VERIFIED; heredar >=2 as-of, 0 falsos PASS y 0 D4. Reusar historia. No convertir 13/47 en obligación de nuevas corridas ni confundir latest CURRENT con validez histórica. Confirmar los checkpoints posteriores por su naturaleza.",
          "validacion": "Read-only 2026-10-14: receipt 38 13/13 screens,47/47 families, zero below-2, false_pass=0,D4=0; tres negativos sintéticos rechazados. Migración prueba rollback y comprueba CP1 DONE/CP2 PENDING, sin activar producción."
        }
      ],
      "rows_returned": 2,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF"
    },
    {
      "id": "M08_Q09",
      "sql_literal": "SELECT payload->'historical_provenance_only' version_notes,payload->'deduplication' deduplication,payload->'excluded_name_candidate' excluded FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "version_notes": {
            "router_note": "Router binding snapshot observes readiness revision 5.12 while governed current readiness snapshot is 5.13; retained as provenance/currentness drift only.",
            "contract_note": "Older input contract rows remain recorded; caller usage is not inferred from their existence."
          },
          "deduplication": {
            "rule": "One logical caller identity per source URI/object identity; evidence from multiple governed sources is merged instead of double-counted.",
            "router_identity": "PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1 maps to live SQL lf_ops.fn_lf_router_input_governance_resolve_v1.",
            "profiles_edge_identity": "EDGE_FN_LF_PROFILES_GOVERNANCE_CALLER_V1 maps to live Edge lf-profiles-governance-caller-v1."
          },
          "excluded": {
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
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF"
    },
    {
      "id": "M08_Q10",
      "sql_literal": "SELECT payload->'usage_stats' usage_stats,payload->>'unexplained_material_callers' unexplained FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "usage_stats": {
            "ig_stat_rows": 0,
            "interpretation": "track_functions none means zero stat rows cannot prove no usage; static governed graph supplies inventory currentness",
            "track_functions": "none"
          },
          "unexplained": "0"
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF"
    },
    {
      "id": "M08_Q11",
      "sql_literal": "WITH v(x) AS (VALUES ('ACTIVE'::text),('RETIRED'::text),(NULL::text)) SELECT count(*) total,count(*) FILTER(WHERE x='ACTIVE') t,count(*) FILTER(WHERE NOT(x='ACTIVE')) f,count(*) FILTER(WHERE (x='ACTIVE') IS NULL) n FROM v",
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
      "scope": "SYNTHETIC_POSITIVE_NEGATIVE"
    },
    {
      "id": "M08_Q12",
      "sql_literal": "WITH c(expected,observed) AS (VALUES(38,38),(38,36),(38,NULL::int)) SELECT expected,observed,(expected=observed) IS TRUE accepted FROM c ORDER BY observed NULLS LAST",
      "rows": [
        {
          "expected": 38,
          "observed": 36,
          "accepted": false
        },
        {
          "expected": 38,
          "observed": 38,
          "accepted": true
        },
        {
          "expected": 38,
          "observed": null,
          "accepted": false
        }
      ],
      "rows_returned": 3,
      "source": "SUPABASE_READ_ONLY",
      "scope": "SYNTHETIC_POSITIVE_NEGATIVE"
    },
    {
      "id": "M08_Q13",
      "sql_literal": "SELECT count(*) FILTER(WHERE created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z') historical_source,count(*) FILTER(WHERE created_at>=TIMESTAMPTZ '2026-10-15T00:00:00Z') after_source FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "historical_source": 1,
          "after_source": 0
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF"
    },
    {
      "id": "M08_Q14",
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
      "scope": "QUERY_PRINCIPAL_ONLY"
    }
  ],
  "algorithm_execution": {
    "D": {
      "conflict_sets": [
        [
          "ASOF_TO_CURRENT_PROMOTION",
          "SOURCE_VERSION_READER_MISSING"
        ],
        [
          "GRAPH_MENTION_AS_CALL",
          "EXECUTION_TRACE_GAP"
        ],
        [
          "ZERO_STAT_AS_ZERO_USE",
          "QUALIFIED_DURATION_COHORT_ABSENT"
        ]
      ],
      "minimal_hitting_sets": [
        [
          "ASOF_TO_CURRENT_PROMOTION",
          "GRAPH_MENTION_AS_CALL",
          "ZERO_STAT_AS_ZERO_USE"
        ],
        [
          "SOURCE_VERSION_READER_MISSING",
          "GRAPH_MENTION_AS_CALL",
          "ZERO_STAT_AS_ZERO_USE"
        ],
        [
          "ASOF_TO_CURRENT_PROMOTION",
          "EXECUTION_TRACE_GAP",
          "ZERO_STAT_AS_ZERO_USE"
        ],
        [
          "SOURCE_VERSION_READER_MISSING",
          "EXECUTION_TRACE_GAP",
          "ZERO_STAT_AS_ZERO_USE"
        ],
        [
          "ASOF_TO_CURRENT_PROMOTION",
          "GRAPH_MENTION_AS_CALL",
          "QUALIFIED_DURATION_COHORT_ABSENT"
        ],
        [
          "SOURCE_VERSION_READER_MISSING",
          "GRAPH_MENTION_AS_CALL",
          "QUALIFIED_DURATION_COHORT_ABSENT"
        ],
        [
          "ASOF_TO_CURRENT_PROMOTION",
          "EXECUTION_TRACE_GAP",
          "QUALIFIED_DURATION_COHORT_ABSENT"
        ],
        [
          "SOURCE_VERSION_READER_MISSING",
          "EXECUTION_TRACE_GAP",
          "QUALIFIED_DURATION_COHORT_ABSENT"
        ]
      ],
      "total_candidate_hitting_sets": 27,
      "barinel": "NOT_CALIBRATABLE_NO_SPECTRA_OR_PRIORS",
      "information_gain": "ORDINAL_ONLY_NO_ENTROPY_PROBABILITIES",
      "causal_status": "MODELED_NOT_CONFIRMED"
    },
    "M": {
      "facts": [
        "E20161",
        "R38",
        "EKB2",
        "ASOF_ONLY",
        "TF_NONE"
      ],
      "rules": {
        "HIST_GRAPH": [
          [
            "E20161",
            "ASOF_ONLY"
          ]
        ],
        "HIST_SOAK": [
          [
            "R38",
            "ASOF_ONLY"
          ]
        ],
        "RISKS": [
          [
            "EKB2",
            "ASOF_ONLY"
          ]
        ],
        "VERSION_AUDIT": [
          [
            "HIST_GRAPH",
            "RISKS"
          ]
        ],
        "NO_ZERO_USAGE": [
          [
            "E20161",
            "TF_NONE"
          ]
        ],
        "DIAGNOSTIC_RISK": [
          [
            "VERSION_AUDIT"
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
          "CLAIM_LIVE"
        ],
        [
          "TF_NONE",
          "CLAIM_NO_USAGE"
        ]
      ],
      "minimal_supports": {
        "E20161": [
          [
            "E20161"
          ]
        ],
        "R38": [
          [
            "R38"
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
        "HIST_GRAPH": [
          [
            "ASOF_ONLY",
            "E20161"
          ]
        ],
        "HIST_SOAK": [
          [
            "ASOF_ONLY",
            "R38"
          ]
        ],
        "RISKS": [
          [
            "ASOF_ONLY",
            "EKB2"
          ]
        ],
        "VERSION_AUDIT": [
          [
            "ASOF_ONLY",
            "E20161",
            "EKB2"
          ]
        ],
        "NO_ZERO_USAGE": [
          [
            "E20161",
            "TF_NONE"
          ]
        ],
        "DIAGNOSTIC_RISK": [
          [
            "ASOF_ONLY",
            "E20161",
            "EKB2"
          ],
          [
            "ASOF_ONLY",
            "EKB2",
            "R38"
          ]
        ]
      },
      "counterfactuals": [
        {
          "removed": [
            "E20161"
          ],
          "claim": "HIST_GRAPH",
          "expected": false,
          "id": "ATMS_Q1",
          "observed": false
        },
        {
          "removed": [
            "R38"
          ],
          "claim": "HIST_SOAK",
          "expected": false,
          "id": "ATMS_Q2",
          "observed": false
        },
        {
          "removed": [
            "EKB2"
          ],
          "claim": "RISKS",
          "expected": false,
          "id": "ATMS_Q3",
          "observed": false
        },
        {
          "removed": [
            "R38"
          ],
          "claim": "DIAGNOSTIC_RISK",
          "expected": true,
          "id": "ATMS_Q4",
          "observed": true
        },
        {
          "removed": [
            "E20161"
          ],
          "claim": "DIAGNOSTIC_RISK",
          "expected": true,
          "id": "ATMS_Q5",
          "observed": true
        },
        {
          "removed": [
            "EKB2"
          ],
          "claim": "DIAGNOSTIC_RISK",
          "expected": false,
          "id": "ATMS_Q6",
          "observed": false
        }
      ],
      "counterfactuals_passed": 6
    },
    "C": {
      "tlp_populations": {
        "sql_callers": {
          "total": 38,
          "t": 38,
          "f": 0,
          "n": 0,
          "unique_caller": 38
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
      "contract_cases": [
        {
          "expected": 38,
          "observed": 36,
          "accepted": false
        },
        {
          "expected": 38,
          "observed": 38,
          "accepted": true
        },
        {
          "expected": 38,
          "observed": null,
          "accepted": false
        }
      ],
      "solver": "NOT_USED_NO_COMPATIBLE_SMT",
      "business_rule_correctness": "NOT_PROVEN"
    }
  },
  "negative_tests": [
    {
      "id": "D_GDE_EIGHT_MINIMAL",
      "pass": true
    },
    {
      "id": "D_GDE_REMOVAL_MISSES_CONFLICT",
      "pass": true
    },
    {
      "id": "M_ATMS_INVALIDATION_PROPAGATION",
      "pass": true
    },
    {
      "id": "C_TLP_CALLERS",
      "pass": true
    },
    {
      "id": "C_TLP_EXTERNAL",
      "pass": true
    },
    {
      "id": "C_TLP_HASHES",
      "pass": true
    },
    {
      "id": "C_TLP_NULL_SYNTHETIC",
      "pass": true
    },
    {
      "id": "C_VALID_COUNT_ACCEPTED",
      "pass": true
    },
    {
      "id": "C_WRONG_COUNT_REJECTED",
      "pass": true
    },
    {
      "id": "C_NULL_COUNT_REJECTED",
      "pass": true
    },
    {
      "id": "CUT_OFF_NOT_PROMOTED",
      "pass": true
    },
    {
      "id": "SOAK_SCOPE_VALID",
      "pass": true
    },
    {
      "id": "NO_NUMERIC_BARINEL",
      "pass": true
    },
    {
      "id": "NO_SMT_SOLVER_CLAIM",
      "pass": true
    },
    {
      "id": "STATIC_EDGE_NOT_EXECUTION",
      "pass": true
    }
  ],
  "findings": [
    {
      "id": "M08-F1",
      "claim": "Historical caller snapshot count 38, lexical edge count 76, callee labels 39; not runtime execution evidence",
      "evidence": [
        "M08_Q01",
        "M08_Q02",
        "M08_Q05"
      ],
      "scope": "MEASURED_ASOF"
    },
    {
      "id": "M08-F2",
      "claim": "External lifecycle population six and SQL callers 38 are distinct domains; TLP partitions independently reconcile their classes",
      "evidence": [
        "M08_Q03",
        "M08_Q06"
      ],
      "scope": "MEASURED_ASOF"
    },
    {
      "id": "M08-F3",
      "claim": "Snapshot source has no usable pg_stat timing; absence under track_functions none cannot prove zero use",
      "evidence": [
        "M08_Q10"
      ],
      "scope": "MEASURED_LIMIT"
    },
    {
      "id": "M08-F4",
      "claim": "Three modeled contradiction families yield eight GDE minimal 3-component hitting sets; no proven root cause",
      "evidence": [
        "M08_Q08",
        "M08_Q09"
      ],
      "scope": "MODELLED_DIAGNOSIS"
    },
    {
      "id": "M08-F5",
      "claim": "ATMS evidentiary retractions propagate to claims while TLP synthetic counterexamples reject invalid/unknown coverage",
      "evidence": [
        "M08_Q01",
        "M08_Q07",
        "M08_Q08",
        "M08_Q11",
        "M08_Q12"
      ],
      "scope": "EXECUTED_METHOD_TESTS"
    }
  ],
  "causal_model": {
    "status": "UNKNOWN_NOT_PROVEN",
    "hypotheses": [
      "Historical source promoted to current without version",
      "Nominal call graph confused with execution",
      "No telemetry used as zero usage"
    ],
    "falsifiers": [
      "qualified current cut with equal identity",
      "dynamic invocation traces",
      "comparable per-stage durations"
    ]
  },
  "candidate_repairs": [
    {
      "action": "Versioned compare of source identities and execution",
      "status": "VERIFY_FIRST_PROPOSAL"
    },
    {
      "action": "Materialized three-valued population and negative guards",
      "status": "VERIFY_FIRST_PROPOSAL"
    }
  ],
  "chosen_repair": "VERIFY_FIRST_NO_RUNTIME_MUTATION",
  "rejected_alternatives": [
    "Retire cached callers from name only",
    "Grant read-only principal EXECUTE",
    "Treat modeled GDE as confirmed fix",
    "Invent BARINEL priors or SMT proof"
  ],
  "omissions_searched": [
    "hash validity vs canonical method",
    "edge/static execution",
    "lifecycle and negative source candidate",
    "time cutoff and receipts",
    "TLP TRUE FALSE NULL",
    "ATMS invalidation",
    "GDE minimality"
  ],
  "unresolved": [
    "full execution traces unavailable",
    "historical hash creation algorithm UNKNOWN",
    "current CP2 authority under P0 not evidenced",
    "E2E timing cohorts unknown"
  ],
  "constraints_preserved": [
    "P0 cutoff",
    "read-only",
    "individual method only",
    "no external judge",
    "no production or grants"
  ],
  "conclusion": "D_M_C_METHOD_EXECUTED_MATERIAL_RESEARCH_WITH_UNRESOLVED_CAUSALITY"
}
$m08_raw$;v_doc jsonb;
 v_spec jsonb:=$m08_spec${"status":"READY","action_kind":"VERIFY_QUERY_ONCE","recipe_mode":"READBACK_EXACT","requires_material_execution":true,"contract_family":"PE10_METHOD_EXECUTION_EVIDENCE","precision":"PE10_METHOD_V1_MATERIAL_EVIDENCE","assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"checkpoint_identity":"PE10_M08","method_algorithms":"D+M+C","literal_sql_count":14,"gde_minimal_hitting_sets":8,"atms_counterfactuals_passed":6,"negative_tests_passed":15,"sql_callers_asof":38,"source_event_id":20161,"git_source_verified":true,"runtime_modified":false}},"evidence_ref":"https://github.com/cristhianlujan/claude-persona-lf-patch/blob/c5c8b55de2a4aa43ae243e48d2f996714c1f8f81/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M08_RAW_V2.json#git_blob_sha=03f0fac382c7144bdd14c9b642e09455c38b3090","verification_queries":["SELECT id,created_at,payload->>'source_pack_version' source_pack,payload->>'sql_caller_count' declared_sql,payload->'scope_guards' scope_guards FROM public.lf_eventos WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'","SELECT count(*) total,count(*) FILTER(WHERE x->>'operational_class'='ACTIVE') t,count(*) FILTER(WHERE NOT(x->>'operational_class'='ACTIVE')) f,count(*) FILTER(WHERE (x->>'operational_class'='ACTIVE') IS NULL) n,count(DISTINCT x->>'dedupe_key') unique_caller FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161","SELECT count(*) total,count(*) FILTER(WHERE x->>'operational_class'='ACTIVE') t,count(*) FILTER(WHERE NOT(x->>'operational_class'='ACTIVE')) f,count(*) FILTER(WHERE (x->>'operational_class'='ACTIVE') IS NULL) n FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'external_inventory') x WHERE e.id=20161","SELECT id,created_at,receipt_kind,subject_ref,payload->>'verification_status' verified,payload->>'screens_total' screens,payload->>'families_total' families,payload->>'known_false_pass_signals' false_pass,payload->>'unresolved_d4' d4 FROM programacion.provenance_receipts WHERE id=38 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'","SELECT codigo,primera_vez,causa_raiz,prevencion,validacion FROM transversal.error_knowledge WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001') AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z' ORDER BY codigo","WITH v(x) AS (VALUES ('ACTIVE'::text),('RETIRED'::text),(NULL::text)) SELECT count(*) total,count(*) FILTER(WHERE x='ACTIVE') t,count(*) FILTER(WHERE NOT(x='ACTIVE')) f,count(*) FILTER(WHERE (x='ACTIVE') IS NULL) n FROM v","WITH c(expected,observed) AS (VALUES(38,38),(38,36),(38,NULL::int)) SELECT expected,observed,(expected=observed) IS TRUE accepted FROM c ORDER BY observed NULLS LAST"],"expected":"M08 D/M/C material source readbacks and method execution; no correctness score, live fix or benchmark.","forbidden":["INVENT_CAUSAL_REPAIR","MARK_DONE_FROM_RAW_ONLY","RECLASSIFY_TIME_CUTOFF","ALTER_OTHER_CHECKPOINTS","CLAIM_SMT_OR_BARINEL"],"target":{"checkpoint":"PE10_M08","declared_events":[20161],"declared_objects":["programacion.engineering_work_checkpoints","public.lf_eventos","programacion.provenance_receipts","transversal.error_knowledge"],"evidence_artifacts":[{"path":"cristhianlujan/claude-persona-lf-patch:docs/profile_updater/experiments/pe10_methods32_p0/PE10_M08_RAW_V2.json","role":"EVIDENCE","purpose":"M08_DMC_ORIGINAL_SPECIFIC_RAW","target_kind":"EXACT_EXISTING_FILE"}]}}$m08_spec$::jsonb;
 v_ref text:='https://github.com/cristhianlujan/claude-persona-lf-patch/blob/c5c8b55de2a4aa43ae243e48d2f996714c1f8f81/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M08_RAW_V2.json#git_blob_sha=03f0fac382c7144bdd14c9b642e09455c38b3090';v_prev text:='chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M08.json#sha256=197bba20c5ac02a7bc0a70e43246499798af8fcca068c091eda6f9df165befd1';
 v_blob text;v_q int;v_gde int;v_atms int;v_neg int;v_ekb int;v_n int;
 v_contract jsonb;v_obs jsonb;v_result jsonb;v_assertion jsonb;v_transition jsonb;v_receipt text;
 v_msg text;v_ctx text;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
 AND target_code LIKE '%lf_pe10_m08_dmc_governed_close_v1'
 AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'M08_TRAIN_EXECUTION_ABSENT'; END IF;
 IF (SELECT status FROM programacion.engineering_work_items WHERE id=1133)<>'IN_PROGRESS'
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>7
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>25
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M08'
 AND status='PENDING' AND evidence_ref=v_prev AND assertion_receipt IS NULL AND completed_at IS NULL)<>1
 OR (SELECT count(*) FROM programacion.pe10_method_variants WHERE method_code='PE10_M08'
 AND case_ref='PE10-IG-M107-M109-P0' AND base_code='A'
 AND algorithm_codes=ARRAY['D','M','C']::text[])<>1
 OR (SELECT count(*) FROM programacion.engineering_plan_units WHERE work_item_id=1133
 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32'
 AND unit_metadata#>>'{action_specs_v1,PE10_M08,status}'='BLOCK_PENDING_MATERIAL_RESEARCH_AND_VALIDATION')<>1
 THEN RAISE EXCEPTION 'M08_PRESTATE_DRIFT'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=1133 AND checkpoint_code IN('PE10_M01','PE10_M02','PE10_M03','PE10_M04','PE10_M05','PE10_M06','PE10_M07')
 AND status='DONE' AND assertion_receipt->>'passed'='true'
 AND assertion_contract_sha256=assertion_receipt->>'contract_sha256'
 AND assertion_receipt_sha256 IN ('1c174f3277f9656ffc4146c210ac64cd037fc92d4fb34d7a7959fe826e3f9b01','0079973e1fec8787d2ef45d92131cad58bcb59f3c591aaf2badd8d86fe34c51b','0cbbc9d58552b2c5ea3d2c9bca1b07c6467cd4145720905f38fc5bf07a46e2a1','49ff7ae0d5966211ccb5a8caccc5718a61677c375a4a4a35c03e2bd6def7697e','085c478b380e63908672c0382798750a9a075afc9b8fa21d0fa809db0684e90e','4d5a9c761bc0171efa908e97d471cb1d372046b235274f141695d4665f1cc4cb','508081f732648de4caa9b7b95bafba2283f5d2e719323a90d941fe3bedbfdd4a'))<>7
 THEN RAISE EXCEPTION 'M08_PREVIOUS_RECEIPTS_CHANGED'; END IF;

 v_blob:=encode(extensions.digest(convert_to('blob '||octet_length(convert_to(v_raw,'UTF8'))::text,'UTF8')
 ||decode('00','hex')||convert_to(v_raw,'UTF8'),'sha1'),'hex');
 IF v_blob<>'03f0fac382c7144bdd14c9b642e09455c38b3090' THEN RAISE EXCEPTION 'M08_GIT_RAW_HASH_MISMATCH'; END IF;
 v_doc:=v_raw::jsonb;
 IF v_doc->>'schema'<>'PE10_METHOD_RAW_V2'
 OR v_doc->>'case_ref'<>'PE10-IG-M107-M109-P0'
 OR v_doc->>'method_code'<>'PE10_M08'
 OR v_doc->>'base_code'<>'A'
 OR v_doc->'algorithm_codes'<>'["D","M","C"]'::jsonb
 OR v_doc->>'source_cutoff'<>'2026-10-15T00:00:00Z'
 OR v_doc#>>'{original_preserved,sha256}'<>'197bba20c5ac02a7bc0a70e43246499798af8fcca068c091eda6f9df165befd1'
 OR v_doc->>'external_method_scoring'<>'NOT_PERFORMED'
 OR v_doc->>'chosen_repair'<>'VERIFY_FIRST_NO_RUNTIME_MUTATION'
 OR v_doc->>'conclusion'<>'D_M_C_METHOD_EXECUTED_MATERIAL_RESEARCH_WITH_UNRESOLVED_CAUSALITY'
 THEN RAISE EXCEPTION 'M08_RAW_IDENTITY_NOT_QUALIFIED'; END IF;

 SELECT count(*) INTO v_q FROM jsonb_array_elements(v_doc->'sql_evidence') e
 WHERE e->>'id' ~ '^M08_Q(0[1-9]|1[0-4])$'
 AND e->>'sql_literal' ~* '^(SELECT|WITH) '
 AND e->>'source'='SUPABASE_READ_ONLY'
 AND jsonb_typeof(e->'rows')='array'
 AND (e->>'rows_returned')::int=jsonb_array_length(e->'rows')
 AND jsonb_array_length(e->'rows')>0;
 IF v_q<>14 OR jsonb_array_length(v_doc->'sql_evidence')<>14
 OR (SELECT count(DISTINCT e->>'id') FROM jsonb_array_elements(v_doc->'sql_evidence') e)<>14
 OR v_doc#>>'{sql_evidence,1,rows,0,total}'<>'38'
 OR v_doc#>>'{sql_evidence,2,rows,0,total}'<>'6'
 OR v_doc#>>'{sql_evidence,4,rows,0,edges}'<>'76'
 OR v_doc#>>'{sql_evidence,6,rows,0,verified}'<>'VERIFIED'
 OR v_doc#>>'{sql_evidence,10,rows,0,n}'<>'1'
 THEN RAISE EXCEPTION 'M08_SQL_READBACK_INVALID'; END IF;

 SELECT count(*) INTO v_gde FROM jsonb_array_elements(v_doc#>'{algorithm_execution,D,minimal_hitting_sets}') s
 WHERE jsonb_array_length(s)=3
 AND (s ? 'ASOF_TO_CURRENT_PROMOTION' OR s ? 'SOURCE_VERSION_READER_MISSING')
 AND (s ? 'GRAPH_MENTION_AS_CALL' OR s ? 'EXECUTION_TRACE_GAP')
 AND (s ? 'ZERO_STAT_AS_ZERO_USE' OR s ? 'QUALIFIED_DURATION_COHORT_ABSENT');
 SELECT count(*) INTO v_atms FROM jsonb_array_elements(v_doc#>'{algorithm_execution,M,counterfactuals}') s
 WHERE s->'expected'=s->'observed';
 SELECT count(*) INTO v_neg FROM jsonb_array_elements(v_doc->'negative_tests') s WHERE s->>'pass'='true';
 IF v_gde<>8 OR jsonb_array_length(v_doc#>'{algorithm_execution,D,minimal_hitting_sets}')<>8
 OR v_atms<>6 OR jsonb_array_length(v_doc#>'{algorithm_execution,M,counterfactuals}')<>6
 OR v_neg<>15 OR jsonb_array_length(v_doc->'negative_tests')<>15
 OR v_doc#>>'{algorithm_execution,D,barinel}'<>'NOT_CALIBRATABLE_NO_SPECTRA_OR_PRIORS'
 OR v_doc#>>'{algorithm_execution,D,information_gain}'<>'ORDINAL_ONLY_NO_ENTROPY_PROBABILITIES'
 OR v_doc#>>'{algorithm_execution,C,solver}'<>'NOT_USED_NO_COMPATIBLE_SMT'
 OR v_doc#>>'{algorithm_execution,C,tlp_populations,sql_callers,total}'<>'38'
 OR v_doc#>>'{algorithm_execution,C,tlp_populations,external,total}'<>'6'
 OR v_doc#>>'{algorithm_execution,C,tlp_populations,synthetic,n}'<>'1'
 OR jsonb_array_length(v_doc#>'{algorithm_execution,C,contract_cases}')<>3
 THEN RAISE EXCEPTION 'M08_COMBINED_ALGORITHMS_OR_NEGATIVES_INCOMPLETE'; END IF;

 SELECT count(*) INTO v_ekb FROM transversal.error_knowledge WHERE codigo IN
 ('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001')
 AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z';
 IF v_ekb<>2
 OR (SELECT count(*) FROM public.lf_eventos WHERE id=20161
 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'
 AND jsonb_array_length(payload->'sql_callers')=38
 AND payload->'usage_stats'->>'track_functions'='none')<>1
 OR (SELECT count(*) FROM programacion.provenance_receipts WHERE id=38
 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'
 AND payload->>'verification_status'='VERIFIED')<>1
 THEN RAISE EXCEPTION 'M08_P0_AUTHORITY_READBACK_FAIL'; END IF;

 UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10_M08}',v_spec,true)
 WHERE work_item_id=1133 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32';
 GET DIAGNOSTICS v_n=ROW_COUNT;
 IF v_n<>1 THEN RAISE EXCEPTION 'M08_ACTION_SPEC_RECORDING_COUNT'; END IF;
 v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M08',
 programacion.fn_engineering_checkpoint_action_spec_v3('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M08'));
 IF v_contract->>'status'<>'READY' OR v_contract->>'mode'<>'EXPLICIT_PASS_WHEN_SUBSET'
 THEN RAISE EXCEPTION 'M08_ASSERTION_CONTRACT_NOT_READY:%',coalesce(v_contract::text,'NULL'); END IF;
 v_obs:=jsonb_build_object('checkpoint_identity','PE10_M08','method_algorithms','D+M+C','literal_sql_count',14,
 'gde_minimal_hitting_sets',8,'atms_counterfactuals_passed',6,'negative_tests_passed',15,
 'sql_callers_asof',38,'source_event_id',20161,'git_source_verified',true,'runtime_modified',false);
 v_result:=jsonb_build_object('status','PASS','observed',v_obs,'evidence_ref',v_ref,
 'validation_kind','PE10_M08_MATERIAL_METHOD_ONLY',
 'independent_quality_scoring','NOT_PERFORMED');
 v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M08',v_result,v_exec);
 IF v_assertion->>'passed'<>'true'
 OR coalesce(v_assertion->>'assertion_receipt_sha256','') !~ '^[a-f0-9]{64}$'
 THEN RAISE EXCEPTION 'M08_CANONICAL_ASSERTION_NOT_RECORDED'; END IF;
 v_receipt:=v_assertion->>'assertion_receipt_sha256';
 v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M08','DONE',v_ref,v_exec,
 'M08 GDE+ATMS+TLP material evidence attested; no product runtime change');
 IF v_transition#>>'{transition,status}'<>'APPLIED'
 THEN RAISE EXCEPTION 'M08_TRANSITION_NOT_APPLIED'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=1133 AND checkpoint_code='PE10_M08'
 AND status='DONE' AND completed_at IS NOT NULL AND evidence_ref=v_ref
 AND assertion_receipt_sha256=v_receipt
 AND assertion_contract_sha256=assertion_receipt->>'contract_sha256'
 AND assertion_receipt->>'passed'='true')<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>8
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>24
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M09' AND status='PENDING')<>1
 THEN RAISE EXCEPTION 'M08_FINAL_GOVERNED_READBACK_FAIL'; END IF;
EXCEPTION WHEN OTHERS THEN
 GET STACKED DIAGNOSTICS v_msg=MESSAGE_TEXT,v_ctx=PG_EXCEPTION_CONTEXT;
 RAISE EXCEPTION 'M08_TRAIN_ROOT_CAUSE state=% msg=% context=%',SQLSTATE,left(v_msg,280),left(v_ctx,140) USING ERRCODE=SQLSTATE;
END $m08_close$;
