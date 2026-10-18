-- M14 alone: D GDE + C metamorphic 3VL + E typed evidence decision.
-- Apply only through authorized ACTUALIZACION_DB_LF Train migration, with full rollback on failure.
DO $m14_close$
DECLARE
 v_exec text;v_raw text:=$m14_raw${
  "schema": "PE10_METHOD_RAW_V2",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M14",
  "base_code": "A",
  "algorithm_codes": [
    "D",
    "C",
    "E"
  ],
  "source_cutoff": "2026-10-15T00:00:00Z",
  "original_preserved": {
    "ref": "chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M14.json",
    "sha256": "4809575beee9815347ce3e53da9c8c68f99d6b3ae13aee9915954daf7153c686"
  },
  "producer": "One A integrated SRCR D/C/E investigator, no peer result input",
  "external_evaluation": "NOT_PERFORMED",
  "sql_evidence": [
    {
      "id": "M14_Q01",
      "sql_literal": "SELECT id,created_at,payload->>'source_pack_version' source_pack,payload->'scope_guards' guards FROM public.lf_eventos WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'",
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
          }
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_CUTOFF"
    },
    {
      "id": "M14_Q02",
      "sql_literal": "SELECT count(*) total,count(*) FILTER(WHERE x->>'operational_class'='ACTIVE') t,count(*) FILTER(WHERE NOT(x->>'operational_class'='ACTIVE')) f,count(*) FILTER(WHERE (x->>'operational_class'='ACTIVE') IS NULL) n,count(DISTINCT x->>'dedupe_key') caller_keys FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161",
      "rows": [
        {
          "total": 38,
          "t": 38,
          "f": 0,
          "n": 0,
          "caller_keys": 38
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_CUTOFF"
    },
    {
      "id": "M14_Q03",
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
      "scope": "HISTORICAL_SOURCE_CUTOFF"
    },
    {
      "id": "M14_Q04",
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
      "scope": "HISTORICAL_SOURCE_CUTOFF"
    },
    {
      "id": "M14_Q05",
      "sql_literal": "SELECT count(*) lexical_edges,count(DISTINCT (x->>'caller')||'->'||c.name) unique_edges,count(DISTINCT c.name) destinations FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x CROSS JOIN LATERAL jsonb_array_elements_text(x->'callees') c(name) WHERE e.id=20161",
      "rows": [
        {
          "lexical_edges": 76,
          "unique_edges": 76,
          "destinations": 39
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_CUTOFF"
    },
    {
      "id": "M14_Q06",
      "sql_literal": "WITH x(flag) AS (VALUES('ACTIVE'::text),('OTHER'::text),(NULL::text)) SELECT count(*) total,count(*) FILTER(WHERE flag='ACTIVE') t,count(*) FILTER(WHERE NOT(flag='ACTIVE')) f,count(*) FILTER(WHERE (flag='ACTIVE') IS NULL) n FROM x",
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
      "scope": "EXPLICIT_SQL_CONTRACT_COUNTEREXAMPLE"
    },
    {
      "id": "M14_Q07",
      "sql_literal": "WITH x(expected,observed) AS (VALUES(38,38),(38,39),(38,NULL::int)) SELECT expected,observed,(expected=observed) IS TRUE accepted FROM x ORDER BY observed NULLS LAST",
      "rows": [
        {
          "expected": 38,
          "observed": 38,
          "accepted": true
        },
        {
          "expected": 38,
          "observed": 39,
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
      "scope": "EXPLICIT_SQL_CONTRACT_COUNTEREXAMPLE"
    },
    {
      "id": "M14_Q08",
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
      "scope": "HISTORICAL_SOURCE_CUTOFF"
    },
    {
      "id": "M14_Q09",
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
      "scope": "HISTORICAL_SOURCE_CUTOFF"
    },
    {
      "id": "M14_Q10",
      "sql_literal": "SELECT jsonb_array_length(payload->'trigger_bindings') trigger_count,jsonb_array_length(payload->'external_inventory') external_count,jsonb_array_length(payload->'consumer_relation_snapshot_json_rows') relation_snapshots,payload->'usage_stats' usage_stats FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "trigger_count": 21,
          "external_count": 6,
          "relation_snapshots": 27,
          "usage_stats": {
            "ig_stat_rows": 0,
            "interpretation": "track_functions none means zero stat rows cannot prove no usage; static governed graph supplies inventory currentness",
            "track_functions": "none"
          }
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_CUTOFF"
    },
    {
      "id": "M14_Q11",
      "sql_literal": "SELECT payload->'historical_provenance_only' provenance,payload->'deduplication' dedup,payload->'excluded_name_candidate' excluded_name FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "provenance": {
            "router_note": "Router binding snapshot observes readiness revision 5.12 while governed current readiness snapshot is 5.13; retained as provenance/currentness drift only.",
            "contract_note": "Older input contract rows remain recorded; caller usage is not inferred from their existence."
          },
          "dedup": {
            "rule": "One logical caller identity per source URI/object identity; evidence from multiple governed sources is merged instead of double-counted.",
            "router_identity": "PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1 maps to live SQL lf_ops.fn_lf_router_input_governance_resolve_v1.",
            "profiles_edge_identity": "EDGE_FN_LF_PROFILES_GOVERNANCE_CALLER_V1 maps to live Edge lf-profiles-governance-caller-v1."
          },
          "excluded_name": {
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
      "scope": "HISTORICAL_SOURCE_CUTOFF"
    },
    {
      "id": "M14_Q12",
      "sql_literal": "SELECT count(*) FILTER(WHERE created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z') asof,count(*) FILTER(WHERE created_at>=TIMESTAMPTZ '2026-10-15T00:00:00Z') post FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "asof": 1,
          "post": 0
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_CUTOFF"
    },
    {
      "id": "M14_Q13",
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
      "scope": "PRINCIPAL_CURRENT_NOT_P0"
    }
  ],
  "algorithm_execution": {
    "D": {
      "conflicts": [
        [
          "SOAK_PROJECTION",
          "QUALIFIED_RECEIPT_CONTEXT"
        ],
        [
          "CP2_AUTHORIZED_READER",
          "CP2_PERMISSION_ERROR"
        ],
        [
          "LEXICAL_CALL_GRAPH",
          "NO_INVOCATION_TRACES"
        ]
      ],
      "minimal_hitting_sets": [
        [
          "SOAK_PROJECTION",
          "CP2_AUTHORIZED_READER",
          "LEXICAL_CALL_GRAPH"
        ],
        [
          "QUALIFIED_RECEIPT_CONTEXT",
          "CP2_AUTHORIZED_READER",
          "LEXICAL_CALL_GRAPH"
        ],
        [
          "SOAK_PROJECTION",
          "CP2_PERMISSION_ERROR",
          "LEXICAL_CALL_GRAPH"
        ],
        [
          "QUALIFIED_RECEIPT_CONTEXT",
          "CP2_PERMISSION_ERROR",
          "LEXICAL_CALL_GRAPH"
        ],
        [
          "SOAK_PROJECTION",
          "CP2_AUTHORIZED_READER",
          "NO_INVOCATION_TRACES"
        ],
        [
          "QUALIFIED_RECEIPT_CONTEXT",
          "CP2_AUTHORIZED_READER",
          "NO_INVOCATION_TRACES"
        ],
        [
          "SOAK_PROJECTION",
          "CP2_PERMISSION_ERROR",
          "NO_INVOCATION_TRACES"
        ],
        [
          "QUALIFIED_RECEIPT_CONTEXT",
          "CP2_PERMISSION_ERROR",
          "NO_INVOCATION_TRACES"
        ]
      ],
      "hitting_total": 27,
      "barinel": "NOT_CALIBRATABLE_NO_SPECTRA",
      "information_gain": "ORDINAL_NEXT_OBSERVATION_ONLY",
      "diagnoses_causal": false
    },
    "C": {
      "three_valued_partitions": {
        "callers": {
          "total": 38,
          "t": 38,
          "f": 0,
          "n": 0,
          "caller_keys": 38
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
          "observed": 39,
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
      "scenarios": [
        {
          "id": "E_ASOF_REAL",
          "inputs": {
            "verified_functional_defect": false,
            "causal_trace": false,
            "source_risk": true,
            "authorized_discriminator": true,
            "missing_data": true,
            "qualified_source": true
          },
          "expected": "VERIFY_FIRST",
          "observed": "VERIFY_FIRST"
        },
        {
          "id": "E_TRUE_DEFECT",
          "inputs": {
            "verified_functional_defect": true,
            "causal_trace": true,
            "source_risk": true,
            "authorized_discriminator": true,
            "missing_data": false,
            "qualified_source": true
          },
          "expected": "REPAIR_REQUIRED",
          "observed": "REPAIR_REQUIRED"
        },
        {
          "id": "E_TLP_NULL",
          "inputs": {
            "verified_functional_defect": false,
            "causal_trace": false,
            "source_risk": false,
            "authorized_discriminator": false,
            "missing_data": true,
            "qualified_source": true
          },
          "expected": "NEEDS_MORE_EVIDENCE",
          "observed": "NEEDS_MORE_EVIDENCE"
        },
        {
          "id": "E_COMPLETE_NOTHING",
          "inputs": {
            "verified_functional_defect": false,
            "causal_trace": false,
            "source_risk": false,
            "authorized_discriminator": false,
            "missing_data": false,
            "qualified_source": true
          },
          "expected": "NO_ACTION_SUPPORTED",
          "observed": "NO_ACTION_SUPPORTED"
        },
        {
          "id": "E_42501_IS_PRIVILEGE",
          "inputs": {
            "verified_functional_defect": false,
            "causal_trace": false,
            "source_risk": true,
            "authorized_discriminator": true,
            "missing_data": true,
            "qualified_source": true
          },
          "expected": "VERIFY_FIRST",
          "observed": "VERIFY_FIRST"
        },
        {
          "id": "E_FAILED_COUNT_NOT_CAUSAL",
          "inputs": {
            "verified_functional_defect": true,
            "causal_trace": false,
            "source_risk": true,
            "authorized_discriminator": true,
            "missing_data": true,
            "qualified_source": true
          },
          "expected": "VERIFY_FIRST",
          "observed": "VERIFY_FIRST"
        },
        {
          "id": "E_NO_AUTHORIZED_SOURCE",
          "inputs": {
            "verified_functional_defect": false,
            "causal_trace": false,
            "source_risk": false,
            "authorized_discriminator": false,
            "missing_data": false,
            "qualified_source": false
          },
          "expected": "NEEDS_MORE_EVIDENCE",
          "observed": "NEEDS_MORE_EVIDENCE"
        }
      ],
      "reversal_criteria": [
        {
          "if": "qualified causal defect",
          "state": "REPAIR_REQUIRED"
        },
        {
          "if": "qualified complete and no risk",
          "state": "NO_ACTION_SUPPORTED"
        },
        {
          "if": "authorized read path unavailable",
          "state": "NEEDS_MORE_EVIDENCE"
        }
      ]
    }
  },
  "negative_tests": [
    {
      "id": "D_GDE_8_MINIMAL",
      "pass": true
    },
    {
      "id": "D_REMOVAL_BREAKS_MINIMALITY",
      "pass": true
    },
    {
      "id": "C_TLP_38_CALLERS",
      "pass": true
    },
    {
      "id": "C_TLP_6_EXTERNAL",
      "pass": true
    },
    {
      "id": "C_TLP_HASH_PARTITION",
      "pass": true
    },
    {
      "id": "C_TLP_NULL_SYNTHTEST",
      "pass": true
    },
    {
      "id": "C_MATCH_ACCEPTS",
      "pass": true
    },
    {
      "id": "C_MISMATCH_REJECTS",
      "pass": true
    },
    {
      "id": "C_NULL_REJECTS",
      "pass": true
    },
    {
      "id": "E_SEVEN_SCENARIOS",
      "pass": true
    },
    {
      "id": "E_ALL_STATES",
      "pass": true
    },
    {
      "id": "E_PERMISSION_IS_NOT_FUNCTIONAL",
      "pass": true
    },
    {
      "id": "E_NULL_UNKNOWN_NOT_CLOSED",
      "pass": true
    },
    {
      "id": "P0_SOAK_PASS_CONTEXT",
      "pass": true
    },
    {
      "id": "P0_CUTOFF_NO_NEW",
      "pass": true
    },
    {
      "id": "NO_USAGE_NOT_INFERRED",
      "pass": true
    },
    {
      "id": "NO_SMT_CLAIM",
      "pass": true
    },
    {
      "id": "NO_BARINEL_CALIBRATION",
      "pass": true
    }
  ],
  "findings": [
    {
      "id": "M14_F1",
      "claim": "Three modeled GDE contradictions yield eight minimum candidate sets but do not establish actual defects",
      "evidence": [
        "M14_Q05",
        "M14_Q08",
        "M14_Q09"
      ],
      "type": "HYPOTHETICAL_DIAGNOSIS"
    },
    {
      "id": "M14_F2",
      "claim": "38 SQL caller and 6 external inventory populations independently reconcile via TLP, not additive",
      "evidence": [
        "M14_Q02",
        "M14_Q03"
      ],
      "type": "MEASURED_ASOF"
    },
    {
      "id": "M14_F3",
      "claim": "Synthetic NULL and wrong-count cases are rejected; neither SMT proof nor business correctness is established",
      "evidence": [
        "M14_Q06",
        "M14_Q07"
      ],
      "type": "EXECUTED_CONTRACT_NEGATIVES"
    },
    {
      "id": "M14_F4",
      "claim": "Typed E decision VERIFY_FIRST relies on source risk, not an observed causal runtime bug",
      "evidence": [
        "M14_Q08",
        "M14_Q09",
        "M14_Q12"
      ],
      "type": "E_TYPOLOGY_EXECUTED"
    }
  ],
  "causal_model": {
    "proven": false,
    "alternatives": [
      "SOAK authority mismatch",
      "CP2 permission vs reader defect",
      "static graph vs invocation absence"
    ]
  },
  "candidate_repairs": [
    {
      "action": "Verify qualified receipt + CP2 read path before any repair",
      "status": "SAFE_READ_ONLY"
    }
  ],
  "chosen_repair": {
    "state": "VERIFY_FIRST",
    "implementation": false,
    "reason": "No validated functional cause; material evidence gap"
  },
  "rejected_alternatives": [
    "Treat NULL as FALSE",
    "Claim applied repair from a typed state",
    "Infer no usage from zero stats",
    "Invent BARINEL/SMT numerical outputs"
  ],
  "omissions_searched": [
    "negative score",
    "read authority",
    "3VL populations",
    "causal trace",
    "historical/current cutoff",
    "source coverage"
  ],
  "unresolved": [
    "No runtime trace",
    "Unknown canonical hash method",
    "No E2E duration cohort"
  ],
  "constraints_preserved": [
    "P0 only",
    "no production",
    "no quality score",
    "no cross-method inputs"
  ],
  "conclusion": "D_C_E_EXECUTED_DIAGNOSIS_METAMORPHIC_TYPED_DECISION_WITH_OPEN_UNKNOWNS"
}
$m14_raw$;v_doc jsonb;
 v_spec jsonb:=$m14_spec${"status":"READY","action_kind":"VERIFY_QUERY_ONCE","recipe_mode":"READBACK_EXACT","requires_material_execution":true,"contract_family":"PE10_METHOD_EXECUTION_EVIDENCE","precision":"PE10_METHOD_V1_MATERIAL_EVIDENCE","assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"checkpoint_identity":"PE10_M14","method_algorithms":"D+C+E","literal_sql_count":13,"gde_minimal_sets":8,"e_scenarios_verified":7,"negative_tests_passed":18,"typed_decision":"VERIFY_FIRST","source_event_id":20161,"git_raw_source_verified":true,"runtime_modified":false}},"evidence_ref":"https://github.com/cristhianlujan/claude-persona-lf-patch/blob/77aebaab956f1f5a59c7780043fdcb1e44150ff5/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M14_RAW_V2.json#git_blob_sha=19265c906d236f0d971c5f50f8f89c9729902459","verification_queries":["SELECT id,created_at,payload->>'source_pack_version' source_pack,payload->'scope_guards' guards FROM public.lf_eventos WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'","SELECT count(*) total,count(*) FILTER(WHERE x->>'operational_class'='ACTIVE') t,count(*) FILTER(WHERE NOT(x->>'operational_class'='ACTIVE')) f,count(*) FILTER(WHERE (x->>'operational_class'='ACTIVE') IS NULL) n,count(DISTINCT x->>'dedupe_key') caller_keys FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161","SELECT count(*) total,count(*) FILTER(WHERE x->>'operational_class'='ACTIVE') t,count(*) FILTER(WHERE NOT(x->>'operational_class'='ACTIVE')) f,count(*) FILTER(WHERE (x->>'operational_class'='ACTIVE') IS NULL) n FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'external_inventory') x WHERE e.id=20161","SELECT count(*) lexical_edges,count(DISTINCT (x->>'caller')||'->'||c.name) unique_edges,count(DISTINCT c.name) destinations FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x CROSS JOIN LATERAL jsonb_array_elements_text(x->'callees') c(name) WHERE e.id=20161","WITH x(flag) AS (VALUES('ACTIVE'::text),('OTHER'::text),(NULL::text)) SELECT count(*) total,count(*) FILTER(WHERE flag='ACTIVE') t,count(*) FILTER(WHERE NOT(flag='ACTIVE')) f,count(*) FILTER(WHERE (flag='ACTIVE') IS NULL) n FROM x","SELECT id,created_at,receipt_kind,subject_ref,payload->>'verification_status' verified,payload->>'screens_total' screens,payload->>'families_total' families,payload->>'known_false_pass_signals' false_pass,payload->>'unresolved_d4' d4 FROM programacion.provenance_receipts WHERE id=38 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'"],"expected":"GDE hypotheses, C 3VL metamorphic negatives and E typed decision; no implemented functional patch","forbidden":["PROMOTE_HISTORICAL_TO_CURRENT","TREAT_TLP_AS_BUSINESS_PROOF","CLAIM_NUMERIC_BARINEL","PATCH_OTHER_CHECKPOINTS","SKIP_CANONICAL_ASSERTION"],"target":{"checkpoint":"PE10_M14","declared_events":[20161],"declared_objects":["public.lf_eventos","programacion.provenance_receipts","transversal.error_knowledge","programacion.engineering_work_checkpoints"],"evidence_artifacts":[{"path":"cristhianlujan/claude-persona-lf-patch:docs/profile_updater/experiments/pe10_methods32_p0/PE10_M14_RAW_V2.json","role":"EVIDENCE","purpose":"M14_D_C_E_EXECUTED_METHOD_RAW","target_kind":"EXACT_EXISTING_FILE"}]}}$m14_spec$::jsonb;
 v_ref text:='https://github.com/cristhianlujan/claude-persona-lf-patch/blob/77aebaab956f1f5a59c7780043fdcb1e44150ff5/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M14_RAW_V2.json#git_blob_sha=19265c906d236f0d971c5f50f8f89c9729902459';v_old text:='chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M14.json#sha256=4809575beee9815347ce3e53da9c8c68f99d6b3ae13aee9915954daf7153c686';v_blob text;
 v_q int;v_gde int;v_e int;v_classes int;v_neg int;v_prev_ok int;v_ekb int;v_n int;
 v_contract jsonb;v_obs jsonb;v_result jsonb;v_assertion jsonb;v_transition jsonb;v_receipt text;
 v_error text;v_context text;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
 AND target_code LIKE '%lf_pe10_m14_dce_governed_close_v1'
 AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'M14_TRAIN_EXECUTION_MISSING'; END IF;
 IF (SELECT status FROM programacion.engineering_work_items WHERE id=1133)<>'IN_PROGRESS'
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>13
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>19
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M14'
 AND status='PENDING' AND evidence_ref=v_old AND assertion_receipt IS NULL AND completed_at IS NULL)<>1
 OR (SELECT count(*) FROM programacion.pe10_method_variants WHERE method_code='PE10_M14' AND base_code='A'
 AND case_ref='PE10-IG-M107-M109-P0' AND algorithm_codes=ARRAY['D','C','E']::text[])<>1
 OR (SELECT count(*) FROM programacion.engineering_plan_units WHERE work_item_id=1133
 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32'
 AND unit_metadata#>>'{action_specs_v1,PE10_M14,status}'='BLOCK_PENDING_MATERIAL_RESEARCH_AND_VALIDATION')<>1
 THEN RAISE EXCEPTION 'M14_PRESTATE_NOT_QUALIFIED'; END IF;
 SELECT count(*) INTO v_prev_ok FROM programacion.engineering_work_checkpoints c
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
('PE10_M11','d0ffbe0d56335daa9a800d0326201686eed5e861745b2fdddcad5dc3b3e56025'),
('PE10_M12','01723c0a370baabe2532358bdac86bbfdbe185ba0514e195547597475d93a383'),
('PE10_M13','c5173d811fcc81c51f832a0073bf8321001f13d3c813780f4ed1faf4883e6b35')) e(code,sha)
 ON e.code=c.checkpoint_code AND e.sha=c.assertion_receipt_sha256
 WHERE c.work_item_id=1133 AND c.status='DONE' AND c.assertion_receipt->>'passed'='true'
 AND c.assertion_contract_sha256=c.assertion_receipt->>'contract_sha256';
 IF v_prev_ok<>13 THEN RAISE EXCEPTION 'M14_PREVIOUS_RECEIPTS_MISMATCH'; END IF;
 v_blob:=encode(extensions.digest(convert_to('blob '||octet_length(convert_to(v_raw,'UTF8'))::text,'UTF8')
 ||decode('00','hex')||convert_to(v_raw,'UTF8'),'sha1'),'hex');
 IF v_blob<>'19265c906d236f0d971c5f50f8f89c9729902459' THEN RAISE EXCEPTION 'M14_GIT_RAW_SHA_WRONG'; END IF;
 v_doc:=v_raw::jsonb;
 IF v_doc->>'schema'<>'PE10_METHOD_RAW_V2' OR v_doc->>'method_code'<>'PE10_M14'
 OR v_doc->>'case_ref'<>'PE10-IG-M107-M109-P0' OR v_doc->>'base_code'<>'A'
 OR v_doc->'algorithm_codes'<>'["D","C","E"]'::jsonb
 OR v_doc->>'source_cutoff'<>'2026-10-15T00:00:00Z'
 OR v_doc#>>'{original_preserved,sha256}'<>'4809575beee9815347ce3e53da9c8c68f99d6b3ae13aee9915954daf7153c686'
 OR v_doc->>'external_evaluation'<>'NOT_PERFORMED'
 OR v_doc#>>'{algorithm_execution,E,actual_state}'<>'VERIFY_FIRST'
 OR v_doc#>>'{chosen_repair,state}'<>'VERIFY_FIRST'
 OR v_doc->>'conclusion'<>'D_C_E_EXECUTED_DIAGNOSIS_METAMORPHIC_TYPED_DECISION_WITH_OPEN_UNKNOWNS'
 THEN RAISE EXCEPTION 'M14_RAW_IDENTITY_OR_SCOPE_INVALID'; END IF;

 SELECT count(*) INTO v_q FROM jsonb_array_elements(v_doc->'sql_evidence') z
 WHERE z->>'id'~'^M14_Q(0[1-9]|1[0-3])$' AND z->>'sql_literal'~* '^(SELECT|WITH) '
 AND z->>'source'='SUPABASE_READ_ONLY' AND jsonb_typeof(z->'rows')='array'
 AND (z->>'rows_returned')::int=jsonb_array_length(z->'rows') AND jsonb_array_length(z->'rows')>0;
 IF v_q<>13 OR jsonb_array_length(v_doc->'sql_evidence')<>13
 OR (SELECT count(DISTINCT z->>'id') FROM jsonb_array_elements(v_doc->'sql_evidence') z)<>13
 OR v_doc#>>'{sql_evidence,1,rows,0,total}'<>'38'
 OR v_doc#>>'{sql_evidence,2,rows,0,total}'<>'6'
 OR v_doc#>>'{sql_evidence,3,rows,0,valid}'<>'38'
 OR v_doc#>>'{sql_evidence,4,rows,0,lexical_edges}'<>'76'
 OR v_doc#>>'{sql_evidence,5,rows,0,n}'<>'1'
 OR v_doc#>>'{sql_evidence,7,rows,0,verified}'<>'VERIFIED'
 OR v_doc#>>'{sql_evidence,11,rows,0,post}'<>'0'
 THEN RAISE EXCEPTION 'M14_SQL_EVIDENCE_INCOMPLETE'; END IF;

 SELECT count(*) INTO v_gde FROM jsonb_array_elements(v_doc#>'{algorithm_execution,D,minimal_hitting_sets}') x
 WHERE jsonb_array_length(x)=3
 AND (x ? 'SOAK_PROJECTION' OR x ? 'QUALIFIED_RECEIPT_CONTEXT')
 AND (x ? 'CP2_AUTHORIZED_READER' OR x ? 'CP2_PERMISSION_ERROR')
 AND (x ? 'LEXICAL_CALL_GRAPH' OR x ? 'NO_INVOCATION_TRACES');
 SELECT count(*) INTO v_e FROM jsonb_array_elements(v_doc#>'{algorithm_execution,E,scenarios}') x
 WHERE x->>'expected'=CASE
 WHEN coalesce((x#>>'{inputs,verified_functional_defect}')::boolean,false)
 AND coalesce((x#>>'{inputs,causal_trace}')::boolean,false) THEN 'REPAIR_REQUIRED'
 WHEN coalesce((x#>>'{inputs,source_risk}')::boolean,false)
 AND coalesce((x#>>'{inputs,authorized_discriminator}')::boolean,false) THEN 'VERIFY_FIRST'
 WHEN coalesce((x#>>'{inputs,missing_data}')::boolean,false)
 OR NOT coalesce((x#>>'{inputs,qualified_source}')::boolean,false) THEN 'NEEDS_MORE_EVIDENCE'
 ELSE 'NO_ACTION_SUPPORTED' END AND x->>'observed'=x->>'expected';
 SELECT count(DISTINCT x->>'observed') INTO v_classes FROM jsonb_array_elements(v_doc#>'{algorithm_execution,E,scenarios}') x;
 SELECT count(*) INTO v_neg FROM jsonb_array_elements(v_doc->'negative_tests') x WHERE x->>'pass'='true';
 IF v_gde<>8 OR jsonb_array_length(v_doc#>'{algorithm_execution,D,minimal_hitting_sets}')<>8
 OR v_e<>7 OR jsonb_array_length(v_doc#>'{algorithm_execution,E,scenarios}')<>7
 OR v_classes<>4 OR v_neg<>18 OR jsonb_array_length(v_doc->'negative_tests')<>18
 OR v_doc#>>'{algorithm_execution,D,barinel}'<>'NOT_CALIBRATABLE_NO_SPECTRA'
 OR v_doc#>>'{algorithm_execution,C,three_valued_partitions,callers,total}'<>'38'
 OR v_doc#>>'{algorithm_execution,C,three_valued_partitions,external,total}'<>'6'
 OR v_doc#>>'{algorithm_execution,C,three_valued_partitions,synthetic,n}'<>'1'
 OR v_doc#>>'{algorithm_execution,C,solver}'<>'NOT_USED_NO_SMT'
 OR jsonb_array_length(v_doc#>'{algorithm_execution,C,contract_cases}')<>3
 THEN RAISE EXCEPTION 'M14_DCE_NEGATIVE_INVARIANTS_FAILED'; END IF;
 SELECT count(*) INTO v_ekb FROM transversal.error_knowledge
 WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001')
 AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z';
 IF v_ekb<>2
 OR (SELECT count(*) FROM public.lf_eventos WHERE id=20161
 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'
 AND jsonb_array_length(payload->'sql_callers')=38 AND jsonb_array_length(payload->'external_inventory')=6)<>1
 OR (SELECT count(*) FROM programacion.provenance_receipts WHERE id=38
 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z' AND payload->>'verification_status'='VERIFIED')<>1
 THEN RAISE EXCEPTION 'M14_FROZEN_AUTHORITIES_CHANGED'; END IF;

 UPDATE programacion.engineering_plan_units SET unit_metadata=jsonb_set(unit_metadata,
 '{action_specs_v1,PE10_M14}',v_spec,true)
 WHERE work_item_id=1133 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32';
 GET DIAGNOSTICS v_n=ROW_COUNT;
 IF v_n<>1 THEN RAISE EXCEPTION 'M14_ACTION_SPEC_NOT_ONE'; END IF;
 v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M14',
 programacion.fn_engineering_checkpoint_action_spec_v3('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M14'));
 IF v_contract->>'status'<>'READY' OR v_contract->>'mode'<>'EXPLICIT_PASS_WHEN_SUBSET'
 THEN RAISE EXCEPTION 'M14_CONTRACT_NOT_READY:%',coalesce(v_contract::text,'NULL'); END IF;
 v_obs:=jsonb_build_object('checkpoint_identity','PE10_M14','method_algorithms','D+C+E',
 'literal_sql_count',13,'gde_minimal_sets',8,'e_scenarios_verified',7,
 'negative_tests_passed',18,'typed_decision','VERIFY_FIRST',
 'source_event_id',20161,'git_raw_source_verified',true,'runtime_modified',false);
 v_result:=jsonb_build_object('status','PASS','observed',v_obs,'evidence_ref',v_ref,
 'validation_kind','M14_DCE_METHOD_MATERIAL_PROOF','domain_fixes','NOT_APPLIED');
 v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M14',v_result,v_exec);
 IF v_assertion->>'passed'<>'true' OR coalesce(v_assertion->>'assertion_receipt_sha256','') !~ '^[a-f0-9]{64}$'
 THEN RAISE EXCEPTION 'M14_ASSERTION_NOT_PASSED'; END IF;
 v_receipt:=v_assertion->>'assertion_receipt_sha256';
 v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M14','DONE',v_ref,v_exec,
 'M14 D+C+E research proof, no production execution or repairs');
 IF v_transition#>>'{transition,status}'<>'APPLIED' THEN RAISE EXCEPTION 'M14_DONE_TRANSITION_FAILED'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133
 AND checkpoint_code='PE10_M14' AND status='DONE' AND completed_at IS NOT NULL
 AND evidence_ref=v_ref AND assertion_receipt_sha256=v_receipt
 AND assertion_receipt->>'passed'='true' AND assertion_contract_sha256=assertion_receipt->>'contract_sha256')<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>14
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>18
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M15' AND status='PENDING')<>1
 THEN RAISE EXCEPTION 'M14_READBACK_FAILED'; END IF;
EXCEPTION WHEN OTHERS THEN
 GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT,v_context=PG_EXCEPTION_CONTEXT;
 RAISE EXCEPTION 'M14_TRAIN_ERROR state=% msg=% context=%',SQLSTATE,left(v_error,300),left(v_context,160) USING ERRCODE=SQLSTATE;
END $m14_close$;
