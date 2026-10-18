-- PE10 M13 C+E evidence-only checkpoint closure, EXACT Merge Train context.
DO $m13_close$
DECLARE
 v_exec text;v_raw text:=$m13_raw${
  "schema": "PE10_METHOD_RAW_V2",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M13",
  "base_code": "A",
  "algorithm_codes": [
    "C",
    "E"
  ],
  "source_cutoff": "2026-10-15T00:00:00Z",
  "original_preserved": {
    "path": "chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M13.json",
    "sha256": "ed1b41639150ea4c775c2ed17b44867b7a3e2fdfa89588bdbe950beb436b03b6"
  },
  "producer": "Integrated SRCR+C+E single method run, no peer-method answers used",
  "external_evaluation": "NOT_PERFORMED",
  "sql_evidence": [
    {
      "id": "M13_Q01",
      "sql_literal": "SELECT id,created_at,payload->>'source_pack_version' source_pack,payload->>'sql_caller_count' declared_callers,payload->'scope_guards' scope_guards FROM public.lf_eventos WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'",
      "rows": [
        {
          "id": 20161,
          "created_at": "2026-10-04 05:14:40.880842+00",
          "source_pack": "SOURCE_PACK_V1",
          "declared_callers": "38",
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
      "scope": "HISTORICAL_SOURCE_ASOF_PRE_CUTOFF"
    },
    {
      "id": "M13_Q02",
      "sql_literal": "SELECT count(*) total,count(*) FILTER(WHERE x->>'operational_class'='ACTIVE') t,count(*) FILTER(WHERE NOT(x->>'operational_class'='ACTIVE')) f,count(*) FILTER(WHERE (x->>'operational_class'='ACTIVE') IS NULL) n,count(DISTINCT x->>'dedupe_key') deduped FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161",
      "rows": [
        {
          "total": 38,
          "t": 38,
          "f": 0,
          "n": 0,
          "deduped": 38
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF_PRE_CUTOFF"
    },
    {
      "id": "M13_Q03",
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
      "scope": "HISTORICAL_SOURCE_ASOF_PRE_CUTOFF"
    },
    {
      "id": "M13_Q04",
      "sql_literal": "SELECT count(*) total,count(*) FILTER(WHERE x->>'definition_md5'~'^[a-f0-9]{32}$') valid,count(*) FILTER(WHERE NOT(x->>'definition_md5'~'^[a-f0-9]{32}$')) invalid,count(*) FILTER(WHERE (x->>'definition_md5'~'^[a-f0-9]{32}$') IS NULL) nulls FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161",
      "rows": [
        {
          "total": 38,
          "valid": 38,
          "invalid": 0,
          "nulls": 0
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF_PRE_CUTOFF"
    },
    {
      "id": "M13_Q05",
      "sql_literal": "WITH v(a) AS(VALUES('ACTIVE'::text),('DISABLED'::text),(NULL::text)) SELECT count(*) total,count(*) FILTER(WHERE a='ACTIVE') t,count(*) FILTER(WHERE NOT(a='ACTIVE')) f,count(*) FILTER(WHERE (a='ACTIVE') IS NULL) n FROM v",
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
      "scope": "EXPLICIT_SYNTHETIC_SQL"
    },
    {
      "id": "M13_Q06",
      "sql_literal": "WITH pairs(expected,observed) AS (VALUES(38,38),(38,39),(38,NULL::int)) SELECT expected,observed,(expected=observed) IS TRUE as accepted FROM pairs ORDER BY observed NULLS LAST",
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
      "scope": "EXPLICIT_SYNTHETIC_SQL"
    },
    {
      "id": "M13_Q07",
      "sql_literal": "SELECT count(*) edges,count(DISTINCT (x->>'caller')||'->'||c.name) unique_edges,count(DISTINCT c.name) callee_names FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x CROSS JOIN LATERAL jsonb_array_elements_text(x->'callees') c(name) WHERE e.id=20161",
      "rows": [
        {
          "edges": 76,
          "unique_edges": 76,
          "callee_names": 39
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF_PRE_CUTOFF"
    },
    {
      "id": "M13_Q08",
      "sql_literal": "SELECT id,created_at,payload->>'verification_status' verified,payload->>'screens_total' screens,payload->>'families_total' families,payload->>'known_false_pass_signals' false_pass,payload->>'unresolved_d4' d4 FROM programacion.provenance_receipts WHERE id=38 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'",
      "rows": [
        {
          "id": 38,
          "created_at": "2026-10-07 16:01:00.760627+00",
          "verified": "VERIFIED",
          "screens": "13",
          "families": "47",
          "false_pass": "0",
          "d4": "0"
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF_PRE_CUTOFF"
    },
    {
      "id": "M13_Q09",
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
      "scope": "HISTORICAL_SOURCE_ASOF_PRE_CUTOFF"
    },
    {
      "id": "M13_Q10",
      "sql_literal": "SELECT jsonb_array_length(payload->'trigger_bindings') triggers,jsonb_array_length(payload->'consumer_relation_snapshot_json_rows') relation_rows,payload->'usage_stats' usage_stats FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "triggers": 21,
          "relation_rows": 27,
          "usage_stats": {
            "ig_stat_rows": 0,
            "interpretation": "track_functions none means zero stat rows cannot prove no usage; static governed graph supplies inventory currentness",
            "track_functions": "none"
          }
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF_PRE_CUTOFF"
    },
    {
      "id": "M13_Q11",
      "sql_literal": "SELECT count(*) FILTER(WHERE created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z') before_cutoff,count(*) FILTER(WHERE created_at>=TIMESTAMPTZ '2026-10-15T00:00:00Z') after_cutoff FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "before_cutoff": 1,
          "after_cutoff": 0
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_SOURCE_ASOF_PRE_CUTOFF"
    },
    {
      "id": "M13_Q12",
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
      "scope": "READONLY_PRINCIPAL_NOT_P0"
    }
  ],
  "algorithm_execution": {
    "C": {
      "three_valued_partitions": {
        "callers": {
          "total": 38,
          "t": 38,
          "f": 0,
          "n": 0,
          "deduped": 38
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
          "nulls": 0
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
      "solver": "NOT_EXECUTED_NO_SMT_ENGINE",
      "business_policy_proof": "NOT_ESTABLISHED"
    },
    "E": {
      "decision_states": [
        "VERIFY_FIRST",
        "REPAIR_REQUIRED",
        "NEEDS_MORE_EVIDENCE",
        "NO_ACTION_SUPPORTED"
      ],
      "actual_state": "VERIFY_FIRST",
      "decision_scenarios": [
        {
          "id": "E_ACTUAL",
          "inputs": {
            "demonstrated_failure": false,
            "causal_evidence": false,
            "source_risk": true,
            "available_select": true,
            "null_or_missing": true,
            "qualified_source": true
          },
          "expected": "VERIFY_FIRST",
          "observed": "VERIFY_FIRST"
        },
        {
          "id": "E_CAUSAL_PROVEN",
          "inputs": {
            "demonstrated_failure": true,
            "causal_evidence": true,
            "source_risk": true,
            "available_select": true,
            "null_or_missing": false,
            "qualified_source": true
          },
          "expected": "REPAIR_REQUIRED",
          "observed": "REPAIR_REQUIRED"
        },
        {
          "id": "E_NULL_MISSING",
          "inputs": {
            "demonstrated_failure": false,
            "causal_evidence": false,
            "source_risk": false,
            "available_select": false,
            "null_or_missing": true,
            "qualified_source": true
          },
          "expected": "NEEDS_MORE_EVIDENCE",
          "observed": "NEEDS_MORE_EVIDENCE"
        },
        {
          "id": "E_COMPLETE_NEGATIVE",
          "inputs": {
            "demonstrated_failure": false,
            "causal_evidence": false,
            "source_risk": false,
            "available_select": false,
            "null_or_missing": false,
            "qualified_source": true
          },
          "expected": "NO_ACTION_SUPPORTED",
          "observed": "NO_ACTION_SUPPORTED"
        },
        {
          "id": "E_42501_PERMISSION",
          "inputs": {
            "demonstrated_failure": false,
            "causal_evidence": false,
            "source_risk": true,
            "available_select": true,
            "null_or_missing": true,
            "qualified_source": true
          },
          "expected": "VERIFY_FIRST",
          "observed": "VERIFY_FIRST"
        },
        {
          "id": "E_INVALID_COUNT_NO_CAUSE",
          "inputs": {
            "demonstrated_failure": true,
            "causal_evidence": false,
            "source_risk": true,
            "available_select": true,
            "null_or_missing": true,
            "qualified_source": true
          },
          "expected": "VERIFY_FIRST",
          "observed": "VERIFY_FIRST"
        },
        {
          "id": "E_SOURCE_UNQUALIFIED",
          "inputs": {
            "demonstrated_failure": false,
            "causal_evidence": false,
            "source_risk": false,
            "available_select": false,
            "null_or_missing": false,
            "qualified_source": false
          },
          "expected": "NEEDS_MORE_EVIDENCE",
          "observed": "NEEDS_MORE_EVIDENCE"
        }
      ],
      "reversal_criteria": [
        {
          "condition": "qualified source demonstrates causal functional defect",
          "state": "REPAIR_REQUIRED"
        },
        {
          "condition": "qualified material coverage has no risk",
          "state": "NO_ACTION_SUPPORTED"
        },
        {
          "condition": "missing/NULL evidence and no eligible read path",
          "state": "NEEDS_MORE_EVIDENCE"
        }
      ],
      "falsifiers": [
        "Time-qualified CP2 reader proof",
        "Runtime invocation traces",
        "Cohort E2E timing and denominator"
      ]
    }
  },
  "negative_tests": [
    {
      "id": "C_TLP_CALLERS_RECONCILED",
      "pass": true
    },
    {
      "id": "C_TLP_EXTERNAL_RECONCILED",
      "pass": true
    },
    {
      "id": "C_TLP_HASHES_PARTITIONED",
      "pass": true
    },
    {
      "id": "C_SYNTHETIC_NULL_EXERCISED",
      "pass": true
    },
    {
      "id": "C_VALID_COUNT_ACCEPTED",
      "pass": true
    },
    {
      "id": "C_INVALID_COUNT_REJECTED",
      "pass": true
    },
    {
      "id": "C_NULL_COUNT_REJECTED",
      "pass": true
    },
    {
      "id": "C_NO_SMT_BUSINESS_PROOF_CLAIM",
      "pass": true
    },
    {
      "id": "E_SEVEN_SCENARIOS",
      "pass": true
    },
    {
      "id": "E_FOUR_STATES_COVERED",
      "pass": true
    },
    {
      "id": "E_42501_NOT_REPAIR_REQUIRED",
      "pass": true
    },
    {
      "id": "E_UNKNOWN_REJECTS_NO_ACTION",
      "pass": true
    },
    {
      "id": "P0_SOURCE_CUTOFF",
      "pass": true
    },
    {
      "id": "P0_SOAK_QUALIFIED",
      "pass": true
    },
    {
      "id": "NOT_ZERO_USAGE_FROM_TRACK_FUNCTIONS",
      "pass": true
    }
  ],
  "findings": [
    {
      "id": "M13-F1",
      "claim": "Historical 38 callers and external inventory 6 reconcile in separate TRUE/FALSE/NULL populations, not directly additive",
      "evidence": [
        "M13_Q02",
        "M13_Q03"
      ],
      "kind": "MEASURED_ASOF"
    },
    {
      "id": "M13-F2",
      "claim": "MD5 syntax 38/38 does not establish historical canonical hash method",
      "evidence": [
        "M13_Q04"
      ],
      "kind": "MEASURED_FORMAT_ONLY"
    },
    {
      "id": "M13-F3",
      "claim": "Synthetic positive, negative and unknown-count guards reject unsupported completeness; no actual business correctness inferred",
      "evidence": [
        "M13_Q05",
        "M13_Q06"
      ],
      "kind": "EXECUTED_SYNTHETIC"
    },
    {
      "id": "M13-F4",
      "claim": "Typed E decision VERIFY_FIRST retains qualified risk and an authorized read-only falsifier without inventing production defect",
      "evidence": [
        "M13_Q08",
        "M13_Q09",
        "M13_Q12"
      ],
      "kind": "EXECUTED_E"
    }
  ],
  "causal_model": {
    "status": "NOT_PROVEN",
    "alternative_explanations": [
      "SOAK projection drift",
      "CP2 permission not functional error",
      "static graph vs live runtime unknown"
    ]
  },
  "candidate_repairs": [
    {
      "action": "Reconcile source P0 identities using 3VL and unknown partition",
      "status": "READ_ONLY_PROPOSAL"
    }
  ],
  "chosen_repair": {
    "decision": "VERIFY_FIRST",
    "implementation": "NOT_PERFORMED",
    "reason": "material unknowns and no proven causal defect"
  },
  "rejected_alternatives": [
    "Conflate NULL with FALSE",
    "Treat SMT proofs as done",
    "Escalate EXECUTE privilege",
    "Claim NO_ACTION_SUPPORTED due zero stats"
  ],
  "omissions_searched": [
    "unknown hash values",
    "missing populations",
    "negative synthetic cases",
    "authority and time scope",
    "decision reversals"
  ],
  "unresolved": [
    "Exact runtime CP2 reader unknown",
    "Historical canonical hashing unknown",
    "E2E perf unknown"
  ],
  "constraints_preserved": [
    "P0",
    "no edits",
    "no other method outputs",
    "no score"
  ],
  "conclusion": "C_E_TYPED_DECISION_AND_TLP_NEGATIVES_EXECUTED_WITH_UNRESOLVED_CAUSALITY"
}
$m13_raw$;v_doc jsonb;
 v_spec jsonb:=$m13_spec${"status":"READY","action_kind":"VERIFY_QUERY_ONCE","recipe_mode":"READBACK_EXACT","requires_material_execution":true,"contract_family":"PE10_METHOD_EXECUTION_EVIDENCE","precision":"PE10_METHOD_V1_MATERIAL_EVIDENCE","assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"checkpoint_identity":"PE10_M13","method_algorithms":"C+E","literal_sql_count":12,"c_positive_negative_checks_passed":15,"typed_e_scenarios_verified":7,"typed_e_decision":"VERIFY_FIRST","historical_sql_callers_total":38,"historical_external_assets_total":6,"source_event_id":20161,"git_source_verified":true,"runtime_modified":false}},"evidence_ref":"https://github.com/cristhianlujan/claude-persona-lf-patch/blob/51ddc9ca2fce82de3e730d5bc1e5c4d907d76efb/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M13_RAW_V2.json#git_blob_sha=fcbdfedc15940a7e52e5d5b68a12925fb685713b","verification_queries":["SELECT id,created_at,payload->>'source_pack_version' source_pack,payload->>'sql_caller_count' declared_callers,payload->'scope_guards' scope_guards FROM public.lf_eventos WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'","SELECT count(*) total,count(*) FILTER(WHERE x->>'operational_class'='ACTIVE') t,count(*) FILTER(WHERE NOT(x->>'operational_class'='ACTIVE')) f,count(*) FILTER(WHERE (x->>'operational_class'='ACTIVE') IS NULL) n,count(DISTINCT x->>'dedupe_key') deduped FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161","SELECT count(*) total,count(*) FILTER(WHERE x->>'operational_class'='ACTIVE') t,count(*) FILTER(WHERE NOT(x->>'operational_class'='ACTIVE')) f,count(*) FILTER(WHERE (x->>'operational_class'='ACTIVE') IS NULL) n FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'external_inventory') x WHERE e.id=20161","SELECT count(*) total,count(*) FILTER(WHERE x->>'definition_md5'~'^[a-f0-9]{32}$') valid,count(*) FILTER(WHERE NOT(x->>'definition_md5'~'^[a-f0-9]{32}$')) invalid,count(*) FILTER(WHERE (x->>'definition_md5'~'^[a-f0-9]{32}$') IS NULL) nulls FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161","WITH v(a) AS(VALUES('ACTIVE'::text),('DISABLED'::text),(NULL::text)) SELECT count(*) total,count(*) FILTER(WHERE a='ACTIVE') t,count(*) FILTER(WHERE NOT(a='ACTIVE')) f,count(*) FILTER(WHERE (a='ACTIVE') IS NULL) n FROM v","WITH pairs(expected,observed) AS (VALUES(38,38),(38,39),(38,NULL::int)) SELECT expected,observed,(expected=observed) IS TRUE as accepted FROM pairs ORDER BY observed NULLS LAST"],"expected":"C 3-valued SQL population and invalidity guards + E source-scoped risk decision; no domain policy proof or repair claimed","forbidden":["ASSERT_NULL_AS_FALSE","CLAIM_SMT_SOLVER","CLAIM_DOMAIN_BUG_PATCHED","MODIFY_PREVIOUS_CHECKPOINT","SKIP_CANONICAL_TRAIN"],"target":{"checkpoint":"PE10_M13","declared_events":[20161],"declared_objects":["public.lf_eventos","programacion.provenance_receipts","transversal.error_knowledge","programacion.engineering_work_checkpoints"],"evidence_artifacts":[{"path":"cristhianlujan/claude-persona-lf-patch:docs/profile_updater/experiments/pe10_methods32_p0/PE10_M13_RAW_V2.json","role":"EVIDENCE","purpose":"M13_C_PLUS_E_TYPED_TLP_METHOD_RAW","target_kind":"EXACT_EXISTING_FILE"}]}}$m13_spec$::jsonb;
 v_ref text:='https://github.com/cristhianlujan/claude-persona-lf-patch/blob/51ddc9ca2fce82de3e730d5bc1e5c4d907d76efb/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M13_RAW_V2.json#git_blob_sha=fcbdfedc15940a7e52e5d5b68a12925fb685713b';v_old text:='chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M13.json#sha256=ed1b41639150ea4c775c2ed17b44867b7a3e2fdfa89588bdbe950beb436b03b6';v_blob text;
 v_q int;v_c int;v_e int;v_four int;v_ekb int;v_prev_ok int;v_n int;
 v_contract jsonb;v_obs jsonb;v_result jsonb;v_assertion jsonb;v_transition jsonb;v_receipt text;
 v_msg text;v_ctx text;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
 AND target_code LIKE '%lf_pe10_m13_ce_governed_close_v1'
 AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'M13_TRAIN_EXECUTION_MISSING'; END IF;
 IF (SELECT status FROM programacion.engineering_work_items WHERE id=1133)<>'IN_PROGRESS'
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>12
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>20
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M13'
 AND status='PENDING' AND evidence_ref=v_old AND assertion_receipt IS NULL AND completed_at IS NULL)<>1
 OR (SELECT count(*) FROM programacion.pe10_method_variants WHERE method_code='PE10_M13'
 AND base_code='A' AND case_ref='PE10-IG-M107-M109-P0' AND algorithm_codes=ARRAY['C','E']::text[])<>1
 OR (SELECT count(*) FROM programacion.engineering_plan_units WHERE work_item_id=1133 AND plan_code='PEVO-PE10-METHODS32-P0'
 AND unit_code='METHODS32' AND unit_metadata#>>'{action_specs_v1,PE10_M13,status}'='BLOCK_PENDING_MATERIAL_RESEARCH_AND_VALIDATION')<>1
 THEN RAISE EXCEPTION 'M13_PRESTATE_DRIFT'; END IF;
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
('PE10_M12','01723c0a370baabe2532358bdac86bbfdbe185ba0514e195547597475d93a383')) e(code,sha)
 ON e.code=c.checkpoint_code AND e.sha=c.assertion_receipt_sha256
 WHERE c.work_item_id=1133 AND c.status='DONE' AND c.assertion_receipt->>'passed'='true'
 AND c.assertion_contract_sha256=c.assertion_receipt->>'contract_sha256';
 IF v_prev_ok<>12 THEN RAISE EXCEPTION 'M13_PREVIOUS_RECEIPTS_CHANGED'; END IF;

 v_blob:=encode(extensions.digest(convert_to('blob '||octet_length(convert_to(v_raw,'UTF8'))::text,'UTF8')
 ||decode('00','hex')||convert_to(v_raw,'UTF8'),'sha1'),'hex');
 IF v_blob<>'fcbdfedc15940a7e52e5d5b68a12925fb685713b' THEN RAISE EXCEPTION 'M13_GIT_IMMUTABLE_RAW_HASH_BAD'; END IF;
 v_doc:=v_raw::jsonb;
 IF v_doc->>'schema'<>'PE10_METHOD_RAW_V2' OR v_doc->>'method_code'<>'PE10_M13'
 OR v_doc->>'case_ref'<>'PE10-IG-M107-M109-P0' OR v_doc->>'base_code'<>'A'
 OR v_doc->'algorithm_codes'<>'["C","E"]'::jsonb
 OR v_doc->>'source_cutoff'<>'2026-10-15T00:00:00Z'
 OR v_doc#>>'{original_preserved,sha256}'<>'ed1b41639150ea4c775c2ed17b44867b7a3e2fdfa89588bdbe950beb436b03b6'
 OR v_doc->>'external_evaluation'<>'NOT_PERFORMED'
 OR v_doc#>>'{algorithm_execution,E,actual_state}'<>'VERIFY_FIRST'
 OR v_doc#>>'{chosen_repair,decision}'<>'VERIFY_FIRST'
 OR v_doc->>'conclusion'<>'C_E_TYPED_DECISION_AND_TLP_NEGATIVES_EXECUTED_WITH_UNRESOLVED_CAUSALITY'
 THEN RAISE EXCEPTION 'M13_SOURCE_RAW_IDENTITY_BAD'; END IF;

 SELECT count(*) INTO v_q FROM jsonb_array_elements(v_doc->'sql_evidence') z
 WHERE z->>'id' ~ '^M13_Q(0[1-9]|1[0-2])$' AND z->>'sql_literal' ~* '^(SELECT|WITH) '
 AND z->>'source'='SUPABASE_READ_ONLY' AND jsonb_typeof(z->'rows')='array'
 AND (z->>'rows_returned')::int=jsonb_array_length(z->'rows')
 AND jsonb_array_length(z->'rows')>0;
 IF v_q<>12 OR jsonb_array_length(v_doc->'sql_evidence')<>12
 OR (SELECT count(DISTINCT z->>'id') FROM jsonb_array_elements(v_doc->'sql_evidence') z)<>12
 OR v_doc#>>'{sql_evidence,1,rows,0,total}'<>'38'
 OR v_doc#>>'{sql_evidence,2,rows,0,total}'<>'6'
 OR v_doc#>>'{sql_evidence,3,rows,0,valid}'<>'38'
 OR v_doc#>>'{sql_evidence,4,rows,0,n}'<>'1'
 OR v_doc#>>'{sql_evidence,7,rows,0,verified}'<>'VERIFIED'
 OR v_doc#>>'{sql_evidence,10,rows,0,after_cutoff}'<>'0'
 THEN RAISE EXCEPTION 'M13_LITERAL_SQL_SOURCE_INSUFFICIENT'; END IF;

 SELECT count(*) INTO v_c FROM jsonb_array_elements(v_doc->'negative_tests') x WHERE x->>'pass'='true';
 SELECT count(*) INTO v_e FROM jsonb_array_elements(v_doc#>'{algorithm_execution,E,decision_scenarios}') x
 WHERE x->>'expected'=CASE
 WHEN coalesce((x#>>'{inputs,demonstrated_failure}')::boolean,false)
 AND coalesce((x#>>'{inputs,causal_evidence}')::boolean,false) THEN 'REPAIR_REQUIRED'
 WHEN coalesce((x#>>'{inputs,source_risk}')::boolean,false)
 AND coalesce((x#>>'{inputs,available_select}')::boolean,false) THEN 'VERIFY_FIRST'
 WHEN coalesce((x#>>'{inputs,null_or_missing}')::boolean,false)
 OR NOT coalesce((x#>>'{inputs,qualified_source}')::boolean,false) THEN 'NEEDS_MORE_EVIDENCE'
 ELSE 'NO_ACTION_SUPPORTED' END AND x->>'observed'=x->>'expected';
 SELECT count(DISTINCT x->>'observed') INTO v_four FROM jsonb_array_elements(v_doc#>'{algorithm_execution,E,decision_scenarios}') x;
 IF v_c<>15 OR jsonb_array_length(v_doc->'negative_tests')<>15
 OR v_e<>7 OR jsonb_array_length(v_doc#>'{algorithm_execution,E,decision_scenarios}')<>7 OR v_four<>4
 OR v_doc#>>'{algorithm_execution,C,three_valued_partitions,callers,total}'<>'38'
 OR v_doc#>>'{algorithm_execution,C,three_valued_partitions,external,total}'<>'6'
 OR v_doc#>>'{algorithm_execution,C,three_valued_partitions,synthetic,n}'<>'1'
 OR jsonb_array_length(v_doc#>'{algorithm_execution,C,count_contract_cases}')<>3
 OR v_doc#>>'{algorithm_execution,C,solver}'<>'NOT_EXECUTED_NO_SMT_ENGINE'
 THEN RAISE EXCEPTION 'M13_C_E_NEGATIVE_OR_TYPED_STATE_INCOMPLETE'; END IF;
 SELECT count(*) INTO v_ekb FROM transversal.error_knowledge
 WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001')
 AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z';
 IF v_ekb<>2 OR (SELECT count(*) FROM public.lf_eventos WHERE id=20161
 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z' AND jsonb_array_length(payload->'sql_callers')=38
 AND jsonb_array_length(payload->'external_inventory')=6)<>1
 OR (SELECT count(*) FROM programacion.provenance_receipts WHERE id=38
 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'
 AND payload->>'verification_status'='VERIFIED')<>1
 THEN RAISE EXCEPTION 'M13_HISTORICAL_READBACK_CHANGED'; END IF;

 UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10_M13}',v_spec,true)
 WHERE work_item_id=1133 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32';
 GET DIAGNOSTICS v_n=ROW_COUNT;
 IF v_n<>1 THEN RAISE EXCEPTION 'M13_CANONICAL_SPEC_WRITE_NOT_ONE'; END IF;
 v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M13',
 programacion.fn_engineering_checkpoint_action_spec_v3('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M13'));
 IF v_contract->>'status'<>'READY' OR v_contract->>'mode'<>'EXPLICIT_PASS_WHEN_SUBSET'
 THEN RAISE EXCEPTION 'M13_ASSERTION_CONTRACT_BLOCKED:%',coalesce(v_contract::text,'NULL'); END IF;
 v_obs:=jsonb_build_object('checkpoint_identity','PE10_M13','method_algorithms','C+E',
 'literal_sql_count',12,'c_positive_negative_checks_passed',15,'typed_e_scenarios_verified',7,
 'typed_e_decision','VERIFY_FIRST','historical_sql_callers_total',38,'historical_external_assets_total',6,
 'source_event_id',20161,'git_source_verified',true,'runtime_modified',false);
 v_result:=jsonb_build_object('status','PASS','observed',v_obs,'evidence_ref',v_ref,
 'validation_kind','M13_C_E_MATERIAL_METHOD_EXECUTION','domain_repair','NOT_PERFORMED');
 v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M13',v_result,v_exec);
 IF v_assertion->>'passed'<>'true' OR coalesce(v_assertion->>'assertion_receipt_sha256','') !~ '^[a-f0-9]{64}$'
 THEN RAISE EXCEPTION 'M13_CANONICAL_ASSERTION_NOT_PASSED'; END IF;
 v_receipt:=v_assertion->>'assertion_receipt_sha256';
 v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M13','DONE',v_ref,v_exec,
 'M13 C 3VL cases and E typed evidence decision verified, no product repair');
 IF v_transition#>>'{transition,status}'<>'APPLIED'
 THEN RAISE EXCEPTION 'M13_CANONICAL_TRANSITION_FAIL'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133
 AND checkpoint_code='PE10_M13' AND status='DONE' AND completed_at IS NOT NULL
 AND assertion_receipt_sha256=v_receipt AND assertion_receipt->>'passed'='true'
 AND assertion_contract_sha256=assertion_receipt->>'contract_sha256' AND evidence_ref=v_ref)<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>13
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>19
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M14' AND status='PENDING')<>1
 THEN RAISE EXCEPTION 'M13_FINAL_TRAIN_READBACK_NOT_DONE'; END IF;
EXCEPTION WHEN OTHERS THEN
 GET STACKED DIAGNOSTICS v_msg=MESSAGE_TEXT,v_ctx=PG_EXCEPTION_CONTEXT;
 RAISE EXCEPTION 'M13_TRAIN_SQLSTATE_% msg=% context=%',SQLSTATE,left(v_msg,290),left(v_ctx,150) USING ERRCODE=SQLSTATE;
END $m13_close$;
