-- PE10 M05: C invariants / TLP metamorphic tests. No product changes, no false business acceptance.
DO $m05_close$
DECLARE
 v_exec text;v_raw text:=$m05_raw${
  "schema": "PE10_METHOD_RAW_V2",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M05",
  "base_code": "A",
  "algorithm_codes": [
    "C"
  ],
  "source_cutoff": "2026-10-15T00:00:00Z",
  "original_preserved": {
    "path": "chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M05.json",
    "sha256": "8fefae266b4b2279cb8d921dd4b2893ac607993fd38ae70c72d6f3f0bf050685"
  },
  "producer": "One integrated SRCR C-method investigation, no other method findings as input",
  "scope": "READ_ONLY_HISTORICAL_REPLAY_PLUS_EXPLICIT_SYNTHETIC_NEGATIVES",
  "external_evaluation": "NOT_PERFORMED",
  "sql_evidence": [
    {
      "id": "M05_Q01",
      "sql_literal": "SELECT id,created_at,payload->>'source_pack_version' pack,payload->>'sql_caller_count' declared_callers,payload->>'trigger_binding_count' declared_triggers,payload->'scope_guards' scope_guards FROM public.lf_eventos WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'",
      "rows": [
        {
          "id": 20161,
          "created_at": "2026-10-04 05:14:40.880842+00",
          "pack": "SOURCE_PACK_V1",
          "declared_callers": "38",
          "declared_triggers": "21",
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
      "scope": "HISTORICAL_ASOF_P0_SNAPSHOT_READBACK",
      "limitations": "No current runtime invocations inferred"
    },
    {
      "id": "M05_Q02",
      "sql_literal": "SELECT count(*) total,count(*) FILTER(WHERE x->>'operational_class'='ACTIVE') t,count(*) FILTER(WHERE NOT(x->>'operational_class'='ACTIVE')) f,count(*) FILTER(WHERE (x->>'operational_class'='ACTIVE') IS NULL) n,count(DISTINCT x->>'dedupe_key') deduplicated FROM public.lf_eventos l CROSS JOIN LATERAL jsonb_array_elements(l.payload->'sql_callers') x WHERE l.id=20161",
      "rows": [
        {
          "total": 38,
          "t": 38,
          "f": 0,
          "n": 0,
          "deduplicated": 38
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_ASOF_P0_SNAPSHOT_READBACK",
      "limitations": "No current runtime invocations inferred"
    },
    {
      "id": "M05_Q03",
      "sql_literal": "SELECT count(*) total,count(*) FILTER(WHERE x->>'operational_class'='ACTIVE') t,count(*) FILTER(WHERE NOT(x->>'operational_class'='ACTIVE')) f,count(*) FILTER(WHERE (x->>'operational_class'='ACTIVE') IS NULL) n FROM public.lf_eventos l CROSS JOIN LATERAL jsonb_array_elements(l.payload->'external_inventory') x WHERE l.id=20161",
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
      "scope": "HISTORICAL_ASOF_P0_SNAPSHOT_READBACK",
      "limitations": "No current runtime invocations inferred"
    },
    {
      "id": "M05_Q04",
      "sql_literal": "SELECT count(*) total,count(*) FILTER(WHERE x->>'definition_md5' ~ '^[a-f0-9]{32}$') valid,count(*) FILTER(WHERE NOT(x->>'definition_md5' ~ '^[a-f0-9]{32}$')) invalid,count(*) FILTER(WHERE (x->>'definition_md5' ~ '^[a-f0-9]{32}$') IS NULL) unknown FROM public.lf_eventos l CROSS JOIN LATERAL jsonb_array_elements(l.payload->'sql_callers') x WHERE l.id=20161",
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
      "scope": "HISTORICAL_ASOF_P0_SNAPSHOT_READBACK",
      "limitations": "No current runtime invocations inferred"
    },
    {
      "id": "M05_Q05",
      "sql_literal": "WITH samples(v) AS (VALUES ('ACTIVE'::text),('INACTIVE'::text),(NULL::text)) SELECT count(*) total,count(*) FILTER (WHERE v='ACTIVE') t,count(*) FILTER (WHERE NOT(v='ACTIVE')) f,count(*) FILTER (WHERE (v='ACTIVE') IS NULL) n FROM samples",
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
      "scope": "EXPLICIT_SYNTHETIC_CONTRACT_NEGATIVES",
      "limitations": "No current runtime invocations inferred"
    },
    {
      "id": "M05_Q06",
      "sql_literal": "WITH examples(expected_n,observed_n) AS (VALUES (38,38),(38,37),(38,NULL::int)) SELECT expected_n,observed_n,(expected_n=observed_n) IS TRUE as accepted FROM examples ORDER BY observed_n NULLS LAST",
      "rows": [
        {
          "expected_n": 38,
          "observed_n": 37,
          "accepted": false
        },
        {
          "expected_n": 38,
          "observed_n": 38,
          "accepted": true
        },
        {
          "expected_n": 38,
          "observed_n": null,
          "accepted": false
        }
      ],
      "rows_returned": 3,
      "source": "SUPABASE_READ_ONLY",
      "scope": "EXPLICIT_SYNTHETIC_CONTRACT_NEGATIVES",
      "limitations": "No current runtime invocations inferred"
    },
    {
      "id": "M05_Q07",
      "sql_literal": "SELECT count(*) nominal_edges,count(DISTINCT (x->>'caller')||'->'||callee.name) distinct_edges,count(DISTINCT x->>'dedupe_key') caller_identities,count(DISTINCT callee.name) callee_names FROM public.lf_eventos l CROSS JOIN LATERAL jsonb_array_elements(l.payload->'sql_callers') x CROSS JOIN LATERAL jsonb_array_elements_text(x->'callees') callee(name) WHERE l.id=20161",
      "rows": [
        {
          "nominal_edges": 76,
          "distinct_edges": 76,
          "caller_identities": 38,
          "callee_names": 39
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_ASOF_P0_SNAPSHOT_READBACK",
      "limitations": "No current runtime invocations inferred"
    },
    {
      "id": "M05_Q08",
      "sql_literal": "SELECT jsonb_array_length(payload->'trigger_bindings') triggers,jsonb_array_length(payload->'consumer_relation_snapshot_json_rows') relation_snapshots,jsonb_array_length(payload->'external_inventory') external_assets,payload->'usage_stats' stats FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "triggers": 21,
          "relation_snapshots": 27,
          "external_assets": 6,
          "stats": {
            "ig_stat_rows": 0,
            "interpretation": "track_functions none means zero stat rows cannot prove no usage; static governed graph supplies inventory currentness",
            "track_functions": "none"
          }
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_ASOF_P0_SNAPSHOT_READBACK",
      "limitations": "No current runtime invocations inferred"
    },
    {
      "id": "M05_Q09",
      "sql_literal": "SELECT codigo,primera_vez,causa_raiz FROM transversal.error_knowledge WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001') AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z' ORDER BY codigo",
      "rows": [
        {
          "codigo": "IG-M107-CP2-READ-ROLE-CURRENTNESS-001",
          "primera_vez": "2026-10-14 23:44:24.874586+00",
          "causa_raiz": "Desalineación entre verificación CP2, autoridad histórica M9.11 y privilegios de lectura declarados."
        },
        {
          "codigo": "IG-M107-SOAK-CRITERION-DRIFT-001",
          "primera_vez": "2026-10-14 23:39:14.146551+00",
          "causa_raiz": "Desalineación de proyección textual del contrato M10.7 frente a la autoridad SOAK_OBSERVATION_HISTORY_V2 de M9.11."
        }
      ],
      "rows_returned": 2,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_ASOF_P0_SNAPSHOT_READBACK",
      "limitations": "No current runtime invocations inferred"
    },
    {
      "id": "M05_Q10",
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
      "scope": "HISTORICAL_ASOF_P0_SNAPSHOT_READBACK",
      "limitations": "No current runtime invocations inferred"
    },
    {
      "id": "M05_Q11",
      "sql_literal": "SELECT count(*) FILTER(WHERE created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z') within_cutoff,count(*) FILTER(WHERE created_at>=TIMESTAMPTZ '2026-10-15T00:00:00Z') after_cutoff FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "within_cutoff": 1,
          "after_cutoff": 0
        }
      ],
      "rows_returned": 1,
      "source": "SUPABASE_READ_ONLY",
      "scope": "HISTORICAL_ASOF_P0_SNAPSHOT_READBACK",
      "limitations": "No current runtime invocations inferred"
    },
    {
      "id": "M05_Q12",
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
      "scope": "TOOL_EXECUTION_IDENTITY_ONLY",
      "limitations": "No current runtime invocations inferred"
    }
  ],
  "algorithm_execution": {
    "C": {
      "module": "METAMORPHIC_AND_INVARIANT_VERIFICATION",
      "TLP_populations": {
        "sql_callers": {
          "total": 38,
          "t": 38,
          "f": 0,
          "n": 0,
          "deduplicated": 38
        },
        "external_inventory": {
          "total": 6,
          "t": 3,
          "f": 3,
          "n": 0
        },
        "definition_hashes": {
          "total": 38,
          "valid": 38,
          "invalid": 0,
          "unknown": 0
        },
        "synthetic_nullable_source": {
          "total": 3,
          "t": 1,
          "f": 1,
          "n": 1
        }
      },
      "source_declared_count": {
        "declared": "38",
        "observed": 38,
        "match": true
      },
      "negative_contract_cases": [
        {
          "expected_n": 38,
          "observed_n": 37,
          "accepted": false
        },
        {
          "expected_n": 38,
          "observed_n": 38,
          "accepted": true
        },
        {
          "expected_n": 38,
          "observed_n": null,
          "accepted": false
        }
      ],
      "nominal_graph": {
        "nominal_edges": 76,
        "distinct_edges": 76,
        "caller_identities": 38,
        "callee_names": 39
      },
      "valid_and_invalid_cases_count": 2,
      "null_denominator_rejected": true,
      "solver": "NOT_USED_NO_QED_OR_VERIEQL_ENGINE_AVAILABLE",
      "business_rule_proof": "NOT_DERIVED_FROM_TLP_ALONE"
    },
    "negative_tests": [
      {
        "id": "TLP_CALLERS_TRUE_FALSE_NULL",
        "pass": true
      },
      {
        "id": "TLP_EXTERNAL_TRUE_FALSE_NULL",
        "pass": true
      },
      {
        "id": "TLP_HASH_VALID_INVALID_UNKNOWN",
        "pass": true
      },
      {
        "id": "TLP_SYNTHETIC_NULL_EXERCISED",
        "pass": true
      },
      {
        "id": "SOURCE_DECLARED_COUNT_CONSISTENT",
        "pass": true
      },
      {
        "id": "INVARIANT_VALID_CASE_ACCEPTED",
        "pass": true
      },
      {
        "id": "INVARIANT_WRONG_COUNT_REJECTED",
        "pass": true
      },
      {
        "id": "INVARIANT_UNKNOWN_DENOMINATOR_REJECTED",
        "pass": true
      },
      {
        "id": "ASOF_NOT_PROMOTED_TO_CURRENT",
        "pass": true
      },
      {
        "id": "NO_UNSUPPORTED_SOLVER_ASSERTION",
        "pass": true
      }
    ]
  },
  "findings": [
    {
      "id": "M05-F01",
      "claim": "TLP partitions reconcile over the 38 historical SQL callers; no NULL in operational_class comparison. This is a consistency test on the snapshot, not live usage.",
      "evidence": [
        "M05_Q01",
        "M05_Q02"
      ],
      "scope": "MEASURED_HISTORICAL"
    },
    {
      "id": "M05-F02",
      "claim": "Six external inventory entries reconcile across TRUE/FALSE/NULL with explicit lifecycle distinction; do not sum with 38 SQL identities.",
      "evidence": [
        "M05_Q03",
        "M05_Q08"
      ],
      "scope": "MEASURED_HISTORICAL"
    },
    {
      "id": "M05-F03",
      "claim": "All 38 historical hash strings are format valid; method of hash construction is UNKNOWN.",
      "evidence": [
        "M05_Q04"
      ],
      "scope": "MEASURED_SYNTAX_ONLY"
    },
    {
      "id": "M05-F04",
      "claim": "Synthetic NULL TLP and valid/invalid count checks reject bad and unknown denominators, proving failure controls exercise negative cases.",
      "evidence": [
        "M05_Q05",
        "M05_Q06"
      ],
      "scope": "MEASURED_SYNTHETIC_SQL"
    },
    {
      "id": "M05-F05",
      "claim": "Historical 76 nominal directed edges to 39 callee names do not prove execution topology, and zero pg_stat rows with track_functions none do not prove no use.",
      "evidence": [
        "M05_Q07",
        "M05_Q08"
      ],
      "scope": "MEASURED_WITH_LIMITS"
    }
  ],
  "causal_model": {
    "status": "NOT_CAUSALLY_PROVEN",
    "hypotheses": [
      "Count/TLP drift may cause false inventory completeness",
      "Mixing distinct domains inflates consumer totals",
      "Historical hash validity mistaken for canonical hash derivation"
    ],
    "falsifiers": [
      "Qualified joined unique population at one cutoff",
      "Explicitly reproduced canonical hash generation",
      "Execution trace evidence for each named edge"
    ]
  },
  "candidate_repairs": [
    {
      "action": "Materialize 3VL and missing-identity partitions in coverage readbacks",
      "status": "PROPOSED_ONLY"
    },
    {
      "action": "Compare source-pinned edges with actual permitted invocation traces",
      "status": "PROPOSED_ONLY"
    }
  ],
  "chosen_repair": "VERIFY_FIRST_NO_PRODUCTION_CHANGE",
  "rejected_alternatives": [
    "TLP equivalence implies business correctness",
    "Invalid counts treated as accepted",
    "UNKNOWN treated as FALSE without explicit rule",
    "Invent QED/SMT solver run"
  ],
  "unresolved": [
    "Canonical definition_md5 source method",
    "Runtime call reachability",
    "E2E timing population and clocks",
    "Coverage beyond event 20161 source"
  ],
  "constraints_preserved": [
    "P0 source as-of cutoff",
    "No direct edits",
    "No runtime activation",
    "No inference of currentness",
    "No unsupported SMT claims"
  ],
  "conclusion": "C_ALGORITHM_MATERIAL_TESTS_COMPLETE_WITH_UNKNOWN_BUSINESS_CAUSES"
}
$m05_raw$;v_doc jsonb;
 v_ref text:='https://github.com/cristhianlujan/claude-persona-lf-patch/blob/b1f9fa790b21c6992c37387cee53279b60ab562c/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M05_RAW_V2.json#git_blob_sha=61fd9d1dfdc872464dc9b68f1aea1583e8f78b02';v_prev text:='chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M05.json#sha256=8fefae266b4b2279cb8d921dd4b2893ac607993fd38ae70c72d6f3f0bf050685';
 v_spec jsonb:=$m05_spec${"status":"READY","action_kind":"VERIFY_QUERY_ONCE","recipe_mode":"READBACK_EXACT","requires_material_execution":true,"contract_family":"PE10_METHOD_EXECUTION_EVIDENCE","precision":"PE10_METHOD_V1_MATERIAL_EVIDENCE","assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"checkpoint_identity":"PE10_M05","method_algorithm":"C","literal_sql_count":12,"metamorphic_negative_tests_passed":10,"tlp_sql_callers_partition_total":38,"tlp_external_partition_total":6,"synthetic_nullable_cases":3,"historical_source_event_id":20161,"git_source_verified":true,"runtime_modified":false}},"evidence_ref":"https://github.com/cristhianlujan/claude-persona-lf-patch/blob/b1f9fa790b21c6992c37387cee53279b60ab562c/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M05_RAW_V2.json#git_blob_sha=61fd9d1dfdc872464dc9b68f1aea1583e8f78b02","verification_queries":["SELECT count(*) total,count(*) FILTER(WHERE x->>'operational_class'='ACTIVE') t,count(*) FILTER(WHERE NOT(x->>'operational_class'='ACTIVE')) f,count(*) FILTER(WHERE (x->>'operational_class'='ACTIVE') IS NULL) n,count(DISTINCT x->>'dedupe_key') deduplicated FROM public.lf_eventos l CROSS JOIN LATERAL jsonb_array_elements(l.payload->'sql_callers') x WHERE l.id=20161","SELECT count(*) total,count(*) FILTER(WHERE x->>'operational_class'='ACTIVE') t,count(*) FILTER(WHERE NOT(x->>'operational_class'='ACTIVE')) f,count(*) FILTER(WHERE (x->>'operational_class'='ACTIVE') IS NULL) n FROM public.lf_eventos l CROSS JOIN LATERAL jsonb_array_elements(l.payload->'external_inventory') x WHERE l.id=20161","SELECT count(*) total,count(*) FILTER(WHERE x->>'definition_md5' ~ '^[a-f0-9]{32}$') valid,count(*) FILTER(WHERE NOT(x->>'definition_md5' ~ '^[a-f0-9]{32}$')) invalid,count(*) FILTER(WHERE (x->>'definition_md5' ~ '^[a-f0-9]{32}$') IS NULL) unknown FROM public.lf_eventos l CROSS JOIN LATERAL jsonb_array_elements(l.payload->'sql_callers') x WHERE l.id=20161","WITH samples(v) AS (VALUES ('ACTIVE'::text),('INACTIVE'::text),(NULL::text)) SELECT count(*) total,count(*) FILTER (WHERE v='ACTIVE') t,count(*) FILTER (WHERE NOT(v='ACTIVE')) f,count(*) FILTER (WHERE (v='ACTIVE') IS NULL) n FROM samples","WITH examples(expected_n,observed_n) AS (VALUES (38,38),(38,37),(38,NULL::int)) SELECT expected_n,observed_n,(expected_n=observed_n) IS TRUE as accepted FROM examples ORDER BY observed_n NULLS LAST","SELECT count(*) nominal_edges,count(DISTINCT (x->>'caller')||'->'||callee.name) distinct_edges,count(DISTINCT x->>'dedupe_key') caller_identities,count(DISTINCT callee.name) callee_names FROM public.lf_eventos l CROSS JOIN LATERAL jsonb_array_elements(l.payload->'sql_callers') x CROSS JOIN LATERAL jsonb_array_elements_text(x->'callees') callee(name) WHERE l.id=20161"],"expected":"SRCR + C TLP three-valued partition and positive/negative contract invariants; no SMT solver or business-correctness inference","forbidden":["TLP_AS_BUSINESS_RULE_PROOF","INVENT_SOLVER_EXECUTION","MARK_DONE_FROM_HASH_ONLY","ALTER_OTHER_CHECKPOINTS","USE_PAST_CUTOFF_AS_CURRENT"],"target":{"checkpoint":"PE10_M05","declared_events":[20161],"declared_objects":["public.lf_eventos","programacion.provenance_receipts","transversal.error_knowledge","programacion.engineering_work_checkpoints"],"evidence_artifacts":[{"path":"cristhianlujan/claude-persona-lf-patch:docs/profile_updater/experiments/pe10_methods32_p0/PE10_M05_RAW_V2.json","role":"EVIDENCE","purpose":"M05_C_ALGORITHM_EXECUTED_RAW_V2","target_kind":"EXACT_EXISTING_FILE"}]}}$m05_spec$::jsonb;
 v_blob text;v_q int;v_tests int;v_n int;v_ekb int;v_tri jsonb;v_contract jsonb;
 v_obs jsonb;v_result jsonb;v_assertion jsonb;v_transition jsonb;v_receipt text;
 v_msg text;v_ctx text;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
 AND target_code LIKE '%lf_pe10_m05_c_invariants_governed_close_v1'
 AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'M05_TRAIN_EXECUTION_ABSENT'; END IF;
 IF (SELECT status FROM programacion.engineering_work_items WHERE id=1133)<>'IN_PROGRESS'
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>4
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>28
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M05'
 AND status='PENDING' AND evidence_ref=v_prev AND assertion_receipt IS NULL AND completed_at IS NULL)<>1
 OR (SELECT count(*) FROM programacion.pe10_method_variants WHERE method_code='PE10_M05'
 AND case_ref='PE10-IG-M107-M109-P0' AND base_code='A'
 AND algorithm_codes=ARRAY['C']::text[])<>1
 OR (SELECT count(*) FROM programacion.engineering_plan_units WHERE work_item_id=1133
 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32'
 AND unit_metadata#>>'{action_specs_v1,PE10_M05,status}'='BLOCK_PENDING_MATERIAL_RESEARCH_AND_VALIDATION')<>1
 THEN RAISE EXCEPTION 'M05_PRESTATE_NOT_MATCHED'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=1133 AND checkpoint_code IN('PE10_M01','PE10_M02','PE10_M03','PE10_M04')
 AND status='DONE' AND assertion_receipt->>'passed'='true'
 AND assertion_contract_sha256=assertion_receipt->>'contract_sha256'
 AND assertion_receipt_sha256 IN (
 '1c174f3277f9656ffc4146c210ac64cd037fc92d4fb34d7a7959fe826e3f9b01',
 '0079973e1fec8787d2ef45d92131cad58bcb59f3c591aaf2badd8d86fe34c51b',
 '0cbbc9d58552b2c5ea3d2c9bca1b07c6467cd4145720905f38fc5bf07a46e2a1',
 '49ff7ae0d5966211ccb5a8caccc5718a61677c375a4a4a35c03e2bd6def7697e'))<>4
 THEN RAISE EXCEPTION 'M05_EARLIER_RECEIPTS_CHANGED'; END IF;

 v_blob:=encode(extensions.digest(convert_to('blob '||octet_length(convert_to(v_raw,'UTF8'))::text,'UTF8')
 ||decode('00','hex')||convert_to(v_raw,'UTF8'),'sha1'),'hex');
 IF v_blob<>'61fd9d1dfdc872464dc9b68f1aea1583e8f78b02' THEN RAISE EXCEPTION 'M05_GIT_BLOB_NOT_EXACT'; END IF;
 v_doc:=v_raw::jsonb;
 IF v_doc->>'schema'<>'PE10_METHOD_RAW_V2'
 OR v_doc->>'case_ref'<>'PE10-IG-M107-M109-P0'
 OR v_doc->>'method_code'<>'PE10_M05'
 OR v_doc->>'base_code'<>'A'
 OR v_doc->'algorithm_codes'<>'["C"]'::jsonb
 OR v_doc->>'source_cutoff'<>'2026-10-15T00:00:00Z'
 OR v_doc#>>'{original_preserved,sha256}'<>'8fefae266b4b2279cb8d921dd4b2893ac607993fd38ae70c72d6f3f0bf050685'
 OR v_doc->>'external_evaluation'<>'NOT_PERFORMED'
 OR v_doc->>'chosen_repair'<>'VERIFY_FIRST_NO_PRODUCTION_CHANGE'
 OR v_doc->>'conclusion'<>'C_ALGORITHM_MATERIAL_TESTS_COMPLETE_WITH_UNKNOWN_BUSINESS_CAUSES'
 THEN RAISE EXCEPTION 'M05_RAW_IDENTITY_FAILED'; END IF;
 SELECT count(*) INTO v_q FROM jsonb_array_elements(v_doc->'sql_evidence') e
 WHERE e->>'id' ~ '^M05_Q(0[1-9]|1[0-2])$'
 AND e->>'sql_literal' ~* '^SELECT |^WITH '
 AND e->>'source'='SUPABASE_READ_ONLY'
 AND jsonb_typeof(e->'rows')='array'
 AND (e->>'rows_returned')::int=jsonb_array_length(e->'rows')
 AND jsonb_array_length(e->'rows')>0;
 IF v_q<>12 OR jsonb_array_length(v_doc->'sql_evidence')<>12
 OR (SELECT count(DISTINCT e->>'id') FROM jsonb_array_elements(v_doc->'sql_evidence') e)<>12
 OR v_doc#>>'{sql_evidence,1,rows,0,total}'<>'38'
 OR v_doc#>>'{sql_evidence,2,rows,0,total}'<>'6'
 OR v_doc#>>'{sql_evidence,3,rows,0,valid}'<>'38'
 OR v_doc#>>'{sql_evidence,4,rows,0,n}'<>'1'
 OR v_doc#>>'{sql_evidence,6,rows,0,nominal_edges}'<>'76'
 THEN RAISE EXCEPTION 'M05_LITERAL_SQL_OR_READBACK_MISMATCH'; END IF;

 SELECT count(*) INTO v_tests FROM jsonb_array_elements(v_doc#>'{algorithm_execution,negative_tests}') t
 WHERE t->>'pass'='true';
 IF v_tests<>10 OR jsonb_array_length(v_doc#>'{algorithm_execution,negative_tests}')<>10
 OR v_doc#>>'{algorithm_execution,C,solver}'<>'NOT_USED_NO_QED_OR_VERIEQL_ENGINE_AVAILABLE'
 OR v_doc#>>'{algorithm_execution,C,business_rule_proof}'<>'NOT_DERIVED_FROM_TLP_ALONE'
 OR v_doc#>>'{algorithm_execution,C,TLP_populations,sql_callers,total}'<>'38'
 OR v_doc#>>'{algorithm_execution,C,TLP_populations,external_inventory,total}'<>'6'
 OR v_doc#>>'{algorithm_execution,C,TLP_populations,synthetic_nullable_source,n}'<>'1'
 OR jsonb_array_length(v_doc#>'{algorithm_execution,C,negative_contract_cases}')<>3
 THEN RAISE EXCEPTION 'M05_C_ALGORITHM_POSITIVE_NEGATIVE_TESTS_MISSING'; END IF;
 SELECT count(*) INTO v_ekb FROM transversal.error_knowledge WHERE codigo IN
 ('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001')
 AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z';
 IF v_ekb<>2
 OR (SELECT count(*) FROM public.lf_eventos WHERE id=20161
 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'
 AND jsonb_array_length(payload->'sql_callers')=38
 AND jsonb_array_length(payload->'external_inventory')=6)<>1
 OR (SELECT count(*) FROM programacion.provenance_receipts WHERE id=38
 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z' AND payload->>'verification_status'='VERIFIED')<>1
 THEN RAISE EXCEPTION 'M05_ASOF_AUTHORITIES_MISMATCH'; END IF;

 UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10_M05}',v_spec,true)
 WHERE work_item_id=1133 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32';
 GET DIAGNOSTICS v_n=ROW_COUNT;
 IF v_n<>1 THEN RAISE EXCEPTION 'M05_ACTION_SPEC_WRITE_COUNT'; END IF;
 v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M05',
 programacion.fn_engineering_checkpoint_action_spec_v3('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M05'));
 IF v_contract->>'status'<>'READY' OR v_contract->>'mode'<>'EXPLICIT_PASS_WHEN_SUBSET'
 THEN RAISE EXCEPTION 'M05_CONTRACT_NOT_READY:%',coalesce(v_contract::text,'NULL'); END IF;
 v_obs:=jsonb_build_object('checkpoint_identity','PE10_M05','method_algorithm','C','literal_sql_count',12,
 'metamorphic_negative_tests_passed',10,'tlp_sql_callers_partition_total',38,
 'tlp_external_partition_total',6,'synthetic_nullable_cases',3,
 'historical_source_event_id',20161,'git_source_verified',true,'runtime_modified',false);
 v_result:=jsonb_build_object('status','PASS','observed',v_obs,'evidence_ref',v_ref,
 'validation_kind','METHOD_C_TLP_METAMORPHIC_MATERIAL_EVIDENCE',
 'business_rule_proof','NOT_INFERRED','solver_execution','NOT_PERFORMED');
 v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M05',v_result,v_exec);
 IF v_assertion->>'passed'<>'true' OR coalesce(v_assertion->>'assertion_receipt_sha256','') !~ '^[a-f0-9]{64}$'
 THEN RAISE EXCEPTION 'M05_CANONICAL_ASSERTION_NOT_PASSED'; END IF;
 v_receipt:=v_assertion->>'assertion_receipt_sha256';
 v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M05','DONE',v_ref,v_exec,
 'M05 C method TLP and contract positive/negative invariants source-verified; no product change');
 IF v_transition#>>'{transition,status}'<>'APPLIED'
 THEN RAISE EXCEPTION 'M05_CANONICAL_TRANSITION_NOT_APPLIED'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133
 AND checkpoint_code='PE10_M05' AND status='DONE' AND completed_at IS NOT NULL
 AND evidence_ref=v_ref AND assertion_receipt_sha256=v_receipt
 AND assertion_contract_sha256=assertion_receipt->>'contract_sha256' AND assertion_receipt->>'passed'='true')<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>5
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>27
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=1133 AND checkpoint_code='PE10_M06' AND status='PENDING')<>1
 THEN RAISE EXCEPTION 'M05_FINAL_READBACK_FAILED'; END IF;
EXCEPTION WHEN OTHERS THEN
 GET STACKED DIAGNOSTICS v_msg=MESSAGE_TEXT,v_ctx=PG_EXCEPTION_CONTEXT;
 RAISE EXCEPTION 'M05_TRAIN_ROOT_CAUSE state=% msg=% context=%',SQLSTATE,left(v_msg,280),left(v_ctx,160) USING ERRCODE=SQLSTATE;
END $m05_close$;
