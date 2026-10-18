-- M12: one method D+M+E, no product repair or permission activation; Train exact-version only.
DO $m12_close$
DECLARE
 v_exec text;v_raw text:=$m12_raw${
  "schema": "PE10_METHOD_RAW_V2",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M12",
  "base_code": "A",
  "algorithm_codes": [
    "D",
    "M",
    "E"
  ],
  "source_cutoff": "2026-10-15T00:00:00Z",
  "original_preserved": {
    "ref": "chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M12.json",
    "sha256": "04392fbcd8e40c7236abef2b7019b2668efd8ff5e46bb50765f9f384b5ef78a3"
  },
  "producer": "One integrated SRCR D+M+E experiment; independent raw output from P0, no peer method results used",
  "external_evaluation": "NOT_PERFORMED",
  "sql_evidence": [
    {
      "id": "M12_Q01",
      "sql_literal": "SELECT id,created_at,payload->>'source_pack_version' pack,payload->'scope_guards' scope_guards,payload->'historical_provenance_only' provenance FROM public.lf_eventos WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'",
      "rows": [
        {
          "id": 20161,
          "created_at": "2026-10-04 05:14:40.880842+00",
          "pack": "SOURCE_PACK_V1",
          "scope_guards": {
            "callers_retired": false,
            "m10_10_executed": false,
            "callers_modified": false,
            "production_change": false,
            "runtime_activation": false,
            "n13_n14_n15_changed": false
          },
          "provenance": {
            "router_note": "Router binding snapshot observes readiness revision 5.12 while governed current readiness snapshot is 5.13; retained as provenance/currentness drift only.",
            "contract_note": "Older input contract rows remain recorded; caller usage is not inferred from their existence."
          }
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_BEFORE_P0_CUTOFF"
    },
    {
      "id": "M12_Q02",
      "sql_literal": "SELECT count(*) total,count(DISTINCT x->>'dedupe_key') deduped,count(*) FILTER(WHERE x->>'currentness_source'='LIVE_PG_PROC') labeled_live FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161",
      "rows": [
        {
          "total": 38,
          "deduped": 38,
          "labeled_live": 38
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_BEFORE_P0_CUTOFF"
    },
    {
      "id": "M12_Q03",
      "sql_literal": "SELECT count(*) lexical_edges,count(DISTINCT c.value) distinct_targets,count(*) FILTER(WHERE c.value ILIKE '%cached%') cached_edges FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x CROSS JOIN LATERAL jsonb_array_elements_text(x->'callees') c(value) WHERE e.id=20161",
      "rows": [
        {
          "lexical_edges": 76,
          "distinct_targets": 39,
          "cached_edges": 11
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_BEFORE_P0_CUTOFF"
    },
    {
      "id": "M12_Q04",
      "sql_literal": "SELECT jsonb_array_length(payload->'trigger_bindings') trigger_bindings,jsonb_array_length(payload->'external_inventory') external_assets,jsonb_array_length(payload->'edge_current') edge_entries,jsonb_array_length(payload->'consumer_relation_snapshot_json_rows') consumer_snapshots,payload->'usage_stats' usage_stats FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "trigger_bindings": 21,
          "external_assets": 6,
          "edge_entries": 4,
          "consumer_snapshots": 27,
          "usage_stats": {
            "ig_stat_rows": 0,
            "interpretation": "track_functions none means zero stat rows cannot prove no usage; static governed graph supplies inventory currentness",
            "track_functions": "none"
          }
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_BEFORE_P0_CUTOFF"
    },
    {
      "id": "M12_Q05",
      "sql_literal": "SELECT id,created_at,receipt_kind,subject_ref,payload->>'verification_status' verified,payload->>'pass' qualified,payload->>'screens_total' screens,payload->>'families_total' families,payload->>'known_false_pass_signals' false_pass,payload->>'unresolved_d4' d4 FROM programacion.provenance_receipts WHERE id=38 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'",
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
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_BEFORE_P0_CUTOFF"
    },
    {
      "id": "M12_Q06",
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
      "scope": "HISTORICAL_SOURCE_BEFORE_P0_CUTOFF"
    },
    {
      "id": "M12_Q07",
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
      "scope": "HISTORICAL_SOURCE_BEFORE_P0_CUTOFF"
    },
    {
      "id": "M12_Q08",
      "sql_literal": "SELECT count(*) total,count(*) FILTER(WHERE x->>'definition_md5'~'^[a-f0-9]{32}$') valid_format,count(*) FILTER(WHERE x->>'definition_md5' IS NULL) absent FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161",
      "rows": [
        {
          "total": 38,
          "valid_format": 38,
          "absent": 0
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_BEFORE_P0_CUTOFF"
    },
    {
      "id": "M12_Q09",
      "sql_literal": "SELECT coalesce(x->>'operational_class','UNKNOWN') class,coalesce(x->>'governance_lifecycle','UNKNOWN') lifecycle,count(*) n FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'external_inventory') x WHERE e.id=20161 GROUP BY 1,2 ORDER BY 1,2",
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
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_BEFORE_P0_CUTOFF"
    },
    {
      "id": "M12_Q10",
      "sql_literal": "SELECT count(*) FILTER(WHERE created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z') historical,count(*) FILTER(WHERE created_at>=TIMESTAMPTZ '2026-10-15T00:00:00Z') later FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "historical": 1,
          "later": 0
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_BEFORE_P0_CUTOFF"
    },
    {
      "id": "M12_Q11",
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
      "scope": "PRESENT_ROLE_ONLY"
    }
  ],
  "algorithm_execution": {
    "D": {
      "conflicts": [
        [
          "HIST_SOAK_TEXT_DRIFT",
          "SOURCE_RECEIPT_BINDING"
        ],
        [
          "CP2_ROLE_PRIVILEGE",
          "CP2_READ_CONTEXT"
        ],
        [
          "STATIC_GRAPH_PROMOTION",
          "MISSING_RUNTIME_TRACE"
        ]
      ],
      "minimal_hitting_sets": [
        [
          "HIST_SOAK_TEXT_DRIFT",
          "CP2_ROLE_PRIVILEGE",
          "STATIC_GRAPH_PROMOTION"
        ],
        [
          "SOURCE_RECEIPT_BINDING",
          "CP2_ROLE_PRIVILEGE",
          "STATIC_GRAPH_PROMOTION"
        ],
        [
          "HIST_SOAK_TEXT_DRIFT",
          "CP2_READ_CONTEXT",
          "STATIC_GRAPH_PROMOTION"
        ],
        [
          "SOURCE_RECEIPT_BINDING",
          "CP2_READ_CONTEXT",
          "STATIC_GRAPH_PROMOTION"
        ],
        [
          "HIST_SOAK_TEXT_DRIFT",
          "CP2_ROLE_PRIVILEGE",
          "MISSING_RUNTIME_TRACE"
        ],
        [
          "SOURCE_RECEIPT_BINDING",
          "CP2_ROLE_PRIVILEGE",
          "MISSING_RUNTIME_TRACE"
        ],
        [
          "HIST_SOAK_TEXT_DRIFT",
          "CP2_READ_CONTEXT",
          "MISSING_RUNTIME_TRACE"
        ],
        [
          "SOURCE_RECEIPT_BINDING",
          "CP2_READ_CONTEXT",
          "MISSING_RUNTIME_TRACE"
        ]
      ],
      "all_hitting_sets_count": 27,
      "barinel": "NOT_CALIBRATABLE_WITHOUT_EXECUTION_SPECTRA",
      "information_gain": "ORDINAL_ONLY_NO_PRIORS",
      "scope": "DIAGNOSTIC_HYPOTHESES_NOT_PROVEN_CAUSAL"
    },
    "M": {
      "facts": [
        "SOURCE20161",
        "RECEIPT38",
        "EKB_PRE_P0",
        "ASOF",
        "SAFE_SELECT",
        "NO_STATS"
      ],
      "rules": {
        "ASOF_GRAPH": [
          [
            "SOURCE20161",
            "ASOF"
          ]
        ],
        "HIST_SOAK": [
          [
            "RECEIPT38",
            "ASOF"
          ]
        ],
        "RISK_CP2": [
          [
            "EKB_PRE_P0",
            "ASOF"
          ]
        ],
        "SOURCE_PROMOTION_RISK": [
          [
            "ASOF_GRAPH"
          ]
        ],
        "RISK_ANY": [
          [
            "RISK_CP2"
          ],
          [
            "SOURCE_PROMOTION_RISK"
          ]
        ],
        "SAFE_CHECK": [
          [
            "SAFE_SELECT",
            "RISK_CP2"
          ],
          [
            "SAFE_SELECT",
            "SOURCE_PROMOTION_RISK"
          ]
        ],
        "NO_USAGE_NOT_PROVEN": [
          [
            "SOURCE20161",
            "NO_STATS"
          ]
        ]
      },
      "nogoods": [
        [
          "ASOF",
          "CLAIM_CURRENT"
        ],
        [
          "NO_STATS",
          "CLAIM_ZERO_USAGE"
        ]
      ],
      "justifications": {
        "SOURCE20161": [
          [
            "SOURCE20161"
          ]
        ],
        "RECEIPT38": [
          [
            "RECEIPT38"
          ]
        ],
        "EKB_PRE_P0": [
          [
            "EKB_PRE_P0"
          ]
        ],
        "ASOF": [
          [
            "ASOF"
          ]
        ],
        "SAFE_SELECT": [
          [
            "SAFE_SELECT"
          ]
        ],
        "NO_STATS": [
          [
            "NO_STATS"
          ]
        ],
        "ASOF_GRAPH": [
          [
            "ASOF",
            "SOURCE20161"
          ]
        ],
        "HIST_SOAK": [
          [
            "ASOF",
            "RECEIPT38"
          ]
        ],
        "RISK_CP2": [
          [
            "ASOF",
            "EKB_PRE_P0"
          ]
        ],
        "SOURCE_PROMOTION_RISK": [
          [
            "ASOF",
            "SOURCE20161"
          ]
        ],
        "RISK_ANY": [
          [
            "ASOF",
            "EKB_PRE_P0"
          ],
          [
            "ASOF",
            "SOURCE20161"
          ]
        ],
        "SAFE_CHECK": [
          [
            "ASOF",
            "EKB_PRE_P0",
            "SAFE_SELECT"
          ],
          [
            "ASOF",
            "SAFE_SELECT",
            "SOURCE20161"
          ]
        ],
        "NO_USAGE_NOT_PROVEN": [
          [
            "NO_STATS",
            "SOURCE20161"
          ]
        ]
      },
      "retractions": [
        {
          "id": "M12_RETRACT_1",
          "removed": [],
          "graph": true,
          "soak": true,
          "risk": true,
          "eligible_verification": true,
          "derived_state": "VERIFY_FIRST"
        },
        {
          "id": "M12_RETRACT_2",
          "removed": [
            "SOURCE20161"
          ],
          "graph": false,
          "soak": true,
          "risk": true,
          "eligible_verification": true,
          "derived_state": "VERIFY_FIRST"
        },
        {
          "id": "M12_RETRACT_3",
          "removed": [
            "RECEIPT38"
          ],
          "graph": true,
          "soak": false,
          "risk": true,
          "eligible_verification": true,
          "derived_state": "VERIFY_FIRST"
        },
        {
          "id": "M12_RETRACT_4",
          "removed": [
            "EKB_PRE_P0"
          ],
          "graph": true,
          "soak": true,
          "risk": true,
          "eligible_verification": true,
          "derived_state": "VERIFY_FIRST"
        },
        {
          "id": "M12_RETRACT_5",
          "removed": [
            "SOURCE20161",
            "EKB_PRE_P0"
          ],
          "graph": false,
          "soak": true,
          "risk": false,
          "eligible_verification": false,
          "derived_state": "NEEDS_MORE_EVIDENCE"
        },
        {
          "id": "M12_RETRACT_6",
          "removed": [
            "SAFE_SELECT"
          ],
          "graph": true,
          "soak": true,
          "risk": true,
          "eligible_verification": false,
          "derived_state": "NEEDS_MORE_EVIDENCE"
        },
        {
          "id": "M12_RETRACT_7",
          "removed": [
            "SOURCE20161",
            "RECEIPT38"
          ],
          "graph": false,
          "soak": false,
          "risk": true,
          "eligible_verification": true,
          "derived_state": "VERIFY_FIRST"
        },
        {
          "id": "M12_RETRACT_8",
          "removed": [
            "EKB_PRE_P0",
            "RECEIPT38"
          ],
          "graph": true,
          "soak": false,
          "risk": true,
          "eligible_verification": true,
          "derived_state": "VERIFY_FIRST"
        }
      ],
      "qualified_current_from_historical": false
    },
    "E": {
      "states": [
        "VERIFY_FIRST",
        "REPAIR_REQUIRED",
        "NEEDS_MORE_EVIDENCE",
        "NO_ACTION_SUPPORTED"
      ],
      "actual_state": "VERIFY_FIRST",
      "scenarios": [
        {
          "id": "E_ACTUAL",
          "inputs": {
            "causal_defect": false,
            "proven_trace": false,
            "material_risk": true,
            "authorized_discriminator": true,
            "missing_evidence": true,
            "qualified_source": true
          },
          "expected": "VERIFY_FIRST",
          "observed": "VERIFY_FIRST"
        },
        {
          "id": "E_POSITIVE_CAUSAL",
          "inputs": {
            "causal_defect": true,
            "proven_trace": true,
            "material_risk": true,
            "authorized_discriminator": true,
            "missing_evidence": false,
            "qualified_source": true
          },
          "expected": "REPAIR_REQUIRED",
          "observed": "REPAIR_REQUIRED"
        },
        {
          "id": "E_UNKNOWN_NO_READ",
          "inputs": {
            "causal_defect": false,
            "proven_trace": false,
            "material_risk": true,
            "authorized_discriminator": false,
            "missing_evidence": true,
            "qualified_source": false
          },
          "expected": "NEEDS_MORE_EVIDENCE",
          "observed": "NEEDS_MORE_EVIDENCE"
        },
        {
          "id": "E_FULL_NEGATIVE",
          "inputs": {
            "causal_defect": false,
            "proven_trace": false,
            "material_risk": false,
            "authorized_discriminator": false,
            "missing_evidence": false,
            "qualified_source": true
          },
          "expected": "NO_ACTION_SUPPORTED",
          "observed": "NO_ACTION_SUPPORTED"
        },
        {
          "id": "E_42501_PERMISSION_ONLY",
          "inputs": {
            "causal_defect": false,
            "proven_trace": false,
            "material_risk": true,
            "authorized_discriminator": true,
            "missing_evidence": true,
            "qualified_source": true
          },
          "expected": "VERIFY_FIRST",
          "observed": "VERIFY_FIRST"
        },
        {
          "id": "E_CAUSAL_PROOF_MISSING",
          "inputs": {
            "causal_defect": true,
            "proven_trace": false,
            "material_risk": true,
            "authorized_discriminator": true,
            "missing_evidence": true,
            "qualified_source": true
          },
          "expected": "VERIFY_FIRST",
          "observed": "VERIFY_FIRST"
        },
        {
          "id": "E_SOURCE_MISSING",
          "inputs": {
            "causal_defect": false,
            "proven_trace": false,
            "material_risk": false,
            "authorized_discriminator": false,
            "missing_evidence": true,
            "qualified_source": false
          },
          "expected": "NEEDS_MORE_EVIDENCE",
          "observed": "NEEDS_MORE_EVIDENCE"
        }
      ],
      "derived_states_after_retraction": [
        {
          "id": "M12_RETRACT_1",
          "removed": [],
          "state": "VERIFY_FIRST"
        },
        {
          "id": "M12_RETRACT_2",
          "removed": [
            "SOURCE20161"
          ],
          "state": "VERIFY_FIRST"
        },
        {
          "id": "M12_RETRACT_3",
          "removed": [
            "RECEIPT38"
          ],
          "state": "VERIFY_FIRST"
        },
        {
          "id": "M12_RETRACT_4",
          "removed": [
            "EKB_PRE_P0"
          ],
          "state": "VERIFY_FIRST"
        },
        {
          "id": "M12_RETRACT_5",
          "removed": [
            "SOURCE20161",
            "EKB_PRE_P0"
          ],
          "state": "NEEDS_MORE_EVIDENCE"
        },
        {
          "id": "M12_RETRACT_6",
          "removed": [
            "SAFE_SELECT"
          ],
          "state": "NEEDS_MORE_EVIDENCE"
        },
        {
          "id": "M12_RETRACT_7",
          "removed": [
            "SOURCE20161",
            "RECEIPT38"
          ],
          "state": "VERIFY_FIRST"
        },
        {
          "id": "M12_RETRACT_8",
          "removed": [
            "EKB_PRE_P0",
            "RECEIPT38"
          ],
          "state": "VERIFY_FIRST"
        }
      ],
      "reversal_criteria": [
        {
          "when": "functional defect materially proved with causal trace",
          "state": "REPAIR_REQUIRED"
        },
        {
          "when": "risk removed and qualifying scope complete",
          "state": "NO_ACTION_SUPPORTED"
        },
        {
          "when": "authorized discriminator becomes unavailable",
          "state": "NEEDS_MORE_EVIDENCE"
        }
      ]
    }
  },
  "negative_tests": [
    {
      "id": "D_EIGHT_DIAGNOSES",
      "pass": true
    },
    {
      "id": "D_NO_DIAGNOSIS_STRICT_SUBSET",
      "pass": true
    },
    {
      "id": "M_GRAPH_REMOVED",
      "pass": true
    },
    {
      "id": "M_SOAK_REMOVED",
      "pass": true
    },
    {
      "id": "M_EKB_REMOVED_ALTERNATIVE",
      "pass": true
    },
    {
      "id": "M_NO_RISK_BOTH_INPUTS",
      "pass": true
    },
    {
      "id": "M_NO_SAFE_SELECT",
      "pass": true
    },
    {
      "id": "E_ALL_SCENARIOS",
      "pass": true
    },
    {
      "id": "E_FOUR_STATES_EXERCISED",
      "pass": true
    },
    {
      "id": "E_42501_NOT_FUNCTIONAL",
      "pass": true
    },
    {
      "id": "P0_AUTHORITY_SCREEN",
      "pass": true
    },
    {
      "id": "P0_HISTORICAL_CUTOFF",
      "pass": true
    },
    {
      "id": "TELEMETRY_ZERO_NOT_ZERO_USE",
      "pass": true
    },
    {
      "id": "HASH_SYNTAX_NOT_CANONICAL_METHOD",
      "pass": true
    },
    {
      "id": "NO_BARINEL_NUMERIC",
      "pass": true
    },
    {
      "id": "NO_PROD_REPAIR",
      "pass": true
    }
  ],
  "findings": [
    {
      "id": "M12_F01",
      "claim": "The 38 historical callers and 76 nominal edges do not establish current execution; third GDE conflict is a trace gap",
      "source": [
        "M12_Q01",
        "M12_Q02",
        "M12_Q03"
      ],
      "scope": "HISTORICAL_MEASUREMENT"
    },
    {
      "id": "M12_F02",
      "claim": "M9.11 SOAK verified 13 screens/47 families with zero false pass and D4; does not establish E2E perf or current CP2 authority",
      "source": [
        "M12_Q05",
        "M12_Q06"
      ],
      "scope": "HISTORICAL_MEASUREMENT"
    },
    {
      "id": "M12_F03",
      "claim": "GDE three modeled risk conflicts give eight minimal diagnostic candidate sets; ATMS shows alternative evidentiary support and dependency invalidation",
      "source": [
        "M12_Q01",
        "M12_Q05",
        "M12_Q06"
      ],
      "scope": "COMPUTED_METHOD"
    },
    {
      "id": "M12_F04",
      "claim": "Removing the authorized discriminator downgrades E decision from VERIFY_FIRST to NEEDS_MORE_EVIDENCE, not a claimed applied repair",
      "source": [
        "M12_Q06",
        "M12_Q11"
      ],
      "scope": "TYPED_ALGORITHM"
    }
  ],
  "causal_model": {
    "proven": false,
    "alternatives": [
      "SOAK projection/receipt mismatch",
      "CP2 read privilege/currentness mismatch",
      "static graph/trace mismatch"
    ],
    "falsifiers": [
      "Versioned qualified runtime trace at same cutoff",
      "Read-authorized CP2 records with exact permission source",
      "Historical receipt/validation and appropriate currentness contract"
    ]
  },
  "candidate_repairs": [
    {
      "action": "Source-pinned SOAK/CP2 reconciliation",
      "status": "READ_ONLY_PROPOSAL"
    },
    {
      "action": "Use ATMS revocation for stale evidence",
      "status": "PROPOSED_CONTROL"
    }
  ],
  "chosen_repair": {
    "state": "VERIFY_FIRST",
    "implementation": false,
    "decision_scope": "P0_SOURCE_ONLY",
    "risk": "No proven runtime defect or performance effect"
  },
  "rejected_alternatives": [
    "Grant EXECUTE to readonly principal",
    "Replace uncertainty by known-answer D4/CP2 repairs",
    "Treat BARINEL numerics as known",
    "Finish domain repair because checkpoint administrative proof exists"
  ],
  "omissions_searched": [
    "nominal and runtime graph difference",
    "hash canonical method",
    "telemetry gap",
    "P0 EKB scope",
    "alternative supports",
    "negative scenario coverage",
    "reversal typed states"
  ],
  "unresolved": [
    "No causal defect proven",
    "No time-qualified runtime trace",
    "No proven canonical inventory hashing method",
    "E2E performance unknown"
  ],
  "constraints_preserved": [
    "P0 cutoff",
    "no product mutations",
    "no other method artifacts consulted",
    "no external quality scoring"
  ],
  "conclusion": "D_M_E_EXECUTED_SOURCE_EVIDENCE_WITH_VERIFICATION_FIRST_NO_APPLIED_REPAIR"
}
$m12_raw$;v_doc jsonb;
 v_spec jsonb:=$m12_spec${"status":"READY","action_kind":"VERIFY_QUERY_ONCE","recipe_mode":"READBACK_EXACT","requires_material_execution":true,"contract_family":"PE10_METHOD_EXECUTION_EVIDENCE","precision":"PE10_METHOD_V1_MATERIAL_EVIDENCE","assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"checkpoint_identity":"PE10_M12","method_algorithms":"D+M+E","literal_sql_count":11,"gde_minimal_hitting_sets":8,"atms_retractions_executed":8,"typed_e_cases_verified":7,"negative_tests_passed":16,"typed_e_state":"VERIFY_FIRST","historical_source_event_id":20161,"git_source_verified":true,"runtime_modified":false}},"evidence_ref":"https://github.com/cristhianlujan/claude-persona-lf-patch/blob/7d1839e9f10c64e6fdd4b4e6d8cf038e694dbd34/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M12_RAW_V2.json#git_blob_sha=7a8d4ed337162133d806946e5e862f49a8f5c874","verification_queries":["SELECT id,created_at,payload->>'source_pack_version' pack,payload->'scope_guards' scope_guards,payload->'historical_provenance_only' provenance FROM public.lf_eventos WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'","SELECT count(*) total,count(DISTINCT x->>'dedupe_key') deduped,count(*) FILTER(WHERE x->>'currentness_source'='LIVE_PG_PROC') labeled_live FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161","SELECT count(*) lexical_edges,count(DISTINCT c.value) distinct_targets,count(*) FILTER(WHERE c.value ILIKE '%cached%') cached_edges FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x CROSS JOIN LATERAL jsonb_array_elements_text(x->'callees') c(value) WHERE e.id=20161","SELECT jsonb_array_length(payload->'trigger_bindings') trigger_bindings,jsonb_array_length(payload->'external_inventory') external_assets,jsonb_array_length(payload->'edge_current') edge_entries,jsonb_array_length(payload->'consumer_relation_snapshot_json_rows') consumer_snapshots,payload->'usage_stats' usage_stats FROM public.lf_eventos WHERE id=20161","SELECT id,created_at,receipt_kind,subject_ref,payload->>'verification_status' verified,payload->>'pass' qualified,payload->>'screens_total' screens,payload->>'families_total' families,payload->>'known_false_pass_signals' false_pass,payload->>'unresolved_d4' d4 FROM programacion.provenance_receipts WHERE id=38 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'","SELECT codigo,primera_vez,causa_raiz,prevencion,validacion FROM transversal.error_knowledge WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001') AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z' ORDER BY codigo"],"expected":"M12 integrated source-specific GDE diagnostic set, ATMS evidence retractions and E typed decision; no product repair","forbidden":["CLAIM_REPAIR_IMPLEMENTED","SKIP_ATMS_RETRACTION_PROOF","PROMOTE_ASOF_TO_CURRENT","TREAT_GDE_AS_PROVEN_CAUSE","SKIP_GOVERNED_TRAIN"],"target":{"checkpoint":"PE10_M12","declared_events":[20161],"declared_objects":["public.lf_eventos","programacion.provenance_receipts","transversal.error_knowledge","programacion.engineering_work_checkpoints"],"evidence_artifacts":[{"path":"cristhianlujan/claude-persona-lf-patch:docs/profile_updater/experiments/pe10_methods32_p0/PE10_M12_RAW_V2.json","role":"EVIDENCE","purpose":"PE10_M12_DME_METHOD_EXECUTED_P0_RAW","target_kind":"EXACT_EXISTING_FILE"}]}}$m12_spec$::jsonb;
 v_ref text:='https://github.com/cristhianlujan/claude-persona-lf-patch/blob/7d1839e9f10c64e6fdd4b4e6d8cf038e694dbd34/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M12_RAW_V2.json#git_blob_sha=7a8d4ed337162133d806946e5e862f49a8f5c874';v_old text:='chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M12.json#sha256=04392fbcd8e40c7236abef2b7019b2668efd8ff5e46bb50765f9f384b5ef78a3';v_blob text;
 v_q int;v_d int;v_m int;v_e int;v_neg int;v_ekb int;v_prev_n int;v_n int;v_e_classes int;
 v_contract jsonb;v_obs jsonb;v_result jsonb;v_assertion jsonb;v_transition jsonb;v_receipt text;
 v_msg text;v_ctx text;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
 AND target_code LIKE '%lf_pe10_m12_dme_governed_close_v1'
 AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'M12_TRAIN_AUTHORITY_MISSING'; END IF;
 IF (SELECT status FROM programacion.engineering_work_items WHERE id=1133)<>'IN_PROGRESS'
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>11
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>21
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M12'
 AND status='PENDING' AND evidence_ref=v_old AND assertion_receipt IS NULL AND completed_at IS NULL)<>1
 OR (SELECT count(*) FROM programacion.pe10_method_variants WHERE method_code='PE10_M12'
 AND case_ref='PE10-IG-M107-M109-P0' AND base_code='A' AND algorithm_codes=ARRAY['D','M','E']::text[])<>1
 OR (SELECT count(*) FROM programacion.engineering_plan_units WHERE work_item_id=1133
 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32'
 AND unit_metadata#>>'{action_specs_v1,PE10_M12,status}'='BLOCK_PENDING_MATERIAL_RESEARCH_AND_VALIDATION')<>1
 THEN RAISE EXCEPTION 'M12_PRESTATE_DRIFT'; END IF;
 SELECT count(*) INTO v_prev_n FROM programacion.engineering_work_checkpoints c
 JOIN (VALUES ('PE10_M01','1c174f3277f9656ffc4146c210ac64cd037fc92d4fb34d7a7959fe826e3f9b01'),
 ('PE10_M02','0079973e1fec8787d2ef45d92131cad58bcb59f3c591aaf2badd8d86fe34c51b'),
 ('PE10_M03','0cbbc9d58552b2c5ea3d2c9bca1b07c6467cd4145720905f38fc5bf07a46e2a1'),
 ('PE10_M04','49ff7ae0d5966211ccb5a8caccc5718a61677c375a4a4a35c03e2bd6def7697e'),
 ('PE10_M05','085c478b380e63908672c0382798750a9a075afc9b8fa21d0fa809db0684e90e'),
 ('PE10_M06','4d5a9c761bc0171efa908e97d471cb1d372046b235274f141695d4665f1cc4cb'),
 ('PE10_M07','508081f732648de4caa9b7b95bafba2283f5d2e719323a90d941fe3bedbfdd4a'),
 ('PE10_M08','ebc8477fea336cb76c25d73cfbcdbe9fe680ca03770734e04ede3fa140512c12'),
 ('PE10_M09','f939334bc3c1d5be819c59309fc375a14fd7360fd4b8705ff6f749bdc0f805df'),
 ('PE10_M10','63855d13ae93adff8c959cc9f071136e5405dfd736a6da2aecafb38ae0cde20b'),
 ('PE10_M11','d0ffbe0d56335daa9a800d0326201686eed5e861745b2fdddcad5dc3b3e56025')) e(code,sha)
 ON e.code=c.checkpoint_code AND e.sha=c.assertion_receipt_sha256
 WHERE c.work_item_id=1133 AND c.status='DONE' AND c.assertion_receipt->>'passed'='true'
 AND c.assertion_contract_sha256=c.assertion_receipt->>'contract_sha256';
 IF v_prev_n<>11 THEN RAISE EXCEPTION 'M12_OLDER_RECEIPTS_CHANGED'; END IF;

 v_blob:=encode(extensions.digest(convert_to('blob '||octet_length(convert_to(v_raw,'UTF8'))::text,'UTF8')
 ||decode('00','hex')||convert_to(v_raw,'UTF8'),'sha1'),'hex');
 IF v_blob<>'7a8d4ed337162133d806946e5e862f49a8f5c874' THEN RAISE EXCEPTION 'M12_RAW_GIT_BLOB_MISMATCH'; END IF;
 v_doc:=v_raw::jsonb;
 IF v_doc->>'schema'<>'PE10_METHOD_RAW_V2' OR v_doc->>'method_code'<>'PE10_M12'
 OR v_doc->>'case_ref'<>'PE10-IG-M107-M109-P0' OR v_doc->>'base_code'<>'A'
 OR v_doc->'algorithm_codes'<>'["D","M","E"]'::jsonb
 OR v_doc->>'source_cutoff'<>'2026-10-15T00:00:00Z'
 OR v_doc#>>'{original_preserved,sha256}'<>'04392fbcd8e40c7236abef2b7019b2668efd8ff5e46bb50765f9f384b5ef78a3'
 OR v_doc->>'external_evaluation'<>'NOT_PERFORMED'
 OR v_doc#>>'{algorithm_execution,E,actual_state}'<>'VERIFY_FIRST'
 OR v_doc#>>'{chosen_repair,state}'<>'VERIFY_FIRST'
 OR v_doc->>'conclusion'<>'D_M_E_EXECUTED_SOURCE_EVIDENCE_WITH_VERIFICATION_FIRST_NO_APPLIED_REPAIR'
 THEN RAISE EXCEPTION 'M12_RAW_IDENTITY_FAILED'; END IF;

 SELECT count(*) INTO v_q FROM jsonb_array_elements(v_doc->'sql_evidence') z
 WHERE z->>'id'~'^M12_Q(0[1-9]|1[01])$' AND z->>'sql_literal'~* '^SELECT '
 AND z->>'source'='SUPABASE_READ_ONLY' AND jsonb_typeof(z->'rows')='array'
 AND (z->>'rows_returned')::int=jsonb_array_length(z->'rows') AND jsonb_array_length(z->'rows')>0;
 IF v_q<>11 OR jsonb_array_length(v_doc->'sql_evidence')<>11
 OR (SELECT count(DISTINCT z->>'id') FROM jsonb_array_elements(v_doc->'sql_evidence') z)<>11
 OR v_doc#>>'{sql_evidence,1,rows,0,total}'<>'38'
 OR v_doc#>>'{sql_evidence,2,rows,0,lexical_edges}'<>'76'
 OR v_doc#>>'{sql_evidence,3,rows,0,usage_stats,track_functions}'<>'none'
 OR v_doc#>>'{sql_evidence,4,rows,0,verified}'<>'VERIFIED'
 OR v_doc#>>'{sql_evidence,9,rows,0,later}'<>'0'
 THEN RAISE EXCEPTION 'M12_SQL_EVIDENCE_NOT_EXACT'; END IF;

 SELECT count(*) INTO v_d FROM jsonb_array_elements(v_doc#>'{algorithm_execution,D,minimal_hitting_sets}') x
 WHERE jsonb_array_length(x)=3 AND (x ? 'HIST_SOAK_TEXT_DRIFT' OR x ? 'SOURCE_RECEIPT_BINDING')
 AND (x ? 'CP2_ROLE_PRIVILEGE' OR x ? 'CP2_READ_CONTEXT')
 AND (x ? 'STATIC_GRAPH_PROMOTION' OR x ? 'MISSING_RUNTIME_TRACE');
 SELECT count(*) INTO v_m FROM jsonb_array_elements(v_doc#>'{algorithm_execution,M,retractions}') x
 WHERE x->>'derived_state' IN ('VERIFY_FIRST','NEEDS_MORE_EVIDENCE')
 AND jsonb_typeof(x->'removed')='array';
 SELECT count(*) INTO v_e FROM jsonb_array_elements(v_doc#>'{algorithm_execution,E,scenarios}') x
 WHERE x->>'expected'=CASE
 WHEN coalesce((x#>>'{inputs,causal_defect}')::boolean,false)
 AND coalesce((x#>>'{inputs,proven_trace}')::boolean,false) THEN 'REPAIR_REQUIRED'
 WHEN coalesce((x#>>'{inputs,material_risk}')::boolean,false)
 AND coalesce((x#>>'{inputs,authorized_discriminator}')::boolean,false) THEN 'VERIFY_FIRST'
 WHEN coalesce((x#>>'{inputs,missing_evidence}')::boolean,false)
 OR NOT coalesce((x#>>'{inputs,qualified_source}')::boolean,false) THEN 'NEEDS_MORE_EVIDENCE'
 ELSE 'NO_ACTION_SUPPORTED' END AND x->>'observed'=x->>'expected';
 SELECT count(DISTINCT x->>'observed') INTO v_e_classes FROM jsonb_array_elements(v_doc#>'{algorithm_execution,E,scenarios}') x;
 SELECT count(*) INTO v_neg FROM jsonb_array_elements(v_doc->'negative_tests') x WHERE x->>'pass'='true';
 IF v_d<>8 OR jsonb_array_length(v_doc#>'{algorithm_execution,D,minimal_hitting_sets}')<>8
 OR v_m<>8 OR jsonb_array_length(v_doc#>'{algorithm_execution,M,retractions}')<>8
 OR v_doc#>>'{algorithm_execution,M,retractions,4,derived_state}'<>'NEEDS_MORE_EVIDENCE'
 OR v_doc#>>'{algorithm_execution,M,retractions,5,derived_state}'<>'NEEDS_MORE_EVIDENCE'
 OR v_e<>7 OR jsonb_array_length(v_doc#>'{algorithm_execution,E,scenarios}')<>7 OR v_e_classes<>4
 OR v_neg<>16 OR jsonb_array_length(v_doc->'negative_tests')<>16
 OR v_doc#>>'{algorithm_execution,D,barinel}'<>'NOT_CALIBRATABLE_WITHOUT_EXECUTION_SPECTRA'
 OR v_doc#>>'{algorithm_execution,D,information_gain}'<>'ORDINAL_ONLY_NO_PRIORS'
 THEN RAISE EXCEPTION 'M12_DME_TESTS_INCOMPLETE_OR_FALSIFIED'; END IF;

 SELECT count(*) INTO v_ekb FROM transversal.error_knowledge
 WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001')
 AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z';
 IF v_ekb<>2 OR (SELECT count(*) FROM public.lf_eventos WHERE id=20161
 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z' AND jsonb_array_length(payload->'sql_callers')=38
 AND payload->'usage_stats'->>'track_functions'='none')<>1
 OR (SELECT count(*) FROM programacion.provenance_receipts WHERE id=38
 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'
 AND payload->>'verification_status'='VERIFIED' AND payload->>'known_false_pass_signals'='0'
 AND payload->>'unresolved_d4'='0')<>1
 THEN RAISE EXCEPTION 'M12_ASOF_GOVERNANCE_READBACK_DIFFERENT'; END IF;

 UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10_M12}',v_spec,true)
 WHERE work_item_id=1133 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32';
 GET DIAGNOSTICS v_n=ROW_COUNT;
 IF v_n<>1 THEN RAISE EXCEPTION 'M12_CANONICAL_SPEC_UPDATE_FAILED'; END IF;
 v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M12',
 programacion.fn_engineering_checkpoint_action_spec_v3('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M12'));
 IF v_contract->>'status'<>'READY' OR v_contract->>'mode'<>'EXPLICIT_PASS_WHEN_SUBSET'
 THEN RAISE EXCEPTION 'M12_ASSERTION_CONTRACT_NOT_READY:%',coalesce(v_contract::text,'NULL'); END IF;
 v_obs:=jsonb_build_object('checkpoint_identity','PE10_M12','method_algorithms','D+M+E',
 'literal_sql_count',11,'gde_minimal_hitting_sets',8,'atms_retractions_executed',8,
 'typed_e_cases_verified',7,'negative_tests_passed',16,'typed_e_state','VERIFY_FIRST',
 'historical_source_event_id',20161,'git_source_verified',true,'runtime_modified',false);
 v_result:=jsonb_build_object('status','PASS','observed',v_obs,'evidence_ref',v_ref,
 'validation_kind','M12_METHOD_DME_MATERIAL_COMPLETENESS_NOT_PRODUCT_REPAIR',
 'method_score','NOT_PERFORMED');
 v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M12',v_result,v_exec);
 IF v_assertion->>'passed'<>'true' OR coalesce(v_assertion->>'assertion_receipt_sha256','') !~ '^[a-f0-9]{64}$'
 THEN RAISE EXCEPTION 'M12_MATERIAL_ASSERTION_NOT_CANONICAL'; END IF;
 v_receipt:=v_assertion->>'assertion_receipt_sha256';
 v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M12','DONE',v_ref,v_exec,
 'M12 GDE D+ATMS M+E typed verification decision attested; no production repair');
 IF v_transition#>>'{transition,status}'<>'APPLIED' THEN RAISE EXCEPTION 'M12_STATUS_TRANSITION_FAILED'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133
 AND checkpoint_code='PE10_M12' AND status='DONE' AND completed_at IS NOT NULL
 AND evidence_ref=v_ref AND assertion_receipt_sha256=v_receipt
 AND assertion_contract_sha256=assertion_receipt->>'contract_sha256' AND assertion_receipt->>'passed'='true')<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>12
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>20
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M13' AND status='PENDING')<>1
 THEN RAISE EXCEPTION 'M12_FINAL_DONE_READBACK_NOT_PROVEN'; END IF;
EXCEPTION WHEN OTHERS THEN
 GET STACKED DIAGNOSTICS v_msg=MESSAGE_TEXT,v_ctx=PG_EXCEPTION_CONTEXT;
 RAISE EXCEPTION 'M12_TRAIN_ERROR state=% msg=% context=%',SQLSTATE,left(v_msg,290),left(v_ctx,140) USING ERRCODE=SQLSTATE;
END $m12_close$;
