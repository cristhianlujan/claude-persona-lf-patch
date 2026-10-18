-- PE10 M09: governed verification of method E decision; does not implement or approve LF repair.
-- Sole authority is Merge Train ACTUALIZACION_DB_LF; single checkpoint status change.
DO $m09_close$
DECLARE
 v_exec text;
 v_raw text:=$m09_raw${
  "schema": "PE10_METHOD_RAW_V2",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M09",
  "base_code": "A",
  "algorithm_codes": [
    "E"
  ],
  "contract": "PE10_METHOD_V1",
  "source_cutoff_utc": "2026-10-15T00:00:00Z",
  "original_preserved": {
    "ref": "chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M09.json",
    "sha256": "49b6c91b84756fe18bf79374275d51be3b33dd5879969898b60e8a3a4e71865a"
  },
  "producer": "One integrated SRCR+E method run; no separate agent or independent comparative scoring represented",
  "mode": "P0_HISTORICAL_READ_ONLY_DECISION_TYPE_NOT_RUNTIME_REPAIR",
  "external_evaluation": "NOT_PERFORMED",
  "sql_evidence": [
    {
      "id": "M09_Q01",
      "sql_literal": "SELECT id,created_at,payload->>'source_pack_version' source_pack,payload->>'fetch_spec_version' fetch_spec,payload->'historical_provenance_only' provenance FROM public.lf_eventos WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'",
      "rows": [
        {
          "id": 20161,
          "created_at": "2026-10-04 05:14:40.880842+00",
          "source_pack": "SOURCE_PACK_V1",
          "fetch_spec": "SOURCE_PACK_LOOKUP_V2",
          "provenance": {
            "router_note": "Router binding snapshot observes readiness revision 5.12 while governed current readiness snapshot is 5.13; retained as provenance/currentness drift only.",
            "contract_note": "Older input contract rows remain recorded; caller usage is not inferred from their existence."
          }
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "readback_scope": "HISTORICAL_P0_SOURCE_READ_IN_PRESENT",
      "time_basis": "The rows predate P0 cutoff; query execution is current and cannot attest P0 runtime"
    },
    {
      "id": "M09_Q02",
      "sql_literal": "SELECT count(*) total_callers,count(DISTINCT x->>'dedupe_key') unique_caller_keys,count(*) FILTER(WHERE x->>'definition_md5'~'^[a-f0-9]{32}$') hash_syntax_valid,count(*) FILTER(WHERE x->>'currentness_source'='LIVE_PG_PROC') labeled_historical_live FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161",
      "rows": [
        {
          "total_callers": 38,
          "unique_caller_keys": 38,
          "hash_syntax_valid": 38,
          "labeled_historical_live": 38
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "readback_scope": "HISTORICAL_P0_SOURCE_READ_IN_PRESENT",
      "time_basis": "The rows predate P0 cutoff; query execution is current and cannot attest P0 runtime"
    },
    {
      "id": "M09_Q03",
      "sql_literal": "SELECT count(*) reference_edges,count(DISTINCT (x->>'caller')||'->'||c.name) distinct_edges,count(DISTINCT c.name) destination_labels FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x CROSS JOIN LATERAL jsonb_array_elements_text(x->'callees') c(name) WHERE e.id=20161",
      "rows": [
        {
          "reference_edges": 76,
          "distinct_edges": 76,
          "destination_labels": 39
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "readback_scope": "HISTORICAL_P0_SOURCE_READ_IN_PRESENT",
      "time_basis": "The rows predate P0 cutoff; query execution is current and cannot attest P0 runtime"
    },
    {
      "id": "M09_Q04",
      "sql_literal": "SELECT jsonb_array_length(payload->'trigger_bindings') trigger_bindings,jsonb_array_length(payload->'edge_current') edge_snapshot_entries,jsonb_array_length(payload->'external_inventory') external_assets,jsonb_array_length(payload->'consumer_relation_snapshot_json_rows') relation_snapshots,payload->'usage_stats' usage_stats FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "trigger_bindings": 21,
          "edge_snapshot_entries": 4,
          "external_assets": 6,
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
      "readback_scope": "HISTORICAL_P0_SOURCE_READ_IN_PRESENT",
      "time_basis": "The rows predate P0 cutoff; query execution is current and cannot attest P0 runtime"
    },
    {
      "id": "M09_Q05",
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
      "readback_scope": "HISTORICAL_P0_SOURCE_READ_IN_PRESENT",
      "time_basis": "The rows predate P0 cutoff; query execution is current and cannot attest P0 runtime"
    },
    {
      "id": "M09_Q06",
      "sql_literal": "SELECT id,created_at,receipt_kind,subject_ref,payload->>'verification_status' verification_status,payload->>'pass' pass,payload->>'screens_total' screens,payload->>'families_total' families,payload->>'screens_below_2' screens_below,payload->>'families_below_2' families_below,payload->>'known_false_pass_signals' false_pass,payload->>'unresolved_d4' unresolved_d4 FROM programacion.provenance_receipts WHERE id=38 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'",
      "rows": [
        {
          "id": 38,
          "created_at": "2026-10-07 16:01:00.760627+00",
          "receipt_kind": "EVIDENCE_VERIFICATION",
          "subject_ref": "plan://IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.11/SOAK_OBSERVATION_HISTORY_V2",
          "verification_status": "VERIFIED",
          "pass": "true",
          "screens": "13",
          "families": "47",
          "screens_below": "0",
          "families_below": "0",
          "false_pass": "0",
          "unresolved_d4": "0"
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "readback_scope": "HISTORICAL_P0_SOURCE_READ_IN_PRESENT",
      "time_basis": "The rows predate P0 cutoff; query execution is current and cannot attest P0 runtime"
    },
    {
      "id": "M09_Q07",
      "sql_literal": "SELECT codigo,primera_vez,causa_raiz,prevencion,validacion FROM transversal.error_knowledge WHERE codigo IN ('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001') AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z' ORDER BY codigo",
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
      "readback_scope": "HISTORICAL_P0_SOURCE_READ_IN_PRESENT",
      "time_basis": "The rows predate P0 cutoff; query execution is current and cannot attest P0 runtime"
    },
    {
      "id": "M09_Q08",
      "sql_literal": "SELECT payload->'scope_guards' scope_guards,payload->'deduplication' deduplication,payload->'excluded_name_candidate' excluded_name_candidate,payload->'ambiguous_name_candidates_checked' ambiguous_checked FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "scope_guards": {
            "callers_retired": false,
            "m10_10_executed": false,
            "callers_modified": false,
            "production_change": false,
            "runtime_activation": false,
            "n13_n14_n15_changed": false
          },
          "deduplication": {
            "rule": "One logical caller identity per source URI/object identity; evidence from multiple governed sources is merged instead of double-counted.",
            "router_identity": "PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1 maps to live SQL lf_ops.fn_lf_router_input_governance_resolve_v1.",
            "profiles_edge_identity": "EDGE_FN_LF_PROFILES_GOVERNANCE_CALLER_V1 maps to live Edge lf-profiles-governance-caller-v1."
          },
          "excluded_name_candidate": {
            "object": "lf-profile-creator-governance-caller-v1",
            "reason": "Current caller.ts invokes configured LF_PROFILE_CREATOR_RUNTIME_SLUG/default run-creacion-perfil-lf and contains no IG call; name/existence is not usage evidence.",
            "sha256": "27594e559e752587c5644463efc67fb9be245319b856766d85435431325cf6ee",
            "version": 16,
            "edge_marker": "ACTIVE",
            "classification": "NOT_IG_CALLER",
            "verified_target": "run-creacion-perfil-lf"
          },
          "ambiguous_checked": 1
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "readback_scope": "HISTORICAL_P0_SOURCE_READ_IN_PRESENT",
      "time_basis": "The rows predate P0 cutoff; query execution is current and cannot attest P0 runtime"
    },
    {
      "id": "M09_Q09",
      "sql_literal": "SELECT jsonb_array_length(payload->'router_binding_snapshot_json_rows') router_snapshots,jsonb_array_length(payload->'contract_snapshot_json_rows') contract_snapshots,jsonb_array_length(payload->'test_suite_snapshot_json_rows') test_suite_snapshots FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "router_snapshots": 4,
          "contract_snapshots": 19,
          "test_suite_snapshots": 1
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "readback_scope": "HISTORICAL_P0_SOURCE_READ_IN_PRESENT",
      "time_basis": "The rows predate P0 cutoff; query execution is current and cannot attest P0 runtime"
    },
    {
      "id": "M09_Q10",
      "sql_literal": "SELECT count(*) FILTER(WHERE created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z') pre_cutoff,count(*) FILTER(WHERE created_at>=TIMESTAMPTZ '2026-10-15T00:00:00Z') post_cutoff FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "pre_cutoff": 1,
          "post_cutoff": 0
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "readback_scope": "HISTORICAL_P0_SOURCE_READ_IN_PRESENT",
      "time_basis": "The rows predate P0 cutoff; query execution is current and cannot attest P0 runtime"
    },
    {
      "id": "M09_Q11",
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
      "readback_scope": "PRESENT_SQL_PRINCIPAL_NOT_P0",
      "time_basis": "The rows predate P0 cutoff; query execution is current and cannot attest P0 runtime"
    }
  ],
  "algorithm_execution": {
    "E": {
      "rules": {
        "state_type": "PE10_E_DECISION_V1",
        "source": "module E DRAFT canonical states; evidence-based diagnostic only",
        "rules": [
          {
            "state": "REPAIR_REQUIRED",
            "when": "specific material defect proved with trace or counterexample and attributable failure; not inferred from access error alone",
            "follow_up": "repair candidate under separate governed authorization and test negative+positive"
          },
          {
            "state": "VERIFY_FIRST",
            "when": "source-backed risk with safe discriminating check remains and repair causality not established",
            "follow_up": "authorized select/readback qualified to same time and cohort"
          },
          {
            "state": "NEEDS_MORE_EVIDENCE",
            "when": "required source unavailable or ambiguous and no discriminating authorized verification path identified",
            "follow_up": "obtain eligible observations rather than fabricate verdict"
          },
          {
            "state": "NO_ACTION_SUPPORTED",
            "when": "sufficient qualified scope has no demonstrated risk or open uncertainty materially affecting action",
            "follow_up": "record negative finding without unjustified patch"
          }
        ]
      },
      "implementation": "Executed pure decision classifier against seven scenarios; diagnostic verdict independent of admin checkpoint DONE.",
      "actual_state": "VERIFY_FIRST",
      "actual_inputs": {
        "proven_defect": false,
        "causal_trace": false,
        "source_risk": true,
        "authorized_falsifier": true,
        "source_qualified": true,
        "material_unknown": true
      },
      "decision_scenarios": [
        {
          "id": "E09_ACTUAL_SOURCE_RISK",
          "inputs": {
            "proven_defect": false,
            "causal_trace": false,
            "source_risk": true,
            "authorized_falsifier": true,
            "source_qualified": true,
            "material_unknown": true
          },
          "expected": "VERIFY_FIRST",
          "type": "ACTUAL_P0_DECISION",
          "observed": "VERIFY_FIRST"
        },
        {
          "id": "E09_42501_IS_NOT_FUNCTIONAL_DEFECT",
          "inputs": {
            "proven_defect": false,
            "causal_trace": false,
            "source_risk": true,
            "authorized_falsifier": true,
            "source_qualified": true,
            "material_unknown": true
          },
          "expected": "VERIFY_FIRST",
          "type": "NEGATIVE_CHECK",
          "observed": "VERIFY_FIRST"
        },
        {
          "id": "E09_NO_QUALIFIED_READ_PATH",
          "inputs": {
            "proven_defect": false,
            "causal_trace": false,
            "source_risk": true,
            "authorized_falsifier": false,
            "source_qualified": false,
            "material_unknown": true
          },
          "expected": "NEEDS_MORE_EVIDENCE",
          "type": "SYNTHETIC_NEGATIVE",
          "observed": "NEEDS_MORE_EVIDENCE"
        },
        {
          "id": "E09_PROVEN_CAUSAL_DEFECT",
          "inputs": {
            "proven_defect": true,
            "causal_trace": true,
            "source_risk": true,
            "authorized_falsifier": true,
            "source_qualified": true,
            "material_unknown": false
          },
          "expected": "REPAIR_REQUIRED",
          "type": "SYNTHETIC_POSITIVE",
          "observed": "REPAIR_REQUIRED"
        },
        {
          "id": "E09_NO_DEMONSTRATED_RISK_FULL_SCOPE",
          "inputs": {
            "proven_defect": false,
            "causal_trace": false,
            "source_risk": false,
            "authorized_falsifier": false,
            "source_qualified": true,
            "material_unknown": false
          },
          "expected": "NO_ACTION_SUPPORTED",
          "type": "SYNTHETIC_NEGATIVE",
          "observed": "NO_ACTION_SUPPORTED"
        },
        {
          "id": "E09_RISK_NO_CAUSAL_TRACE",
          "inputs": {
            "proven_defect": true,
            "causal_trace": false,
            "source_risk": true,
            "authorized_falsifier": true,
            "source_qualified": true,
            "material_unknown": true
          },
          "expected": "VERIFY_FIRST",
          "type": "SYNTHETIC_NEGATIVE",
          "observed": "VERIFY_FIRST"
        },
        {
          "id": "E09_MISSING_SOURCE_NOR_RISK",
          "inputs": {
            "proven_defect": false,
            "causal_trace": false,
            "source_risk": false,
            "authorized_falsifier": false,
            "source_qualified": false,
            "material_unknown": true
          },
          "expected": "NEEDS_MORE_EVIDENCE",
          "type": "SYNTHETIC_NEGATIVE",
          "observed": "NEEDS_MORE_EVIDENCE"
        }
      ],
      "positive_negative_tests": [
        {
          "id": "E09_ACTUAL_SOURCE_RISK",
          "pass": true,
          "expected": "VERIFY_FIRST",
          "observed": "VERIFY_FIRST"
        },
        {
          "id": "E09_42501_IS_NOT_FUNCTIONAL_DEFECT",
          "pass": true,
          "expected": "VERIFY_FIRST",
          "observed": "VERIFY_FIRST"
        },
        {
          "id": "E09_NO_QUALIFIED_READ_PATH",
          "pass": true,
          "expected": "NEEDS_MORE_EVIDENCE",
          "observed": "NEEDS_MORE_EVIDENCE"
        },
        {
          "id": "E09_PROVEN_CAUSAL_DEFECT",
          "pass": true,
          "expected": "REPAIR_REQUIRED",
          "observed": "REPAIR_REQUIRED"
        },
        {
          "id": "E09_NO_DEMONSTRATED_RISK_FULL_SCOPE",
          "pass": true,
          "expected": "NO_ACTION_SUPPORTED",
          "observed": "NO_ACTION_SUPPORTED"
        },
        {
          "id": "E09_RISK_NO_CAUSAL_TRACE",
          "pass": true,
          "expected": "VERIFY_FIRST",
          "observed": "VERIFY_FIRST"
        },
        {
          "id": "E09_MISSING_SOURCE_NOR_RISK",
          "pass": true,
          "expected": "NEEDS_MORE_EVIDENCE",
          "observed": "NEEDS_MORE_EVIDENCE"
        },
        {
          "id": "E09_RECENT_USAGE_STATS_NOT_INFERRED",
          "pass": true,
          "evidence": "M09_Q04"
        },
        {
          "id": "E09_HISTORICAL_CUTOFF",
          "pass": true,
          "evidence": "M09_Q10"
        },
        {
          "id": "E09_SOAK_NOT_E2E_METRICS",
          "pass": true,
          "evidence": "M09_Q06"
        }
      ],
      "risks": [
        {
          "id": "RISK_ASOF",
          "description": "Historical caller snapshot may be misrepresented as live",
          "evidence": [
            "M09_Q01",
            "M09_Q02",
            "M09_Q03"
          ]
        },
        {
          "id": "RISK_SOAK",
          "description": "Confusing qualified historical SOAK acceptance with current E2E performance",
          "evidence": [
            "M09_Q06",
            "M09_Q07"
          ]
        },
        {
          "id": "RISK_AUTHORITY",
          "description": "Mistaking documented CP2 privilege limitation for a functional failure",
          "evidence": [
            "M09_Q07",
            "M09_Q11"
          ]
        }
      ],
      "reversal_criteria": [
        {
          "trigger": "Same-cutoff qualified authorized live trace proves function-level defect and causal association",
          "next_state": "REPAIR_REQUIRED"
        },
        {
          "trigger": "Qualified same-cutoff source and tests eliminate all material risk",
          "next_state": "NO_ACTION_SUPPORTED"
        },
        {
          "trigger": "Discriminating read path unavailable with material uncertainty",
          "next_state": "NEEDS_MORE_EVIDENCE"
        }
      ],
      "falsifiers": [
        "P0-time qualified call graph and actual invocation traces",
        "Authorized equivalent CP2 SELECT context",
        "Actual representative E2E stage timestamps and cohort denominators"
      ]
    }
  },
  "findings": [
    {
      "id": "M09-F1",
      "claim": "Event 20161 has 38 named historical caller identities with nominal edges; neither proves current invocations or production need for change",
      "source": [
        "M09_Q01",
        "M09_Q02",
        "M09_Q03"
      ],
      "confidence": "MEASURED_ASOF_ONLY"
    },
    {
      "id": "M09-F2",
      "claim": "M9.11 receipt 38 is historically VERIFIED (13 screens/47 families, 0 false PASS and D4); does not certify CP2 currentness or E2E timing",
      "source": [
        "M09_Q06",
        "M09_Q07"
      ],
      "confidence": "MEASURED_ASOF_ONLY"
    },
    {
      "id": "M09-F3",
      "claim": "Two EKB entries pre-cutoff explain soak-criterion drift and CP2 read permission risk; neither proves a runnable repair in the P0 restricted scope",
      "source": [
        "M09_Q07"
      ],
      "confidence": "MEASURED_HISTORICAL"
    },
    {
      "id": "M09-F4",
      "claim": "track_functions none cannot establish zero usage or latency improvement; recommendation is VERIFY_FIRST with material unknowns",
      "source": [
        "M09_Q04",
        "M09_Q10"
      ],
      "confidence": "OBSERVED_LIMIT_AND_DECISION"
    }
  ],
  "causal_model": {
    "causal_defect_proven": false,
    "hypotheses": [
      "Version-as-of mismatch",
      "Reader-authority mismatch",
      "Historical SOAK evidence replaced by latest-only projection"
    ],
    "limitations": [
      "No current qualified invocation trace",
      "No performance cohort and denominator",
      "No valid functional CP2 execute privilege from readonly actor"
    ]
  },
  "candidate_repairs": [
    {
      "action": "Obtain time-pinned authorized readbacks and compare caller/evidence identity without altering permissions",
      "status": "FIRST_SAFE_VERIFICATION"
    },
    {
      "action": "Fetch valid previous SOAK history receipt for current checkpoint contract without reruns",
      "status": "PROPOSED"
    }
  ],
  "chosen_repair": {
    "type": "VERIFY_FIRST",
    "scope": "HISTORICAL_RISK_TRIAGE_NOT_LIVE_PATCH",
    "reason": "Source risks and safe read-only falsifiers exist; no proved runtime defect or quantified benefit",
    "verification_route": "Authorized SELECT readbacks with same temporal basis, no RLS or runtime modification"
  },
  "rejected_alternatives": [
    "Patch production on historic risk alone",
    "Change read-only permissions to obtain CP2 PASS",
    "Claim NO_ACTION_SUPPORTED because stats absent",
    "Claim REPAIR_REQUIRED merely due 42501"
  ],
  "omissions_searched": [
    "E states alternatives and reversals",
    "authority of M9.11 vs CP2",
    "complete typed risks and falsifiers",
    "historical provenance",
    "zero-telemetry fallacy",
    "nominal graph vs invoked runtime",
    "source identity and temporal cutoff"
  ],
  "unresolved": [
    "Exact current execution graph not in P0",
    "Historical inventory hash canonical derivation not proven",
    "Qualified benchmark end-to-end latency unavailable",
    "No proven material defect eligible for repair"
  ],
  "constraints_preserved": [
    "P0 historical cutoff",
    "No product/runtime mutation",
    "No cross-method comparison",
    "Original RAW unchanged",
    "No ad hoc EXECUTE elevation"
  ],
  "research_conclusion": "E_TYPED_DECISION_EXECUTED_VERIFY_FIRST_WITH_UNRESOLVED_MATERIAL_EVIDENCE",
  "admin_checkpoint_status_at_start": "PENDING"
}
$m09_raw$;
 v_doc jsonb;v_blob text;v_ref text:='https://github.com/cristhianlujan/claude-persona-lf-patch/blob/bba9a86bbfd9f4fbebf8684f5bf533821e16cfdb/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M09_RAW_V2.json#git_blob_sha=f2e0f7501f14aef0ddf142cd695f774c70f37df1';v_old text:='chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M09.json#sha256=49b6c91b84756fe18bf79374275d51be3b33dd5879969898b60e8a3a4e71865a';
 v_spec jsonb:=$m09_spec${"status":"READY","action_kind":"VERIFY_QUERY_ONCE","recipe_mode":"READBACK_EXACT","requires_material_execution":true,"contract_family":"PE10_METHOD_EXECUTION_EVIDENCE","precision":"PE10_METHOD_V1_MATERIAL_EVIDENCE","assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"checkpoint_identity":"PE10_M09","algorithm_code":"E","literal_sql_count":11,"typed_decision":"VERIFY_FIRST","decision_scenarios_verified":7,"negative_tests_passed":10,"historical_source_event_id":20161,"git_source_verified":true,"runtime_modified":false}},"evidence_ref":"https://github.com/cristhianlujan/claude-persona-lf-patch/blob/bba9a86bbfd9f4fbebf8684f5bf533821e16cfdb/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M09_RAW_V2.json#git_blob_sha=f2e0f7501f14aef0ddf142cd695f774c70f37df1","verification_queries":["SELECT id,created_at,payload->>'source_pack_version' source_pack,payload->>'fetch_spec_version' fetch_spec,payload->'historical_provenance_only' provenance FROM public.lf_eventos WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'","SELECT count(*) total_callers,count(DISTINCT x->>'dedupe_key') unique_caller_keys,count(*) FILTER(WHERE x->>'definition_md5'~'^[a-f0-9]{32}$') hash_syntax_valid,count(*) FILTER(WHERE x->>'currentness_source'='LIVE_PG_PROC') labeled_historical_live FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161","SELECT count(*) reference_edges,count(DISTINCT (x->>'caller')||'->'||c.name) distinct_edges,count(DISTINCT c.name) destination_labels FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x CROSS JOIN LATERAL jsonb_array_elements_text(x->'callees') c(name) WHERE e.id=20161","SELECT jsonb_array_length(payload->'trigger_bindings') trigger_bindings,jsonb_array_length(payload->'edge_current') edge_snapshot_entries,jsonb_array_length(payload->'external_inventory') external_assets,jsonb_array_length(payload->'consumer_relation_snapshot_json_rows') relation_snapshots,payload->'usage_stats' usage_stats FROM public.lf_eventos WHERE id=20161","SELECT id,created_at,receipt_kind,subject_ref,payload->>'verification_status' verification_status,payload->>'pass' pass,payload->>'screens_total' screens,payload->>'families_total' families,payload->>'screens_below_2' screens_below,payload->>'families_below_2' families_below,payload->>'known_false_pass_signals' false_pass,payload->>'unresolved_d4' unresolved_d4 FROM programacion.provenance_receipts WHERE id=38 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'","SELECT codigo,primera_vez,causa_raiz,prevencion,validacion FROM transversal.error_knowledge WHERE codigo IN ('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001') AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z' ORDER BY codigo"],"expected":"Completed source-grounded evidence-decision method E, 4-state counterexamples, material uncertainties declared; not production repair or expert score","forbidden":["MARK_AS_APPLIED_REPAIR","PROMOTE_ASOF_TO_CURRENT","SKIP_ASSERTION_RECEIPT","CLAIM_NO_ACTION_FROM_MISSING_STATS","CHANGE_OTHER_CHECKPOINTS"],"target":{"checkpoint":"PE10_M09","declared_events":[20161],"declared_objects":["public.lf_eventos","programacion.provenance_receipts","transversal.error_knowledge","programacion.engineering_work_checkpoints"],"evidence_artifacts":[{"path":"cristhianlujan/claude-persona-lf-patch:docs/profile_updater/experiments/pe10_methods32_p0/PE10_M09_RAW_V2.json","role":"EVIDENCE","purpose":"PE10_M09_E_TYPED_DECISION_ORIGINAL_SPECIFIC_RAW","target_kind":"EXACT_EXISTING_FILE"}]}}$m09_spec$::jsonb;
 v_q int;v_states int;v_tests int;v_ekb int;v_n int;v_prev_ok int;v_proven_count int;
 v_contract jsonb;v_observed jsonb;v_result jsonb;v_assertion jsonb;v_transition jsonb;v_receipt text;
 v_msg text;v_ctx text;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
 AND target_code LIKE '%lf_pe10_m09_e_decision_close_v1'
 AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'M09_NO_ACTIVE_MIGRATION_TRAIN_EXECUTION'; END IF;
 IF (SELECT status FROM programacion.engineering_work_items WHERE id=1133)<>'IN_PROGRESS'
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>8
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>24
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M09'
 AND status='PENDING' AND evidence_ref=v_old AND assertion_receipt IS NULL AND completed_at IS NULL)<>1
 OR (SELECT count(*) FROM programacion.pe10_method_variants WHERE method_code='PE10_M09'
 AND case_ref='PE10-IG-M107-M109-P0' AND base_code='A' AND algorithm_codes=ARRAY['E']::text[])<>1
 OR (SELECT count(*) FROM programacion.engineering_plan_units WHERE work_item_id=1133
 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32' AND disposition='ASSIGNED'
 AND unit_metadata->>'checkpoint_ordering'='INDEPENDENT_METHOD_VARIANTS'
 AND unit_metadata#>>'{action_specs_v1,PE10_M09,status}'='BLOCK_PENDING_MATERIAL_RESEARCH_AND_VALIDATION')<>1
 THEN RAISE EXCEPTION 'M09_PRESTATE_DRIFT'; END IF;

 SELECT count(*) INTO v_prev_ok
 FROM programacion.engineering_work_checkpoints c
 JOIN (VALUES
 ('PE10_M01','1c174f3277f9656ffc4146c210ac64cd037fc92d4fb34d7a7959fe826e3f9b01'),
('PE10_M02','0079973e1fec8787d2ef45d92131cad58bcb59f3c591aaf2badd8d86fe34c51b'),
('PE10_M03','0cbbc9d58552b2c5ea3d2c9bca1b07c6467cd4145720905f38fc5bf07a46e2a1'),
('PE10_M04','49ff7ae0d5966211ccb5a8caccc5718a61677c375a4a4a35c03e2bd6def7697e'),
('PE10_M05','085c478b380e63908672c0382798750a9a075afc9b8fa21d0fa809db0684e90e'),
('PE10_M06','4d5a9c761bc0171efa908e97d471cb1d372046b235274f141695d4665f1cc4cb'),
('PE10_M07','508081f732648de4caa9b7b95bafba2283f5d2e719323a90d941fe3bedbfdd4a'),
('PE10_M08','ebc8477fea336cb76c25d73cfbcdbe9fe680ca03770734e04ede3fa140512c12')
 ) AS e(code,receipt_sha)
 ON e.code=c.checkpoint_code AND e.receipt_sha=c.assertion_receipt_sha256
 WHERE c.work_item_id=1133 AND c.status='DONE' AND c.assertion_receipt->>'passed'='true'
 AND c.assertion_contract_sha256=c.assertion_receipt->>'contract_sha256';
 IF v_prev_ok<>8 THEN RAISE EXCEPTION 'M09_PREVIOUS_RECEIPT_IDENTITY_DRIFT'; END IF;

 v_blob:=encode(extensions.digest(convert_to('blob '||octet_length(convert_to(v_raw,'UTF8'))::text,'UTF8')
 ||decode('00','hex')||convert_to(v_raw,'UTF8'),'sha1'),'hex');
 IF v_blob<>'f2e0f7501f14aef0ddf142cd695f774c70f37df1' THEN RAISE EXCEPTION 'M09_RAW_GIT_BLOB_MISMATCH'; END IF;
 v_doc:=v_raw::jsonb;
 IF v_doc->>'schema'<>'PE10_METHOD_RAW_V2'
 OR v_doc->>'case_ref'<>'PE10-IG-M107-M109-P0'
 OR v_doc->>'method_code'<>'PE10_M09'
 OR v_doc->>'base_code'<>'A'
 OR v_doc->'algorithm_codes'<>'["E"]'::jsonb
 OR v_doc->>'source_cutoff_utc'<>'2026-10-15T00:00:00Z'
 OR v_doc#>>'{original_preserved,sha256}'<>'49b6c91b84756fe18bf79374275d51be3b33dd5879969898b60e8a3a4e71865a'
 OR v_doc->>'external_evaluation'<>'NOT_PERFORMED'
 OR v_doc#>>'{algorithm_execution,E,actual_state}'<>'VERIFY_FIRST'
 OR v_doc#>>'{chosen_repair,type}'<>'VERIFY_FIRST'
 OR v_doc->>'research_conclusion'<>'E_TYPED_DECISION_EXECUTED_VERIFY_FIRST_WITH_UNRESOLVED_MATERIAL_EVIDENCE'
 THEN RAISE EXCEPTION 'M09_RAW_IDENTITY_OR_DECISION_SCOPE_INVALID'; END IF;

 SELECT count(*) INTO v_q FROM jsonb_array_elements(v_doc->'sql_evidence') e
 WHERE e->>'id' ~ '^M09_Q(0[1-9]|1[01])$'
 AND e->>'sql_literal' ~* '^SELECT '
 AND e->>'source'='SUPABASE_READ_ONLY'
 AND jsonb_typeof(e->'rows')='array'
 AND (e->>'rows_returned')::int=jsonb_array_length(e->'rows')
 AND jsonb_array_length(e->'rows')>0;
 IF v_q<>11 OR jsonb_array_length(v_doc->'sql_evidence')<>11
 OR (SELECT count(DISTINCT e->>'id') FROM jsonb_array_elements(v_doc->'sql_evidence') e)<>11
 OR v_doc#>>'{sql_evidence,1,rows,0,total_callers}'<>'38'
 OR v_doc#>>'{sql_evidence,2,rows,0,reference_edges}'<>'76'
 OR v_doc#>>'{sql_evidence,3,rows,0,usage_stats,track_functions}'<>'none'
 OR v_doc#>>'{sql_evidence,5,rows,0,verification_status}'<>'VERIFIED'
 OR v_doc#>>'{sql_evidence,9,rows,0,post_cutoff}'<>'0'
 OR v_doc#>>'{sql_evidence,10,rows,0,read_only}'<>'on'
 THEN RAISE EXCEPTION 'M09_SQL_READBACK_INCOMPLETE_OR_CONTRADICTED'; END IF;

 -- Recompute the decision engine from provided booleans on the DB side,
 -- not merely comparing two agent-authored strings or hardcoding PASS.
 SELECT count(*) INTO v_states
 FROM jsonb_array_elements(v_doc#>'{algorithm_execution,E,decision_scenarios}') s
 WHERE s->>'expected'=CASE
 WHEN coalesce((s#>>'{inputs,proven_defect}')::boolean,false)
  AND coalesce((s#>>'{inputs,causal_trace}')::boolean,false) THEN 'REPAIR_REQUIRED'
 WHEN coalesce((s#>>'{inputs,source_risk}')::boolean,false)
  AND coalesce((s#>>'{inputs,authorized_falsifier}')::boolean,false) THEN 'VERIFY_FIRST'
 WHEN NOT coalesce((s#>>'{inputs,source_qualified}')::boolean,false)
  OR coalesce((s#>>'{inputs,material_unknown}')::boolean,false) THEN 'NEEDS_MORE_EVIDENCE'
 ELSE 'NO_ACTION_SUPPORTED' END
 AND s->>'observed'=s->>'expected';
 SELECT count(DISTINCT s->>'observed') INTO v_proven_count
 FROM jsonb_array_elements(v_doc#>'{algorithm_execution,E,decision_scenarios}') s;
 SELECT count(*) INTO v_tests FROM jsonb_array_elements(v_doc#>'{algorithm_execution,E,positive_negative_tests}') t WHERE t->>'pass'='true';
 IF v_states<>7 OR jsonb_array_length(v_doc#>'{algorithm_execution,E,decision_scenarios}')<>7
 OR v_proven_count<>4 OR v_tests<>10
 OR jsonb_array_length(v_doc#>'{algorithm_execution,E,positive_negative_tests}')<>10
 OR jsonb_array_length(v_doc#>'{algorithm_execution,E,reversal_criteria}')<>3
 OR jsonb_array_length(v_doc#>'{algorithm_execution,E,risks}')<>3
 THEN RAISE EXCEPTION 'M09_TYPED_DECISION_POSITIVE_NEGATIVE_FAILED'; END IF;

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
 AND payload->>'known_false_pass_signals'='0'
 AND payload->>'unresolved_d4'='0')<>1
 THEN RAISE EXCEPTION 'M09_HISTORICAL_AUTHORITY_SOURCE_READBACK_FAILED'; END IF;

 UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10_M09}',v_spec,true)
 WHERE work_item_id=1133 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32';
 GET DIAGNOSTICS v_n=ROW_COUNT;
 IF v_n<>1 THEN RAISE EXCEPTION 'M09_ACTION_SPEC_NOT_SINGLE'; END IF;
 v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M09',
 programacion.fn_engineering_checkpoint_action_spec_v3('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M09'));
 IF v_contract->>'status'<>'READY' OR v_contract->>'mode'<>'EXPLICIT_PASS_WHEN_SUBSET'
 THEN RAISE EXCEPTION 'M09_CANONICAL_ASSERTION_CONTRACT_NOT_READY:%',coalesce(v_contract::text,'NULL'); END IF;

 v_observed:=jsonb_build_object('checkpoint_identity','PE10_M09','algorithm_code','E',
 'literal_sql_count',11,'typed_decision','VERIFY_FIRST','decision_scenarios_verified',v_states,
 'negative_tests_passed',v_tests,'historical_source_event_id',20161,
 'git_source_verified',true,'runtime_modified',false);
 v_result:=jsonb_build_object('status','PASS','observed',v_observed,'evidence_ref',v_ref,
 'validation_kind','M09_METHOD_E_MATERIAL_DECISION_EXECUTED',
 'external_method_evaluation','NOT_PERFORMED','repair_implemented',false);
 v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M09',v_result,v_exec);
 IF v_assertion->>'passed'<>'true'
 OR coalesce(v_assertion->>'assertion_receipt_sha256','') !~ '^[a-f0-9]{64}$'
 THEN RAISE EXCEPTION 'M09_CANONICAL_ASSERTION_NOT_CERTIFIED'; END IF;
 v_receipt:=v_assertion->>'assertion_receipt_sha256';
 v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M09','DONE',v_ref,v_exec,
 'M09 E method typed decision VERIFY_FIRST was executed and certified; no LF repair applied');
 IF v_transition#>>'{transition,status}'<>'APPLIED'
 THEN RAISE EXCEPTION 'M09_CANONICAL_TRANSITION_NOT_APPLIED'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=1133 AND checkpoint_code='PE10_M09'
 AND status='DONE' AND completed_at IS NOT NULL
 AND assertion_receipt_sha256=v_receipt
 AND assertion_contract_sha256=assertion_receipt->>'contract_sha256'
 AND assertion_receipt->>'passed'='true' AND evidence_ref=v_ref)<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>9
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>23
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=1133 AND checkpoint_code='PE10_M10' AND status='PENDING')<>1
 THEN RAISE EXCEPTION 'M09_FINAL_TRAIN_READBACK_INCONSISTENT'; END IF;
EXCEPTION WHEN OTHERS THEN
 GET STACKED DIAGNOSTICS v_msg=MESSAGE_TEXT,v_ctx=PG_EXCEPTION_CONTEXT;
 RAISE EXCEPTION 'M09_TRAIN_CAUSE state=% msg=% context=%',SQLSTATE,left(v_msg,300),left(v_ctx,160) USING ERRCODE=SQLSTATE;
END $m09_close$;
