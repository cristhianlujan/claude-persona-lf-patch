-- PE10/M11 research-only close through ACTUALIZACION_DB_LF Migration Merge Train.
DO $m11_close$
DECLARE
 v_exec text;v_raw text:=$m11_raw${
  "schema": "PE10_METHOD_RAW_V2",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M11",
  "base_code": "A",
  "algorithm_codes": [
    "M",
    "E"
  ],
  "source_cutoff": "2026-10-15T00:00:00Z",
  "original_preserved": {
    "ref": "chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M11.json",
    "sha256": "2e96a42a53379abc98ce503a60db4fabedfdb68f222605b137618fa9ca5872be"
  },
  "producer": "Single SRCR+M+E method run without other method outputs",
  "external_evaluation": "NOT_PERFORMED",
  "source_scope": "P0_HISTORICAL_READ_ONLY",
  "sql_evidence": [
    {
      "id": "M11_Q01",
      "sql_literal": "SELECT id,created_at,payload->>'source_pack_version' source_pack,payload->'historical_provenance_only' provenance,payload->'scope_guards' scope_guards FROM public.lf_eventos WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'",
      "rows": [
        {
          "id": 20161,
          "created_at": "2026-10-04 05:14:40.880842+00",
          "source_pack": "SOURCE_PACK_V1",
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
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_PRE_CUTOFF"
    },
    {
      "id": "M11_Q02",
      "sql_literal": "SELECT count(*) total_callers,count(DISTINCT x->>'dedupe_key') unique_callers,count(*) FILTER(WHERE x->>'currentness_source'='LIVE_PG_PROC') source_labeled_live FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161",
      "rows": [
        {
          "total_callers": 38,
          "unique_callers": 38,
          "source_labeled_live": 38
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_PRE_CUTOFF"
    },
    {
      "id": "M11_Q03",
      "sql_literal": "SELECT count(*) lexical_edges,count(DISTINCT (x->>'caller')||'->'||callee.name) distinct_edges,count(DISTINCT callee.name) target_names FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x CROSS JOIN LATERAL jsonb_array_elements_text(x->'callees') callee(name) WHERE e.id=20161",
      "rows": [
        {
          "lexical_edges": 76,
          "distinct_edges": 76,
          "target_names": 39
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_PRE_CUTOFF"
    },
    {
      "id": "M11_Q04",
      "sql_literal": "SELECT jsonb_array_length(payload->'trigger_bindings') trigger_rows,jsonb_array_length(payload->'external_inventory') external_rows,jsonb_array_length(payload->'consumer_relation_snapshot_json_rows') relation_rows,payload->'usage_stats' stats FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "trigger_rows": 21,
          "external_rows": 6,
          "relation_rows": 27,
          "stats": {
            "ig_stat_rows": 0,
            "interpretation": "track_functions none means zero stat rows cannot prove no usage; static governed graph supplies inventory currentness",
            "track_functions": "none"
          }
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_PRE_CUTOFF"
    },
    {
      "id": "M11_Q05",
      "sql_literal": "SELECT id,created_at,receipt_kind,subject_ref,payload->>'verification_status' verified,payload->>'pass' passed,payload->>'screens_total' screens,payload->>'families_total' families,payload->>'known_false_pass_signals' false_pass,payload->>'unresolved_d4' d4 FROM programacion.provenance_receipts WHERE id=38 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'",
      "rows": [
        {
          "id": 38,
          "created_at": "2026-10-07 16:01:00.760627+00",
          "receipt_kind": "EVIDENCE_VERIFICATION",
          "subject_ref": "plan://IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.11/SOAK_OBSERVATION_HISTORY_V2",
          "verified": "VERIFIED",
          "passed": "true",
          "screens": "13",
          "families": "47",
          "false_pass": "0",
          "d4": "0"
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_PRE_CUTOFF"
    },
    {
      "id": "M11_Q06",
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
      "scope": "HISTORICAL_SOURCE_PRE_CUTOFF"
    },
    {
      "id": "M11_Q07",
      "sql_literal": "SELECT payload->'deduplication' deduplication,payload->'excluded_name_candidate' excluded_candidate,payload->'ambiguous_name_candidates_checked' ambiguous_names FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "deduplication": {
            "rule": "One logical caller identity per source URI/object identity; evidence from multiple governed sources is merged instead of double-counted.",
            "router_identity": "PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1 maps to live SQL lf_ops.fn_lf_router_input_governance_resolve_v1.",
            "profiles_edge_identity": "EDGE_FN_LF_PROFILES_GOVERNANCE_CALLER_V1 maps to live Edge lf-profiles-governance-caller-v1."
          },
          "excluded_candidate": {
            "object": "lf-profile-creator-governance-caller-v1",
            "reason": "Current caller.ts invokes configured LF_PROFILE_CREATOR_RUNTIME_SLUG/default run-creacion-perfil-lf and contains no IG call; name/existence is not usage evidence.",
            "sha256": "27594e559e752587c5644463efc67fb9be245319b856766d85435431325cf6ee",
            "version": 16,
            "edge_marker": "ACTIVE",
            "classification": "NOT_IG_CALLER",
            "verified_target": "run-creacion-perfil-lf"
          },
          "ambiguous_names": 1
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_PRE_CUTOFF"
    },
    {
      "id": "M11_Q08",
      "sql_literal": "SELECT count(*) hashes,count(*) FILTER(WHERE x->>'definition_md5' ~ '^[0-9a-f]{32}$') format_valid,count(*) FILTER(WHERE x->>'definition_md5' IS NULL) missing_hash FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161",
      "rows": [
        {
          "hashes": 38,
          "format_valid": 38,
          "missing_hash": 0
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_PRE_CUTOFF"
    },
    {
      "id": "M11_Q09",
      "sql_literal": "SELECT count(*) FILTER(WHERE created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z') before_cutoff,count(*) FILTER(WHERE created_at>=TIMESTAMPTZ '2026-10-15T00:00:00Z') after_cutoff FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "before_cutoff": 1,
          "after_cutoff": 0
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_PRE_CUTOFF"
    },
    {
      "id": "M11_Q10",
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
      "scope": "CURRENT_PRINCIPAL_NOT_P0"
    }
  ],
  "algorithm_execution": {
    "M": {
      "facts": [
        "E20161",
        "R38",
        "EKB2",
        "ASOF",
        "SAFE_SELECT_ROUTE",
        "NO_TELEMETRY"
      ],
      "rules": {
        "CALLERS_ASOF": [
          [
            "E20161",
            "ASOF"
          ]
        ],
        "HIST_SOAK": [
          [
            "R38",
            "ASOF"
          ]
        ],
        "HIST_CP2_RISK": [
          [
            "EKB2",
            "ASOF"
          ]
        ],
        "SOURCE_CAUTION": [
          [
            "CALLERS_ASOF"
          ]
        ],
        "METHOD_RISK": [
          [
            "HIST_CP2_RISK"
          ],
          [
            "SOURCE_CAUTION"
          ]
        ],
        "SAFE_VERIFICATION": [
          [
            "SAFE_SELECT_ROUTE",
            "HIST_CP2_RISK"
          ],
          [
            "SAFE_SELECT_ROUTE",
            "SOURCE_CAUTION"
          ]
        ],
        "ZERO_STATS_NOT_NO_USE": [
          [
            "E20161",
            "NO_TELEMETRY"
          ]
        ]
      },
      "nogoods": [
        [
          "ASOF",
          "CLAIM_CURRENT"
        ],
        [
          "NO_TELEMETRY",
          "CLAIM_ZERO_USAGE"
        ]
      ],
      "minimal_justifications": {
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
        "ASOF": [
          [
            "ASOF"
          ]
        ],
        "SAFE_SELECT_ROUTE": [
          [
            "SAFE_SELECT_ROUTE"
          ]
        ],
        "NO_TELEMETRY": [
          [
            "NO_TELEMETRY"
          ]
        ],
        "CALLERS_ASOF": [
          [
            "ASOF",
            "E20161"
          ]
        ],
        "HIST_SOAK": [
          [
            "ASOF",
            "R38"
          ]
        ],
        "HIST_CP2_RISK": [
          [
            "ASOF",
            "EKB2"
          ]
        ],
        "SOURCE_CAUTION": [
          [
            "ASOF",
            "E20161"
          ]
        ],
        "METHOD_RISK": [
          [
            "ASOF",
            "E20161"
          ],
          [
            "ASOF",
            "EKB2"
          ]
        ],
        "SAFE_VERIFICATION": [
          [
            "ASOF",
            "E20161",
            "SAFE_SELECT_ROUTE"
          ],
          [
            "ASOF",
            "EKB2",
            "SAFE_SELECT_ROUTE"
          ]
        ],
        "ZERO_STATS_NOT_NO_USE": [
          [
            "E20161",
            "NO_TELEMETRY"
          ]
        ]
      },
      "counterfactuals": [
        {
          "id": "M11_CF_1",
          "removed": [],
          "labels": {
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
            "ASOF": [
              [
                "ASOF"
              ]
            ],
            "SAFE_SELECT_ROUTE": [
              [
                "SAFE_SELECT_ROUTE"
              ]
            ],
            "NO_TELEMETRY": [
              [
                "NO_TELEMETRY"
              ]
            ],
            "CALLERS_ASOF": [
              [
                "ASOF",
                "E20161"
              ]
            ],
            "HIST_SOAK": [
              [
                "ASOF",
                "R38"
              ]
            ],
            "HIST_CP2_RISK": [
              [
                "ASOF",
                "EKB2"
              ]
            ],
            "SOURCE_CAUTION": [
              [
                "ASOF",
                "E20161"
              ]
            ],
            "METHOD_RISK": [
              [
                "ASOF",
                "E20161"
              ],
              [
                "ASOF",
                "EKB2"
              ]
            ],
            "SAFE_VERIFICATION": [
              [
                "ASOF",
                "E20161",
                "SAFE_SELECT_ROUTE"
              ],
              [
                "ASOF",
                "EKB2",
                "SAFE_SELECT_ROUTE"
              ]
            ],
            "ZERO_STATS_NOT_NO_USE": [
              [
                "E20161",
                "NO_TELEMETRY"
              ]
            ]
          },
          "state": "VERIFY_FIRST"
        },
        {
          "id": "M11_CF_2",
          "removed": [
            "E20161"
          ],
          "labels": {
            "E20161": [],
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
            "ASOF": [
              [
                "ASOF"
              ]
            ],
            "SAFE_SELECT_ROUTE": [
              [
                "SAFE_SELECT_ROUTE"
              ]
            ],
            "NO_TELEMETRY": [
              [
                "NO_TELEMETRY"
              ]
            ],
            "CALLERS_ASOF": [],
            "HIST_SOAK": [
              [
                "ASOF",
                "R38"
              ]
            ],
            "HIST_CP2_RISK": [
              [
                "ASOF",
                "EKB2"
              ]
            ],
            "SOURCE_CAUTION": [],
            "METHOD_RISK": [
              [
                "ASOF",
                "EKB2"
              ]
            ],
            "SAFE_VERIFICATION": [
              [
                "ASOF",
                "EKB2",
                "SAFE_SELECT_ROUTE"
              ]
            ],
            "ZERO_STATS_NOT_NO_USE": []
          },
          "state": "VERIFY_FIRST"
        },
        {
          "id": "M11_CF_3",
          "removed": [
            "EKB2"
          ],
          "labels": {
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
            "EKB2": [],
            "ASOF": [
              [
                "ASOF"
              ]
            ],
            "SAFE_SELECT_ROUTE": [
              [
                "SAFE_SELECT_ROUTE"
              ]
            ],
            "NO_TELEMETRY": [
              [
                "NO_TELEMETRY"
              ]
            ],
            "CALLERS_ASOF": [
              [
                "ASOF",
                "E20161"
              ]
            ],
            "HIST_SOAK": [
              [
                "ASOF",
                "R38"
              ]
            ],
            "HIST_CP2_RISK": [],
            "SOURCE_CAUTION": [
              [
                "ASOF",
                "E20161"
              ]
            ],
            "METHOD_RISK": [
              [
                "ASOF",
                "E20161"
              ]
            ],
            "SAFE_VERIFICATION": [
              [
                "ASOF",
                "E20161",
                "SAFE_SELECT_ROUTE"
              ]
            ],
            "ZERO_STATS_NOT_NO_USE": [
              [
                "E20161",
                "NO_TELEMETRY"
              ]
            ]
          },
          "state": "VERIFY_FIRST"
        },
        {
          "id": "M11_CF_4",
          "removed": [
            "R38"
          ],
          "labels": {
            "E20161": [
              [
                "E20161"
              ]
            ],
            "R38": [],
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
            "SAFE_SELECT_ROUTE": [
              [
                "SAFE_SELECT_ROUTE"
              ]
            ],
            "NO_TELEMETRY": [
              [
                "NO_TELEMETRY"
              ]
            ],
            "CALLERS_ASOF": [
              [
                "ASOF",
                "E20161"
              ]
            ],
            "HIST_SOAK": [],
            "HIST_CP2_RISK": [
              [
                "ASOF",
                "EKB2"
              ]
            ],
            "SOURCE_CAUTION": [
              [
                "ASOF",
                "E20161"
              ]
            ],
            "METHOD_RISK": [
              [
                "ASOF",
                "E20161"
              ],
              [
                "ASOF",
                "EKB2"
              ]
            ],
            "SAFE_VERIFICATION": [
              [
                "ASOF",
                "E20161",
                "SAFE_SELECT_ROUTE"
              ],
              [
                "ASOF",
                "EKB2",
                "SAFE_SELECT_ROUTE"
              ]
            ],
            "ZERO_STATS_NOT_NO_USE": [
              [
                "E20161",
                "NO_TELEMETRY"
              ]
            ]
          },
          "state": "VERIFY_FIRST"
        },
        {
          "id": "M11_CF_5",
          "removed": [
            "E20161",
            "EKB2"
          ],
          "labels": {
            "E20161": [],
            "R38": [
              [
                "R38"
              ]
            ],
            "EKB2": [],
            "ASOF": [
              [
                "ASOF"
              ]
            ],
            "SAFE_SELECT_ROUTE": [
              [
                "SAFE_SELECT_ROUTE"
              ]
            ],
            "NO_TELEMETRY": [
              [
                "NO_TELEMETRY"
              ]
            ],
            "CALLERS_ASOF": [],
            "HIST_SOAK": [
              [
                "ASOF",
                "R38"
              ]
            ],
            "HIST_CP2_RISK": [],
            "SOURCE_CAUTION": [],
            "METHOD_RISK": [],
            "SAFE_VERIFICATION": [],
            "ZERO_STATS_NOT_NO_USE": []
          },
          "state": "NEEDS_MORE_EVIDENCE"
        },
        {
          "id": "M11_CF_6",
          "removed": [
            "SAFE_SELECT_ROUTE"
          ],
          "labels": {
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
            "ASOF": [
              [
                "ASOF"
              ]
            ],
            "SAFE_SELECT_ROUTE": [],
            "NO_TELEMETRY": [
              [
                "NO_TELEMETRY"
              ]
            ],
            "CALLERS_ASOF": [
              [
                "ASOF",
                "E20161"
              ]
            ],
            "HIST_SOAK": [
              [
                "ASOF",
                "R38"
              ]
            ],
            "HIST_CP2_RISK": [
              [
                "ASOF",
                "EKB2"
              ]
            ],
            "SOURCE_CAUTION": [
              [
                "ASOF",
                "E20161"
              ]
            ],
            "METHOD_RISK": [
              [
                "ASOF",
                "E20161"
              ],
              [
                "ASOF",
                "EKB2"
              ]
            ],
            "SAFE_VERIFICATION": [],
            "ZERO_STATS_NOT_NO_USE": [
              [
                "E20161",
                "NO_TELEMETRY"
              ]
            ]
          },
          "state": "NEEDS_MORE_EVIDENCE"
        },
        {
          "id": "M11_CF_7",
          "removed": [
            "E20161",
            "R38"
          ],
          "labels": {
            "E20161": [],
            "R38": [],
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
            "SAFE_SELECT_ROUTE": [
              [
                "SAFE_SELECT_ROUTE"
              ]
            ],
            "NO_TELEMETRY": [
              [
                "NO_TELEMETRY"
              ]
            ],
            "CALLERS_ASOF": [],
            "HIST_SOAK": [],
            "HIST_CP2_RISK": [
              [
                "ASOF",
                "EKB2"
              ]
            ],
            "SOURCE_CAUTION": [],
            "METHOD_RISK": [
              [
                "ASOF",
                "EKB2"
              ]
            ],
            "SAFE_VERIFICATION": [
              [
                "ASOF",
                "EKB2",
                "SAFE_SELECT_ROUTE"
              ]
            ],
            "ZERO_STATS_NOT_NO_USE": []
          },
          "state": "VERIFY_FIRST"
        },
        {
          "id": "M11_CF_8",
          "removed": [
            "EKB2",
            "R38"
          ],
          "labels": {
            "E20161": [
              [
                "E20161"
              ]
            ],
            "R38": [],
            "EKB2": [],
            "ASOF": [
              [
                "ASOF"
              ]
            ],
            "SAFE_SELECT_ROUTE": [
              [
                "SAFE_SELECT_ROUTE"
              ]
            ],
            "NO_TELEMETRY": [
              [
                "NO_TELEMETRY"
              ]
            ],
            "CALLERS_ASOF": [
              [
                "ASOF",
                "E20161"
              ]
            ],
            "HIST_SOAK": [],
            "HIST_CP2_RISK": [],
            "SOURCE_CAUTION": [
              [
                "ASOF",
                "E20161"
              ]
            ],
            "METHOD_RISK": [
              [
                "ASOF",
                "E20161"
              ]
            ],
            "SAFE_VERIFICATION": [
              [
                "ASOF",
                "E20161",
                "SAFE_SELECT_ROUTE"
              ]
            ],
            "ZERO_STATS_NOT_NO_USE": [
              [
                "E20161",
                "NO_TELEMETRY"
              ]
            ]
          },
          "state": "VERIFY_FIRST"
        }
      ],
      "withdrawal_checks": "Evidence changes support labels and typed E state",
      "claims_current_source_as_live": false
    },
    "E": {
      "states": [
        "VERIFY_FIRST",
        "REPAIR_REQUIRED",
        "NEEDS_MORE_EVIDENCE",
        "NO_ACTION_SUPPORTED"
      ],
      "actual_state": "VERIFY_FIRST",
      "typed_decision_scenarios": [
        {
          "id": "E_REAL",
          "inputs": {
            "proved_defect": false,
            "causal_trace": false,
            "qualified_risk": true,
            "safe_falsifier": true,
            "material_unknown": true,
            "qualified_source": true
          },
          "expected": "VERIFY_FIRST",
          "observed": "VERIFY_FIRST"
        },
        {
          "id": "E_PROVEN_CAUSAL",
          "inputs": {
            "proved_defect": true,
            "causal_trace": true,
            "qualified_risk": true,
            "safe_falsifier": true,
            "material_unknown": false,
            "qualified_source": true
          },
          "expected": "REPAIR_REQUIRED",
          "observed": "REPAIR_REQUIRED"
        },
        {
          "id": "E_ONLY_PERMISSION_42501",
          "inputs": {
            "proved_defect": false,
            "causal_trace": false,
            "qualified_risk": true,
            "safe_falsifier": true,
            "material_unknown": true,
            "qualified_source": true
          },
          "expected": "VERIFY_FIRST",
          "observed": "VERIFY_FIRST"
        },
        {
          "id": "E_NO_READER",
          "inputs": {
            "proved_defect": false,
            "causal_trace": false,
            "qualified_risk": true,
            "safe_falsifier": false,
            "material_unknown": true,
            "qualified_source": false
          },
          "expected": "NEEDS_MORE_EVIDENCE",
          "observed": "NEEDS_MORE_EVIDENCE"
        },
        {
          "id": "E_COMPLETE_NEGATIVE",
          "inputs": {
            "proved_defect": false,
            "causal_trace": false,
            "qualified_risk": false,
            "safe_falsifier": false,
            "material_unknown": false,
            "qualified_source": true
          },
          "expected": "NO_ACTION_SUPPORTED",
          "observed": "NO_ACTION_SUPPORTED"
        },
        {
          "id": "E_NO_CAUSAL_TRACE",
          "inputs": {
            "proved_defect": true,
            "causal_trace": false,
            "qualified_risk": true,
            "safe_falsifier": true,
            "material_unknown": true,
            "qualified_source": true
          },
          "expected": "VERIFY_FIRST",
          "observed": "VERIFY_FIRST"
        },
        {
          "id": "E_MISSING_P0_SOURCE",
          "inputs": {
            "proved_defect": false,
            "causal_trace": false,
            "qualified_risk": false,
            "safe_falsifier": false,
            "material_unknown": true,
            "qualified_source": false
          },
          "expected": "NEEDS_MORE_EVIDENCE",
          "observed": "NEEDS_MORE_EVIDENCE"
        }
      ],
      "decision_from_retractions": [
        {
          "id": "M11_CF_1",
          "removed": [],
          "state": "VERIFY_FIRST"
        },
        {
          "id": "M11_CF_2",
          "removed": [
            "E20161"
          ],
          "state": "VERIFY_FIRST"
        },
        {
          "id": "M11_CF_3",
          "removed": [
            "EKB2"
          ],
          "state": "VERIFY_FIRST"
        },
        {
          "id": "M11_CF_4",
          "removed": [
            "R38"
          ],
          "state": "VERIFY_FIRST"
        },
        {
          "id": "M11_CF_5",
          "removed": [
            "E20161",
            "EKB2"
          ],
          "state": "NEEDS_MORE_EVIDENCE"
        },
        {
          "id": "M11_CF_6",
          "removed": [
            "SAFE_SELECT_ROUTE"
          ],
          "state": "NEEDS_MORE_EVIDENCE"
        },
        {
          "id": "M11_CF_7",
          "removed": [
            "E20161",
            "R38"
          ],
          "state": "VERIFY_FIRST"
        },
        {
          "id": "M11_CF_8",
          "removed": [
            "EKB2",
            "R38"
          ],
          "state": "VERIFY_FIRST"
        }
      ],
      "reversal_criteria": [
        {
          "trigger": "qualified same-cutoff causal defect demonstrated",
          "state": "REPAIR_REQUIRED"
        },
        {
          "trigger": "qualified evidence removes risk and unknowns",
          "state": "NO_ACTION_SUPPORTED"
        },
        {
          "trigger": "no authorized discriminating SELECT path",
          "state": "NEEDS_MORE_EVIDENCE"
        }
      ],
      "falsifiers": [
        "Authorized historical CP2 equivalent SELECT/readback",
        "Versioned caller graph at a single timestamp",
        "Representative execution traces and E2E cohort duration"
      ]
    }
  },
  "negative_tests": [
    {
      "id": "ATMS_MATERIAL_SOURCE_REMOVAL",
      "pass": true
    },
    {
      "id": "ATMS_ALTERNATE_RISK_SUPPORT",
      "pass": true
    },
    {
      "id": "ATMS_ALL_RISK_SOURCES_REMOVED",
      "pass": true
    },
    {
      "id": "ATMS_REMOVE_SAFE_SELECT_BLOCKS_VERIFY_FIRST",
      "pass": true
    },
    {
      "id": "E_TYPED_SEVEN_CASES",
      "pass": true
    },
    {
      "id": "E_FOUR_DISTINCT_STATES",
      "pass": true
    },
    {
      "id": "E_42501_NOT_FUNCTIONAL_DEFECT",
      "pass": true
    },
    {
      "id": "E_DATA_SCOPE_P0",
      "pass": true
    },
    {
      "id": "E_SOURCE_SOAK_QUALIFIED",
      "pass": true
    },
    {
      "id": "E_LIVE_USAGE_CANNOT_BE_INFERRED",
      "pass": true
    },
    {
      "id": "E_HASH_FORMAT_NOT_SOURCE_METHOD",
      "pass": true
    },
    {
      "id": "E_UNKNOWN_NOT_IMPLEMENTED",
      "pass": true
    }
  ],
  "findings": [
    {
      "id": "M11_F01",
      "claim": "Historical 38 SQL callers/76 nominal references are not actual current invocations; risk claims require versioned evidence",
      "evidence": [
        "M11_Q01",
        "M11_Q02",
        "M11_Q03"
      ],
      "type": "MEASURED_ASOF_LIMIT"
    },
    {
      "id": "M11_F02",
      "claim": "Historical verified SOAK receipt id 38 does not establish current CP2/read permissions or E2E timing",
      "evidence": [
        "M11_Q05",
        "M11_Q06"
      ],
      "type": "MEASURED_SOURCE_SCOPE"
    },
    {
      "id": "M11_F03",
      "claim": "ATMS labels retract under removal of independent source facts while alternate risk supports survive one source withdrawal",
      "evidence": [
        "M11_Q01",
        "M11_Q05",
        "M11_Q06"
      ],
      "type": "EXECUTED_METHOD"
    },
    {
      "id": "M11_F04",
      "claim": "Typed decision VERIFY_FIRST may downgrade to NEEDS_MORE_EVIDENCE when authorized read route is removed; no patch/implemented repair is demonstrated",
      "evidence": [
        "M11_Q06",
        "M11_Q10"
      ],
      "type": "EXECUTED_METHOD_WITH_UNKNOWN"
    }
  ],
  "causal_model": {
    "status": "UNPROVEN",
    "alternatives": [
      "Source-time inventory promoted to current",
      "M9.11 proof projection drift",
      "CP2 permission vs functional error"
    ],
    "falsifiers": [
      "Qualified as-of consumer identities and traces",
      "M9.11 source receipt equivalence",
      "Read-only CP2 evidence path"
    ]
  },
  "candidate_repairs": [
    {
      "action": "Reconcile qualified SOAK and CP2 evidence against historical source",
      "status": "READ_ONLY_PROPOSAL"
    },
    {
      "action": "Read once and carry source variables through ATMS instead of repeated SQL",
      "status": "PROPOSED_COST_REDUCTION_NOT_MEASURED"
    }
  ],
  "chosen_repair": {
    "state": "VERIFY_FIRST",
    "rationale": "EKB risk with legitimate SELECT falsifiers and material unknowns",
    "implementation": "NOT_PERFORMED",
    "reversal": "Demonstrated changed evidence can change classification"
  },
  "rejected_alternatives": [
    "Claim no use from track_functions none",
    "Add production patches without causal proof",
    "Elevate EXECUTE to read-only user"
  ],
  "omissions_searched": [
    "source cutoffs",
    "telemetry",
    "SOAK and CP2 authority",
    "hash syntactic validity",
    "ATMS alternative supports and nogoods",
    "typed E transitions"
  ],
  "unresolved": [
    "No causal defect proved",
    "Exact P0 live invocation graph unknown",
    "Canonical MD5 representation not established",
    "No E2E latency cohort"
  ],
  "constraints_preserved": [
    "P0 same case",
    "Only single integrated A arm",
    "No quality score",
    "No product mutation"
  ],
  "conclusion": "M_E_ALGORITHMS_EXECUTED_EVIDENCE_RETRACTION_AND_TYPED_VERIFY_FIRST"
}
$m11_raw$;v_doc jsonb;
 v_spec jsonb:=$m11_spec${"status":"READY","action_kind":"VERIFY_QUERY_ONCE","recipe_mode":"READBACK_EXACT","requires_material_execution":true,"contract_family":"PE10_METHOD_EXECUTION_EVIDENCE","precision":"PE10_METHOD_V1_MATERIAL_EVIDENCE","assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"checkpoint_identity":"PE10_M11","method_algorithms":"M+E","literal_sql_count":10,"atms_retractions_executed":8,"typed_e_scenarios_verified":7,"negative_checks_passed":12,"typed_decision":"VERIFY_FIRST","historical_source_event_id":20161,"git_source_verified":true,"runtime_modified":false}},"evidence_ref":"https://github.com/cristhianlujan/claude-persona-lf-patch/blob/534126b1b941f2e648820e3469f26bb6ae3a49f1/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M11_RAW_V2.json#git_blob_sha=432f3e292808f80930495445bb794dde6d9733ba","verification_queries":["SELECT id,created_at,payload->>'source_pack_version' source_pack,payload->'historical_provenance_only' provenance,payload->'scope_guards' scope_guards FROM public.lf_eventos WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'","SELECT count(*) total_callers,count(DISTINCT x->>'dedupe_key') unique_callers,count(*) FILTER(WHERE x->>'currentness_source'='LIVE_PG_PROC') source_labeled_live FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161","SELECT jsonb_array_length(payload->'trigger_bindings') trigger_rows,jsonb_array_length(payload->'external_inventory') external_rows,jsonb_array_length(payload->'consumer_relation_snapshot_json_rows') relation_rows,payload->'usage_stats' stats FROM public.lf_eventos WHERE id=20161","SELECT id,created_at,receipt_kind,subject_ref,payload->>'verification_status' verified,payload->>'pass' passed,payload->>'screens_total' screens,payload->>'families_total' families,payload->>'known_false_pass_signals' false_pass,payload->>'unresolved_d4' d4 FROM programacion.provenance_receipts WHERE id=38 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'","SELECT codigo,primera_vez,causa_raiz,prevencion,validacion FROM transversal.error_knowledge WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001') AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z' ORDER BY codigo"],"expected":"M ATMS evidence withdrawal materially changes support + E evidence decision, no runtime patch or method success judgment","forbidden":["CLAIM_IMPLEMENTED_REPAIR","SKIP_NEGATIVE_PROPAGATION","CLAIM_SOURCE_IS_CURRENT","OVERRIDE_PRIOR_CHECKPOINTS","BYPASS_TRAIN"],"target":{"checkpoint":"PE10_M11","declared_events":[20161],"declared_objects":["public.lf_eventos","programacion.provenance_receipts","transversal.error_knowledge","programacion.engineering_work_checkpoints"],"evidence_artifacts":[{"path":"cristhianlujan/claude-persona-lf-patch:docs/profile_updater/experiments/pe10_methods32_p0/PE10_M11_RAW_V2.json","role":"EVIDENCE","purpose":"M11_M_E_EXECUTED_DECISION_RETRACTIONS","target_kind":"EXACT_EXISTING_FILE"}]}}$m11_spec$::jsonb;
 v_ref text:='https://github.com/cristhianlujan/claude-persona-lf-patch/blob/534126b1b941f2e648820e3469f26bb6ae3a49f1/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M11_RAW_V2.json#git_blob_sha=432f3e292808f80930495445bb794dde6d9733ba';v_old text:='chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M11.json#sha256=2e96a42a53379abc98ce503a60db4fabedfdb68f222605b137618fa9ca5872be';
 v_blob text;v_q int;v_atms int;v_e int;v_negative int;v_ekb int;v_n int;v_previous int;v_four int;
 v_contract jsonb;v_obs jsonb;v_result jsonb;v_assertion jsonb;v_transition jsonb;v_receipt text;v_msg text;v_ctx text;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
 AND target_code LIKE '%lf_pe10_m11_me_governed_close_v1'
 AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'M11_NOT_IN_TRAIN_EXECUTION'; END IF;
 IF (SELECT status FROM programacion.engineering_work_items WHERE id=1133)<>'IN_PROGRESS'
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>10
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>22
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133
 AND checkpoint_code='PE10_M11' AND status='PENDING' AND evidence_ref=v_old
 AND assertion_receipt IS NULL AND completed_at IS NULL)<>1
 OR (SELECT count(*) FROM programacion.pe10_method_variants WHERE method_code='PE10_M11'
 AND base_code='A' AND case_ref='PE10-IG-M107-M109-P0'
 AND algorithm_codes=ARRAY['M','E']::text[])<>1
 OR (SELECT count(*) FROM programacion.engineering_plan_units WHERE work_item_id=1133
 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32'
 AND unit_metadata#>>'{action_specs_v1,PE10_M11,status}'='BLOCK_PENDING_MATERIAL_RESEARCH_AND_VALIDATION')<>1
 THEN RAISE EXCEPTION 'M11_PRIOR_STATE_OR_METHOD_DRIFT'; END IF;
 SELECT count(*) INTO v_previous FROM programacion.engineering_work_checkpoints c
 JOIN (VALUES ('PE10_M01','1c174f3277f9656ffc4146c210ac64cd037fc92d4fb34d7a7959fe826e3f9b01'),
 ('PE10_M02','0079973e1fec8787d2ef45d92131cad58bcb59f3c591aaf2badd8d86fe34c51b'),
 ('PE10_M03','0cbbc9d58552b2c5ea3d2c9bca1b07c6467cd4145720905f38fc5bf07a46e2a1'),
 ('PE10_M04','49ff7ae0d5966211ccb5a8caccc5718a61677c375a4a4a35c03e2bd6def7697e'),
 ('PE10_M05','085c478b380e63908672c0382798750a9a075afc9b8fa21d0fa809db0684e90e'),
 ('PE10_M06','4d5a9c761bc0171efa908e97d471cb1d372046b235274f141695d4665f1cc4cb'),
 ('PE10_M07','508081f732648de4caa9b7b95bafba2283f5d2e719323a90d941fe3bedbfdd4a'),
 ('PE10_M08','ebc8477fea336cb76c25d73cfbcdbe9fe680ca03770734e04ede3fa140512c12'),
 ('PE10_M09','f939334bc3c1d5be819c59309fc375a14fd7360fd4b8705ff6f749bdc0f805df'),
 ('PE10_M10','63855d13ae93adff8c959cc9f071136e5405dfd736a6da2aecafb38ae0cde20b')) e(code,sha)
 ON e.code=c.checkpoint_code AND e.sha=c.assertion_receipt_sha256
 WHERE c.work_item_id=1133 AND c.status='DONE' AND c.assertion_receipt->>'passed'='true'
 AND c.assertion_contract_sha256=c.assertion_receipt->>'contract_sha256';
 IF v_previous<>10 THEN RAISE EXCEPTION 'M11_PREVIOUS_RECEIPTS_FAILED'; END IF;

 v_blob:=encode(extensions.digest(convert_to('blob '||octet_length(convert_to(v_raw,'UTF8'))::text,'UTF8')
 ||decode('00','hex')||convert_to(v_raw,'UTF8'),'sha1'),'hex');
 IF v_blob<>'432f3e292808f80930495445bb794dde6d9733ba' THEN RAISE EXCEPTION 'M11_GIT_BLOB_NOT_MATCHING_RAW'; END IF;
 v_doc:=v_raw::jsonb;
 IF v_doc->>'schema'<>'PE10_METHOD_RAW_V2'
 OR v_doc->>'case_ref'<>'PE10-IG-M107-M109-P0'
 OR v_doc->>'method_code'<>'PE10_M11'
 OR v_doc->>'base_code'<>'A'
 OR v_doc->'algorithm_codes'<>'["M","E"]'::jsonb
 OR v_doc->>'source_cutoff'<>'2026-10-15T00:00:00Z'
 OR v_doc#>>'{original_preserved,sha256}'<>'2e96a42a53379abc98ce503a60db4fabedfdb68f222605b137618fa9ca5872be'
 OR v_doc->>'external_evaluation'<>'NOT_PERFORMED'
 OR v_doc#>>'{algorithm_execution,E,actual_state}'<>'VERIFY_FIRST'
 OR v_doc#>>'{chosen_repair,state}'<>'VERIFY_FIRST'
 OR v_doc->>'conclusion'<>'M_E_ALGORITHMS_EXECUTED_EVIDENCE_RETRACTION_AND_TYPED_VERIFY_FIRST'
 THEN RAISE EXCEPTION 'M11_RAW_IDENTITY_SCOPE_NOT_QUALIFIED'; END IF;
 SELECT count(*) INTO v_q FROM jsonb_array_elements(v_doc->'sql_evidence') x
 WHERE x->>'id' ~ '^M11_Q(0[1-9]|10)$' AND x->>'sql_literal' ~* '^SELECT '
 AND x->>'source'='SUPABASE_READ_ONLY' AND jsonb_typeof(x->'rows')='array'
 AND (x->>'rows_returned')::int=jsonb_array_length(x->'rows')
 AND jsonb_array_length(x->'rows')>0;
 IF v_q<>10 OR jsonb_array_length(v_doc->'sql_evidence')<>10
 OR (SELECT count(DISTINCT z->>'id') FROM jsonb_array_elements(v_doc->'sql_evidence') z)<>10
 OR v_doc#>>'{sql_evidence,1,rows,0,total_callers}'<>'38'
 OR v_doc#>>'{sql_evidence,2,rows,0,lexical_edges}'<>'76'
 OR v_doc#>>'{sql_evidence,3,rows,0,stats,track_functions}'<>'none'
 OR v_doc#>>'{sql_evidence,4,rows,0,verified}'<>'VERIFIED'
 OR v_doc#>>'{sql_evidence,8,rows,0,after_cutoff}'<>'0'
 THEN RAISE EXCEPTION 'M11_HISTORICAL_SQL_EVIDENCE_INCONSISTENT'; END IF;

 -- Material ATMS: withdrawal of all original support facts must revoke claim,
 -- while one of two independent facts can still support METHOD_RISK.
 IF v_doc#>>'{algorithm_execution,M,counterfactuals,1,state}'<>'VERIFY_FIRST'
 OR v_doc#>>'{algorithm_execution,M,counterfactuals,2,state}'<>'VERIFY_FIRST'
 OR v_doc#>>'{algorithm_execution,M,counterfactuals,4,state}'<>'NEEDS_MORE_EVIDENCE'
 OR v_doc#>>'{algorithm_execution,M,counterfactuals,5,state}'<>'NEEDS_MORE_EVIDENCE'
 OR jsonb_array_length(v_doc#>'{algorithm_execution,M,counterfactuals}')<>8
 OR jsonb_array_length(v_doc#>'{algorithm_execution,M,nogoods}')<>2
 THEN RAISE EXCEPTION 'M11_ATMS_MATERIAL_WITHDRAWAL_MISSING'; END IF;
 SELECT count(*) INTO v_atms FROM jsonb_array_elements(v_doc#>'{algorithm_execution,M,counterfactuals}') x
 WHERE x->>'state' IN('VERIFY_FIRST','NEEDS_MORE_EVIDENCE')
 AND jsonb_typeof(x->'removed')='array';
 SELECT count(*) INTO v_e FROM jsonb_array_elements(v_doc#>'{algorithm_execution,E,typed_decision_scenarios}') x
 WHERE x->>'expected'=CASE
 WHEN coalesce((x#>>'{inputs,proved_defect}')::boolean,false)
 AND coalesce((x#>>'{inputs,causal_trace}')::boolean,false) THEN 'REPAIR_REQUIRED'
 WHEN coalesce((x#>>'{inputs,qualified_risk}')::boolean,false)
 AND coalesce((x#>>'{inputs,safe_falsifier}')::boolean,false) THEN 'VERIFY_FIRST'
 WHEN coalesce((x#>>'{inputs,material_unknown}')::boolean,false)
 OR NOT coalesce((x#>>'{inputs,qualified_source}')::boolean,false) THEN 'NEEDS_MORE_EVIDENCE'
 ELSE 'NO_ACTION_SUPPORTED' END AND x->>'observed'=x->>'expected';
 SELECT count(DISTINCT x->>'observed') INTO v_four
 FROM jsonb_array_elements(v_doc#>'{algorithm_execution,E,typed_decision_scenarios}') x;
 SELECT count(*) INTO v_negative FROM jsonb_array_elements(v_doc->'negative_tests') x
 WHERE x->>'pass'='true';
 IF v_atms<>8 OR v_e<>7
 OR jsonb_array_length(v_doc#>'{algorithm_execution,E,typed_decision_scenarios}')<>7
 OR v_four<>4 OR v_negative<>12 OR jsonb_array_length(v_doc->'negative_tests')<>12
 THEN RAISE EXCEPTION 'M11_E_TYPED_OR_M_NEGATIVE_CHECKS_NOT_SUFFICIENT'; END IF;

 SELECT count(*) INTO v_ekb FROM transversal.error_knowledge
 WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001')
 AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z';
 IF v_ekb<>2
 OR (SELECT count(*) FROM public.lf_eventos WHERE id=20161
 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z' AND jsonb_array_length(payload->'sql_callers')=38
 AND payload->'usage_stats'->>'track_functions'='none')<>1
 OR (SELECT count(*) FROM programacion.provenance_receipts WHERE id=38
 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z' AND payload->>'verification_status'='VERIFIED')<>1
 THEN RAISE EXCEPTION 'M11_ASOF_SOURCE_READBACK_FAILED'; END IF;

 UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10_M11}',v_spec,true)
 WHERE work_item_id=1133 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32';
 GET DIAGNOSTICS v_n=ROW_COUNT;
 IF v_n<>1 THEN RAISE EXCEPTION 'M11_SPEC_WRITE_NOT_EXACTLY_ONE'; END IF;
 v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M11',
 programacion.fn_engineering_checkpoint_action_spec_v3('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M11'));
 IF v_contract->>'status'<>'READY' OR v_contract->>'mode'<>'EXPLICIT_PASS_WHEN_SUBSET'
 THEN RAISE EXCEPTION 'M11_CONTRACT_NOT_READY:%',coalesce(v_contract::text,'NULL'); END IF;
 v_obs:=jsonb_build_object('checkpoint_identity','PE10_M11','method_algorithms','M+E','literal_sql_count',10,
 'atms_retractions_executed',8,'typed_e_scenarios_verified',7,'negative_checks_passed',12,
 'typed_decision','VERIFY_FIRST','historical_source_event_id',20161,'git_source_verified',true,'runtime_modified',false);
 v_result:=jsonb_build_object('status','PASS','observed',v_obs,'evidence_ref',v_ref,
 'validation_kind','M11_ATMS_TO_E_MATERIAL_METHOD_EXECUTION','external_scoring','NOT_PERFORMED');
 v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M11',v_result,v_exec);
 IF v_assertion->>'passed'<>'true'
 OR coalesce(v_assertion->>'assertion_receipt_sha256','') !~ '^[a-f0-9]{64}$'
 THEN RAISE EXCEPTION 'M11_CANONICAL_ASSERTION_NOT_CONFIRMED'; END IF;
 v_receipt:=v_assertion->>'assertion_receipt_sha256';
 v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M11','DONE',v_ref,v_exec,
 'M11 method M+E evidence dependency and typed VERIFY_FIRST validated; no product repair');
 IF v_transition#>>'{transition,status}'<>'APPLIED'
 THEN RAISE EXCEPTION 'M11_CANONICAL_TRANSITION_NOT_APPLIED'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M11'
 AND status='DONE' AND completed_at IS NOT NULL AND evidence_ref=v_ref
 AND assertion_receipt_sha256=v_receipt AND assertion_receipt->>'passed'='true'
 AND assertion_contract_sha256=assertion_receipt->>'contract_sha256')<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>11
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>21
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M12' AND status='PENDING')<>1
 THEN RAISE EXCEPTION 'M11_FINAL_TRAIN_READBACK_FAIL'; END IF;
EXCEPTION WHEN OTHERS THEN
 GET STACKED DIAGNOSTICS v_msg=MESSAGE_TEXT,v_ctx=PG_EXCEPTION_CONTEXT;
 RAISE EXCEPTION 'M11_TRAIN_SQLSTATE_% msg=% context=%',SQLSTATE,left(v_msg,270),left(v_ctx,140) USING ERRCODE=SQLSTATE;
END $m11_close$;
