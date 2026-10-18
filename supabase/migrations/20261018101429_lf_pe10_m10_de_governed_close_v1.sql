-- PE10 M10 D+E: certify method execution only through governed Migration Merge Train.
DO $m10_close$
DECLARE
 v_exec text;v_raw text:=$m10_raw${
  "schema": "PE10_METHOD_RAW_V2",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M10",
  "base_code": "A",
  "algorithm_codes": [
    "D",
    "E"
  ],
  "source_cutoff": "2026-10-15T00:00:00Z",
  "original_preserved": {
    "path": "chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M10.json",
    "sha256": "f7a3a2979c0e8094f3168ac0b5f6d4d8f9902f1664dc5529cc7a88c53789e3d6"
  },
  "producer": "One integrated SRCR researcher running D GDE then E typed decision without peer-method answers",
  "external_evaluation": "NOT_PERFORMED",
  "source_scope": "P0 HISTORICAL READ_ONLY",
  "sql_evidence": [
    {
      "id": "M10_Q01",
      "sql_literal": "SELECT id,created_at,payload->>'source_pack_version' source_pack,payload->>'fetch_spec_version' fetch_spec,payload->'scope_guards' guards FROM public.lf_eventos WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'",
      "rows": [
        {
          "id": 20161,
          "created_at": "2026-10-04 05:14:40.880842+00",
          "source_pack": "SOURCE_PACK_V1",
          "fetch_spec": "SOURCE_PACK_LOOKUP_V2",
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
      "scope": "HISTORICAL_SOURCE_PRE_CUTOFF_RETRIEVED_NOW"
    },
    {
      "id": "M10_Q02",
      "sql_literal": "SELECT count(*) total_callers,count(DISTINCT x->>'dedupe_key') unique_callers,count(*) FILTER(WHERE x->>'currentness_source'='LIVE_PG_PROC') historical_live_label FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161",
      "rows": [
        {
          "total_callers": 38,
          "unique_callers": 38,
          "historical_live_label": 38
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_PRE_CUTOFF_RETRIEVED_NOW"
    },
    {
      "id": "M10_Q03",
      "sql_literal": "SELECT count(*) lexical_edges,count(DISTINCT c.name) distinct_callees,count(*) FILTER(WHERE c.name ILIKE '%cached%') cached_edges FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x CROSS JOIN LATERAL jsonb_array_elements_text(x->'callees') c(name) WHERE e.id=20161",
      "rows": [
        {
          "lexical_edges": 76,
          "distinct_callees": 39,
          "cached_edges": 11
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_PRE_CUTOFF_RETRIEVED_NOW"
    },
    {
      "id": "M10_Q04",
      "sql_literal": "SELECT count(*) assets,count(*) FILTER(WHERE x->>'operational_class'='ACTIVE') active_assets,count(*) FILTER(WHERE x->>'governance_lifecycle'='CANDIDATE_READ_ONLY') readonly_candidates FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'external_inventory') x WHERE e.id=20161",
      "rows": [
        {
          "assets": 6,
          "active_assets": 3,
          "readonly_candidates": 4
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_PRE_CUTOFF_RETRIEVED_NOW"
    },
    {
      "id": "M10_Q05",
      "sql_literal": "SELECT jsonb_array_length(payload->'trigger_bindings') triggers,jsonb_array_length(payload->'edge_current') edge_snapshots,jsonb_array_length(payload->'consumer_relation_snapshot_json_rows') consumer_relation_snapshots,payload->'usage_stats' usage_stats FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "triggers": 21,
          "edge_snapshots": 4,
          "consumer_relation_snapshots": 27,
          "usage_stats": {
            "ig_stat_rows": 0,
            "interpretation": "track_functions none means zero stat rows cannot prove no usage; static governed graph supplies inventory currentness",
            "track_functions": "none"
          }
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_PRE_CUTOFF_RETRIEVED_NOW"
    },
    {
      "id": "M10_Q06",
      "sql_literal": "SELECT id,created_at,receipt_kind,subject_ref,payload->>'verification_status' verified,payload->>'pass' qualified,payload->>'screens_total' screens,payload->>'families_total' families,payload->>'screens_below_2' screens_below,payload->>'families_below_2' families_below,payload->>'known_false_pass_signals' false_pass,payload->>'unresolved_d4' d4 FROM programacion.provenance_receipts WHERE id=38 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'",
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
          "screens_below": "0",
          "families_below": "0",
          "false_pass": "0",
          "d4": "0"
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_PRE_CUTOFF_RETRIEVED_NOW"
    },
    {
      "id": "M10_Q07",
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
      "scope": "HISTORICAL_SOURCE_PRE_CUTOFF_RETRIEVED_NOW"
    },
    {
      "id": "M10_Q08",
      "sql_literal": "SELECT payload->'historical_provenance_only' provenance,payload->'excluded_name_candidate' excluded_candidate,payload->'deduplication' identity_rule FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "provenance": {
            "router_note": "Router binding snapshot observes readiness revision 5.12 while governed current readiness snapshot is 5.13; retained as provenance/currentness drift only.",
            "contract_note": "Older input contract rows remain recorded; caller usage is not inferred from their existence."
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
          "identity_rule": {
            "rule": "One logical caller identity per source URI/object identity; evidence from multiple governed sources is merged instead of double-counted.",
            "router_identity": "PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1 maps to live SQL lf_ops.fn_lf_router_input_governance_resolve_v1.",
            "profiles_edge_identity": "EDGE_FN_LF_PROFILES_GOVERNANCE_CALLER_V1 maps to live Edge lf-profiles-governance-caller-v1."
          }
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_PRE_CUTOFF_RETRIEVED_NOW"
    },
    {
      "id": "M10_Q09",
      "sql_literal": "SELECT count(*) total,count(*) FILTER(WHERE x->>'definition_md5' ~ '^[a-f0-9]{32}$') format_valid,count(*) FILTER(WHERE x->>'definition_md5' IS NULL) absent FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161",
      "rows": [
        {
          "total": 38,
          "format_valid": 38,
          "absent": 0
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_PRE_CUTOFF_RETRIEVED_NOW"
    },
    {
      "id": "M10_Q10",
      "sql_literal": "SELECT count(*) FILTER(WHERE created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z') before_cutoff,count(*) FILTER(WHERE created_at>=TIMESTAMPTZ '2026-10-15T00:00:00Z') after_cutoff FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "before_cutoff": 1,
          "after_cutoff": 0
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_PRE_CUTOFF_RETRIEVED_NOW"
    },
    {
      "id": "M10_Q11",
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
      "scope": "CURRENT_READONLY_PRINCIPAL_NOT_P0"
    }
  ],
  "algorithm_execution": {
    "D": {
      "conflict_sets": [
        [
          "SOAK_TEXT_PROJECTION_DRIFT",
          "M911_SOAK_AUTHORITY_BINDING"
        ],
        [
          "CP2_PERMISSION_GAP",
          "CP2_ASOF_READER_GAP"
        ],
        [
          "CALL_GRAPH_STATIC_ONLY",
          "NO_DYNAMIC_TRACES"
        ]
      ],
      "minimal_hitting_sets": [
        [
          "SOAK_TEXT_PROJECTION_DRIFT",
          "CP2_PERMISSION_GAP",
          "CALL_GRAPH_STATIC_ONLY"
        ],
        [
          "M911_SOAK_AUTHORITY_BINDING",
          "CP2_PERMISSION_GAP",
          "CALL_GRAPH_STATIC_ONLY"
        ],
        [
          "SOAK_TEXT_PROJECTION_DRIFT",
          "CP2_ASOF_READER_GAP",
          "CALL_GRAPH_STATIC_ONLY"
        ],
        [
          "M911_SOAK_AUTHORITY_BINDING",
          "CP2_ASOF_READER_GAP",
          "CALL_GRAPH_STATIC_ONLY"
        ],
        [
          "SOAK_TEXT_PROJECTION_DRIFT",
          "CP2_PERMISSION_GAP",
          "NO_DYNAMIC_TRACES"
        ],
        [
          "M911_SOAK_AUTHORITY_BINDING",
          "CP2_PERMISSION_GAP",
          "NO_DYNAMIC_TRACES"
        ],
        [
          "SOAK_TEXT_PROJECTION_DRIFT",
          "CP2_ASOF_READER_GAP",
          "NO_DYNAMIC_TRACES"
        ],
        [
          "M911_SOAK_AUTHORITY_BINDING",
          "CP2_ASOF_READER_GAP",
          "NO_DYNAMIC_TRACES"
        ]
      ],
      "enumerated_hitting_sets": 27,
      "information_gain_rank": [
        {
          "candidate": "Qualified M9.11 soak receipt vs text projection",
          "rank": 1,
          "source_queries": [
            "M10_Q06",
            "M10_Q07"
          ],
          "purpose": "Distinguish as-of SOAK criterion drift from absent evidence",
          "cost": "READ_ONLY"
        },
        {
          "candidate": "CP2 historical authority vs authorized reader",
          "rank": 2,
          "source_queries": [
            "M10_Q07",
            "M10_Q11"
          ],
          "purpose": "Distinguish permission 42501 from functional failure",
          "cost": "ROLE_CONSTRAINT"
        },
        {
          "candidate": "Actual invoked graph/time versus nominal function references",
          "rank": 3,
          "source_queries": [
            "M10_Q02",
            "M10_Q03",
            "M10_Q05"
          ],
          "purpose": "Require cohort and runtime trace before any performance/coverage repair",
          "cost": "UNKNOWN"
        }
      ],
      "expected_probabilistic_ig": "NOT_COMPUTED_NO_PRIORS",
      "barinel": "NOT_CALIBRATABLE_NO_PROPER_SPECTRA",
      "diagnostic_scope": "MODELED_ASSUMPTIONS_NOT_PROVEN_DEFECTS"
    },
    "E": {
      "decision_rules": [
        "REPAIR_REQUIRED only if demonstrated defect and causal evidence",
        "VERIFY_FIRST if risk and safe falsifier",
        "NEEDS_MORE_EVIDENCE when material uncertainty and no authorized evidence route",
        "NO_ACTION_SUPPORTED when sufficiently qualified and no material risk"
      ],
      "typed_decision": "VERIFY_FIRST",
      "scenarios": [
        {
          "id": "E_ACTUAL",
          "inputs": {
            "demonstrated_defect": false,
            "material_causal_proof": false,
            "observed_risk": true,
            "available_safe_falsifier": true,
            "material_unknown": true,
            "qualified_source": true
          },
          "expected": "VERIFY_FIRST",
          "basis": "historical sources only",
          "observed": "VERIFY_FIRST"
        },
        {
          "id": "E_42501_NOT_CAUSAL_DEFECT",
          "inputs": {
            "demonstrated_defect": false,
            "material_causal_proof": false,
            "observed_risk": true,
            "available_safe_falsifier": true,
            "material_unknown": true,
            "qualified_source": true
          },
          "expected": "VERIFY_FIRST",
          "basis": "negative permission case",
          "observed": "VERIFY_FIRST"
        },
        {
          "id": "E_MISSING_SAFE_READER",
          "inputs": {
            "demonstrated_defect": false,
            "material_causal_proof": false,
            "observed_risk": true,
            "available_safe_falsifier": false,
            "material_unknown": true,
            "qualified_source": false
          },
          "expected": "NEEDS_MORE_EVIDENCE",
          "basis": "synthetic exclusion",
          "observed": "NEEDS_MORE_EVIDENCE"
        },
        {
          "id": "E_CAUSAL_DEFECT_PROVED",
          "inputs": {
            "demonstrated_defect": true,
            "material_causal_proof": true,
            "observed_risk": true,
            "available_safe_falsifier": true,
            "material_unknown": false,
            "qualified_source": true
          },
          "expected": "REPAIR_REQUIRED",
          "basis": "synthetic positive",
          "observed": "REPAIR_REQUIRED"
        },
        {
          "id": "E_NO_RISK_QUALIFIED",
          "inputs": {
            "demonstrated_defect": false,
            "material_causal_proof": false,
            "observed_risk": false,
            "available_safe_falsifier": false,
            "material_unknown": false,
            "qualified_source": true
          },
          "expected": "NO_ACTION_SUPPORTED",
          "basis": "synthetic negative",
          "observed": "NO_ACTION_SUPPORTED"
        },
        {
          "id": "E_FAULT_WITHOUT_CAUSAL_TRACE",
          "inputs": {
            "demonstrated_defect": true,
            "material_causal_proof": false,
            "observed_risk": true,
            "available_safe_falsifier": true,
            "material_unknown": true,
            "qualified_source": true
          },
          "expected": "VERIFY_FIRST",
          "basis": "causal negative",
          "observed": "VERIFY_FIRST"
        },
        {
          "id": "E_INCOMPLETE_CONTEXT",
          "inputs": {
            "demonstrated_defect": false,
            "material_causal_proof": false,
            "observed_risk": false,
            "available_safe_falsifier": false,
            "material_unknown": true,
            "qualified_source": false
          },
          "expected": "NEEDS_MORE_EVIDENCE",
          "basis": "missing observation",
          "observed": "NEEDS_MORE_EVIDENCE"
        }
      ],
      "scope": "HISTORICAL_RISK_TRIAGE_ONLY",
      "reversal_criteria": [
        {
          "trigger": "same-time causal trace of a material functional defect",
          "next": "REPAIR_REQUIRED"
        },
        {
          "trigger": "qualified source resolves remaining risk",
          "next": "NO_ACTION_SUPPORTED"
        },
        {
          "trigger": "no valid authorized falsifier exists",
          "next": "NEEDS_MORE_EVIDENCE"
        }
      ],
      "falsifiers": [
        "Qualified M9.11 soak receipt vs text projection",
        "CP2 historical authority vs authorized reader",
        "Actual invoked graph/time versus nominal function references"
      ]
    }
  },
  "negative_tests": [
    {
      "id": "GDE_8_MINIMAL_SET",
      "pass": true
    },
    {
      "id": "GDE_PROPER_SUBSETS_FAIL",
      "pass": true
    },
    {
      "id": "E_TYPED_SEVEN_SCENARIOS",
      "pass": true
    },
    {
      "id": "E_ALL_FOUR_STATES",
      "pass": true
    },
    {
      "id": "E_42501_NOT_REPAIR_REQUIRED",
      "pass": true
    },
    {
      "id": "E_NO_CLAIM_PERFORMANCE_GAIN",
      "pass": true
    },
    {
      "id": "E_SOAK_PROVENANCE_SCOPE",
      "pass": true
    },
    {
      "id": "E_VALID_MD5_SYNTAX_NOT_DERIVATION",
      "pass": true
    },
    {
      "id": "E_ASOF_CUTOFF",
      "pass": true
    },
    {
      "id": "E_SOURCE_EKB_2",
      "pass": true
    },
    {
      "id": "E_NO_QA_SCORE",
      "pass": true
    },
    {
      "id": "GDE_NO_INVENTED_BARINEL_PRIORS",
      "pass": true
    }
  ],
  "findings": [
    {
      "id": "M10_F01",
      "claim": "EKB-before-P0 documents two risk families, not a proven patch specification. Four evidence alternatives generate 8 minimal hitting sets when combined with invocation uncertainty.",
      "evidence": [
        "M10_Q07",
        "M10_Q03",
        "M10_Q05"
      ],
      "classification": "MODELED_GDE"
    },
    {
      "id": "M10_F02",
      "claim": "M9.11 receipt 38 VERIFIED with zero false PASS/D4 is historical soak proof, not an E2E runtime performance certification.",
      "evidence": [
        "M10_Q06",
        "M10_Q07"
      ],
      "classification": "MEASURED_HISTORICAL"
    },
    {
      "id": "M10_F03",
      "claim": "Historical event contains 38 SQL callers and 76 lexical edges; labels of LIVE_PG_PROC within snapshot cannot guarantee current invocation.",
      "evidence": [
        "M10_Q01",
        "M10_Q02",
        "M10_Q03"
      ],
      "classification": "MEASURED_SOURCE_SCOPE"
    },
    {
      "id": "M10_F04",
      "claim": "The typed method E decision is VERIFY_FIRST and not REPAIR_REQUIRED because no material causal defect evidence was retrieved.",
      "evidence": [
        "M10_Q06",
        "M10_Q07",
        "M10_Q11"
      ],
      "classification": "DECISION_HYPOTHESIS_GOVERNED"
    }
  ],
  "causal_model": {
    "status": "CAUSAL_UNKNOWN",
    "alternatives": [
      "SOAK source projection vs authoritative receipt",
      "CP2 permission vs currentness",
      "Static reference graph vs trace gap"
    ],
    "negative_falsifiers": [
      "Prove current same-cutoff invocation before claiming usage",
      "Demonstrate functional defect before moving decision to REPAIR_REQUIRED",
      "Reject numerical expected entropy/BARINEL with no spectra"
    ]
  },
  "candidate_repairs": [
    {
      "action": "Reuse time-qualified SOAK receipt to evaluate mismatch",
      "scope": "READ_ONLY"
    },
    {
      "action": "Authorized CP2 SELECT versus privilege diagnosis",
      "scope": "READ_ONLY"
    },
    {
      "action": "Version-bound execution tracing if existing nonmutating authority permits",
      "scope": "UNKNOWN"
    }
  ],
  "chosen_repair": {
    "state": "VERIFY_FIRST",
    "reason": "Source-backed risks with safe next observation; repair causality unproven",
    "reversal_criteria": "Defined by method E",
    "runtime_modification": false
  },
  "rejected_alternatives": [
    "Programmatic mutation under P0",
    "Invent posterior defect probabilities",
    "Mark CP2 functional fail based on 42501"
  ],
  "omissions_searched": [
    "SOAK provenance",
    "CP2 permission",
    "function inventory",
    "nominal edges",
    "external assets",
    "historical MD5 syntax",
    "telemetry gap",
    "decision risk and reversal"
  ],
  "unresolved": [
    "Actual time-qualified CP2 runtime state not measured",
    "Hash canonical construction UNKNOWN",
    "Actual performance cohort UNKNOWN",
    "No confirmed actionable defect"
  ],
  "constraints_preserved": [
    "Case P0 cutoff",
    "No product runtime mutation",
    "No prior method outputs supplied",
    "No external oracle",
    "Preserve RAW source"
  ],
  "conclusion": "D_GDE_AND_E_TYPED_DECISION_EXECUTED_VERIFY_FIRST_NOT_APPLIED_REPAIR"
}
$m10_raw$;v_doc jsonb;
 v_spec jsonb:=$m10_spec${"status":"READY","action_kind":"VERIFY_QUERY_ONCE","recipe_mode":"READBACK_EXACT","requires_material_execution":true,"contract_family":"PE10_METHOD_EXECUTION_EVIDENCE","precision":"PE10_METHOD_V1_MATERIAL_EVIDENCE","assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"checkpoint_identity":"PE10_M10","method_algorithms":"D+E","literal_sql_count":11,"gde_minimal_hitting_sets":8,"evidence_decision":"VERIFY_FIRST","evidence_scenarios_verified":7,"negative_tests_passed":12,"historical_source_event_id":20161,"git_source_verified":true,"runtime_modified":false}},"evidence_ref":"https://github.com/cristhianlujan/claude-persona-lf-patch/blob/626603d6b8b172456aa816fb8e6aafce9b812d23/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M10_RAW_V2.json#git_blob_sha=cf8b9a31ac96e16b9f458b777a0a65291410ecfd","verification_queries":["SELECT id,created_at,payload->>'source_pack_version' source_pack,payload->>'fetch_spec_version' fetch_spec,payload->'scope_guards' guards FROM public.lf_eventos WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'","SELECT count(*) total_callers,count(DISTINCT x->>'dedupe_key') unique_callers,count(*) FILTER(WHERE x->>'currentness_source'='LIVE_PG_PROC') historical_live_label FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161","SELECT count(*) lexical_edges,count(DISTINCT c.name) distinct_callees,count(*) FILTER(WHERE c.name ILIKE '%cached%') cached_edges FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x CROSS JOIN LATERAL jsonb_array_elements_text(x->'callees') c(name) WHERE e.id=20161","SELECT jsonb_array_length(payload->'trigger_bindings') triggers,jsonb_array_length(payload->'edge_current') edge_snapshots,jsonb_array_length(payload->'consumer_relation_snapshot_json_rows') consumer_relation_snapshots,payload->'usage_stats' usage_stats FROM public.lf_eventos WHERE id=20161","SELECT id,created_at,receipt_kind,subject_ref,payload->>'verification_status' verified,payload->>'pass' qualified,payload->>'screens_total' screens,payload->>'families_total' families,payload->>'screens_below_2' screens_below,payload->>'families_below_2' families_below,payload->>'known_false_pass_signals' false_pass,payload->>'unresolved_d4' d4 FROM programacion.provenance_receipts WHERE id=38 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'","SELECT codigo,primera_vez,causa_raiz,prevencion,validacion FROM transversal.error_knowledge WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001') AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z' ORDER BY codigo"],"expected":"D GDE hypothesis spectrum plus E governed evidence decision, no BARINEL priors or production repair claim","forbidden":["CLAIM_E_FUTURE_REPAIR_APPLIED","PROMOTE_HISTORICAL_TO_CURRENT","SKIP_GOVERNED_ASSERTION","RETIRE_CACHED_WITHOUT_TRACE","ALTER_OTHER_CHECKPOINTS"],"target":{"checkpoint":"PE10_M10","declared_events":[20161],"declared_objects":["public.lf_eventos","programacion.provenance_receipts","transversal.error_knowledge","programacion.engineering_work_checkpoints"],"evidence_artifacts":[{"path":"cristhianlujan/claude-persona-lf-patch:docs/profile_updater/experiments/pe10_methods32_p0/PE10_M10_RAW_V2.json","role":"EVIDENCE","purpose":"M10_GDE_AND_TYPED_DECISION_METHOD_RAW","target_kind":"EXACT_EXISTING_FILE"}]}}$m10_spec$::jsonb;
 v_ref text:='https://github.com/cristhianlujan/claude-persona-lf-patch/blob/626603d6b8b172456aa816fb8e6aafce9b812d23/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M10_RAW_V2.json#git_blob_sha=cf8b9a31ac96e16b9f458b777a0a65291410ecfd';v_prev text:='chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M10.json#sha256=f7a3a2979c0e8094f3168ac0b5f6d4d8f9902f1664dc5529cc7a88c53789e3d6';v_blob text;
 v_q int;v_gde int;v_e int;v_states int;v_neg int;v_ekb int;v_prev_ok int;v_n int;
 v_contract jsonb;v_obs jsonb;v_result jsonb;v_assertion jsonb;v_transition jsonb;v_receipt text;
 v_error text;v_context text;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
 AND target_code LIKE '%lf_pe10_m10_de_governed_close_v1'
 AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'M10_TRAIN_EXECUTOR_MISSING'; END IF;
 IF (SELECT status FROM programacion.engineering_work_items WHERE id=1133)<>'IN_PROGRESS'
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>9
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>23
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M10'
 AND status='PENDING' AND evidence_ref=v_prev AND assertion_receipt IS NULL AND completed_at IS NULL)<>1
 OR (SELECT count(*) FROM programacion.pe10_method_variants WHERE method_code='PE10_M10'
 AND base_code='A' AND case_ref='PE10-IG-M107-M109-P0'
 AND algorithm_codes=ARRAY['D','E']::text[])<>1
 OR (SELECT count(*) FROM programacion.engineering_plan_units WHERE work_item_id=1133
 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32' AND disposition='ASSIGNED'
 AND unit_metadata->>'checkpoint_ordering'='INDEPENDENT_METHOD_VARIANTS'
 AND unit_metadata#>>'{action_specs_v1,PE10_M10,status}'='BLOCK_PENDING_MATERIAL_RESEARCH_AND_VALIDATION')<>1
 THEN RAISE EXCEPTION 'M10_PRESTATE_OR_METHOD_CONTRACT_DRIFT'; END IF;
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
 ('PE10_M09','f939334bc3c1d5be819c59309fc375a14fd7360fd4b8705ff6f749bdc0f805df')
 ) e(code,sha) ON e.code=c.checkpoint_code AND e.sha=c.assertion_receipt_sha256
 WHERE c.work_item_id=1133 AND c.status='DONE' AND c.assertion_receipt->>'passed'='true'
 AND c.assertion_contract_sha256=c.assertion_receipt->>'contract_sha256';
 IF v_prev_ok<>9 THEN RAISE EXCEPTION 'M10_PRIOR_RECEIPTS_MISMATCH'; END IF;
 v_blob:=encode(extensions.digest(convert_to('blob '||octet_length(convert_to(v_raw,'UTF8'))::text,'UTF8')
 ||decode('00','hex')||convert_to(v_raw,'UTF8'),'sha1'),'hex');
 IF v_blob<>'cf8b9a31ac96e16b9f458b777a0a65291410ecfd' THEN RAISE EXCEPTION 'M10_IMMUTABLE_GIT_BLOB_INVALID'; END IF;
 v_doc:=v_raw::jsonb;
 IF v_doc->>'schema'<>'PE10_METHOD_RAW_V2'
 OR v_doc->>'method_code'<>'PE10_M10'
 OR v_doc->>'case_ref'<>'PE10-IG-M107-M109-P0'
 OR v_doc->>'base_code'<>'A'
 OR v_doc->'algorithm_codes'<>'["D","E"]'::jsonb
 OR v_doc->>'source_cutoff'<>'2026-10-15T00:00:00Z'
 OR v_doc#>>'{original_preserved,sha256}'<>'f7a3a2979c0e8094f3168ac0b5f6d4d8f9902f1664dc5529cc7a88c53789e3d6'
 OR v_doc->>'external_evaluation'<>'NOT_PERFORMED'
 OR v_doc#>>'{algorithm_execution,E,typed_decision}'<>'VERIFY_FIRST'
 OR v_doc#>>'{chosen_repair,state}'<>'VERIFY_FIRST'
 OR v_doc->>'conclusion'<>'D_GDE_AND_E_TYPED_DECISION_EXECUTED_VERIFY_FIRST_NOT_APPLIED_REPAIR'
 THEN RAISE EXCEPTION 'M10_RAW_IDENTITY_SCOPE_FAILED'; END IF;

 SELECT count(*) INTO v_q FROM jsonb_array_elements(v_doc->'sql_evidence') z
 WHERE z->>'id'~'^M10_Q(0[1-9]|1[01])$'
 AND z->>'sql_literal'~* '^SELECT '
 AND z->>'source'='SUPABASE_READ_ONLY'
 AND jsonb_typeof(z->'rows')='array'
 AND (z->>'rows_returned')::integer=jsonb_array_length(z->'rows')
 AND jsonb_array_length(z->'rows')>0;
 IF v_q<>11 OR jsonb_array_length(v_doc->'sql_evidence')<>11
 OR (SELECT count(DISTINCT z->>'id') FROM jsonb_array_elements(v_doc->'sql_evidence') z)<>11
 OR v_doc#>>'{sql_evidence,1,rows,0,total_callers}'<>'38'
 OR v_doc#>>'{sql_evidence,2,rows,0,lexical_edges}'<>'76'
 OR v_doc#>>'{sql_evidence,4,rows,0,usage_stats,track_functions}'<>'none'
 OR v_doc#>>'{sql_evidence,5,rows,0,verified}'<>'VERIFIED'
 OR v_doc#>>'{sql_evidence,9,rows,0,after_cutoff}'<>'0'
 OR v_doc#>>'{sql_evidence,10,rows,0,read_only}'<>'on'
 THEN RAISE EXCEPTION 'M10_SOURCE_QUERY_MATERIAL_PROOF_INCOMPLETE'; END IF;

 SELECT count(*) INTO v_gde FROM jsonb_array_elements(v_doc#>'{algorithm_execution,D,minimal_hitting_sets}') x
 WHERE jsonb_array_length(x)=3
 AND (x ? 'SOAK_TEXT_PROJECTION_DRIFT' OR x ? 'M911_SOAK_AUTHORITY_BINDING')
 AND (x ? 'CP2_PERMISSION_GAP' OR x ? 'CP2_ASOF_READER_GAP')
 AND (x ? 'CALL_GRAPH_STATIC_ONLY' OR x ? 'NO_DYNAMIC_TRACES');
 SELECT count(*) INTO v_e FROM jsonb_array_elements(v_doc#>'{algorithm_execution,E,scenarios}') s
 WHERE s->>'expected'=CASE
 WHEN coalesce((s#>>'{inputs,demonstrated_defect}')::boolean,false)
 AND coalesce((s#>>'{inputs,material_causal_proof}')::boolean,false) THEN 'REPAIR_REQUIRED'
 WHEN coalesce((s#>>'{inputs,observed_risk}')::boolean,false)
 AND coalesce((s#>>'{inputs,available_safe_falsifier}')::boolean,false) THEN 'VERIFY_FIRST'
 WHEN coalesce((s#>>'{inputs,material_unknown}')::boolean,false)
 OR NOT coalesce((s#>>'{inputs,qualified_source}')::boolean,false) THEN 'NEEDS_MORE_EVIDENCE'
 ELSE 'NO_ACTION_SUPPORTED' END
 AND s->>'observed'=s->>'expected';
 SELECT count(DISTINCT s->>'observed') INTO v_states FROM jsonb_array_elements(v_doc#>'{algorithm_execution,E,scenarios}') s;
 SELECT count(*) INTO v_neg FROM jsonb_array_elements(v_doc->'negative_tests') t WHERE t->>'pass'='true';
 IF v_gde<>8 OR jsonb_array_length(v_doc#>'{algorithm_execution,D,minimal_hitting_sets}')<>8
 OR v_e<>7 OR jsonb_array_length(v_doc#>'{algorithm_execution,E,scenarios}')<>7
 OR v_states<>4 OR v_neg<>12 OR jsonb_array_length(v_doc->'negative_tests')<>12
 OR v_doc#>>'{algorithm_execution,D,barinel}'<>'NOT_CALIBRATABLE_NO_PROPER_SPECTRA'
 OR v_doc#>>'{algorithm_execution,D,expected_probabilistic_ig}'<>'NOT_COMPUTED_NO_PRIORS'
 OR jsonb_array_length(v_doc#>'{algorithm_execution,E,reversal_criteria}')<>3
 THEN RAISE EXCEPTION 'M10_GDE_E_METHOD_TESTS_INVALID'; END IF;

 SELECT count(*) INTO v_ekb FROM transversal.error_knowledge WHERE codigo IN(
 'IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001')
 AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z';
 IF v_ekb<>2
 OR (SELECT count(*) FROM public.lf_eventos WHERE id=20161
 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'
 AND jsonb_array_length(payload->'sql_callers')=38
 AND payload->'usage_stats'->>'track_functions'='none')<>1
 OR (SELECT count(*) FROM programacion.provenance_receipts WHERE id=38
 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'
 AND payload->>'verification_status'='VERIFIED'
 AND payload->>'known_false_pass_signals'='0' AND payload->>'unresolved_d4'='0')<>1
 THEN RAISE EXCEPTION 'M10_HISTORICAL_SOURCE_READBACK_DRIFT'; END IF;
 UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10_M10}',v_spec,true)
 WHERE work_item_id=1133 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32';
 GET DIAGNOSTICS v_n=ROW_COUNT;
 IF v_n<>1 THEN RAISE EXCEPTION 'M10_ACTION_SPEC_UPDATE_NOT_ONE'; END IF;
 v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M10',
 programacion.fn_engineering_checkpoint_action_spec_v3('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M10'));
 IF v_contract->>'status'<>'READY' OR v_contract->>'mode'<>'EXPLICIT_PASS_WHEN_SUBSET'
 THEN RAISE EXCEPTION 'M10_CANONICAL_ASSERTION_CONTRACT_NOT_READY:%',coalesce(v_contract::text,'NULL'); END IF;
 v_obs:=jsonb_build_object('checkpoint_identity','PE10_M10','method_algorithms','D+E',
 'literal_sql_count',11,'gde_minimal_hitting_sets',8,'evidence_decision','VERIFY_FIRST',
 'evidence_scenarios_verified',v_e,'negative_tests_passed',v_neg,
 'historical_source_event_id',20161,'git_source_verified',true,'runtime_modified',false);
 v_result:=jsonb_build_object('status','PASS','observed',v_obs,'evidence_ref',v_ref,
 'validation_kind','M10_GDE_E_MATERIAL_METHOD_EXECUTION_NOT_APPLIED_REPAIR',
 'external_method_score','NOT_PERFORMED');
 v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M10',v_result,v_exec);
 IF v_assertion->>'passed'<>'true'
 OR coalesce(v_assertion->>'assertion_receipt_sha256','') !~ '^[a-f0-9]{64}$'
 THEN RAISE EXCEPTION 'M10_CANONICAL_RECEIPT_NOT_PASSED'; END IF;
 v_receipt:=v_assertion->>'assertion_receipt_sha256';
 v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M10','DONE',v_ref,v_exec,
 'M10 GDE+D and E typed decision attested; outcome VERIFY_FIRST, no production repair');
 IF v_transition#>>'{transition,status}'<>'APPLIED'
 THEN RAISE EXCEPTION 'M10_CANONICAL_TRANSITION_NOT_APPLIED'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M10'
 AND status='DONE' AND completed_at IS NOT NULL AND assertion_receipt_sha256=v_receipt
 AND assertion_contract_sha256=assertion_receipt->>'contract_sha256'
 AND assertion_receipt->>'passed'='true' AND evidence_ref=v_ref)<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>10
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>22
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M11' AND status='PENDING')<>1
 THEN RAISE EXCEPTION 'M10_FINAL_TRAIN_READBACK_FAILED'; END IF;
EXCEPTION WHEN OTHERS THEN
 GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT,v_context=PG_EXCEPTION_CONTEXT;
 RAISE EXCEPTION 'M10_TRAIN_ROOT_CAUSE state=% msg=% context=%',SQLSTATE,left(v_error,290),left(v_context,145) USING ERRCODE=SQLSTATE;
END $m10_close$;
