-- PE10 M15: exactly one checkpoint. Governance: PR/PASE -> ACTUALIZACION_DB_LF Merge Train.
-- Evidence-only method M+C+E. No production fixes, no role grants, no method-scoring.
DO $m15_train_close$
DECLARE
 v_exec text;v_raw text:=$m15_raw${
  "schema": "PE10_METHOD_RAW_V2",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M15",
  "base_code": "A",
  "algorithm_codes": [
    "M",
    "C",
    "E"
  ],
  "source_cutoff": "2026-10-15T00:00:00Z",
  "original_preserved": {
    "path": "chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M15.json",
    "sha256": "cceaeb904bad988a95be757f2bd7b5bad048f27d489ca6bc41f46ccc3f388dcb"
  },
  "producer": "Single role-bound SRCR integrated M/C/E; no other variant result as evidence",
  "external_evaluation": "NOT_PERFORMED",
  "sql_evidence": [
    {
      "id": "M15_Q01",
      "sql_literal": "SELECT id,created_at,payload->>'source_pack_version' source_pack,payload->'scope_guards' scope_guards FROM public.lf_eventos WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'",
      "rows": [
        {
          "id": 20161,
          "created_at": "2026-10-04 05:14:40.880842+00",
          "source_pack": "SOURCE_PACK_V1",
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
      "scope": "P0_SOURCE_TIME_HISTORICAL"
    },
    {
      "id": "M15_Q02",
      "sql_literal": "SELECT count(*) total,count(*) FILTER(WHERE x->>'operational_class'='ACTIVE') t,count(*) FILTER(WHERE NOT(x->>'operational_class'='ACTIVE')) f,count(*) FILTER(WHERE (x->>'operational_class'='ACTIVE') IS NULL) n,count(DISTINCT x->>'dedupe_key') unique_keys FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161",
      "rows": [
        {
          "total": 38,
          "t": 38,
          "f": 0,
          "n": 0,
          "unique_keys": 38
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "P0_SOURCE_TIME_HISTORICAL"
    },
    {
      "id": "M15_Q03",
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
      "scope": "P0_SOURCE_TIME_HISTORICAL"
    },
    {
      "id": "M15_Q04",
      "sql_literal": "SELECT count(*) total,count(*) FILTER(WHERE x->>'definition_md5'~'^[a-f0-9]{32}$') valid,count(*) FILTER(WHERE NOT(x->>'definition_md5'~'^[a-f0-9]{32}$')) invalid,count(*) FILTER(WHERE (x->>'definition_md5'~'^[a-f0-9]{32}$') IS NULL) n FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161",
      "rows": [
        {
          "total": 38,
          "valid": 38,
          "invalid": 0,
          "n": 0
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "P0_SOURCE_TIME_HISTORICAL"
    },
    {
      "id": "M15_Q05",
      "sql_literal": "WITH v(x) AS(VALUES('ACTIVE'::text),('OTHER'::text),(NULL::text)) SELECT count(*) total,count(*) FILTER(WHERE x='ACTIVE') t,count(*) FILTER(WHERE NOT(x='ACTIVE')) f,count(*) FILTER(WHERE (x='ACTIVE') IS NULL) n FROM v",
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
      "scope": "SYNTHETIC_SQL_TEST"
    },
    {
      "id": "M15_Q06",
      "sql_literal": "WITH pairs(expected,observed) AS (VALUES(38,38),(38,40),(38,NULL::int)) SELECT expected,observed,(expected=observed) IS TRUE accepted FROM pairs ORDER BY observed NULLS LAST",
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
      "scope": "SYNTHETIC_SQL_TEST"
    },
    {
      "id": "M15_Q07",
      "sql_literal": "SELECT count(*) lexical_edges,count(DISTINCT (x->>'caller')||'->'||c.name) distinct_edges FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x CROSS JOIN LATERAL jsonb_array_elements_text(x->'callees') c(name) WHERE e.id=20161",
      "rows": [
        {
          "lexical_edges": 76,
          "distinct_edges": 76
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "P0_SOURCE_TIME_HISTORICAL"
    },
    {
      "id": "M15_Q08",
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
      "scope": "P0_SOURCE_TIME_HISTORICAL"
    },
    {
      "id": "M15_Q09",
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
      "scope": "P0_SOURCE_TIME_HISTORICAL"
    },
    {
      "id": "M15_Q10",
      "sql_literal": "SELECT jsonb_array_length(payload->'trigger_bindings') triggers,jsonb_array_length(payload->'external_inventory') external_assets,payload->'usage_stats' usage_stats FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "triggers": 21,
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
      "scope": "P0_SOURCE_TIME_HISTORICAL"
    },
    {
      "id": "M15_Q11",
      "sql_literal": "SELECT count(*) FILTER(WHERE created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z') before_cutoff,count(*) FILTER(WHERE created_at>=TIMESTAMPTZ '2026-10-15T00:00:00Z') after_cutoff FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "before_cutoff": 1,
          "after_cutoff": 0
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "P0_SOURCE_TIME_HISTORICAL"
    },
    {
      "id": "M15_Q12",
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
        "ASOF_SOURCE",
        "QUALIFIED_SOAK",
        "HIST_EKB",
        "SOURCE_CUTOFF",
        "AUTH_SELECT",
        "STATS_DISABLED"
      ],
      "rules": {
        "HIST_CALLERS": [
          [
            "ASOF_SOURCE",
            "SOURCE_CUTOFF"
          ]
        ],
        "SOAK_HISTORY": [
          [
            "QUALIFIED_SOAK",
            "SOURCE_CUTOFF"
          ]
        ],
        "PRIVILEGE_RISK": [
          [
            "HIST_EKB",
            "SOURCE_CUTOFF"
          ]
        ],
        "SOURCE_RISK": [
          [
            "HIST_CALLERS"
          ]
        ],
        "METHOD_RISK": [
          [
            "PRIVILEGE_RISK"
          ],
          [
            "SOURCE_RISK"
          ]
        ],
        "SAFE_CHECK": [
          [
            "AUTH_SELECT",
            "PRIVILEGE_RISK"
          ],
          [
            "AUTH_SELECT",
            "SOURCE_RISK"
          ]
        ],
        "UNKNOWN_USAGE": [
          [
            "ASOF_SOURCE",
            "STATS_DISABLED"
          ]
        ]
      },
      "nogoods": [
        [
          "SOURCE_CUTOFF",
          "ASSERT_LIVE"
        ],
        [
          "STATS_DISABLED",
          "ASSERT_NO_USAGE"
        ]
      ],
      "minimal_justifications": {
        "ASOF_SOURCE": [
          [
            "ASOF_SOURCE"
          ]
        ],
        "QUALIFIED_SOAK": [
          [
            "QUALIFIED_SOAK"
          ]
        ],
        "HIST_EKB": [
          [
            "HIST_EKB"
          ]
        ],
        "SOURCE_CUTOFF": [
          [
            "SOURCE_CUTOFF"
          ]
        ],
        "AUTH_SELECT": [
          [
            "AUTH_SELECT"
          ]
        ],
        "STATS_DISABLED": [
          [
            "STATS_DISABLED"
          ]
        ],
        "HIST_CALLERS": [
          [
            "ASOF_SOURCE",
            "SOURCE_CUTOFF"
          ]
        ],
        "SOAK_HISTORY": [
          [
            "QUALIFIED_SOAK",
            "SOURCE_CUTOFF"
          ]
        ],
        "PRIVILEGE_RISK": [
          [
            "HIST_EKB",
            "SOURCE_CUTOFF"
          ]
        ],
        "SOURCE_RISK": [
          [
            "ASOF_SOURCE",
            "SOURCE_CUTOFF"
          ]
        ],
        "METHOD_RISK": [
          [
            "ASOF_SOURCE",
            "SOURCE_CUTOFF"
          ],
          [
            "HIST_EKB",
            "SOURCE_CUTOFF"
          ]
        ],
        "SAFE_CHECK": [
          [
            "ASOF_SOURCE",
            "AUTH_SELECT",
            "SOURCE_CUTOFF"
          ],
          [
            "AUTH_SELECT",
            "HIST_EKB",
            "SOURCE_CUTOFF"
          ]
        ],
        "UNKNOWN_USAGE": [
          [
            "ASOF_SOURCE",
            "STATS_DISABLED"
          ]
        ]
      },
      "retractions": [
        {
          "id": "M15_R1",
          "removed": [],
          "soak": true,
          "risk": true,
          "safe": true,
          "state": "VERIFY_FIRST"
        },
        {
          "id": "M15_R2",
          "removed": [
            "ASOF_SOURCE"
          ],
          "soak": true,
          "risk": true,
          "safe": true,
          "state": "VERIFY_FIRST"
        },
        {
          "id": "M15_R3",
          "removed": [
            "QUALIFIED_SOAK"
          ],
          "soak": false,
          "risk": true,
          "safe": true,
          "state": "VERIFY_FIRST"
        },
        {
          "id": "M15_R4",
          "removed": [
            "HIST_EKB"
          ],
          "soak": true,
          "risk": true,
          "safe": true,
          "state": "VERIFY_FIRST"
        },
        {
          "id": "M15_R5",
          "removed": [
            "ASOF_SOURCE",
            "HIST_EKB"
          ],
          "soak": true,
          "risk": false,
          "safe": false,
          "state": "NEEDS_MORE_EVIDENCE"
        },
        {
          "id": "M15_R6",
          "removed": [
            "AUTH_SELECT"
          ],
          "soak": true,
          "risk": true,
          "safe": false,
          "state": "NEEDS_MORE_EVIDENCE"
        },
        {
          "id": "M15_R7",
          "removed": [
            "QUALIFIED_SOAK",
            "HIST_EKB"
          ],
          "soak": false,
          "risk": true,
          "safe": true,
          "state": "VERIFY_FIRST"
        },
        {
          "id": "M15_R8",
          "removed": [
            "ASOF_SOURCE",
            "QUALIFIED_SOAK"
          ],
          "soak": false,
          "risk": true,
          "safe": true,
          "state": "VERIFY_FIRST"
        }
      ],
      "unknown_current_status": true
    },
    "C": {
      "three_valued_partitions": {
        "callers": {
          "total": 38,
          "t": 38,
          "f": 0,
          "n": 0,
          "unique_keys": 38
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
      "solver": "NOT_USED_NO_SMT",
      "business_rule_certified": false
    },
    "E": {
      "actual_state": "VERIFY_FIRST",
      "decision_scenarios": [
        {
          "id": "E_ACTUAL",
          "inputs": {
            "proven_defect": false,
            "causal": false,
            "risk": true,
            "safe": true,
            "missing": true,
            "source": true
          },
          "expected": "VERIFY_FIRST",
          "observed": "VERIFY_FIRST"
        },
        {
          "id": "E_PROVEN_DEFECT",
          "inputs": {
            "proven_defect": true,
            "causal": true,
            "risk": true,
            "safe": true,
            "missing": false,
            "source": true
          },
          "expected": "REPAIR_REQUIRED",
          "observed": "REPAIR_REQUIRED"
        },
        {
          "id": "E_TLP_UNKNOWN",
          "inputs": {
            "proven_defect": false,
            "causal": false,
            "risk": false,
            "safe": false,
            "missing": true,
            "source": true
          },
          "expected": "NEEDS_MORE_EVIDENCE",
          "observed": "NEEDS_MORE_EVIDENCE"
        },
        {
          "id": "E_NO_RISK_FULL_SCOPE",
          "inputs": {
            "proven_defect": false,
            "causal": false,
            "risk": false,
            "safe": false,
            "missing": false,
            "source": true
          },
          "expected": "NO_ACTION_SUPPORTED",
          "observed": "NO_ACTION_SUPPORTED"
        },
        {
          "id": "E_CP2_42501_ONLY",
          "inputs": {
            "proven_defect": false,
            "causal": false,
            "risk": true,
            "safe": true,
            "missing": true,
            "source": true
          },
          "expected": "VERIFY_FIRST",
          "observed": "VERIFY_FIRST"
        },
        {
          "id": "E_CAUSAL_UNKNOWN",
          "inputs": {
            "proven_defect": true,
            "causal": false,
            "risk": true,
            "safe": true,
            "missing": true,
            "source": true
          },
          "expected": "VERIFY_FIRST",
          "observed": "VERIFY_FIRST"
        },
        {
          "id": "E_UNVERIFIABLE",
          "inputs": {
            "proven_defect": false,
            "causal": false,
            "risk": false,
            "safe": false,
            "missing": true,
            "source": false
          },
          "expected": "NEEDS_MORE_EVIDENCE",
          "observed": "NEEDS_MORE_EVIDENCE"
        }
      ],
      "state_from_retraction": [
        {
          "removed": [],
          "state": "VERIFY_FIRST"
        },
        {
          "removed": [
            "ASOF_SOURCE"
          ],
          "state": "VERIFY_FIRST"
        },
        {
          "removed": [
            "QUALIFIED_SOAK"
          ],
          "state": "VERIFY_FIRST"
        },
        {
          "removed": [
            "HIST_EKB"
          ],
          "state": "VERIFY_FIRST"
        },
        {
          "removed": [
            "ASOF_SOURCE",
            "HIST_EKB"
          ],
          "state": "NEEDS_MORE_EVIDENCE"
        },
        {
          "removed": [
            "AUTH_SELECT"
          ],
          "state": "NEEDS_MORE_EVIDENCE"
        },
        {
          "removed": [
            "QUALIFIED_SOAK",
            "HIST_EKB"
          ],
          "state": "VERIFY_FIRST"
        },
        {
          "removed": [
            "ASOF_SOURCE",
            "QUALIFIED_SOAK"
          ],
          "state": "VERIFY_FIRST"
        }
      ],
      "reversal_criteria": [
        {
          "when": "qualified causal defect is proven",
          "state": "REPAIR_REQUIRED"
        },
        {
          "when": "unknown facts and defects resolved",
          "state": "NO_ACTION_SUPPORTED"
        },
        {
          "when": "evidence read path unavailable",
          "state": "NEEDS_MORE_EVIDENCE"
        }
      ]
    }
  },
  "negative_tests": [
    {
      "id": "M_ATMS_WITHDRAW_SOURCE_RETAINS_EKB_ALTERNATIVE",
      "pass": true,
      "expected": "After withdrawing ASOF_SOURCE, risk remains supported by historical EKB, safe SELECT remains and decision remains VERIFY_FIRST",
      "observed": "risk=true,safe=true,state=VERIFY_FIRST"
    },
    {
      "id": "M_ATMS_SOAK_WITHDRAWAL",
      "pass": true
    },
    {
      "id": "M_ATMS_EKB_ALTERNATE_SOURCE",
      "pass": true
    },
    {
      "id": "M_ATMS_ALL_RISK_REMOVED",
      "pass": true
    },
    {
      "id": "M_ATMS_DISCRIMINATOR_REMOVED",
      "pass": true
    },
    {
      "id": "C_CALLERS_TLP",
      "pass": true
    },
    {
      "id": "C_EXTERNAL_TLP",
      "pass": true
    },
    {
      "id": "C_HASH_TLP",
      "pass": true
    },
    {
      "id": "C_SYNTHETIC_NULL",
      "pass": true
    },
    {
      "id": "C_VALID_ACCEPT",
      "pass": true
    },
    {
      "id": "C_WRONG_REJECT",
      "pass": true
    },
    {
      "id": "C_UNKNOWN_REJECT",
      "pass": true
    },
    {
      "id": "E_SEVEN_SCENARIOS",
      "pass": true
    },
    {
      "id": "E_FOUR_STATES",
      "pass": true
    },
    {
      "id": "E_42501_NOT_REPAIR",
      "pass": true
    },
    {
      "id": "P0_HISTORICAL_LIMIT",
      "pass": true
    },
    {
      "id": "P0_SOAK_QUALIFIED",
      "pass": true
    },
    {
      "id": "NO_NUMERIC_SMT",
      "pass": true
    },
    {
      "id": "NO_ABSENCE_STATS_NO_USAGE",
      "pass": true
    }
  ],
  "findings": [
    {
      "id": "M15_F01",
      "claim": "Historical call inventory 38 and external inventory 6 reconcile separate TLP 3VL populations; do not sum as equivalent identities",
      "evidence": [
        "M15_Q02",
        "M15_Q03"
      ],
      "type": "MEASURED_ASOF"
    },
    {
      "id": "M15_F02",
      "claim": "ATMS retracts graph, SOAK or permission-derived claims when their source facts are removed; alternative risk supports survive one-source withdrawal",
      "evidence": [
        "M15_Q01",
        "M15_Q08",
        "M15_Q09"
      ],
      "type": "METHOD_COMPUTED"
    },
    {
      "id": "M15_F03",
      "claim": "Positive/wrong/NULL denominator cases exercise negative controls without solver-derived policy proof",
      "evidence": [
        "M15_Q05",
        "M15_Q06"
      ],
      "type": "SQL_TEST"
    },
    {
      "id": "M15_F04",
      "claim": "Typed evidence decision is VERIFY_FIRST; CP2 42501 does not establish functional defect",
      "evidence": [
        "M15_Q09",
        "M15_Q12"
      ],
      "type": "TYPE_DECISION"
    }
  ],
  "causal_model": {
    "status": "HYPOTHESIS_ONLY",
    "alternatives": [
      "Stale graph readback",
      "SOAK criterion projection",
      "Reader permission rather than functional CP2 defect"
    ]
  },
  "candidate_repairs": [
    {
      "action": "Reconcile source-time P0 and authorized history via SELECT",
      "status": "VERIFY_FIRST"
    }
  ],
  "chosen_repair": {
    "state": "VERIFY_FIRST",
    "implemented": false
  },
  "rejected_alternatives": [
    "Infer no usage from no stats",
    "Claim all unknown NULL are absent errors",
    "Patch product based on ATMS support alone"
  ],
  "omissions_searched": [
    "source attribution",
    "three-valued coverage",
    "negative cases",
    "qualified SOAK criteria",
    "typed reversible states"
  ],
  "unresolved": [
    "Canonical historical hashing UNKNOWN",
    "Runtime traces not measured",
    "E2E latency unknown"
  ],
  "constraints_preserved": [
    "P0",
    "No runtime mutating write",
    "No peer outputs",
    "No quality judgments"
  ],
  "conclusion": "M_C_E_METHOD_EXECUTED_ATMS_TLP_AND_TYPED_DECISION_NO_APPLIED_REPAIR"
}
$m15_raw$;
 v_doc jsonb;v_blob text;v_spec jsonb:=$m15_spec${"status":"READY","action_kind":"VERIFY_QUERY_ONCE","recipe_mode":"READBACK_EXACT","requires_material_execution":true,"contract_family":"PE10_METHOD_EXECUTION_EVIDENCE","precision":"PE10_METHOD_V1_MATERIAL_EVIDENCE","assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"checkpoint_identity":"PE10_M15","method_algorithms":"M+C+E","literal_sql_count":12,"atms_retractions_recomputed":8,"typed_e_scenarios_recomputed":7,"three_valued_checks_passed":19,"decision":"VERIFY_FIRST","historical_source_event_id":20161,"git_raw_source_verified":true,"runtime_modified":false}},"evidence_ref":"https://github.com/cristhianlujan/claude-persona-lf-patch/blob/8d841790984d9ccbc3bda4b43f22c7f40c0d3926/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M15_RAW_V2.json#git_blob_sha=f4bb49cbf41a5fbb648274e963332ddaf80dc94b","verification_queries":["SELECT id,created_at,payload->>'source_pack_version' source_pack,payload->'scope_guards' scope_guards FROM public.lf_eventos WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'","SELECT count(*) total,count(*) FILTER(WHERE x->>'operational_class'='ACTIVE') t,count(*) FILTER(WHERE NOT(x->>'operational_class'='ACTIVE')) f,count(*) FILTER(WHERE (x->>'operational_class'='ACTIVE') IS NULL) n,count(DISTINCT x->>'dedupe_key') unique_keys FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161","SELECT count(*) total,count(*) FILTER(WHERE x->>'operational_class'='ACTIVE') t,count(*) FILTER(WHERE NOT(x->>'operational_class'='ACTIVE')) f,count(*) FILTER(WHERE (x->>'operational_class'='ACTIVE') IS NULL) n FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'external_inventory') x WHERE e.id=20161","SELECT count(*) total,count(*) FILTER(WHERE x->>'definition_md5'~'^[a-f0-9]{32}$') valid,count(*) FILTER(WHERE NOT(x->>'definition_md5'~'^[a-f0-9]{32}$')) invalid,count(*) FILTER(WHERE (x->>'definition_md5'~'^[a-f0-9]{32}$') IS NULL) n FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161","WITH v(x) AS(VALUES('ACTIVE'::text),('OTHER'::text),(NULL::text)) SELECT count(*) total,count(*) FILTER(WHERE x='ACTIVE') t,count(*) FILTER(WHERE NOT(x='ACTIVE')) f,count(*) FILTER(WHERE (x='ACTIVE') IS NULL) n FROM v","WITH pairs(expected,observed) AS (VALUES(38,38),(38,40),(38,NULL::int)) SELECT expected,observed,(expected=observed) IS TRUE accepted FROM pairs ORDER BY observed NULLS LAST","SELECT id,created_at,receipt_kind,subject_ref,payload->>'verification_status' verified,payload->>'screens_total' screens,payload->>'families_total' families,payload->>'known_false_pass_signals' false_pass,payload->>'unresolved_d4' d4 FROM programacion.provenance_receipts WHERE id=38 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'","SELECT codigo,primera_vez,causa_raiz,prevencion FROM transversal.error_knowledge WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001') AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z' ORDER BY codigo"],"expected":"M15 M ATMS evidentiary invalidations, C SQL TLP and typed E decision research only; no business runtime fix, no external scoring.","forbidden":["MARK_DONE_FROM_HASH_ONLY","OMIT_ATMS_COUNTERFACTUAL_RECOMPUTATION","CLAIM_SMT_SOLVER","CLAIM_APPLIED_REPAIR","TOUCH_OTHER_CHECKPOINTS"],"target":{"checkpoint":"PE10_M15","declared_events":[20161],"declared_objects":["public.lf_eventos","programacion.provenance_receipts","transversal.error_knowledge","programacion.engineering_work_checkpoints"],"evidence_artifacts":[{"path":"cristhianlujan/claude-persona-lf-patch:docs/profile_updater/experiments/pe10_methods32_p0/PE10_M15_RAW_V2.json","role":"EVIDENCE","purpose":"PE10_M15_INTEGRATED_M_C_E_METHOD_RAW_V2","target_kind":"EXACT_EXISTING_FILE"}]}}$m15_spec$::jsonb;
 v_ref text:='https://github.com/cristhianlujan/claude-persona-lf-patch/blob/8d841790984d9ccbc3bda4b43f22c7f40c0d3926/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M15_RAW_V2.json#git_blob_sha=f4bb49cbf41a5fbb648274e963332ddaf80dc94b';v_old text:='chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M15.json#sha256=cceaeb904bad988a95be757f2bd7b5bad048f27d489ca6bc41f46ccc3f388dcb';
 v_q int;v_m int;v_e int;v_states int;v_neg int;v_ekb int;v_previous int;v_n int;v_c int;
 v_contract jsonb;v_observed jsonb;v_result jsonb;v_assertion jsonb;v_transition jsonb;v_receipt text;
 v_error text;v_context text;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
 AND target_code LIKE '%lf_pe10_m15_mce_governed_close_v1'
 AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'M15_TRAIN_CONTEXT_ABSENT'; END IF;
 IF (SELECT status FROM programacion.engineering_work_items WHERE id=1133)<>'IN_PROGRESS'
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>14
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>18
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M15' AND id=1639
 AND status='PENDING' AND evidence_ref=v_old AND assertion_receipt IS NULL AND completed_at IS NULL)<>1
 OR (SELECT count(*) FROM programacion.pe10_method_variants WHERE method_code='PE10_M15'
 AND case_ref='PE10-IG-M107-M109-P0' AND base_code='A' AND algorithm_codes=ARRAY['M','C','E']::text[])<>1
 OR (SELECT count(*) FROM programacion.engineering_plan_units WHERE work_item_id=1133
 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32'
 AND unit_metadata#>>'{action_specs_v1,PE10_M15,status}'='BLOCK_PENDING_MATERIAL_RESEARCH_AND_VALIDATION')<>1
 THEN RAISE EXCEPTION 'M15_PRESTATE_METHOD_AUTHORITY_CHANGED'; END IF;

 SELECT count(*) INTO v_previous FROM programacion.engineering_work_checkpoints c
 JOIN (VALUES
 ('PE10_M01','1c174f3277f9656ffc4146c210ac64cd037fc92d4fb34d7a7959fe826e3f9b01'),
 ('PE10_M02','0079973e1fec8787d2ef45d92131cad58bcb59f3c591aaf2badd8d86fe34c51b'),
 ('PE10_M03','0cbbc9d58552b2c5ea3d2c9bca1b07c6467cd4145720905f38fc5bf07a46e2a1'),
 ('PE10_M04','49ff7ae0d5966211ccb5a8caccc5718a61677c375a4a4a35c03e2bd6def7697e'),
 ('PE10_M05','085c478b380e63908672c0382798750a9a075afc9b8fa21d0fa809db0684e90e'),
 ('PE10_M06','4d5a9c761bc0171efa908e97d471cb1d372046b235274f141695d4665f1cc4cb'),
 ('PE10_M07','508081f732648de4caa9b7b95bafba2283f5d2e719323a90d941fe3bedbfdd4a'),
 ('PE10_M08','ebc8477fea336cb76c25d73cfbcdbe9fe680ca03770734e04ede3fa140512c12'),
 ('PE10_M09','f939334bc3c1d5be819c59309fc375a14fd7360fd4b8705ff6f749bdc0f805df'),
 ('PE10_M10','63855d13ae93adff8c959cc9f071136e5405dfd736a6da2aecafb38ae0cde20b'),
 ('PE10_M11','d0ffbe0d56335daa9a800d0326201686eed5e861745b2fdddcad5dc3b3e56025'),
 ('PE10_M12','01723c0a370baabe2532358bdac86bbfdbe185ba0514e195547597475d93a383'),
 ('PE10_M13','c5173d811fcc81c51f832a0073bf8321001f13d3c813780f4ed1faf4883e6b35'),
 ('PE10_M14','6b4e248faab213612d2a88992603e02b02bc75e608fc11a6ddcef76382ee4f4a')
 ) e(code,sha) ON e.code=c.checkpoint_code AND e.sha=c.assertion_receipt_sha256
 WHERE c.work_item_id=1133 AND c.status='DONE' AND c.assertion_receipt->>'passed'='true'
 AND c.assertion_contract_sha256=c.assertion_receipt->>'contract_sha256';
 IF v_previous<>14 THEN RAISE EXCEPTION 'M15_PRIOR_CANONICAL_RECEIPTS_DRIFT'; END IF;

 v_blob:=encode(extensions.digest(convert_to('blob '||octet_length(convert_to(v_raw,'UTF8'))::text,'UTF8')
 ||decode('00','hex')||convert_to(v_raw,'UTF8'),'sha1'),'hex');
 IF v_blob<>'f4bb49cbf41a5fbb648274e963332ddaf80dc94b' THEN RAISE EXCEPTION 'M15_FROZEN_GIT_BLOB_NOT_EXACT'; END IF;
 v_doc:=v_raw::jsonb;
 IF v_doc->>'schema'<>'PE10_METHOD_RAW_V2'
 OR v_doc->>'case_ref'<>'PE10-IG-M107-M109-P0'
 OR v_doc->>'method_code'<>'PE10_M15'
 OR v_doc->>'base_code'<>'A'
 OR v_doc->'algorithm_codes'<>'["M","C","E"]'::jsonb
 OR v_doc->>'source_cutoff'<>'2026-10-15T00:00:00Z'
 OR v_doc#>>'{original_preserved,sha256}'<>'cceaeb904bad988a95be757f2bd7b5bad048f27d489ca6bc41f46ccc3f388dcb'
 OR v_doc->>'external_evaluation'<>'NOT_PERFORMED'
 OR v_doc#>>'{algorithm_execution,E,actual_state}'<>'VERIFY_FIRST'
 OR v_doc#>>'{chosen_repair,state}'<>'VERIFY_FIRST'
 OR v_doc->>'conclusion'<>'M_C_E_METHOD_EXECUTED_ATMS_TLP_AND_TYPED_DECISION_NO_APPLIED_REPAIR'
 THEN RAISE EXCEPTION 'M15_RAW_IDENTITY_OR_SCOPE_MISMATCH'; END IF;

 SELECT count(*) INTO v_q FROM jsonb_array_elements(v_doc->'sql_evidence') z
 WHERE z->>'id' ~ '^M15_Q(0[1-9]|1[0-2])$' AND z->>'sql_literal' ~* '^(SELECT|WITH) '
 AND z->>'source'='SUPABASE_READ_ONLY' AND jsonb_typeof(z->'rows')='array'
 AND (z->>'rows_returned')::int=jsonb_array_length(z->'rows')
 AND jsonb_array_length(z->'rows')>0;
 IF v_q<>12 OR jsonb_array_length(v_doc->'sql_evidence')<>12
 OR (SELECT count(DISTINCT z->>'id') FROM jsonb_array_elements(v_doc->'sql_evidence') z)<>12
 OR v_doc#>>'{sql_evidence,1,rows,0,total}'<>'38'
 OR v_doc#>>'{sql_evidence,2,rows,0,total}'<>'6'
 OR v_doc#>>'{sql_evidence,3,rows,0,valid}'<>'38'
 OR v_doc#>>'{sql_evidence,4,rows,0,n}'<>'1'
 OR v_doc#>>'{sql_evidence,6,rows,0,lexical_edges}'<>'76'
 OR v_doc#>>'{sql_evidence,7,rows,0,verified}'<>'VERIFIED'
 OR v_doc#>>'{sql_evidence,10,rows,0,after_cutoff}'<>'0'
 THEN RAISE EXCEPTION 'M15_LITERAL_SQL_READBACK_INSUFFICIENT'; END IF;

 -- Recompute ATMS independently from raw true/false authoring:
 -- Risk = (historical source AND cutoff) OR (EKB AND cutoff).
 -- SOAK = receipt AND cutoff, SAFE = AUTH_SELECT AND Risk.
 WITH inp AS (
 SELECT z, z->'removed' AS rem FROM jsonb_array_elements(v_doc#>'{algorithm_execution,M,retractions}') z
 ),derived AS (
 SELECT z,rem,
 (NOT (rem ? 'QUALIFIED_SOAK') AND NOT (rem ? 'SOURCE_CUTOFF')) AS soak_ok,
 ((NOT (rem ? 'ASOF_SOURCE') OR NOT (rem ? 'HIST_EKB')) AND NOT (rem ? 'SOURCE_CUTOFF')) AS risk_ok
 FROM inp
 ),checked AS (
 SELECT z,soak_ok,risk_ok,(risk_ok AND NOT (rem ? 'AUTH_SELECT')) AS safe_ok FROM derived
 )
 SELECT count(*) INTO v_m FROM checked
 WHERE z->'soak'=to_jsonb(soak_ok) AND z->'risk'=to_jsonb(risk_ok)
 AND z->'safe'=to_jsonb(safe_ok)
 AND z->>'state'=CASE WHEN risk_ok AND safe_ok THEN 'VERIFY_FIRST' ELSE 'NEEDS_MORE_EVIDENCE' END;
 IF v_m<>8 OR jsonb_array_length(v_doc#>'{algorithm_execution,M,retractions}')<>8
 OR jsonb_array_length(v_doc#>'{algorithm_execution,M,nogoods}')<>2
 OR jsonb_array_length(v_doc#>'{algorithm_execution,M,minimal_justifications,METHOD_RISK}')<>2
 OR v_doc#>>'{algorithm_execution,M,retractions,4,state}'<>'NEEDS_MORE_EVIDENCE'
 OR v_doc#>>'{algorithm_execution,M,retractions,5,state}'<>'NEEDS_MORE_EVIDENCE'
 OR v_doc#>>'{algorithm_execution,M,retractions,1,state}'<>'VERIFY_FIRST'
 THEN RAISE EXCEPTION 'M15_ATMS_RETROACTIVE_RECOMPUTATION_FAILED'; END IF;

 SELECT count(*) INTO v_e FROM jsonb_array_elements(v_doc#>'{algorithm_execution,E,decision_scenarios}') x
 WHERE x->>'expected'=CASE
 WHEN coalesce((x#>>'{inputs,proven_defect}')::boolean,false)
 AND coalesce((x#>>'{inputs,causal}')::boolean,false) THEN 'REPAIR_REQUIRED'
 WHEN coalesce((x#>>'{inputs,risk}')::boolean,false)
 AND coalesce((x#>>'{inputs,safe}')::boolean,false) THEN 'VERIFY_FIRST'
 WHEN coalesce((x#>>'{inputs,missing}')::boolean,false)
 OR NOT coalesce((x#>>'{inputs,source}')::boolean,false) THEN 'NEEDS_MORE_EVIDENCE'
 ELSE 'NO_ACTION_SUPPORTED' END AND x->>'observed'=x->>'expected';
 SELECT count(DISTINCT x->>'observed') INTO v_states
 FROM jsonb_array_elements(v_doc#>'{algorithm_execution,E,decision_scenarios}') x;
 SELECT count(*) INTO v_neg FROM jsonb_array_elements(v_doc->'negative_tests') x WHERE x->>'pass'='true';
 IF v_e<>7 OR jsonb_array_length(v_doc#>'{algorithm_execution,E,decision_scenarios}')<>7
 OR v_states<>4 OR v_neg<>19 OR jsonb_array_length(v_doc->'negative_tests')<>19
 OR v_doc#>>'{algorithm_execution,C,three_valued_partitions,callers,total}'<>'38'
 OR v_doc#>>'{algorithm_execution,C,three_valued_partitions,external,total}'<>'6'
 OR v_doc#>>'{algorithm_execution,C,three_valued_partitions,synthetic,n}'<>'1'
 OR jsonb_array_length(v_doc#>'{algorithm_execution,C,contract_cases}')<>3
 OR v_doc#>>'{algorithm_execution,C,solver}'<>'NOT_USED_NO_SMT'
 THEN RAISE EXCEPTION 'M15_METAMORPHIC_OR_TYPED_DECISION_FAILED'; END IF;

 SELECT count(*) INTO v_ekb FROM transversal.error_knowledge WHERE codigo IN (
 'IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001')
 AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z';
 IF v_ekb<>2 OR (SELECT count(*) FROM public.lf_eventos WHERE id=20161
 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'
 AND jsonb_array_length(payload->'sql_callers')=38
 AND jsonb_array_length(payload->'external_inventory')=6
 AND payload->'usage_stats'->>'track_functions'='none')<>1
 OR (SELECT count(*) FROM programacion.provenance_receipts WHERE id=38
 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'
 AND payload->>'verification_status'='VERIFIED'
 AND payload->>'known_false_pass_signals'='0' AND payload->>'unresolved_d4'='0')<>1
 THEN RAISE EXCEPTION 'M15_FROZEN_SOURCE_READBACK_CONFLICT'; END IF;

 UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10_M15}',v_spec,true)
 WHERE work_item_id=1133 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32';
 GET DIAGNOSTICS v_n=ROW_COUNT;
 IF v_n<>1 THEN RAISE EXCEPTION 'M15_ACTION_SPEC_NOT_EXACTLY_ONE'; END IF;
 v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M15',
 programacion.fn_engineering_checkpoint_action_spec_v3('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M15'));
 IF v_contract->>'status'<>'READY' OR v_contract->>'mode'<>'EXPLICIT_PASS_WHEN_SUBSET'
 THEN RAISE EXCEPTION 'M15_ASSERTION_CONTRACT_NOT_READY:%',coalesce(v_contract::text,'NULL'); END IF;
 v_observed:=jsonb_build_object('checkpoint_identity','PE10_M15','method_algorithms','M+C+E',
 'literal_sql_count',12,'atms_retractions_recomputed',v_m,
 'typed_e_scenarios_recomputed',v_e,'three_valued_checks_passed',v_neg,
 'decision','VERIFY_FIRST','historical_source_event_id',20161,
 'git_raw_source_verified',true,'runtime_modified',false);
 v_result:=jsonb_build_object('status','PASS','observed',v_observed,'evidence_ref',v_ref,
 'validation_kind','M15_M_C_E_EVIDENCE_ONLY_NOT_APPLIED_REPAIR',
 'domain_functional_repair','NOT_PERFORMED');
 v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M15',v_result,v_exec);
 IF v_assertion->>'passed'<>'true'
 OR coalesce(v_assertion->>'assertion_receipt_sha256','') !~ '^[a-f0-9]{64}$'
 THEN RAISE EXCEPTION 'M15_CANONICAL_ASSERTION_NOT_PASSED'; END IF;
 v_receipt:=v_assertion->>'assertion_receipt_sha256';
 v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M15','DONE',v_ref,v_exec,
 'M15 ATMS, TLP and typed E verify-first decision source-certified; no runtime patch');
 IF v_transition#>>'{transition,status}'<>'APPLIED'
 THEN RAISE EXCEPTION 'M15_CANONICAL_TRANSITION_NOT_APPLIED'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=1133 AND checkpoint_code='PE10_M15' AND status='DONE'
 AND evidence_ref=v_ref AND completed_at IS NOT NULL
 AND assertion_receipt_sha256=v_receipt AND assertion_receipt->>'passed'='true'
 AND assertion_contract_sha256=assertion_receipt->>'contract_sha256')<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>15
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>17
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133
 AND checkpoint_code='PE10_M16' AND status='PENDING')<>1
 THEN RAISE EXCEPTION 'M15_POST_TRAIN_GOVERNED_READBACK_NOT_VERIFIED'; END IF;
EXCEPTION WHEN OTHERS THEN
 GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT,v_context=PG_EXCEPTION_CONTEXT;
 RAISE EXCEPTION 'M15_TRAIN_CAUSE state=% message=% context=%',SQLSTATE,left(v_error,295),left(v_context,170) USING ERRCODE=SQLSTATE;
END $m15_train_close$;
