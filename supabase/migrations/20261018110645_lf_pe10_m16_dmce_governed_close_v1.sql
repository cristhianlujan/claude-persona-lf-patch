-- PE10 M16: independently certify entire A-arm D+M+C+E via exact-authorized LF migration Train only.
DO $m16_close$
DECLARE
 v_exec text;v_raw text:=$m16_raw${
  "schema": "PE10_METHOD_RAW_V2",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M16",
  "base_code": "A",
  "algorithm_codes": [
    "D",
    "M",
    "C",
    "E"
  ],
  "source_cutoff": "2026-10-15T00:00:00Z",
  "original_preserved": {
    "ref": "chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M16.json",
    "sha256": "aa4c29172f6355e748f15b0fb6d3d4e3e2f1f2b358f2de63b293ee8837a0dda3"
  },
  "producer": "One integrated A SRCR method-specific independent research, no outside method scoring or method outputs",
  "external_evaluation": "NOT_PERFORMED",
  "sql_evidence": [
    {
      "id": "M16_Q01",
      "sql_literal": "SELECT id,created_at,payload->>'source_pack_version' source_pack,payload->'scope_guards' guards,payload->'historical_provenance_only' provenance FROM public.lf_eventos WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'",
      "rows": [
        {
          "id": 20161,
          "created_at": "2026-10-04 05:14:40.880842+00",
          "source_pack": "SOURCE_PACK_V1",
          "guards": {
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
      "scope": "HISTORICAL_SOURCE_ASOF_P0"
    },
    {
      "id": "M16_Q02",
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
      "scope": "HISTORICAL_SOURCE_ASOF_P0"
    },
    {
      "id": "M16_Q03",
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
      "scope": "HISTORICAL_SOURCE_ASOF_P0"
    },
    {
      "id": "M16_Q04",
      "sql_literal": "SELECT count(*) total,count(*) FILTER(WHERE x->>'definition_md5' ~ '^[a-f0-9]{32}$') valid,count(*) FILTER(WHERE NOT(x->>'definition_md5' ~ '^[a-f0-9]{32}$')) invalid,count(*) FILTER(WHERE (x->>'definition_md5' ~ '^[a-f0-9]{32}$') IS NULL) unknown FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161",
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
      "scope": "HISTORICAL_SOURCE_ASOF_P0"
    },
    {
      "id": "M16_Q05",
      "sql_literal": "SELECT count(*) lexical_edges,count(DISTINCT (x->>'caller')||'->'||c.name) distinct_edges,count(DISTINCT c.name) callee_names,count(*) FILTER(WHERE c.name ILIKE '%cached%') cached_refs FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x CROSS JOIN LATERAL jsonb_array_elements_text(x->'callees') c(name) WHERE e.id=20161",
      "rows": [
        {
          "lexical_edges": 76,
          "distinct_edges": 76,
          "callee_names": 39,
          "cached_refs": 11
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF_P0"
    },
    {
      "id": "M16_Q06",
      "sql_literal": "SELECT jsonb_array_length(payload->'trigger_bindings') trigger_bindings,jsonb_array_length(payload->'external_inventory') externals,jsonb_array_length(payload->'edge_current') edge_current,jsonb_array_length(payload->'consumer_relation_snapshot_json_rows') consumer_snapshots,payload->'usage_stats' usage_stats FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "trigger_bindings": 21,
          "externals": 6,
          "edge_current": 4,
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
      "scope": "HISTORICAL_SOURCE_ASOF_P0"
    },
    {
      "id": "M16_Q07",
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
      "scope": "HISTORICAL_SOURCE_ASOF_P0"
    },
    {
      "id": "M16_Q08",
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
      "scope": "HISTORICAL_SOURCE_ASOF_P0"
    },
    {
      "id": "M16_Q09",
      "sql_literal": "SELECT payload->'deduplication' deduplication,payload->'excluded_name_candidate' excluded,payload->'ambiguous_name_candidates_checked' ambiguous,payload->'scope_guards' guards FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
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
          },
          "ambiguous": 1,
          "guards": {
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
      "scope": "HISTORICAL_SOURCE_ASOF_P0"
    },
    {
      "id": "M16_Q10",
      "sql_literal": "WITH cases(expected,observed) AS (VALUES(38,38),(38,37),(38,NULL::int)) SELECT expected,observed,(expected=observed) IS TRUE accepted FROM cases ORDER BY observed NULLS LAST",
      "rows": [
        {
          "expected": 38,
          "observed": 37,
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
      "scope": "SYNTHETIC_CONTRACT_VALID_AND_NEGATIVE"
    },
    {
      "id": "M16_Q11",
      "sql_literal": "WITH flags(v) AS (VALUES('ACTIVE'::text),('OTHER'::text),(NULL::text)) SELECT count(*) total,count(*) FILTER(WHERE v='ACTIVE') t,count(*) FILTER(WHERE NOT(v='ACTIVE')) f,count(*) FILTER(WHERE (v='ACTIVE') IS NULL) n FROM flags",
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
      "scope": "SYNTHETIC_CONTRACT_VALID_AND_NEGATIVE"
    },
    {
      "id": "M16_Q12",
      "sql_literal": "SELECT count(*) FILTER(WHERE created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z') before_cutoff,count(*) FILTER(WHERE created_at>=TIMESTAMPTZ '2026-10-15T00:00:00Z') after_cutoff FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "before_cutoff": 1,
          "after_cutoff": 0
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF_P0"
    },
    {
      "id": "M16_Q13",
      "sql_literal": "SELECT coalesce(x->>'operational_class','UNKNOWN') operational_class,coalesce(x->>'governance_lifecycle','UNKNOWN') lifecycle,count(*) n FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'external_inventory') x WHERE e.id=20161 GROUP BY 1,2 ORDER BY 1,2",
      "rows": [
        {
          "operational_class": "ACTIVE",
          "lifecycle": "CANDIDATE_READ_ONLY",
          "n": 2
        },
        {
          "operational_class": "ACTIVE",
          "lifecycle": "RUNTIME_SANDBOX_CANARY",
          "n": 1
        },
        {
          "operational_class": "CANDIDATE",
          "lifecycle": "CANDIDATE_READ_ONLY",
          "n": 1
        },
        {
          "operational_class": "CANDIDATE",
          "lifecycle": "NO_HABILITADO",
          "n": 1
        },
        {
          "operational_class": "CANDIDATE_TEST",
          "lifecycle": "CANDIDATE_READ_ONLY",
          "n": 1
        }
      ],
      "rows_returned": 5,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF_P0"
    },
    {
      "id": "M16_Q14",
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
    "D": {
      "conflicts": [
        [
          "SOAK_PROJECTION_DRIFT",
          "QUALIFIED_SOAK_RECEIPT_CONTEXT"
        ],
        [
          "CP2_READER_CURRENTNESS_GAP",
          "CP2_PRIVILEGE_42501"
        ],
        [
          "STATIC_CALLEE_LEXEME",
          "DYNAMIC_INVOCATION_EVIDENCE_GAP"
        ]
      ],
      "minimal_hitting_sets": [
        [
          "SOAK_PROJECTION_DRIFT",
          "CP2_READER_CURRENTNESS_GAP",
          "STATIC_CALLEE_LEXEME"
        ],
        [
          "QUALIFIED_SOAK_RECEIPT_CONTEXT",
          "CP2_READER_CURRENTNESS_GAP",
          "STATIC_CALLEE_LEXEME"
        ],
        [
          "SOAK_PROJECTION_DRIFT",
          "CP2_PRIVILEGE_42501",
          "STATIC_CALLEE_LEXEME"
        ],
        [
          "QUALIFIED_SOAK_RECEIPT_CONTEXT",
          "CP2_PRIVILEGE_42501",
          "STATIC_CALLEE_LEXEME"
        ],
        [
          "SOAK_PROJECTION_DRIFT",
          "CP2_READER_CURRENTNESS_GAP",
          "DYNAMIC_INVOCATION_EVIDENCE_GAP"
        ],
        [
          "QUALIFIED_SOAK_RECEIPT_CONTEXT",
          "CP2_READER_CURRENTNESS_GAP",
          "DYNAMIC_INVOCATION_EVIDENCE_GAP"
        ],
        [
          "SOAK_PROJECTION_DRIFT",
          "CP2_PRIVILEGE_42501",
          "DYNAMIC_INVOCATION_EVIDENCE_GAP"
        ],
        [
          "QUALIFIED_SOAK_RECEIPT_CONTEXT",
          "CP2_PRIVILEGE_42501",
          "DYNAMIC_INVOCATION_EVIDENCE_GAP"
        ]
      ],
      "total_candidate_hitting_sets": 27,
      "barinel": "NOT_CALIBRATABLE_NO_EXECUTION_SPECTRA",
      "information_gain": "ORDINAL_ONLY_NO_VALID_PRIORS",
      "causality": "MODELED_NOT_PROVEN"
    },
    "M": {
      "facts": [
        "EVENT_20161",
        "SOAK_RECEIPT_38",
        "EKB_BEFORE_CUTOFF",
        "SOURCE_ASOF",
        "AUTHORIZED_SELECT_ROUTE",
        "TRACK_FUNCTIONS_NONE"
      ],
      "rules": {
        "CALLERS_ASOF": [
          [
            "EVENT_20161",
            "SOURCE_ASOF"
          ]
        ],
        "SOAK_QUALIFIED": [
          [
            "SOAK_RECEIPT_38",
            "SOURCE_ASOF"
          ]
        ],
        "CP2_RISK": [
          [
            "EKB_BEFORE_CUTOFF",
            "SOURCE_ASOF"
          ]
        ],
        "GRAPH_RISK": [
          [
            "CALLERS_ASOF"
          ]
        ],
        "RISKS": [
          [
            "CP2_RISK"
          ],
          [
            "GRAPH_RISK"
          ]
        ],
        "FALSIFIER_ROUTE": [
          [
            "AUTHORIZED_SELECT_ROUTE",
            "RISKS"
          ]
        ],
        "NO_ZERO_USAGE": [
          [
            "EVENT_20161",
            "TRACK_FUNCTIONS_NONE"
          ]
        ]
      },
      "nogoods": [
        [
          "SOURCE_ASOF",
          "CLAIM_CURRENT"
        ],
        [
          "TRACK_FUNCTIONS_NONE",
          "CLAIM_NO_USE"
        ]
      ],
      "minimal_justifications": {
        "EVENT_20161": [
          [
            "EVENT_20161"
          ]
        ],
        "SOAK_RECEIPT_38": [
          [
            "SOAK_RECEIPT_38"
          ]
        ],
        "EKB_BEFORE_CUTOFF": [
          [
            "EKB_BEFORE_CUTOFF"
          ]
        ],
        "SOURCE_ASOF": [
          [
            "SOURCE_ASOF"
          ]
        ],
        "AUTHORIZED_SELECT_ROUTE": [
          [
            "AUTHORIZED_SELECT_ROUTE"
          ]
        ],
        "TRACK_FUNCTIONS_NONE": [
          [
            "TRACK_FUNCTIONS_NONE"
          ]
        ],
        "CALLERS_ASOF": [
          [
            "EVENT_20161",
            "SOURCE_ASOF"
          ]
        ],
        "SOAK_QUALIFIED": [
          [
            "SOAK_RECEIPT_38",
            "SOURCE_ASOF"
          ]
        ],
        "CP2_RISK": [
          [
            "EKB_BEFORE_CUTOFF",
            "SOURCE_ASOF"
          ]
        ],
        "GRAPH_RISK": [
          [
            "EVENT_20161",
            "SOURCE_ASOF"
          ]
        ],
        "RISKS": [
          [
            "EKB_BEFORE_CUTOFF",
            "SOURCE_ASOF"
          ],
          [
            "EVENT_20161",
            "SOURCE_ASOF"
          ]
        ],
        "FALSIFIER_ROUTE": [
          [
            "AUTHORIZED_SELECT_ROUTE",
            "EKB_BEFORE_CUTOFF",
            "SOURCE_ASOF"
          ],
          [
            "AUTHORIZED_SELECT_ROUTE",
            "EVENT_20161",
            "SOURCE_ASOF"
          ]
        ],
        "NO_ZERO_USAGE": [
          [
            "EVENT_20161",
            "TRACK_FUNCTIONS_NONE"
          ]
        ]
      },
      "retractions": [
        {
          "id": "M16_R1",
          "removed": [],
          "qualified_soak": true,
          "risks": true,
          "authorized_falsifier": true,
          "decision": "VERIFY_FIRST"
        },
        {
          "id": "M16_R2",
          "removed": [
            "EVENT_20161"
          ],
          "qualified_soak": true,
          "risks": true,
          "authorized_falsifier": true,
          "decision": "VERIFY_FIRST"
        },
        {
          "id": "M16_R3",
          "removed": [
            "EKB_BEFORE_CUTOFF"
          ],
          "qualified_soak": true,
          "risks": true,
          "authorized_falsifier": true,
          "decision": "VERIFY_FIRST"
        },
        {
          "id": "M16_R4",
          "removed": [
            "SOAK_RECEIPT_38"
          ],
          "qualified_soak": false,
          "risks": true,
          "authorized_falsifier": true,
          "decision": "VERIFY_FIRST"
        },
        {
          "id": "M16_R5",
          "removed": [
            "EVENT_20161",
            "EKB_BEFORE_CUTOFF"
          ],
          "qualified_soak": true,
          "risks": false,
          "authorized_falsifier": false,
          "decision": "NEEDS_MORE_EVIDENCE"
        },
        {
          "id": "M16_R6",
          "removed": [
            "AUTHORIZED_SELECT_ROUTE"
          ],
          "qualified_soak": true,
          "risks": true,
          "authorized_falsifier": false,
          "decision": "NEEDS_MORE_EVIDENCE"
        },
        {
          "id": "M16_R7",
          "removed": [
            "SOAK_RECEIPT_38",
            "EKB_BEFORE_CUTOFF"
          ],
          "qualified_soak": false,
          "risks": true,
          "authorized_falsifier": true,
          "decision": "VERIFY_FIRST"
        },
        {
          "id": "M16_R8",
          "removed": [
            "SOURCE_ASOF"
          ],
          "qualified_soak": false,
          "risks": false,
          "authorized_falsifier": false,
          "decision": "NEEDS_MORE_EVIDENCE"
        }
      ],
      "temporal_identity": "P0_SOURCE_ONLY"
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
        "hashes": {
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
      "count_contract_cases": [
        {
          "expected": 38,
          "observed": 37,
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
      "solver": "NOT_EXECUTED_NO_SMT",
      "business_rule_correctness": "NOT_PROVEN_BY_PARITY"
    },
    "E": {
      "actual_state": "VERIFY_FIRST",
      "decision_scenarios": [
        {
          "id": "E_P0_CASE",
          "inputs": {
            "functional_defect": false,
            "causal_trace": false,
            "qualified_risk": true,
            "safe_reader": true,
            "material_unknown": true,
            "qualified_source": true
          },
          "expected": "VERIFY_FIRST",
          "observed": "VERIFY_FIRST"
        },
        {
          "id": "E_CAUSAL_POSITIVE",
          "inputs": {
            "functional_defect": true,
            "causal_trace": true,
            "qualified_risk": true,
            "safe_reader": true,
            "material_unknown": false,
            "qualified_source": true
          },
          "expected": "REPAIR_REQUIRED",
          "observed": "REPAIR_REQUIRED"
        },
        {
          "id": "E_MISSING_READER",
          "inputs": {
            "functional_defect": false,
            "causal_trace": false,
            "qualified_risk": true,
            "safe_reader": false,
            "material_unknown": true,
            "qualified_source": false
          },
          "expected": "NEEDS_MORE_EVIDENCE",
          "observed": "NEEDS_MORE_EVIDENCE"
        },
        {
          "id": "E_FULLY_CLEARED",
          "inputs": {
            "functional_defect": false,
            "causal_trace": false,
            "qualified_risk": false,
            "safe_reader": false,
            "material_unknown": false,
            "qualified_source": true
          },
          "expected": "NO_ACTION_SUPPORTED",
          "observed": "NO_ACTION_SUPPORTED"
        },
        {
          "id": "E_42501_NOT_FUNCTIONAL",
          "inputs": {
            "functional_defect": false,
            "causal_trace": false,
            "qualified_risk": true,
            "safe_reader": true,
            "material_unknown": true,
            "qualified_source": true
          },
          "expected": "VERIFY_FIRST",
          "observed": "VERIFY_FIRST"
        },
        {
          "id": "E_UNPROVEN_CAUSALITY",
          "inputs": {
            "functional_defect": true,
            "causal_trace": false,
            "qualified_risk": true,
            "safe_reader": true,
            "material_unknown": true,
            "qualified_source": true
          },
          "expected": "VERIFY_FIRST",
          "observed": "VERIFY_FIRST"
        },
        {
          "id": "E_UNKNOWN_NO_SCOPE",
          "inputs": {
            "functional_defect": false,
            "causal_trace": false,
            "qualified_risk": false,
            "safe_reader": false,
            "material_unknown": true,
            "qualified_source": false
          },
          "expected": "NEEDS_MORE_EVIDENCE",
          "observed": "NEEDS_MORE_EVIDENCE"
        }
      ],
      "derived_atms_states": [
        {
          "id": "M16_R1",
          "removed": [],
          "state": "VERIFY_FIRST"
        },
        {
          "id": "M16_R2",
          "removed": [
            "EVENT_20161"
          ],
          "state": "VERIFY_FIRST"
        },
        {
          "id": "M16_R3",
          "removed": [
            "EKB_BEFORE_CUTOFF"
          ],
          "state": "VERIFY_FIRST"
        },
        {
          "id": "M16_R4",
          "removed": [
            "SOAK_RECEIPT_38"
          ],
          "state": "VERIFY_FIRST"
        },
        {
          "id": "M16_R5",
          "removed": [
            "EVENT_20161",
            "EKB_BEFORE_CUTOFF"
          ],
          "state": "NEEDS_MORE_EVIDENCE"
        },
        {
          "id": "M16_R6",
          "removed": [
            "AUTHORIZED_SELECT_ROUTE"
          ],
          "state": "NEEDS_MORE_EVIDENCE"
        },
        {
          "id": "M16_R7",
          "removed": [
            "SOAK_RECEIPT_38",
            "EKB_BEFORE_CUTOFF"
          ],
          "state": "VERIFY_FIRST"
        },
        {
          "id": "M16_R8",
          "removed": [
            "SOURCE_ASOF"
          ],
          "state": "NEEDS_MORE_EVIDENCE"
        }
      ],
      "reversal_criteria": [
        {
          "trigger": "qualified causal defect and trace",
          "next": "REPAIR_REQUIRED"
        },
        {
          "trigger": "risk cleared in qualified scope",
          "next": "NO_ACTION_SUPPORTED"
        },
        {
          "trigger": "authorized reader unavailable",
          "next": "NEEDS_MORE_EVIDENCE"
        }
      ]
    }
  },
  "negative_tests": [
    {
      "id": "D_8_MINIMAL_SETS",
      "pass": true
    },
    {
      "id": "D_PROPER_SUBSET_INVALID",
      "pass": true
    },
    {
      "id": "M_REMOVE_EVENT_GRAPH",
      "pass": true
    },
    {
      "id": "M_REMOVE_EKB_ALT_GRAPH",
      "pass": true
    },
    {
      "id": "M_REMOVE_RECEIPT_RETRACT_SOAK",
      "pass": true
    },
    {
      "id": "M_REMOVE_ALL_RISK_TO_UNKNOWN",
      "pass": true
    },
    {
      "id": "M_REMOVE_SAFE_READER",
      "pass": true
    },
    {
      "id": "M_REMOVE_ASOF_INVALIDATES",
      "pass": true
    },
    {
      "id": "C_CALLER_TLP",
      "pass": true
    },
    {
      "id": "C_EXTERNAL_TLP",
      "pass": true
    },
    {
      "id": "C_HASH_RECONCILED",
      "pass": true
    },
    {
      "id": "C_SYNTHETIC_NULL_EXERCISED",
      "pass": true
    },
    {
      "id": "C_VALID_ACCEPT",
      "pass": true
    },
    {
      "id": "C_MISMATCH_REJECT",
      "pass": true
    },
    {
      "id": "C_NULL_REJECT",
      "pass": true
    },
    {
      "id": "E_SEVEN_TYPED_CASES",
      "pass": true
    },
    {
      "id": "E_FOUR_STATES",
      "pass": true
    },
    {
      "id": "E_PERMISSION_NOT_FUNCTIONAL",
      "pass": true
    },
    {
      "id": "P0_RECEIPT_SCOPE",
      "pass": true
    },
    {
      "id": "P0_CUTOFF",
      "pass": true
    },
    {
      "id": "P0_NOSTATS_NOT_ZERO_USAGE",
      "pass": true
    },
    {
      "id": "NO_SMT_NO_BARINEL",
      "pass": true
    }
  ],
  "findings": [
    {
      "id": "M16_F01",
      "claim": "Historical caller population 38 and nominal 76 lexical edges are source labels, not dynamic execution evidence",
      "evidence": [
        "M16_Q01",
        "M16_Q02",
        "M16_Q05"
      ],
      "kind": "MEASURED_HISTORICAL"
    },
    {
      "id": "M16_F02",
      "claim": "TLP independently reconciles 38 SQL callers and 6 external assets, not a combined unique consumer universe; syntactic MD5 valid 38, canonical algorithm unknown",
      "evidence": [
        "M16_Q02",
        "M16_Q03",
        "M16_Q04"
      ],
      "kind": "MEASURED_HISTORICAL"
    },
    {
      "id": "M16_F03",
      "claim": "GDE modeled conflicts have 8 minimal diagnoses, without causal root proof or calibrated BARINEL; ATMS removal updates evidence labels and E state",
      "evidence": [
        "M16_Q06",
        "M16_Q07",
        "M16_Q08"
      ],
      "kind": "COMPUTED_WITH_ASSUMPTIONS"
    },
    {
      "id": "M16_F04",
      "claim": "SOAK receipt id38 pre P0 supports historical 13/47 no false pass or D4, not qualified E2E latency or CP2 functional PASS",
      "evidence": [
        "M16_Q07",
        "M16_Q08"
      ],
      "kind": "MEASURED_WITH_LIMITS"
    },
    {
      "id": "M16_F05",
      "claim": "Case E verifies VERIFY_FIRST and reversals with 7 typed positive/negative cases, while wrong and NULL population counts fail closed",
      "evidence": [
        "M16_Q10",
        "M16_Q11",
        "M16_Q08"
      ],
      "kind": "EXECUTED_METHOD"
    }
  ],
  "causal_model": {
    "status": "UNKNOWN",
    "hypotheses": [
      "SOAK criterion projection drift",
      "CP2 privilege vs currentness gap",
      "Static named call graph mistaken as invocation evidence"
    ],
    "falsifiers": [
      "Qualified P0-time CP2 SELECT via authorized provider",
      "Time-pinned M9.11 history and source comparison",
      "Actual per-stage comparable E2E runtime cohort"
    ]
  },
  "candidate_repairs": [
    {
      "action": "Verify typed source/timestamp/identity before applying any CP2 correction",
      "status": "PROPOSED_READ_ONLY"
    },
    {
      "action": "Preserve 3VL and nogood on missing evidence, not silent FALSE",
      "status": "PROPOSED_CONTROL"
    }
  ],
  "chosen_repair": {
    "state": "VERIFY_FIRST",
    "applied": false,
    "reason": "Material source risks, no causal defect proved"
  },
  "rejected_alternatives": [
    "Activate runtime to fill P0 gap",
    "Infer speed from disabled pg_stat",
    "Invent BARINEL probabilities",
    "Treat TLP matching engine counts as domain success"
  ],
  "omissions_searched": [
    "role authority",
    "historical provenance",
    "unknown hashes",
    "external identity populations",
    "3VL NULL negative",
    "multiple ATMS alternative supports",
    "E decision reversal",
    "live traces vs nominal edges"
  ],
  "unresolved": [
    "Historical canonical MD5 production method UNKNOWN",
    "CP2 qualified current/read route not directly observed",
    "No E2E median/p90 source",
    "No demonstrated product repair"
  ],
  "constraints_preserved": [
    "P0 cutoff",
    "readonly",
    "no runtime/role changes",
    "no external evaluation",
    "no other method outputs as data"
  ],
  "conclusion": "D_M_C_E_INTEGRATED_METHOD_EXECUTED_WITH_VERIFY_FIRST_AND_OPEN_CAUSAL_QUESTIONS"
}
$m16_raw$;v_doc jsonb;
 v_spec jsonb:=$m16_spec${"status":"READY","action_kind":"VERIFY_QUERY_ONCE","recipe_mode":"READBACK_EXACT","requires_material_execution":true,"contract_family":"PE10_METHOD_EXECUTION_EVIDENCE","precision":"PE10_METHOD_V1_MATERIAL_EVIDENCE","assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"checkpoint_identity":"PE10_M16","method_algorithms":"D+M+C+E","literal_sql_count":14,"gde_minimal_diagnoses":8,"atms_retractions_recomputed":8,"typed_e_scenarios_recomputed":7,"negative_controls_passed":22,"typed_decision":"VERIFY_FIRST","historical_source_event_id":20161,"git_source_verified":true,"runtime_modified":false}},"evidence_ref":"https://github.com/cristhianlujan/claude-persona-lf-patch/blob/1dc906b6a95c523dd6262f2aad1930c38fe79945/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M16_RAW_V2.json#git_blob_sha=02a22aa2f0657c55f5f1fc48e1afd4ae99b1475f","verification_queries":["SELECT id,created_at,payload->>'source_pack_version' source_pack,payload->'scope_guards' guards,payload->'historical_provenance_only' provenance FROM public.lf_eventos WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'","SELECT count(*) total,count(*) FILTER(WHERE x->>'operational_class'='ACTIVE') t,count(*) FILTER(WHERE NOT(x->>'operational_class'='ACTIVE')) f,count(*) FILTER(WHERE (x->>'operational_class'='ACTIVE') IS NULL) n,count(DISTINCT x->>'dedupe_key') unique_keys FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161","SELECT count(*) total,count(*) FILTER(WHERE x->>'operational_class'='ACTIVE') t,count(*) FILTER(WHERE NOT(x->>'operational_class'='ACTIVE')) f,count(*) FILTER(WHERE (x->>'operational_class'='ACTIVE') IS NULL) n FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'external_inventory') x WHERE e.id=20161","SELECT count(*) total,count(*) FILTER(WHERE x->>'definition_md5' ~ '^[a-f0-9]{32}$') valid,count(*) FILTER(WHERE NOT(x->>'definition_md5' ~ '^[a-f0-9]{32}$')) invalid,count(*) FILTER(WHERE (x->>'definition_md5' ~ '^[a-f0-9]{32}$') IS NULL) unknown FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161","SELECT count(*) lexical_edges,count(DISTINCT (x->>'caller')||'->'||c.name) distinct_edges,count(DISTINCT c.name) callee_names,count(*) FILTER(WHERE c.name ILIKE '%cached%') cached_refs FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x CROSS JOIN LATERAL jsonb_array_elements_text(x->'callees') c(name) WHERE e.id=20161","SELECT id,created_at,receipt_kind,subject_ref,payload->>'verification_status' verified,payload->>'screens_total' screens,payload->>'families_total' families,payload->>'known_false_pass_signals' false_pass,payload->>'unresolved_d4' d4 FROM programacion.provenance_receipts WHERE id=38 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'","SELECT codigo,primera_vez,causa_raiz,prevencion,validacion FROM transversal.error_knowledge WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001') AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z' ORDER BY codigo","WITH cases(expected,observed) AS (VALUES(38,38),(38,37),(38,NULL::int)) SELECT expected,observed,(expected=observed) IS TRUE accepted FROM cases ORDER BY observed NULLS LAST","WITH flags(v) AS (VALUES('ACTIVE'::text),('OTHER'::text),(NULL::text)) SELECT count(*) total,count(*) FILTER(WHERE v='ACTIVE') t,count(*) FILTER(WHERE NOT(v='ACTIVE')) f,count(*) FILTER(WHERE (v='ACTIVE') IS NULL) n FROM flags"],"expected":"Full D+M+C+E single A-arm method source materiality with dynamic revalidation of ATMS/E, no product remediation or judge scoring","forbidden":["CLAIM_PRODUCTION_REPAIR","CLAIM_NUMERIC_BARINEL","CLAIM_SMT_PROOF","MARK_DONE_FROM_HASH_ONLY","ALTER_ADJACENT_METHODS"],"target":{"checkpoint":"PE10_M16","declared_events":[20161],"declared_objects":["public.lf_eventos","programacion.provenance_receipts","transversal.error_knowledge","programacion.engineering_work_checkpoints"],"evidence_artifacts":[{"path":"cristhianlujan/claude-persona-lf-patch:docs/profile_updater/experiments/pe10_methods32_p0/PE10_M16_RAW_V2.json","role":"EVIDENCE","purpose":"M16_FULL_A_D_M_C_E_SOURCE_RAW","target_kind":"EXACT_EXISTING_FILE"}]}}$m16_spec$::jsonb;
 v_ref text:='https://github.com/cristhianlujan/claude-persona-lf-patch/blob/1dc906b6a95c523dd6262f2aad1930c38fe79945/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M16_RAW_V2.json#git_blob_sha=02a22aa2f0657c55f5f1fc48e1afd4ae99b1475f';v_old text:='chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M16.json#sha256=aa4c29172f6355e748f15b0fb6d3d4e3e2f1f2b358f2de63b293ee8837a0dda3';v_blob text;
 v_q int;v_d int;v_m int;v_e int;v_classes int;v_c int;v_ekb int;v_prev_ok int;v_n int;
 v_contract jsonb;v_obs jsonb;v_result jsonb;v_assertion jsonb;v_transition jsonb;v_receipt text;
 v_err text;v_ctx text;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
 AND target_code LIKE '%lf_pe10_m16_dmce_governed_close_v1'
 AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'M16_NO_AUTHORIZED_TRAIN_EXECUTION'; END IF;
 IF (SELECT status FROM programacion.engineering_work_items WHERE id=1133)<>'IN_PROGRESS'
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>15
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>17
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M16'
 AND id=1640 AND status='PENDING' AND evidence_ref=v_old
 AND assertion_receipt IS NULL AND completed_at IS NULL)<>1
 OR (SELECT count(*) FROM programacion.pe10_method_variants WHERE method_code='PE10_M16'
 AND case_ref='PE10-IG-M107-M109-P0' AND base_code='A'
 AND algorithm_codes=ARRAY['D','M','C','E']::text[])<>1
 OR (SELECT count(*) FROM programacion.engineering_plan_units WHERE work_item_id=1133
 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32'
 AND unit_metadata#>>'{action_specs_v1,PE10_M16,status}'='BLOCK_PENDING_MATERIAL_RESEARCH_AND_VALIDATION')<>1
 THEN RAISE EXCEPTION 'M16_PRESTATE_DRIFT'; END IF;
 SELECT count(*) INTO v_prev_ok FROM programacion.engineering_work_checkpoints c
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
('PE10_M14','6b4e248faab213612d2a88992603e02b02bc75e608fc11a6ddcef76382ee4f4a'),
('PE10_M15','1e43cfc81056ee40c1f94f56438bac1e34ce5cb6331112c9c602b438fb1f8319')
 ) e(code,sha) ON e.code=c.checkpoint_code AND e.sha=c.assertion_receipt_sha256
 WHERE c.work_item_id=1133 AND c.status='DONE' AND c.assertion_receipt->>'passed'='true'
 AND c.assertion_contract_sha256=c.assertion_receipt->>'contract_sha256';
 IF v_prev_ok<>15 THEN RAISE EXCEPTION 'M16_PRIOR_15_RECEIPTS_NOT_IDENTICAL'; END IF;

 v_blob:=encode(extensions.digest(convert_to('blob '||octet_length(convert_to(v_raw,'UTF8'))::text,'UTF8')
 ||decode('00','hex')||convert_to(v_raw,'UTF8'),'sha1'),'hex');
 IF v_blob<>'02a22aa2f0657c55f5f1fc48e1afd4ae99b1475f' THEN RAISE EXCEPTION 'M16_IMMUTABLE_GIT_BLOB_DIFFERS'; END IF;
 v_doc:=v_raw::jsonb;
 IF v_doc->>'schema'<>'PE10_METHOD_RAW_V2'
 OR v_doc->>'method_code'<>'PE10_M16'
 OR v_doc->>'case_ref'<>'PE10-IG-M107-M109-P0'
 OR v_doc->>'base_code'<>'A'
 OR v_doc->'algorithm_codes'<>'["D","M","C","E"]'::jsonb
 OR v_doc->>'source_cutoff'<>'2026-10-15T00:00:00Z'
 OR v_doc#>>'{original_preserved,sha256}'<>'aa4c29172f6355e748f15b0fb6d3d4e3e2f1f2b358f2de63b293ee8837a0dda3'
 OR v_doc->>'external_evaluation'<>'NOT_PERFORMED'
 OR v_doc#>>'{algorithm_execution,E,actual_state}'<>'VERIFY_FIRST'
 OR v_doc#>>'{chosen_repair,state}'<>'VERIFY_FIRST'
 OR v_doc->>'conclusion'<>'D_M_C_E_INTEGRATED_METHOD_EXECUTED_WITH_VERIFY_FIRST_AND_OPEN_CAUSAL_QUESTIONS'
 THEN RAISE EXCEPTION 'M16_METHOD_OR_P0_SOURCE_NOT_QUALIFIED'; END IF;
 SELECT count(*) INTO v_q FROM jsonb_array_elements(v_doc->'sql_evidence') z
 WHERE z->>'id' ~ '^M16_Q(0[1-9]|1[0-4])$'
 AND z->>'sql_literal' ~* '^(SELECT|WITH) ' AND z->>'source'='SUPABASE_READ_ONLY'
 AND jsonb_typeof(z->'rows')='array' AND (z->>'rows_returned')::int=jsonb_array_length(z->'rows')
 AND jsonb_array_length(z->'rows')>0;
 IF v_q<>14 OR jsonb_array_length(v_doc->'sql_evidence')<>14
 OR (SELECT count(DISTINCT z->>'id') FROM jsonb_array_elements(v_doc->'sql_evidence') z)<>14
 OR v_doc#>>'{sql_evidence,1,rows,0,total}'<>'38'
 OR v_doc#>>'{sql_evidence,2,rows,0,total}'<>'6'
 OR v_doc#>>'{sql_evidence,3,rows,0,valid}'<>'38'
 OR v_doc#>>'{sql_evidence,4,rows,0,lexical_edges}'<>'76'
 OR v_doc#>>'{sql_evidence,6,rows,0,verified}'<>'VERIFIED'
 OR v_doc#>>'{sql_evidence,10,rows,0,n}'<>'1'
 OR v_doc#>>'{sql_evidence,11,rows,0,after_cutoff}'<>'0'
 THEN RAISE EXCEPTION 'M16_SQL_LITERAL_READBACK_MISSING'; END IF;

 SELECT count(*) INTO v_d FROM jsonb_array_elements(v_doc#>'{algorithm_execution,D,minimal_hitting_sets}') x
 WHERE jsonb_array_length(x)=3
 AND (x ? 'SOAK_PROJECTION_DRIFT' OR x ? 'QUALIFIED_SOAK_RECEIPT_CONTEXT')
 AND (x ? 'CP2_READER_CURRENTNESS_GAP' OR x ? 'CP2_PRIVILEGE_42501')
 AND (x ? 'STATIC_CALLEE_LEXEME' OR x ? 'DYNAMIC_INVOCATION_EVIDENCE_GAP');
 IF v_d<>8 OR jsonb_array_length(v_doc#>'{algorithm_execution,D,minimal_hitting_sets}')<>8
 OR v_doc#>>'{algorithm_execution,D,barinel}'<>'NOT_CALIBRATABLE_NO_EXECUTION_SPECTRA'
 OR v_doc#>>'{algorithm_execution,D,information_gain}'<>'ORDINAL_ONLY_NO_VALID_PRIORS'
 THEN RAISE EXCEPTION 'M16_D_GDE_NOT_MINIMAL_OR_UNSUPPORTED_CALIBRATION'; END IF;

 -- Source-independent recomputation of eight M/ATMS withdrawal predictions.
 WITH input AS (
 SELECT z->'removed' rem,z FROM jsonb_array_elements(v_doc#>'{algorithm_execution,M,retractions}') z
 ),support AS (
 SELECT z,rem,
 (NOT (rem ? 'SOAK_RECEIPT_38') AND NOT (rem ? 'SOURCE_ASOF')) soak_ok,
 (NOT (rem ? 'SOURCE_ASOF') AND
   (NOT (rem ? 'EVENT_20161') OR NOT (rem ? 'EKB_BEFORE_CUTOFF'))) risks_ok
 FROM input
 ),outputs AS (
 SELECT z,soak_ok,risks_ok,(risks_ok AND NOT (rem ? 'AUTHORIZED_SELECT_ROUTE')) safe_ok FROM support
 )
 SELECT count(*) INTO v_m FROM outputs
 WHERE z->'qualified_soak'=to_jsonb(soak_ok)
 AND z->'risks'=to_jsonb(risks_ok)
 AND z->'authorized_falsifier'=to_jsonb(safe_ok)
 AND z->>'decision'=CASE WHEN risks_ok AND safe_ok THEN 'VERIFY_FIRST' ELSE 'NEEDS_MORE_EVIDENCE' END;
 IF v_m<>8 OR jsonb_array_length(v_doc#>'{algorithm_execution,M,retractions}')<>8
 OR jsonb_array_length(v_doc#>'{algorithm_execution,M,nogoods}')<>2
 OR jsonb_array_length(v_doc#>'{algorithm_execution,M,minimal_justifications,RISKS}')<>2
 OR v_doc#>>'{algorithm_execution,M,retractions,4,decision}'<>'NEEDS_MORE_EVIDENCE'
 OR v_doc#>>'{algorithm_execution,M,retractions,5,decision}'<>'NEEDS_MORE_EVIDENCE'
 THEN RAISE EXCEPTION 'M16_M_ATMS_INVALIDATION_NOT_RECOMPUTABLE'; END IF;

 SELECT count(*) INTO v_e FROM jsonb_array_elements(v_doc#>'{algorithm_execution,E,decision_scenarios}') x
 WHERE x->>'expected'=CASE
 WHEN coalesce((x#>>'{inputs,functional_defect}')::boolean,false)
 AND coalesce((x#>>'{inputs,causal_trace}')::boolean,false) THEN 'REPAIR_REQUIRED'
 WHEN coalesce((x#>>'{inputs,qualified_risk}')::boolean,false)
 AND coalesce((x#>>'{inputs,safe_reader}')::boolean,false) THEN 'VERIFY_FIRST'
 WHEN coalesce((x#>>'{inputs,material_unknown}')::boolean,false)
 OR NOT coalesce((x#>>'{inputs,qualified_source}')::boolean,false) THEN 'NEEDS_MORE_EVIDENCE'
 ELSE 'NO_ACTION_SUPPORTED' END AND x->>'observed'=x->>'expected';
 SELECT count(DISTINCT x->>'observed') INTO v_classes FROM jsonb_array_elements(v_doc#>'{algorithm_execution,E,decision_scenarios}') x;
 SELECT count(*) INTO v_c FROM jsonb_array_elements(v_doc->'negative_tests') x WHERE x->>'pass'='true';
 IF v_e<>7 OR jsonb_array_length(v_doc#>'{algorithm_execution,E,decision_scenarios}')<>7
 OR v_classes<>4 OR v_c<>22 OR jsonb_array_length(v_doc->'negative_tests')<>22
 OR v_doc#>>'{algorithm_execution,C,three_valued_partitions,callers,total}'<>'38'
 OR v_doc#>>'{algorithm_execution,C,three_valued_partitions,external,total}'<>'6'
 OR v_doc#>>'{algorithm_execution,C,three_valued_partitions,synthetic,n}'<>'1'
 OR jsonb_array_length(v_doc#>'{algorithm_execution,C,count_contract_cases}')<>3
 OR v_doc#>>'{algorithm_execution,C,solver}'<>'NOT_EXECUTED_NO_SMT'
 THEN RAISE EXCEPTION 'M16_C_E_AND_NEGATIVE_CONTROLS_FAILED'; END IF;

 SELECT count(*) INTO v_ekb FROM transversal.error_knowledge WHERE codigo IN(
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
 AND payload->>'known_false_pass_signals'='0'
 AND payload->>'unresolved_d4'='0')<>1
 THEN RAISE EXCEPTION 'M16_SOURCE_AUTHORITY_P0_INVALID'; END IF;

 UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10_M16}',v_spec,true)
 WHERE work_item_id=1133 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32';
 GET DIAGNOSTICS v_n=ROW_COUNT;
 IF v_n<>1 THEN RAISE EXCEPTION 'M16_ACTION_SPEC_NOT_ONE'; END IF;
 v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M16',
 programacion.fn_engineering_checkpoint_action_spec_v3('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M16'));
 IF v_contract->>'status'<>'READY' OR v_contract->>'mode'<>'EXPLICIT_PASS_WHEN_SUBSET'
 THEN RAISE EXCEPTION 'M16_ASSERTION_CONTRACT_NOT_READY:%',coalesce(v_contract::text,'NULL'); END IF;
 v_obs:=jsonb_build_object('checkpoint_identity','PE10_M16','method_algorithms','D+M+C+E',
 'literal_sql_count',14,'gde_minimal_diagnoses',v_d,'atms_retractions_recomputed',v_m,
 'typed_e_scenarios_recomputed',v_e,'negative_controls_passed',v_c,
 'typed_decision','VERIFY_FIRST','historical_source_event_id',20161,
 'git_source_verified',true,'runtime_modified',false);
 v_result:=jsonb_build_object('status','PASS','observed',v_obs,'evidence_ref',v_ref,
 'validation_kind','M16_INTEGRATED_A_METHOD_MATERIAL_EVIDENCE',
 'product_repair_implemented',false,'method_evaluator_ranking','NOT_PERFORMED');
 v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M16',v_result,v_exec);
 IF v_assertion->>'passed'<>'true'
 OR coalesce(v_assertion->>'assertion_receipt_sha256','') !~ '^[a-f0-9]{64}$'
 THEN RAISE EXCEPTION 'M16_ASSERTION_RECEIPT_NOT_PASSED'; END IF;
 v_receipt:=v_assertion->>'assertion_receipt_sha256';
 v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M16','DONE',v_ref,v_exec,
 'M16 integrated A D+M+C+E research source-attested; no product repair');
 IF v_transition#>>'{transition,status}'<>'APPLIED' THEN RAISE EXCEPTION 'M16_CANONICAL_TRANSITION_FAIL'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=1133 AND checkpoint_code='PE10_M16' AND status='DONE'
 AND evidence_ref=v_ref AND completed_at IS NOT NULL
 AND assertion_receipt_sha256=v_receipt AND assertion_receipt->>'passed'='true'
 AND assertion_contract_sha256=assertion_receipt->>'contract_sha256')<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>16
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>16
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133
 AND checkpoint_code='PE10_M17' AND status='PENDING')<>1
 THEN RAISE EXCEPTION 'M16_FINAL_TRAIN_READBACK_FAILED'; END IF;
EXCEPTION WHEN OTHERS THEN
 GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT,v_ctx=PG_EXCEPTION_CONTEXT;
 RAISE EXCEPTION 'M16_TRAIN_ERROR state=% message=% context=%',SQLSTATE,left(v_err,300),left(v_ctx,150) USING ERRCODE=SQLSTATE;
END $m16_close$;
