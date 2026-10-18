-- PE10 M01: close one material researched method, no rerun of original, no other checkpoint.
-- Train-only source-first. Original SHA-256 58667ea7e8abec32c52e1495cff2eb9c6da1b8c62dce10cbc6464071cc04bc96; source blob 6867e4b299d0e6763dbf3eeb1530cbde7e52d3f2.
DO $m01_close$
DECLARE
 v_exec text;
 v_raw text := $m01_raw${
  "schema": "PE10_METHOD_RAW_V2",
  "method_code": "PE10_M01",
  "case_ref": "PE10-IG-M107-M109-P0",
  "base_code": "A",
  "algorithm_codes": [],
  "source_cutoff": "2026-10-15T00:00:00Z",
  "scope": "HISTORICAL_READ_ONLY_NO_REPAIR",
  "method_contract": "PE10_METHOD_V1 SRCR_BASELINE",
  "original_raw_preserved": {
    "path": "chatgpt-file://file_000000004e48820e8414025654581746/prior_originals/PE10_M01_RAW.json",
    "sha256": "58667ea7e8abec32c52e1495cff2eb9c6da1b8c62dce10cbc6464071cc04bc96",
    "note": "The prior original remains unchanged; verified material readback here is additive, not a replacement or new blinded method sample."
  },
  "producer": "GPT-6 current read-only source verification of original M01 historical claims",
  "run_mode": "ONE_METHOD_ONLY_SRCR_BASELINE",
  "method_evaluation": "NOT_PERFORMED; no cross-method scoring",
  "sql_evidence": [
    {
      "id": "M01_R01",
      "sql_literal": "SELECT id,created_at,payload->>'evidence_schema_version' evidence_schema,payload->>'acceptance_declared' acceptance_declared,payload->>'source_pack_version' source_pack,payload->>'fetch_spec_version' fetch_spec FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "id": 20161,
          "created_at": "2026-10-04 05:14:40.880842+00",
          "evidence_schema": "operational-event/v2",
          "acceptance_declared": "false",
          "source_pack": "SOURCE_PACK_V1",
          "fetch_spec": "SOURCE_PACK_LOOKUP_V2"
        }
      ],
      "row_count": 1,
      "source": "SUPABASE_READ_ONLY",
      "observed_at_utc": "2026-10-18T08:25:19.512Z",
      "evidence_time_basis": "HISTORICAL_P0_SOURCE_TIME"
    },
    {
      "id": "M01_R02",
      "sql_literal": "SELECT jsonb_array_length(l.payload->'sql_callers') inventory_count,count(DISTINCT e->>'caller') unique_callers,count(*) FILTER(WHERE e->>'definition_md5' IS NULL) missing_digest,count(*) FILTER(WHERE e->>'operational_class' IS NULL) missing_class FROM public.lf_eventos l CROSS JOIN LATERAL jsonb_array_elements(l.payload->'sql_callers') e WHERE l.id=20161 GROUP BY l.payload->'sql_callers'",
      "rows": [
        {
          "inventory_count": 38,
          "unique_callers": 38,
          "missing_digest": 0,
          "missing_class": 0
        }
      ],
      "row_count": 1,
      "source": "SUPABASE_READ_ONLY",
      "observed_at_utc": "2026-10-18T08:25:19.993Z",
      "evidence_time_basis": "HISTORICAL_P0_SOURCE_TIME"
    },
    {
      "id": "M01_R03",
      "sql_literal": "SELECT e->>'operational_class' category,e->>'currentness_source' source,count(*) n FROM public.lf_eventos l CROSS JOIN LATERAL jsonb_array_elements(l.payload->'sql_callers') e WHERE l.id=20161 GROUP BY 1,2 ORDER BY 1,2",
      "rows": [
        {
          "category": "ACTIVE",
          "source": "LIVE_PG_PROC",
          "n": 38
        }
      ],
      "row_count": 1,
      "source": "SUPABASE_READ_ONLY",
      "observed_at_utc": "2026-10-18T08:25:21.895Z",
      "evidence_time_basis": "HISTORICAL_P0_SOURCE_TIME"
    },
    {
      "id": "M01_R04",
      "sql_literal": "SELECT codigo,primera_vez,ultima_vez,causa_raiz,prevencion,validacion FROM transversal.error_knowledge WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001') AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z' ORDER BY codigo",
      "rows": [
        {
          "codigo": "IG-M107-CP2-READ-ROLE-CURRENTNESS-001",
          "primera_vez": "2026-10-14 23:44:24.874586+00",
          "ultima_vez": "2026-10-14 23:44:24.874586+00",
          "causa_raiz": "Desalineación entre verificación CP2, autoridad histórica M9.11 y privilegios de lectura declarados.",
          "prevencion": "Leer EKB y action_spec. No elevar EXECUTE ni crear motor. Reusar recibo verificado SOAK_OBSERVATION_HISTORY_V2 y revisar la cohorte mediante tablas con SELECT autorizado. Considerar recuentos brutos como evidencia complementaria, nunca sustituto de as-of. Rectificar únicamente queries CP2.",
          "validacion": "2026-10-14: Q1 receipt 38 PASS, Q2 cohort PASS_OBSERVED 13/13 screens, 47 families, 199 completed runs. SQL 42501 reproducido. Migración revierte primer ensayo y lee CP2 DONE, otros tres pendientes sin autorizar producción."
        },
        {
          "codigo": "IG-M107-SOAK-CRITERION-DRIFT-001",
          "primera_vez": "2026-10-14 23:39:14.146551+00",
          "ultima_vez": "2026-10-14 23:39:14.146551+00",
          "causa_raiz": "Desalineación de proyección textual del contrato M10.7 frente a la autoridad SOAK_OBSERVATION_HISTORY_V2 de M9.11.",
          "prevencion": "Antes de CP1 leer M9.11 DONE y el recibo VERIFIED; heredar >=2 as-of, 0 falsos PASS y 0 D4. Reusar historia. No convertir 13/47 en obligación de nuevas corridas ni confundir latest CURRENT con validez histórica. Confirmar los checkpoints posteriores por su naturaleza.",
          "validacion": "Read-only 2026-10-14: receipt 38 13/13 screens,47/47 families, zero below-2, false_pass=0,D4=0; tres negativos sintéticos rechazados. Migración prueba rollback y comprueba CP1 DONE/CP2 PENDING, sin activar producción."
        }
      ],
      "row_count": 2,
      "source": "SUPABASE_READ_ONLY",
      "observed_at_utc": "2026-10-18T08:25:22.414Z",
      "evidence_time_basis": "HISTORICAL_P0_SOURCE_TIME"
    },
    {
      "id": "M01_R05",
      "sql_literal": "SELECT payload->'deduplication' deduplication,payload->'usage_stats' usage_stats,payload->'scope_guards' scope_guards,payload->'m03_baseline' m03_baseline FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "deduplication": {
            "rule": "One logical caller identity per source URI/object identity; evidence from multiple governed sources is merged instead of double-counted.",
            "router_identity": "PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1 maps to live SQL lf_ops.fn_lf_router_input_governance_resolve_v1.",
            "profiles_edge_identity": "EDGE_FN_LF_PROFILES_GOVERNANCE_CALLER_V1 maps to live Edge lf-profiles-governance-caller-v1."
          },
          "usage_stats": {
            "ig_stat_rows": 0,
            "interpretation": "track_functions none means zero stat rows cannot prove no usage; static governed graph supplies inventory currentness",
            "track_functions": "none"
          },
          "scope_guards": {
            "callers_retired": false,
            "m10_10_executed": false,
            "callers_modified": false,
            "production_change": false,
            "runtime_activation": false,
            "n13_n14_n15_changed": false
          },
          "m03_baseline": {
            "seed_count": 109,
            "evidence_pr": 1318,
            "scope_count": 118,
            "graph_sha256": "b55f76227fa15f08b7b1de8f2da776bde36fb7d26bc50b96765005b9cc318c3c",
            "close_event_id": 19567,
            "merge_commit_sha": "375d803de434fb5be69513694bd7f839533ca84e",
            "trigger_bindings": 21,
            "readback_event_id": 19566,
            "internal_sql_edges": 262,
            "constraint_bindings": 5,
            "incoming_boundary_edges": 33,
            "outgoing_boundary_edges": 2
          }
        }
      ],
      "row_count": 1,
      "source": "SUPABASE_READ_ONLY",
      "observed_at_utc": "2026-10-18T08:25:23.043Z",
      "evidence_time_basis": "HISTORICAL_P0_SOURCE_TIME"
    },
    {
      "id": "M01_R06",
      "sql_literal": "SELECT jsonb_typeof(payload->'external_inventory') external_type,jsonb_typeof(payload->'contract_snapshot_json_rows') contract_type,payload->>'sql_caller_count' declared_sql_callers,payload->>'unexplained_material_callers' unexplained_material_callers,payload->'historical_callers_confirmed' historical_callers_confirmed FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "external_type": "array",
          "contract_type": "array",
          "declared_sql_callers": "38",
          "unexplained_material_callers": "0",
          "historical_callers_confirmed": []
        }
      ],
      "row_count": 1,
      "source": "SUPABASE_READ_ONLY",
      "observed_at_utc": "2026-10-18T08:25:23.537Z",
      "evidence_time_basis": "HISTORICAL_P0_SOURCE_TIME"
    },
    {
      "id": "M01_R07",
      "sql_literal": "SELECT count(*) inventory_count,count(*) FILTER(WHERE (e->>'definition_md5') ~ '^[0-9a-f]{32}$') md5_valid,count(*) FILTER(WHERE e->>'definition_md5' IS NULL) md5_null,count(*) FILTER(WHERE (e->>'definition_md5') !~ '^[0-9a-f]{32}$') md5_bad,count(DISTINCT e->>'definition_md5') unique_hashes,count(*) FILTER(WHERE jsonb_typeof(e->'callees')<>'array') bad_callees FROM public.lf_eventos l CROSS JOIN LATERAL jsonb_array_elements(l.payload->'sql_callers') e WHERE l.id=20161",
      "rows": [
        {
          "inventory_count": 38,
          "md5_valid": 38,
          "md5_null": 0,
          "md5_bad": 0,
          "unique_hashes": 38,
          "bad_callees": 0
        }
      ],
      "row_count": 1,
      "source": "SUPABASE_READ_ONLY",
      "observed_at_utc": "2026-10-18T08:25:24.042Z",
      "evidence_time_basis": "HISTORICAL_P0_SOURCE_TIME"
    },
    {
      "id": "M01_R08",
      "sql_literal": "SELECT e->>'caller' caller,jsonb_array_length(e->'callees') callee_count,e->>'provenance' provenance FROM public.lf_eventos l CROSS JOIN LATERAL jsonb_array_elements(l.payload->'sql_callers') e WHERE l.id=20161 ORDER BY callee_count DESC,caller LIMIT 10",
      "rows": [
        {
          "caller": "programacion.fn_input_governance_curator_materialize_v1",
          "callee_count": 5,
          "provenance": "preferred_input/SOURCE_PACK_LOOKUP_V2"
        },
        {
          "caller": "programacion.fn_input_governance_curator_rebind_v1",
          "callee_count": 4,
          "provenance": "preferred_input/SOURCE_PACK_LOOKUP_V2"
        },
        {
          "caller": "programacion.fn_input_governance_execute",
          "callee_count": 4,
          "provenance": "preferred_input/SOURCE_PACK_LOOKUP_V2"
        },
        {
          "caller": "programacion.fn_input_governance_recurate_v2",
          "callee_count": 4,
          "provenance": "preferred_input/SOURCE_PACK_LOOKUP_V2"
        },
        {
          "caller": "programacion.fn_input_governance_shadow_evaluate_v2",
          "callee_count": 4,
          "provenance": "preferred_input/SOURCE_PACK_LOOKUP_V2"
        },
        {
          "caller": "programacion.fn_input_governance_validate_v2",
          "callee_count": 4,
          "provenance": "preferred_input/SOURCE_PACK_LOOKUP_V2"
        },
        {
          "caller": "programacion.fn_input_governance_bootstrap_materialize_v2",
          "callee_count": 3,
          "provenance": "preferred_input/SOURCE_PACK_LOOKUP_V2"
        },
        {
          "caller": "programacion.fn_input_governance_bootstrap_validate_v1",
          "callee_count": 3,
          "provenance": "preferred_input/SOURCE_PACK_LOOKUP_V2"
        },
        {
          "caller": "programacion.fn_input_governance_semantic_probe_v3",
          "callee_count": 3,
          "provenance": "preferred_input/SOURCE_PACK_LOOKUP_V2"
        },
        {
          "caller": "programacion.fn_input_governance_semantic_probe_v3_cached_v1",
          "callee_count": 3,
          "provenance": "preferred_input/SOURCE_PACK_LOOKUP_V2"
        }
      ],
      "row_count": 10,
      "source": "SUPABASE_READ_ONLY",
      "observed_at_utc": "2026-10-18T08:25:24.549Z",
      "evidence_time_basis": "HISTORICAL_P0_SOURCE_TIME"
    },
    {
      "id": "M01_R09",
      "sql_literal": "SELECT id,created_at,receipt_kind,subject_ref,payload->>'verification_status' verification_status,payload->>'pass' historical_pass,payload->>'screens_total' screens_total,payload->>'families_total' families_total,payload->>'known_false_pass_signals' false_pass,payload->>'unresolved_d4' unresolved_d4 FROM programacion.provenance_receipts WHERE id=38 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'",
      "rows": [
        {
          "id": 38,
          "created_at": "2026-10-07 16:01:00.760627+00",
          "receipt_kind": "EVIDENCE_VERIFICATION",
          "subject_ref": "plan://IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.11/SOAK_OBSERVATION_HISTORY_V2",
          "verification_status": "VERIFIED",
          "historical_pass": "true",
          "screens_total": "13",
          "families_total": "47",
          "false_pass": "0",
          "unresolved_d4": "0"
        }
      ],
      "row_count": 1,
      "source": "SUPABASE_READ_ONLY",
      "observed_at_utc": "2026-10-18T08:25:25.021Z",
      "evidence_time_basis": "HISTORICAL_P0_SOURCE_TIME"
    },
    {
      "id": "M01_R10",
      "sql_literal": "SELECT current_user role,current_setting('transaction_read_only') read_only,current_setting('request.jwt.claim.role',true) jwt_role",
      "rows": [
        {
          "role": "supabase_read_only_user",
          "read_only": "on",
          "jwt_role": null
        }
      ],
      "row_count": 1,
      "source": "SUPABASE_READ_ONLY",
      "observed_at_utc": "2026-10-18T08:25:25.587Z",
      "evidence_time_basis": "QUERY_EXECUTION_TIME_ONLY"
    }
  ],
  "findings": [
    {
      "id": "M01_F01",
      "claim": "38 unique named historical SQL callers and 38/38 format-valid md5 literals were observed in event 20161; these counts attest source metadata, not a current-world caller inventory.",
      "evidence": [
        "M01_R01",
        "M01_R02",
        "M01_R03",
        "M01_R07"
      ],
      "scope": "MEASURED_HISTORICAL"
    },
    {
      "id": "M01_F02",
      "claim": "At historical event 20161 track_functions=none, so zero stat rows cannot establish zero function use or improved speed; no E2E benchmark follows from the inventory.",
      "evidence": [
        "M01_R05"
      ],
      "scope": "MEASURED_WITH_LOGICAL_LIMIT"
    },
    {
      "id": "M01_F03",
      "claim": "Two pre-cutoff EKB entries identify a soak-criterion drift risk and CP2 privilege/currentness problem. A 42501 permission denial is not functional test failure; later remediation is not implied.",
      "evidence": [
        "M01_R04",
        "M01_R10"
      ],
      "scope": "MEASURED_HISTORICAL_EKB"
    },
    {
      "id": "M01_F04",
      "claim": "Historical receipt 38 is a separate M9.11 soak evidence, which cannot certify M03 or LF runtime timing; do not substitute last 13 for whole longitudinal series.",
      "evidence": [
        "M01_R09",
        "M01_R04"
      ],
      "scope": "MEASURED_HISTORICAL_RECEIPT"
    },
    {
      "id": "M01_F05",
      "claim": "Baseline scope and SQL edges have a different population from 38 listed callers; counts must not be added to invent unique coverage.",
      "evidence": [
        "M01_R05",
        "M01_R06"
      ],
      "scope": "MEASURED_POPULATION_NOT_EQUIVALENCE"
    }
  ],
  "causal_model": {
    "status": "HYPOTHESES_NOT_CAUSALLY_PROVEN",
    "alternatives": [
      "Stale source-time caller classification can look CURRENT when reused after capture",
      "Historical SOAK reduced to latest-only window creates false acceptances",
      "Read authority 42501 can mask data access without demonstrating a functional error",
      "Non-equivalent population denominators can fabricate apparent performance improvement"
    ],
    "falsifiers": [
      "Find versioned source under target cutoff inconsistent with snapshot identities",
      "Show actual qualified longitudinal soak receipt and negative controls",
      "Prove equivalent authorized CP2 read path or exact privileged operation context"
    ]
  },
  "candidate_repairs": [
    {
      "mode": "VERIFY_FIRST",
      "action": "Use source-pinned historical caller identities and time-qualified M9.11 receipts, then a separately labeled CURRENT readback if required",
      "implementation": "NOT_PERFORMED"
    }
  ],
  "chosen_repair": "VERIFY_FIRST",
  "rejected_alternatives": [
    "Grant unnecessary EXECUTE to bypass read-only role",
    "Treat zero usage stats as no calls",
    "Treat event MD5 format as canonical hash derivation",
    "Alter runtime or retire cached functions without live corroboration"
  ],
  "omissions_searched": [
    "historical snapshot metadata",
    "caller identity/count",
    "hash syntax and NULL classification",
    "sampled caller edges",
    "EKB/permission",
    "soak source receipt",
    "population denominators",
    "telemetry absence"
  ],
  "negative_tests": [
    {
      "test": "HASH_PARTITION",
      "observed": "valid=38,null=0,invalid=0,total=38",
      "pass": true
    },
    {
      "test": "REJECT_CURRENTNESS_PROMOTION",
      "pass": true,
      "evidence": "Historical event source date before P0 cutoff and no same-clock CURRENT source included; conclusion scoped as historical"
    },
    {
      "test": "REJECT_ZERO_USE_INFERENCE",
      "pass": true,
      "evidence": "Historical usage_stats.track_functions=none"
    },
    {
      "test": "REJECT_SOAK_AS_PERFORMANCE",
      "pass": true,
      "evidence": "M9.11 receipt has soak scope, not E2E timing"
    }
  ],
  "constraints_preserved": [
    "LF only",
    "P0 cutoff 2026-10-15",
    "One method only, no other method findings",
    "No runtime or permission mutations",
    "Original RAW bytes preserved",
    "No external evaluator judgment"
  ],
  "unresolved": [
    "Source-side canonical hash serialization UNKNOWN",
    "Exact target-cutoff caller currentness UNKNOWN",
    "Comparable end-to-end performance and stage costs UNKNOWN",
    "Business repair not executed or judged"
  ],
  "investigation_result": "RAW_RESEARCH_EVIDENCE_VERIFIED_ORIGINAL_PRESERVED",
  "next_safe_step": "Freeze original-associated SQL readback and execute governed material assertion/transition via Train, without domain claim"
}
$m01_raw$;
 v_doc jsonb;
 v_blob text;
 v_ref text:='https://github.com/cristhianlujan/claude-persona-lf-patch/blob/3be90aefcd3f48c5ce3c0bac5a3573149eda6bf9/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M01_RAW_V2.json#git_blob_sha=6867e4b299d0e6763dbf3eeb1530cbde7e52d3f2';
 v_original text:='chatgpt-file://file_000000004e48820e8414025654581746/prior_originals/PE10_M01_RAW.json#sha256=58667ea7e8abec32c52e1495cff2eb9c6da1b8c62dce10cbc6464071cc04bc96';
 v_spec jsonb:=$m01_spec${"status":"READY","action_kind":"VERIFY_QUERY_ONCE","recipe_mode":"READBACK_EXACT","requires_material_execution":true,"contract_family":"PE10_METHOD_EXECUTION_EVIDENCE","precision":"PE10_METHOD_V1_MATERIAL_EVIDENCE","assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"checkpoint_identity":"PE10_M01","method_algorithm":"SRCR_BASELINE","literal_sql_count":10,"negative_tests_passed":4,"historical_source_event_id":20161,"original_sha256_preserved":true,"source_is_historical":true,"runtime_modified":false}},"evidence_ref":"https://github.com/cristhianlujan/claude-persona-lf-patch/blob/3be90aefcd3f48c5ce3c0bac5a3573149eda6bf9/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M01_RAW_V2.json#git_blob_sha=6867e4b299d0e6763dbf3eeb1530cbde7e52d3f2","verification_queries":["SELECT jsonb_array_length(l.payload->'sql_callers') inventory_count,count(DISTINCT e->>'caller') unique_callers,count(*) FILTER(WHERE e->>'definition_md5' IS NULL) missing_digest,count(*) FILTER(WHERE e->>'operational_class' IS NULL) missing_class FROM public.lf_eventos l CROSS JOIN LATERAL jsonb_array_elements(l.payload->'sql_callers') e WHERE l.id=20161 GROUP BY l.payload->'sql_callers'","SELECT codigo,primera_vez,ultima_vez,causa_raiz,prevencion,validacion FROM transversal.error_knowledge WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001') AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z' ORDER BY codigo","SELECT payload->'deduplication' deduplication,payload->'usage_stats' usage_stats,payload->'scope_guards' scope_guards,payload->'m03_baseline' m03_baseline FROM public.lf_eventos WHERE id=20161","SELECT count(*) inventory_count,count(*) FILTER(WHERE (e->>'definition_md5') ~ '^[0-9a-f]{32}$') md5_valid,count(*) FILTER(WHERE e->>'definition_md5' IS NULL) md5_null,count(*) FILTER(WHERE (e->>'definition_md5') !~ '^[0-9a-f]{32}$') md5_bad,count(DISTINCT e->>'definition_md5') unique_hashes,count(*) FILTER(WHERE jsonb_typeof(e->'callees')<>'array') bad_callees FROM public.lf_eventos l CROSS JOIN LATERAL jsonb_array_elements(l.payload->'sql_callers') e WHERE l.id=20161","SELECT id,created_at,receipt_kind,subject_ref,payload->>'verification_status' verification_status,payload->>'pass' historical_pass,payload->>'screens_total' screens_total,payload->>'families_total' families_total,payload->>'known_false_pass_signals' false_pass,payload->>'unresolved_d4' unresolved_d4 FROM programacion.provenance_receipts WHERE id=38 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'"],"expected":"Existing baseline SRCR original verified with 10 read-only SQL literal results; no external method correctness evaluation; no production change","forbidden":["SOURCE_CURRENTNESS_REWIND","TREAT_SHA_AS_A_METHOD_PASS","REPLACE_ORIGINAL_RAW","SKIP_CANONICAL_RECEIPT"],"target":{"checkpoint":"PE10_M01","declared_events":[20161],"declared_objects":["public.lf_eventos","programacion.provenance_receipts","transversal.error_knowledge","programacion.engineering_work_checkpoints"],"evidence_artifacts":[{"path":"cristhianlujan/claude-persona-lf-patch:docs/profile_updater/experiments/pe10_methods32_p0/PE10_M01_RAW_V2.json","role":"EVIDENCE","purpose":"ORIGINAL_PRESERVING_VERIFIED_RAW_V2","target_kind":"EXACT_EXISTING_FILE"}]}}$m01_spec$::jsonb;
 v_contract jsonb;
 v_qcount int;
 v_negcount int;
 v_n int;
 v_caller_count int;
 v_valid_md5 int;
 v_ekb int;
 v_soak text;
 v_observed jsonb;
 v_result jsonb;
 v_assertion jsonb;
 v_transition jsonb;
 v_receipt_sha text;
 v_dbg_msg text;
 v_dbg_context text;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF'
 AND target_type='MIGRATION'
 AND target_code LIKE '%lf_pe10_m01_original_verified_close_v1'
 AND status='IN_PROGRESS'
 ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'PE10_M01_TRAIN_EXECUTION_ABSENT'; END IF;
 IF (SELECT status FROM programacion.engineering_work_items WHERE id=1133)<>'IN_PROGRESS'
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>31
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M01'
   AND status='PENDING' AND evidence_ref='chatgpt-file://file_000000004e48820e8414025654581746/prior_originals/PE10_M01_RAW.json#sha256=58667ea7e8abec32c52e1495cff2eb9c6da1b8c62dce10cbc6464071cc04bc96' AND assertion_receipt IS NULL)<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M03'
   AND status='DONE' AND assertion_receipt_sha256='0cbbc9d58552b2c5ea3d2c9bca1b07c6467cd4145720905f38fc5bf07a46e2a1')<>1
 OR (SELECT count(*) FROM programacion.engineering_plan_units WHERE work_item_id=1133
 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32' AND disposition='ASSIGNED'
 AND unit_metadata->>'checkpoint_ordering'='INDEPENDENT_METHOD_VARIANTS')<>1
 OR (SELECT unit_metadata#>>'{action_specs_v1,PE10_M01,status}' FROM programacion.engineering_plan_units WHERE work_item_id=1133)<>'BLOCK_PENDING_MATERIAL_RESEARCH_AND_VALIDATION'
 THEN RAISE EXCEPTION 'PE10_M01_PRESTATE_DRIFT'; END IF;

 v_blob:=encode(extensions.digest(convert_to('blob '||octet_length(convert_to(v_raw,'UTF8'))::text,'UTF8')
 ||decode('00','hex')||convert_to(v_raw,'UTF8'),'sha1'),'hex');
 IF v_blob<>'6867e4b299d0e6763dbf3eeb1530cbde7e52d3f2' THEN RAISE EXCEPTION 'PE10_M01_RAW_GIT_BLOB_MISMATCH'; END IF;
 v_doc:=v_raw::jsonb;
 IF v_doc->>'schema'<>'PE10_METHOD_RAW_V2'
 OR v_doc->>'case_ref'<>'PE10-IG-M107-M109-P0'
 OR v_doc->>'method_code'<>'PE10_M01'
 OR v_doc->>'base_code'<>'A'
 OR v_doc->'algorithm_codes'<>'[]'::jsonb
 OR v_doc#>>'{original_raw_preserved,sha256}'<>'58667ea7e8abec32c52e1495cff2eb9c6da1b8c62dce10cbc6464071cc04bc96'
 OR v_doc->>'source_cutoff'<>'2026-10-15T00:00:00Z'
 OR v_doc->>'method_evaluation' IS NULL
 THEN RAISE EXCEPTION 'PE10_M01_RAW_IDENTITY_INVALID'; END IF;
 SELECT count(*) INTO v_qcount FROM jsonb_array_elements(v_doc->'sql_evidence') e
 WHERE e->>'id' ~ '^M01_R[0-9]{2}$'
 AND e->>'sql_literal' ~* '^SELECT '
 AND e->>'source'='SUPABASE_READ_ONLY'
 AND NOT e ? 'error'
 AND jsonb_typeof(e->'rows')='array'
 AND jsonb_array_length(e->'rows')>0
 AND (e->>'row_count')::int=jsonb_array_length(e->'rows');
 IF v_qcount<>10 OR jsonb_array_length(v_doc->'sql_evidence')<>10
 OR (SELECT count(DISTINCT e->>'id') FROM jsonb_array_elements(v_doc->'sql_evidence') e)<>10
 THEN RAISE EXCEPTION 'PE10_M01_RAW_SQL_INCOMPLETE'; END IF;

 SELECT count(*) INTO v_negcount FROM jsonb_array_elements(v_doc->'negative_tests') x WHERE x->>'pass'='true';
 IF v_negcount<>4 OR jsonb_array_length(v_doc->'negative_tests')<>4
 OR v_doc#>>'{sql_evidence,1,rows,0,inventory_count}'<>'38'
 OR v_doc#>>'{sql_evidence,6,rows,0,md5_valid}'<>'38'
 OR v_doc#>>'{sql_evidence,6,rows,0,md5_null}'<>'0'
 OR v_doc#>>'{sql_evidence,6,rows,0,md5_bad}'<>'0'
 OR v_doc#>>'{sql_evidence,8,rows,0,verification_status}'<>'VERIFIED'
 THEN RAISE EXCEPTION 'PE10_M01_NEGATIVE_OR_SOURCE_READBACK_FAILED'; END IF;

 SELECT jsonb_array_length(payload->'sql_callers') INTO v_caller_count
 FROM public.lf_eventos WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15 00:00:00+00';
 SELECT count(*) INTO v_valid_md5
 FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') j
 WHERE e.id=20161 AND j->>'definition_md5' ~ '^[a-f0-9]{32}$';
 SELECT count(*) INTO v_ekb FROM transversal.error_knowledge
 WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001')
 AND primera_vez<TIMESTAMPTZ '2026-10-15 00:00:00+00';
 SELECT payload->>'verification_status' INTO v_soak FROM programacion.provenance_receipts
 WHERE id=38 AND created_at<TIMESTAMPTZ '2026-10-15 00:00:00+00';
 IF v_caller_count<>38 OR v_valid_md5<>38 OR v_ekb<>2 OR v_soak<>'VERIFIED'
 THEN RAISE EXCEPTION 'PE10_M01_LIVE_READ_OF_HISTORICAL_SOURCE_MISMATCH'; END IF;
 UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10_M01}',v_spec,true)
 WHERE work_item_id=1133 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32';
 GET DIAGNOSTICS v_n=ROW_COUNT;
 IF v_n<>1 THEN RAISE EXCEPTION 'PE10_M01_SPEC_PATCH_COUNT'; END IF;
 IF (SELECT unit_metadata#>>'{action_specs_v1,PE10_M03,status}' FROM programacion.engineering_plan_units WHERE work_item_id=1133)<>'READY'
 THEN RAISE EXCEPTION 'PE10_M01_M03_SPEC_COLLATERAL_DRIFT'; END IF;

 v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M01',
 programacion.fn_engineering_checkpoint_action_spec_v3('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M01'));
 IF v_contract->>'status'<>'READY' OR v_contract->>'mode'<>'EXPLICIT_PASS_WHEN_SUBSET'
 THEN RAISE EXCEPTION 'PE10_M01_ASSERTION_CONTRACT_NOT_READY:%',coalesce(v_contract::text,'NULL'); END IF;
 v_observed:=jsonb_build_object('checkpoint_identity','PE10_M01','method_algorithm','SRCR_BASELINE',
 'literal_sql_count',v_qcount,'negative_tests_passed',v_negcount,'historical_source_event_id',20161,
 'original_sha256_preserved',true,'source_is_historical',true,'runtime_modified',false);
 v_result:=jsonb_build_object('status','PASS','observed',v_observed,'evidence_ref',v_ref,
 'verification_kind','HISTORICAL_METHOD_RESEARCH_MATERIALITY_ONLY','external_evaluation','NOT_PERFORMED');
 v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M01',v_result,v_exec);
 IF v_assertion->>'passed'<>'true'
 OR coalesce(v_assertion->>'assertion_receipt_sha256','') !~ '^[a-f0-9]{64}$'
 THEN RAISE EXCEPTION 'PE10_M01_ASSERTION_NOT_RECORDED'; END IF;
 v_receipt_sha:=v_assertion->>'assertion_receipt_sha256';
 v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M01','DONE',v_ref,v_exec,
 'PE10_M01 original-preserving baseline research verified through Train; no runtime repair asserted');
 IF v_transition#>>'{transition,status}'<>'APPLIED' THEN RAISE EXCEPTION 'PE10_M01_TRANSITION_NOT_APPLIED'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1133 AND checkpoint_code='PE10_M01'
     AND status='DONE' AND evidence_ref=v_ref
     AND assertion_receipt_sha256=v_receipt_sha
     AND assertion_contract_sha256=assertion_receipt->>'contract_sha256'
     AND assertion_receipt->>'passed'='true'
     AND completed_at IS NOT NULL)<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>2
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>30
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M02' AND status='PENDING')<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M03' AND status='DONE' AND assertion_receipt_sha256='0cbbc9d58552b2c5ea3d2c9bca1b07c6467cd4145720905f38fc5bf07a46e2a1')<>1
 THEN RAISE EXCEPTION 'PE10_M01_POSTSTATE_READBACK_FAILED'; END IF;
EXCEPTION WHEN OTHERS THEN
 GET STACKED DIAGNOSTICS v_dbg_msg=MESSAGE_TEXT,v_dbg_context=PG_EXCEPTION_CONTEXT;
 RAISE EXCEPTION 'PE10_M01_CLOSE_CAUSE state=% msg=% context=%',SQLSTATE,left(v_dbg_msg,280),left(v_dbg_context,180) USING ERRCODE=SQLSTATE;
END $m01_close$;
