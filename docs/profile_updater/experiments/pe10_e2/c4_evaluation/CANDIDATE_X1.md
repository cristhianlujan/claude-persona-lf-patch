# CANDIDATE X1

Case: PE10-IG-M107-M109-P0 (same case for every candidate). Pair P: the two candidates of a pair come from the same method family; their order is randomized.
Content below is verbatim producer output; nothing was edited.

### ROLE REPORT: ARCHITECTURE

{
  "schema": "PE10_M18_ROLE_RAW_V1",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M18",
  "role_code": "ARCHITECTURE",
  "base_code": "B",
  "algorithm_codes": ["D"],
  "source_cutoff": "2026-10-15T00:00:00Z",
  "role_bound_single_context": true,
  "autonomous_agent_claim": false,
  "cross_method_inputs_used": false,
  "method_application": {
    "D": {
      "gde_conflict_sets": [
        {
          "id": "ARQ_CS1",
          "observation": "Historical snapshot labels callers LIVE_PG_PROC while 22/38 current names have no empirical md5(prosrc) match to historical definition_md5.",
          "components": ["snapshot_freshness", "post_snapshot_function_definition_change", "historical_hash_representation_unknown"]
        },
        {
          "id": "ARQ_CS2",
          "observation": "All 21 historical trigger bindings still exist with the same trigger->function name mapping.",
          "components": ["broad_trigger_topology_drift", "trigger_function_rebinding"]
        }
      ],
      "minimal_hitting_sets": [
        ["snapshot_freshness"],
        ["post_snapshot_function_definition_change"],
        ["historical_hash_representation_unknown"]
      ],
      "barinel": {
        "status": "NOT_CALIBRATED",
        "reason": "No executable pass/fail spectrum with justified priors and component traces was available; probabilities would be fabricated."
      },
      "information_gain": {
        "mode": "ORDINAL_DISCRIMINATION_COST",
        "highest_value_next_query": "Inspect changed current function bodies only for material callee-path changes against historical callees, while preserving historical/current separation.",
        "reason": "This distinguishes harmless implementation drift from changed dependency topology at lower cost than broad database re-inventory."
      }
    }
  },
  "queries": [
    {
      "id": "M18_ARQ_Q1",
      "scope": "P0_HISTORICAL",
      "sql": "SELECT id, created_at, jsonb_object_keys(payload) AS payload_key FROM public.lf_eventos WHERE id=20161 ORDER BY payload_key;",
      "result_summary": "Event 20161 exists at 2026-10-04 05:14:40.880842+00 and exposes caller, trigger, external inventory, usage, scope and provenance fields."
    },
    {
      "id": "M18_ARQ_Q2",
      "scope": "P0_HISTORICAL",
      "sql": "SELECT jsonb_pretty(payload->'sql_callers'->0) AS first_caller, jsonb_pretty(payload->'trigger_bindings'->0) AS first_trigger, jsonb_pretty(payload->'external_inventory'->0) AS first_external, jsonb_pretty(payload->'usage_stats') AS usage_stats, jsonb_pretty(payload->'scope_guards') AS scope_guards FROM public.lf_eventos WHERE id=20161;",
      "result_summary": "Historical caller rows include caller, callees, caller_oid, definition_md5, operational_class and currentness_source; usage_stats says track_functions=none and zero stat rows cannot prove no usage; scope_guards says no production/runtime changes."
    },
    {
      "id": "M18_ARQ_Q3",
      "scope": "P0_HISTORICAL_PLUS_EXPLICIT_CURRENT_READBACK",
      "sql": "WITH e AS (SELECT payload FROM public.lf_eventos WHERE id=20161), callers AS (SELECT x->>'caller' caller,x->>'definition_md5' historical_md5,x->>'operational_class' operational_class,x->>'currentness_source' source_label,x->'callees' callees FROM e,jsonb_array_elements(payload->'sql_callers') x), live AS (SELECT n.nspname||'.'||p.proname caller,count(*) overloads,array_agg(md5(p.prosrc) ORDER BY p.oid) current_prosrc_md5 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace GROUP BY 1) SELECT count(*) snapshot_rows,count(DISTINCT c.caller) unique_callers,sum(jsonb_array_length(c.callees)) lexical_edges,count(*) FILTER (WHERE l.caller IS NULL) absent_current_names,count(*) FILTER (WHERE l.caller IS NOT NULL AND c.historical_md5=ANY(l.current_prosrc_md5)) at_least_one_current_hash_match,count(*) FILTER (WHERE l.caller IS NOT NULL AND NOT(c.historical_md5=ANY(l.current_prosrc_md5))) current_name_but_hash_changed FROM callers c LEFT JOIN live l USING(caller);",
      "result_summary": "38 snapshot rows, 38 unique callers, 76 lexical edges, 0 absent current names, 16 empirical historical/current md5(prosrc) matches and 22 current names with changed empirical hash."
    },
    {
      "id": "M18_ARQ_Q4",
      "scope": "P0_HISTORICAL_PLUS_EXPLICIT_CURRENT_READBACK",
      "sql": "Compare event 20161 trigger_bindings by table_name+trigger_name with current pg_trigger and trigger function identity.",
      "result_summary": "21 historical trigger rows; 21 exact current trigger matches; 0 missing trigger bindings; 0 trigger-function name mismatches."
    },
    {
      "id": "M18_ARQ_Q5",
      "scope": "P0_HISTORICAL",
      "sql": "Expand event 20161 external_inventory and count rows/distinct dedupe_key.",
      "result_summary": "6 external rows and 6 unique external dedupe keys spanning ACTIVE/CANDIDATE/CANDIDATE_TEST and multiple governance lifecycle states."
    }
  ],
  "findings": [
    {
      "id": "M18_ARQ_F1",
      "claim": "The historical SQL caller identity set remains name-resolvable today, but the snapshot cannot certify current function definitions: 22/38 caller names have a different empirical md5(prosrc) than the historical definition_md5.",
      "classification": "MEASURED_CURRENT_COMPARISON_WITH_HISTORICAL_LIMIT",
      "evidence_refs": ["M18_ARQ_Q3"],
      "confidence": "HIGH",
      "impact": "HIGH",
      "new_vs_input": true,
      "limit": "The historical hash construction method is not proven canonical by this comparison; matching is empirical only."
    },
    {
      "id": "M18_ARQ_F2",
      "claim": "Broad trigger-binding drift is falsified at current name/function mapping level for the 21 bindings in the snapshot.",
      "classification": "MEASURED_CURRENT_COMPARISON",
      "evidence_refs": ["M18_ARQ_Q4"],
      "confidence": "HIGH",
      "impact": "MEDIUM",
      "new_vs_input": true
    },
    {
      "id": "M18_ARQ_F3",
      "claim": "The six external inventory entries form a separate identity/lifecycle domain; no evidence here justifies adding them to the 38 SQL-caller denominator.",
      "classification": "MEASURED_HISTORICAL_SCOPE",
      "evidence_refs": ["M18_ARQ_Q5"],
      "confidence": "HIGH",
      "impact": "MEDIUM",
      "new_vs_input": false
    }
  ],
  "negative_falsifiers": [
    {
      "id": "M18_ARQ_N1",
      "hypothesis": "Most historical caller names disappeared from current pg_proc.",
      "result": "FALSIFIED",
      "evidence_refs": ["M18_ARQ_Q3"]
    },
    {
      "id": "M18_ARQ_N2",
      "hypothesis": "Trigger rebinding is the dominant topology drift visible from the P0 trigger set.",
      "result": "FALSIFIED",
      "evidence_refs": ["M18_ARQ_Q4"]
    },
    {
      "id": "M18_ARQ_N3",
      "hypothesis": "Historical definition_md5 equals md5(prosrc) by proven canonical contract.",
      "result": "NOT_PROVEN",
      "evidence_refs": ["M18_ARQ_Q3"]
    }
  ],
  "causal_hypothesis": {
    "state": "PARTIAL",
    "claim": "A material false-currentness risk exists because function definitions changed after the historical snapshot while caller identities and trigger bindings largely persisted. Whether those changes alter the relevant dependency paths remains unproven."
  },
  "minimal_safe_action": "Inspect only the 22 changed current bodies for material changes in the historical callee relations before any live-topology or optimization conclusion.",
  "unresolved": [
    "Canonical historical hash-construction method",
    "Whether any of the 22 changed bodies altered relevant callee paths",
    "Runtime execution frequency of the 38 callers"
  ],
  "constraints_preserved": [
    "READ_ONLY",
    "No production mutation",
    "Historical/current separation",
    "No peer role reports used",
    "No external evaluation",
    "No autonomous-agent claim"
  ],
  "measured_costs": {
    "sql_observations": 5,
    "transport_elapsed_ms": "NOT_MEASURED",
    "barinel_calibration": "NOT_AVAILABLE"
  },
  "role_output_frozen": true
}

### ROLE REPORT: PERFORMANCE

{
  "schema": "PE10_M18_ROLE_RAW_V1",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M18",
  "role_code": "PERFORMANCE",
  "base_code": "B",
  "algorithm_codes": ["D"],
  "source_cutoff": "2026-10-15T00:00:00Z",
  "role_bound_single_context": true,
  "autonomous_agent_claim": false,
  "cross_method_inputs_used": false,
  "method_application": {
    "D": {
      "gde_conflict_sets": [
        {
          "id": "PERF_CS1",
          "observation": "Event 20161 contains no top-level timing keys and track_functions=none, while input_readiness_runs contains stage duration fields.",
          "components": ["evidence_source_selection", "missing_function_stats", "stage_duration_instrumentation"]
        },
        {
          "id": "PERF_CS2",
          "observation": "Latest pre-cutoff revisions 5.13 and 5.13.1 have overlapping screens but materially different stage-duration distributions and zero-duration prevalence.",
          "components": ["cohort_equivalence", "revision_effect", "zero_duration_semantics", "workload_effect"]
        }
      ],
      "minimal_hitting_sets": [
        ["cohort_equivalence"],
        ["revision_effect"],
        ["zero_duration_semantics"],
        ["workload_effect"]
      ],
      "barinel": {
        "status": "NOT_CALIBRATED",
        "reason": "No justified component spectra with independent pass/fail outcome probabilities; ranking by likelihood would be fabricated."
      },
      "information_gain": {
        "mode": "ORDINAL_DISCRIMINATION_COST",
        "selected_query": "Compare 5.13 vs 5.13.1 on overlapping pantalla_id and constant family_count before any aggregate speed conclusion.",
        "reason": "It directly tests cohort mismatch at low read-only cost."
      }
    }
  },
  "queries": [
    {
      "id": "M18_PERF_Q1",
      "scope": "P0_HISTORICAL",
      "result_summary": "Event 20161 usage_stats has track_functions=none, ig_stat_rows=0, and no top-level timing/duration/elapsed/latency keys."
    },
    {
      "id": "M18_PERF_Q2",
      "scope": "P0_HISTORICAL",
      "result_summary": "Provenance receipt 38 is VERIFIED for SOAK quality history: 13 screens, 47 families, zero known false PASS signals and zero unresolved D4; it contains no latency distribution."
    },
    {
      "id": "M18_PERF_Q3",
      "scope": "EXPLICIT_CURRENT_TABLE_WITH_PRE_CUTOFF_ROWS",
      "result_summary": "ig_direct_requests_v1 has six rows before cutoff with e2e_ms from 46,596.626 to 322,785.297; consumers are STORY_CREATOR/MANUAL and last_status is BLOCKED, so they are not a qualified Curator/Validator benchmark cohort."
    },
    {
      "id": "M18_PERF_Q4",
      "scope": "CURRENT_READBACK",
      "result_summary": "current_setting('track_functions')=none; curator/validator-related pg_stat_user_functions call/total/self times are NULL. Missing stats cannot support zero-usage or speed claims."
    },
    {
      "id": "M18_PERF_Q5",
      "scope": "SCHEMA_READBACK",
      "result_summary": "input_readiness_runs contains curator_completed_at, validator_completed_at, curator_duration_ms and validator_duration_ms, allowing direct pre-cutoff stage analysis."
    },
    {
      "id": "M18_PERF_Q6",
      "scope": "PRE_CUTOFF_MEASURED",
      "result_summary": "255 runs before cutoff; curator duration known in 248 and validator in 233. Zero durations: curator 75, validator 99. Positive-only p50/p90: curator 28,148/115,850.6 ms; validator 78,758.5/257,428.6 ms."
    },
    {
      "id": "M18_PERF_Q7",
      "scope": "PRE_CUTOFF_MEASURED",
      "result_summary": "By status: BLOCKED=20 (validator durations all NULL), COMPLETED=233 (curator zero=75, validator zero=99), CURATING=2 (both durations NULL)."
    },
    {
      "id": "M18_PERF_Q8",
      "scope": "PRE_CUTOFF_MEASURED",
      "result_summary": "For COMPLETED zero-duration rows, wall-clock deltas computed from stage timestamps are also exactly 0 ms; zero values are internally timestamp-consistent, not demonstrably corrupted."
    },
    {
      "id": "M18_PERF_Q9",
      "scope": "PRE_CUTOFF_MEASURED",
      "result_summary": "Contract revisions vary sharply. Revision 5.13: 86 completed, curator positive p50/p90 23,915/45,223 ms, validator 69,597/155,020.2 ms. Revision 5.13.1: 20 completed, curator 60,257.5/136,648.4 ms, validator 246,293/408,971.6 ms; zero counts also differ."
    },
    {
      "id": "M18_PERF_Q10",
      "scope": "PRE_CUTOFF_MATCHED_SCREEN_CHECK",
      "result_summary": "5.13 covers 42 screens, 5.13.1 covers 16, all 16 overlap and family_count remains 47 in shown rows. Many overlapping screens have higher positive stage medians in 5.13.1, but per-screen n is often 1-2 and zero-duration handling differs."
    }
  ],
  "findings": [
    {
      "id": "M18_PERF_F1",
      "claim": "Event 20161 and pg_stat_user_functions cannot substantiate a speed claim; function statistics are unavailable because track_functions=none.",
      "classification": "MEASURED_SOURCE_LIMIT",
      "evidence_refs": ["M18_PERF_Q1","M18_PERF_Q4"],
      "confidence": "HIGH",
      "impact": "HIGH",
      "new_vs_input": true
    },
    {
      "id": "M18_PERF_F2",
      "claim": "Pre-cutoff input_readiness_runs contains usable stage-duration evidence, but aggregate comparison is confounded by revision mix and a large exact-zero cohort.",
      "classification": "MEASURED_WITH_COHORT_LIMIT",
      "evidence_refs": ["M18_PERF_Q6","M18_PERF_Q7","M18_PERF_Q8","M18_PERF_Q9"],
      "confidence": "HIGH",
      "impact": "HIGH",
      "new_vs_input": true
    },
    {
      "id": "M18_PERF_F3",
      "claim": "A naive latest-revision improvement claim is not supported: on the 16 overlapping screens, 5.13.1 commonly shows larger positive stage times than 5.13, but sample sizes and zero-duration handling prevent a causal regression conclusion.",
      "classification": "MEASURED_DIRECTION_WITH_CAUSAL_LIMIT",
      "evidence_refs": ["M18_PERF_Q9","M18_PERF_Q10"],
      "confidence": "MEDIUM_HIGH",
      "impact": "HIGH",
      "new_vs_input": true
    },
    {
      "id": "M18_PERF_F4",
      "claim": "SOAK receipt 38 certifies quality-history conditions, not end-to-end or stage latency.",
      "classification": "MEASURED_SCOPE",
      "evidence_refs": ["M18_PERF_Q2"],
      "confidence": "HIGH",
      "impact": "MEDIUM",
      "new_vs_input": false
    }
  ],
  "negative_falsifiers": [
    {
      "id": "M18_PERF_N1",
      "hypothesis": "Zero pg_stat rows prove no Curator/Validator calls.",
      "result": "FALSIFIED_AS_INFERENCE",
      "evidence_refs": ["M18_PERF_Q1","M18_PERF_Q4"]
    },
    {
      "id": "M18_PERF_N2",
      "hypothesis": "Zero duration rows are demonstrably inconsistent with their timestamps.",
      "result": "FALSIFIED",
      "evidence_refs": ["M18_PERF_Q8"]
    },
    {
      "id": "M18_PERF_N3",
      "hypothesis": "Receipt 38 is a performance receipt.",
      "result": "FALSIFIED",
      "evidence_refs": ["M18_PERF_Q2"]
    },
    {
      "id": "M18_PERF_N4",
      "hypothesis": "5.13 and 5.13.1 are fully equivalent cohorts.",
      "result": "FALSIFIED",
      "evidence_refs": ["M18_PERF_Q9","M18_PERF_Q10"]
    }
  ],
  "causal_hypothesis": {
    "state": "UNPROVEN",
    "alternatives": [
      "Actual stage regression in 5.13.1",
      "Different execution path or workload despite same family_count",
      "Instrumentation/zero-duration semantics changed across revisions",
      "Selection bias from only 16 overlapping screens and low per-screen n"
    ]
  },
  "minimal_safe_action": "Build a same-screen, same-path, same-revision-transition cohort using only positive qualified durations and explicitly model zero-duration semantics before accepting or rejecting the performance optimization.",
  "unresolved": [
    "Semantic meaning of exact-zero stage durations by revision",
    "Whether 5.13.1 changed execution path or only instrumentation",
    "Qualified end-to-end denominator linked to the same Curator/Validator runs",
    "Statistical significance with matched repeated observations"
  ],
  "constraints_preserved": [
    "READ_ONLY",
    "No production mutation",
    "Historical/current separation",
    "No peer role reports used",
    "No external evaluation",
    "No false BARINEL probabilities"
  ],
  "measured_costs": {
    "sql_observations": 10,
    "transport_elapsed_ms": "NOT_MEASURED",
    "barinel_calibration": "NOT_AVAILABLE"
  },
  "role_output_frozen": true
}

### ROLE REPORT: AUTHORITY

{
  "schema": "PE10_M18_ROLE_RAW_V1",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M18",
  "role_code": "AUTHORITY",
  "base_code": "B",
  "algorithm_codes": ["D"],
  "source_cutoff": "2026-10-15T00:00:00Z",
  "role_bound_single_context": true,
  "autonomous_agent_claim": false,
  "cross_method_inputs_used": false,
  "method_application": {
    "D": {
      "gde_conflict_sets": [
        {
          "id": "AUTH_CS1",
          "observation": "CP2 historical EKB records SQLSTATE 42501 on fn_input_readiness_run_is_current while the read-only principal has SELECT on the underlying evidence tables but no EXECUTE on either current function variant.",
          "components": ["unauthorized_function_readback", "authority_boundary", "wrong_evidence_path"]
        },
        {
          "id": "AUTH_CS2",
          "observation": "SOAK canonical receipt 38 verifies historical criteria, while CP2 EKB explicitly rejects latest-13 CURRENT as historical substitute.",
          "components": ["historical_authority_source", "currentness_projection", "cohort_substitution"]
        }
      ],
      "minimal_hitting_sets": [
        ["wrong_evidence_path"],
        ["unauthorized_function_readback"],
        ["cohort_substitution"]
      ],
      "barinel": {
        "status": "NOT_CALIBRATED",
        "reason": "No independent executable test spectrum with justified priors exists for authority-failure components."
      },
      "information_gain": {
        "mode": "ORDINAL_DISCRIMINATION_COST",
        "highest_value_next_query": "Reconstruct CP2 evidence only from authorized SELECT tables/receipts and compare it with the exact historical receipt contract, without invoking the forbidden currentness function.",
        "reason": "It discriminates data insufficiency from access-path error without privilege elevation."
      }
    }
  },
  "queries": [
    {
      "id": "M18_AUTH_Q1",
      "scope": "P0_HISTORICAL",
      "result_summary": "Both EKB records are pre-cutoff and VALIDATED_TESTED. CP2 record says the currentness function readback failed with SQLSTATE 42501 and latest-13 is not equivalent to historical as-of; prevention explicitly says do not elevate EXECUTE. SOAK drift record requires >=2 eligible observations, zero false PASS and zero D4 from receipt 38."
    },
    {
      "id": "M18_AUTH_Q2",
      "scope": "P0_HISTORICAL",
      "result_summary": "Receipt 38 created 2026-10-07 is VERIFIED SOAK_OBSERVATION_HISTORY_V2 with 13 screens, 47 families, zero below-2, zero known false PASS and zero unresolved D4."
    },
    {
      "id": "M18_AUTH_Q3",
      "scope": "CURRENT_IDENTITY_READBACK",
      "result_summary": "current_user=session_user=supabase_read_only_user; transaction_read_only=on; track_functions=none."
    },
    {
      "id": "M18_AUTH_Q4",
      "scope": "CURRENT_PRIVILEGE_READBACK",
      "result_summary": "Two current fn_input_readiness_run_is_current(bigint) variants resolve in programacion and public; current read-only principal has EXECUTE=false on both."
    },
    {
      "id": "M18_AUTH_Q5",
      "scope": "CURRENT_CHECKPOINT_READBACK",
      "result_summary": "M17 remains DONE with governed receipt; M18 remains PENDING with no assertion receipt/completed_at; M19 remains PENDING."
    },
    {
      "id": "M18_AUTH_Q6",
      "scope": "CURRENT_PRIVILEGE_READBACK",
      "result_summary": "Current read-only principal has programacion USAGE and SELECT on input_readiness_runs, provenance_receipts and transversal.error_knowledge."
    }
  ],
  "findings": [
    {
      "id": "M18_AUTH_F1",
      "claim": "The observed 42501 is an authority/readback-path condition, not evidence of a functional CP2 defect. The permitted connector still lacks EXECUTE on both currentness-function variants while retaining SELECT on the evidence tables.",
      "classification": "MEASURED_HISTORICAL_AND_CURRENT_AUTHORITY",
      "evidence_refs": ["M18_AUTH_Q1","M18_AUTH_Q3","M18_AUTH_Q4","M18_AUTH_Q6"],
      "confidence": "HIGH",
      "impact": "HIGH",
      "new_vs_input": true
    },
    {
      "id": "M18_AUTH_F2",
      "claim": "Receipt 38 is the authoritative historical SOAK source for the stated criteria; a latest CURRENT sample cannot substitute for it.",
      "classification": "MEASURED_HISTORICAL_AUTHORITY",
      "evidence_refs": ["M18_AUTH_Q1","M18_AUTH_Q2"],
      "confidence": "HIGH",
      "impact": "HIGH",
      "new_vs_input": false
    },
    {
      "id": "M18_AUTH_F3",
      "claim": "No privilege elevation is needed to continue safe evidence review: required historical/current records are readable by SELECT while the forbidden function remains non-executable.",
      "classification": "MEASURED_CURRENT_BOUNDARY",
      "evidence_refs": ["M18_AUTH_Q4","M18_AUTH_Q6"],
      "confidence": "HIGH",
      "impact": "MEDIUM",
      "new_vs_input": true
    },
    {
      "id": "M18_AUTH_F4",
      "claim": "Administrative experiment state is still open at this role freeze: M18 has no governed assertion receipt and is not DONE.",
      "classification": "MEASURED_CURRENT_STATE",
      "evidence_refs": ["M18_AUTH_Q5"],
      "confidence": "HIGH",
      "impact": "MEDIUM",
      "new_vs_input": true
    }
  ],
  "negative_falsifiers": [
    {
      "id": "M18_AUTH_N1",
      "hypothesis": "The read-only connector currently has EXECUTE on fn_input_readiness_run_is_current.",
      "result": "FALSIFIED",
      "evidence_refs": ["M18_AUTH_Q4"]
    },
    {
      "id": "M18_AUTH_N2",
      "hypothesis": "Lack of EXECUTE prevents all relevant CP2 evidence reads.",
      "result": "FALSIFIED",
      "evidence_refs": ["M18_AUTH_Q6"]
    },
    {
      "id": "M18_AUTH_N3",
      "hypothesis": "Receipt 38 proves current CP2 functionality.",
      "result": "FALSIFIED_AS_SCOPE_INFERENCE",
      "evidence_refs": ["M18_AUTH_Q1","M18_AUTH_Q2"]
    },
    {
      "id": "M18_AUTH_N4",
      "hypothesis": "M18 can already be represented as governed DONE.",
      "result": "FALSIFIED",
      "evidence_refs": ["M18_AUTH_Q5"]
    }
  ],
  "causal_hypothesis": {
    "state": "PARTIAL",
    "claim": "The known CP2 evidence gap is best explained by an unauthorized readback choice plus temporal-cohort substitution, not by demonstrated Curator/Validator functional failure."
  },
  "minimal_safe_action": "Use receipt 38 and authorized SELECT-only cohort tables for CP2 reconstruction; do not elevate EXECUTE and do not convert current permission state into historical proof.",
  "unresolved": [
    "Equivalent CP2 functional result under an authorized evidence-only query contract",
    "Historical grants beyond what the pre-cutoff EKB validation records",
    "Whether any later authorized CP2 evidence materially changes the diagnosis"
  ],
  "constraints_preserved": [
    "READ_ONLY",
    "No privilege elevation",
    "No production mutation",
    "Historical/current separation",
    "No peer role reports used",
    "No autonomous-agent claim"
  ],
  "measured_costs": {
    "sql_observations": 6,
    "transport_elapsed_ms": "NOT_MEASURED",
    "barinel_calibration": "NOT_AVAILABLE"
  },
  "role_output_frozen": true
}

### ROLE REPORT: COVERAGE

{
  "schema": "PE10_M18_ROLE_RAW_V1",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M18",
  "role_code": "COVERAGE",
  "base_code": "B",
  "algorithm_codes": ["D"],
  "source_cutoff": "2026-10-15T00:00:00Z",
  "role_bound_single_context": true,
  "autonomous_agent_claim": false,
  "cross_method_inputs_used": false,
  "method_application": {
    "D": {
      "gde_conflict_sets": [
        {
          "id": "COVER_CS1",
          "observation": "The historical snapshot is internally complete for its declared arrays, but 6 of 39 unqualified callee tokens resolve to multiple current schemas.",
          "components": ["callee_identity_qualification", "wrapper_duplication", "topology_resolution"]
        },
        {
          "id": "COVER_CS2",
          "observation": "Current name-pattern search finds 64 functions not in the historical caller identity set, but name-pattern membership does not establish caller status or historical omission.",
          "components": ["population_complement", "caller_classification", "post_snapshot_objects"]
        }
      ],
      "minimal_hitting_sets": [
        ["callee_identity_qualification"],
        ["caller_classification"],
        ["post_snapshot_objects"]
      ],
      "barinel": {
        "status": "NOT_CALIBRATED",
        "reason": "No pass/fail component spectrum or justified priors exist for completeness defects."
      },
      "information_gain": {
        "mode": "ORDINAL_DISCRIMINATION_COST",
        "highest_value_next_query": "Resolve the six ambiguous callee tokens by caller-body/schema context, then classify current complement candidates by actual references rather than names.",
        "reason": "This attacks denominator and topology ambiguity without inflating the inventory."
      }
    }
  },
  "queries": [
    {
      "id": "M18_COVER_Q1",
      "scope": "P0_HISTORICAL",
      "result_summary": "Declared sql_caller_count=38 equals actual array length 38; declared trigger_binding_count=21 equals actual 21; external inventory=6; unexplained_material_callers=0; one ambiguous-name candidate was checked and excluded."
    },
    {
      "id": "M18_COVER_Q2",
      "scope": "P0_HISTORICAL",
      "result_summary": "38/38 caller identities are distinct; zero missing caller/hash/class/currentness fields; all callees are arrays; all 38 definition_md5 values are syntactically valid 32-char lowercase hex; 76 callee edges."
    },
    {
      "id": "M18_COVER_Q3",
      "scope": "HISTORICAL_TOKENS_PLUS_CURRENT_NAME_RESOLUTION",
      "result_summary": "39 unique historical callee tokens; 0 unresolved by current proname; 33 have one current name candidate and 6 are ambiguous across multiple schemas: curator_materialize_v1, execute, safe_autofix_v1, validator_validate_v1, worker_spec and input_readiness_run_is_current."
    },
    {
      "id": "M18_COVER_Q4",
      "scope": "P0_HISTORICAL",
      "result_summary": "The snapshot records one excluded candidate as NOT_IG_CALLER, explicit deduplication rules, zero unexplained material callers, and no historical_callers_confirmed entries."
    },
    {
      "id": "M18_COVER_Q5",
      "scope": "P0_HISTORICAL",
      "result_summary": "SQL inventory has 38 rows/38 unique names; external inventory has 6 rows/6 unique dedupe keys; exact raw-name overlap between the two sets is zero."
    },
    {
      "id": "M18_COVER_Q6",
      "scope": "CURRENT_COMPLEMENT_DISCOVERY",
      "result_summary": "95 current functions in programacion/public/lf_ops match input_governance|input_readiness|guard_input; 31 are historical caller identities and 64 are not. The 64 are complement candidates only, not proven callers or historical omissions."
    },
    {
      "id": "M18_COVER_Q7",
      "scope": "P0_HISTORICAL",
      "result_summary": "76 historical edge rows have zero duplicate caller+callee pairs; 21 trigger rows have 21 unique dedupe keys; all 6 external entries contain required identity/class/lifecycle fields."
    }
  ],
  "findings": [
    {
      "id": "M18_COVER_F1",
      "claim": "The event-20161 inventory is internally self-consistent for its declared population: counts reconcile, required caller fields are populated, hash syntax is valid, and no duplicate caller-callee edge pairs were found.",
      "classification": "MEASURED_HISTORICAL_INTERNAL_INTEGRITY",
      "evidence_refs": ["M18_COVER_Q1","M18_COVER_Q2","M18_COVER_Q7"],
      "confidence": "HIGH",
      "impact": "MEDIUM",
      "new_vs_input": true
    },
    {
      "id": "M18_COVER_F2",
      "claim": "Historical callee identities are not fully schema-qualified: 6/39 callee tokens currently have multiple schema candidates, so name-only topology reconstruction can select the wrong object.",
      "classification": "MEASURED_CURRENT_RESOLUTION_RISK",
      "evidence_refs": ["M18_COVER_Q3"],
      "confidence": "HIGH",
      "impact": "HIGH",
      "new_vs_input": true
    },
    {
      "id": "M18_COVER_F3",
      "claim": "The six external records should remain a separate identity/lifecycle set unless a proven mapping exists; raw-name overlap with the SQL caller set is zero and the snapshot defines separate dedupe identities.",
      "classification": "MEASURED_HISTORICAL_SCOPE",
      "evidence_refs": ["M18_COVER_Q4","M18_COVER_Q5"],
      "confidence": "HIGH",
      "impact": "MEDIUM",
      "new_vs_input": true
    },
    {
      "id": "M18_COVER_F4",
      "claim": "Current complement discovery finds 64 name-pattern functions outside the historical caller set, but this is not evidence that 64 callers were omitted. Each candidate needs actual reference/lifecycle classification.",
      "classification": "MEASURED_CURRENT_COMPLEMENT_WITH_CLASSIFICATION_LIMIT",
      "evidence_refs": ["M18_COVER_Q6"],
      "confidence": "HIGH",
      "impact": "HIGH",
      "new_vs_input": true
    }
  ],
  "negative_falsifiers": [
    {
      "id": "M18_COVER_N1",
      "hypothesis": "The 38-row snapshot contains duplicate caller identities or malformed/missing definition_md5 fields.",
      "result": "FALSIFIED",
      "evidence_refs": ["M18_COVER_Q2"]
    },
    {
      "id": "M18_COVER_N2",
      "hypothesis": "All historical callee tokens resolve uniquely by current function name.",
      "result": "FALSIFIED",
      "evidence_refs": ["M18_COVER_Q3"]
    },
    {
      "id": "M18_COVER_N3",
      "hypothesis": "Every current function matching the IG naming pattern is a caller and should be added to the denominator.",
      "result": "NOT_SUPPORTED",
      "evidence_refs": ["M18_COVER_Q6"]
    },
    {
      "id": "M18_COVER_N4",
      "hypothesis": "The external inventory can be mechanically merged with the SQL caller set.",
      "result": "NOT_SUPPORTED",
      "evidence_refs": ["M18_COVER_Q4","M18_COVER_Q5"]
    }
  ],
  "causal_hypothesis": {
    "state": "PARTIAL",
    "claim": "Coverage error risk is concentrated in identity qualification and current-complement classification, not in obvious corruption of the historical 38-row snapshot."
  },
  "minimal_safe_action": "Qualify ambiguous callee tokens by schema/object identity and classify current complement candidates through actual references before changing any caller denominator or declaring live coverage.",
  "unresolved": [
    "Historical schema identity for six currently ambiguous callee tokens",
    "Which current complement candidates are true callers versus callees/helpers/wrappers",
    "Whether any post-snapshot object creates a material route omitted from P0"
  ],
  "constraints_preserved": [
    "READ_ONLY",
    "No production mutation",
    "Historical/current separation",
    "No name-pattern candidate promoted to caller",
    "No peer role reports used",
    "No autonomous-agent claim"
  ],
  "measured_costs": {
    "sql_observations": 7,
    "transport_elapsed_ms": "NOT_MEASURED",
    "barinel_calibration": "NOT_AVAILABLE"
  },
  "role_output_frozen": true
}

### ROLE REPORT: INNOVATION

{
  "schema": "PE10_M18_ROLE_RAW_V1",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M18",
  "role_code": "INNOVATION",
  "base_code": "B",
  "algorithm_codes": ["D"],
  "source_cutoff": "2026-10-15T00:00:00Z",
  "role_bound_single_context": true,
  "autonomous_agent_claim": false,
  "cross_method_inputs_used": false,
  "method_application": {
    "D": {
      "gde_conflict_sets": [
        {
          "id": "INNOV_CS1",
          "observation": "Event 20161 explicitly carries provenance/currentness drift notes and acceptance_declared=false, while current lexical bodies retain 70/76 historical callee tokens but replace or remove six historical edges.",
          "components": ["snapshot_promotion_to_live", "post_snapshot_path_evolution", "lexical_vs_runtime_semantics"]
        },
        {
          "id": "INNOV_CS2",
          "observation": "Current complement discovery exposes queue/direct/handoff/continuation/context/cached-v2 path shapes outside the historical caller identity set.",
          "components": ["new_path_shapes", "caller_classification", "post_snapshot_lifecycle"]
        },
        {
          "id": "INNOV_CS3",
          "observation": "Pre-cutoff revision 5.13 and 5.13.1 occupy different time windows and screen populations despite constant family_count=47.",
          "components": ["revision_effect", "temporal_confounding", "screen_mix"]
        }
      ],
      "minimal_hitting_sets": [
        ["post_snapshot_path_evolution"],
        ["caller_classification"],
        ["temporal_confounding"]
      ],
      "barinel": {
        "status": "NOT_CALIBRATED",
        "reason": "The available observations are structural/temporal rather than an independent pass/fail component spectrum with justified priors."
      },
      "information_gain": {
        "mode": "ORDINAL_DISCRIMINATION_COST",
        "highest_value_next_query": "Classify the six changed lexical edges and the 23 new path-shape candidates by actual references and lifecycle provenance before any current completeness/performance conclusion.",
        "reason": "It distinguishes harmless refactoring from material route evolution and avoids a full blind re-inventory."
      }
    }
  },
  "queries": [
    {
      "id": "M18_INNOV_Q1",
      "scope": "P0_HISTORICAL",
      "result_summary": "Event 20161 records source_pack SOURCE_PACK_V1 / lookup V2, git provenance, acceptance_declared=false, and historical_provenance_only notes that router readiness was 5.12 while governed current readiness snapshot was 5.13; existence of older contracts is explicitly not caller-usage evidence."
    },
    {
      "id": "M18_INNOV_Q2",
      "scope": "P0_HISTORICAL",
      "result_summary": "Temporal order before cutoff is event 20161 on 2026-10-04, receipt 38 on 2026-10-07, SOAK EKB on 2026-10-14 23:39, CP2 authority EKB on 2026-10-14 23:44."
    },
    {
      "id": "M18_INNOV_Q3",
      "scope": "HISTORICAL_EDGES_PLUS_CURRENT_LEXICAL_READBACK",
      "result_summary": "Of 76 historical caller-callee lexical edges, 70 callee tokens are still present in current caller bodies and 6 are absent. All six absent edges belong to callers whose empirical md5(prosrc) differs from historical definition_md5. Among 55 edges on changed-hash callers, 49 retain the historical token and 6 do not."
    },
    {
      "id": "M18_INNOV_Q4",
      "scope": "CURRENT_COMPLEMENT_DISCOVERY",
      "result_summary": "64 current IG-pattern functions are outside the historical caller identity set; 23 have queue/direct-step/handoff/continuation/context/cached-v2 path-shape names. These are candidate route-evolution signals, not proven callers."
    },
    {
      "id": "M18_INNOV_Q5",
      "scope": "PRE_CUTOFF_TEMPORAL_COHORT",
      "result_summary": "Revision 5.13 has 86 completed runs across 42 screens from 2026-09-28 to 2026-10-05; 5.13.1 has 20 completed runs across 16 screens from 2026-10-08 to 2026-10-14. Both show family_count=47, but zero-stage prevalence and screen mix differ."
    },
    {
      "id": "M18_INNOV_Q6",
      "scope": "CURRENT_CHANGED_BODY_TOKEN_READBACK",
      "result_summary": "Five callers responsible for the six missing historical tokens now reference newer path shapes: bootstrap cached_v1 points to cached_v2; recurate_source_stale points to cached_v2; shadow_evaluate points to bootstrap_classify_v2_ctx; curator_materialize now includes curator plan/handoff and validator handoff; validate_v2 now references evidence rehydrate/semantic-scope paths. This is lexical structural evidence only, not runtime execution proof."
    }
  ],
  "findings": [
    {
      "id": "M18_INNOV_F1",
      "claim": "The P0 event itself warns against promoting its snapshot to live authority: acceptance_declared=false and its provenance notes already document version/currentness drift.",
      "classification": "MEASURED_HISTORICAL_PROVENANCE",
      "evidence_refs": ["M18_INNOV_Q1","M18_INNOV_Q2"],
      "confidence": "HIGH",
      "impact": "HIGH",
      "new_vs_input": true
    },
    {
      "id": "M18_INNOV_F2",
      "claim": "Current lexical topology shows selective evolution rather than wholesale disappearance: 70/76 historical callee tokens remain, while six historical edges no longer appear and newer cached/context/handoff paths appear in those changed bodies.",
      "classification": "MEASURED_CURRENT_LEXICAL_EVOLUTION",
      "evidence_refs": ["M18_INNOV_Q3","M18_INNOV_Q6"],
      "confidence": "HIGH",
      "impact": "HIGH",
      "new_vs_input": true,
      "limit": "Lexical references do not prove runtime execution."
    },
    {
      "id": "M18_INNOV_F3",
      "claim": "Queue/direct/handoff/continuation/context/cached-v2 functions are plausible route-evolution candidates outside the historical caller set, but names alone cannot establish that they are callers or were omitted at P0 time.",
      "classification": "CURRENT_CANDIDATE_SIGNAL_NOT_CALLER_PROOF",
      "evidence_refs": ["M18_INNOV_Q4"],
      "confidence": "MEDIUM_HIGH",
      "impact": "HIGH",
      "new_vs_input": true
    },
    {
      "id": "M18_INNOV_F4",
      "claim": "Performance comparison by revision is temporally and population-confounded even when family_count remains 47; 5.13 and 5.13.1 cover different time windows and screen populations.",
      "classification": "MEASURED_TEMPORAL_CONFOUNDING",
      "evidence_refs": ["M18_INNOV_Q5"],
      "confidence": "HIGH",
      "impact": "HIGH",
      "new_vs_input": true
    }
  ],
  "negative_falsifiers": [
    {
      "id": "M18_INNOV_N1",
      "hypothesis": "All 76 historical lexical caller-callee edges remain unchanged in current bodies.",
      "result": "FALSIFIED",
      "evidence_refs": ["M18_INNOV_Q3"]
    },
    {
      "id": "M18_INNOV_N2",
      "hypothesis": "Changed function hashes imply complete loss of historical callee relations.",
      "result": "FALSIFIED",
      "evidence_refs": ["M18_INNOV_Q3"]
    },
    {
      "id": "M18_INNOV_N3",
      "hypothesis": "Current queue/handoff/context-shaped functions are proven historical omissions solely from their names.",
      "result": "NOT_SUPPORTED",
      "evidence_refs": ["M18_INNOV_Q4"]
    },
    {
      "id": "M18_INNOV_N4",
      "hypothesis": "Revision 5.13 and 5.13.1 are temporally equivalent performance cohorts.",
      "result": "FALSIFIED",
      "evidence_refs": ["M18_INNOV_Q5"]
    }
  ],
  "causal_hypothesis": {
    "state": "PARTIAL",
    "claim": "The strongest alternative to a simple Curator/Validator defect is evidence staleness plus post-snapshot route evolution and cohort drift. Structural changes are demonstrable; their runtime and causal performance effect is not."
  },
  "minimal_safe_action": "Perform targeted reference/lifecycle classification of changed lexical edges and new path-shape candidates, then construct a matched performance cohort; avoid broad repair until those two uncertainties are resolved.",
  "unresolved": [
    "Runtime execution of new path-shape candidates",
    "Creation/provenance dates for current complement functions",
    "Whether changed lexical edges alter observed business behavior",
    "Matched causal performance effect of 5.13.1"
  ],
  "constraints_preserved": [
    "READ_ONLY",
    "No production mutation",
    "Historical/current separation",
    "Lexical evidence not promoted to runtime proof",
    "No peer role reports used",
    "No autonomous-agent claim"
  ],
  "measured_costs": {
    "sql_observations": 6,
    "transport_elapsed_ms": "NOT_MEASURED",
    "barinel_calibration": "NOT_AVAILABLE"
  },
  "role_output_frozen": true
}

### SYNTHESIS

{
  "schema": "PE10_M18_SYNTHESIS_V1",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M18",
  "base_code": "B",
  "algorithm_codes": ["D"],
  "source_cutoff": "2026-10-15T00:00:00Z",
  "role_code": "SYNTHESIZER",
  "source_scope": "READ_ONLY_P0_HISTORICAL_AND_EXPLICIT_CURRENT_ROLE",
  "role_bound_single_context": true,
  "autonomous_agent_claim": false,
  "source_pieces_frozen_before_synthesis": true,
  "no_new_sql_in_synthesis": true,
  "synthesis_inputs": [
    {
      "role": "ARCHITECTURE",
      "path": "docs/profile_updater/experiments/pe10_methods32_p0/M18_roles/ARCHITECTURE_RAW_V1.json",
      "source_commit": "ca54c5382d1010eb180cc352f0f386bc10df8e59",
      "git_blob_sha": "4d8b77869d4cf6e89ae18462eb8b4c0f9905aa7e",
      "evidence_ref": "https://github.com/cristhianlujan/claude-persona-lf-patch/blob/ca54c5382d1010eb180cc352f0f386bc10df8e59/docs/profile_updater/experiments/pe10_methods32_p0/M18_roles/ARCHITECTURE_RAW_V1.json#git_blob_sha=4d8b77869d4cf6e89ae18462eb8b4c0f9905aa7e",
      "readbacks": 5,
      "negative_tests": 3,
      "role_output_frozen": true
    },
    {
      "role": "PERFORMANCE",
      "path": "docs/profile_updater/experiments/pe10_methods32_p0/M18_roles/PERFORMANCE_RAW_V1.json",
      "source_commit": "7847646440754522d6469e4561514e8cef484954",
      "git_blob_sha": "1e756ac669f0d61b12ae231b7e873d9c86893761",
      "evidence_ref": "https://github.com/cristhianlujan/claude-persona-lf-patch/blob/7847646440754522d6469e4561514e8cef484954/docs/profile_updater/experiments/pe10_methods32_p0/M18_roles/PERFORMANCE_RAW_V1.json#git_blob_sha=1e756ac669f0d61b12ae231b7e873d9c86893761",
      "readbacks": 10,
      "negative_tests": 4,
      "role_output_frozen": true
    },
    {
      "role": "AUTHORITY",
      "path": "docs/profile_updater/experiments/pe10_methods32_p0/M18_roles/AUTHORITY_RAW_V1.json",
      "source_commit": "1da3740a6dcab3b0415c5b08659e2d6e9b0f2b1f",
      "git_blob_sha": "fa0d63ee65ec597ba423d0821cb4245714d0b70b",
      "evidence_ref": "https://github.com/cristhianlujan/claude-persona-lf-patch/blob/1da3740a6dcab3b0415c5b08659e2d6e9b0f2b1f/docs/profile_updater/experiments/pe10_methods32_p0/M18_roles/AUTHORITY_RAW_V1.json#git_blob_sha=fa0d63ee65ec597ba423d0821cb4245714d0b70b",
      "readbacks": 6,
      "negative_tests": 4,
      "role_output_frozen": true
    },
    {
      "role": "COVERAGE",
      "path": "docs/profile_updater/experiments/pe10_methods32_p0/M18_roles/COVERAGE_RAW_V1.json",
      "source_commit": "c6620c7ac22b71b9f304dfd673da402a46f25008",
      "git_blob_sha": "410c86ef7c0566840781e615b85c76805a7e0057",
      "evidence_ref": "https://github.com/cristhianlujan/claude-persona-lf-patch/blob/c6620c7ac22b71b9f304dfd673da402a46f25008/docs/profile_updater/experiments/pe10_methods32_p0/M18_roles/COVERAGE_RAW_V1.json#git_blob_sha=410c86ef7c0566840781e615b85c76805a7e0057",
      "readbacks": 7,
      "negative_tests": 4,
      "role_output_frozen": true
    },
    {
      "role": "INNOVATION",
      "path": "docs/profile_updater/experiments/pe10_methods32_p0/M18_roles/INNOVATION_RAW_V1.json",
      "source_commit": "de25f49f94aab4a320d8f3d3e14f61b7d6ec6c87",
      "git_blob_sha": "77af141dc562d929ebb355073731eb372f549f3e",
      "evidence_ref": "https://github.com/cristhianlujan/claude-persona-lf-patch/blob/de25f49f94aab4a320d8f3d3e14f61b7d6ec6c87/docs/profile_updater/experiments/pe10_methods32_p0/M18_roles/INNOVATION_RAW_V1.json#git_blob_sha=77af141dc562d929ebb355073731eb372f549f3e",
      "readbacks": 6,
      "negative_tests": 4,
      "role_output_frozen": true
    }
  ],
  "readbacks_total": 34,
  "negative_tests_total": 19,
  "gde_conflict_sets_total": 11,
  "barinel": {
    "status": "NOT_CALIBRATED",
    "roles_not_calibrated": 5,
    "reason": "None of the five frozen role reports had an independent executable pass/fail component spectrum with justified priors; numeric BARINEL probabilities would be fabricated."
  },
  "information_gain_mode": "ORDINAL_DISCRIMINATION_COST",
  "findings": [
    {
      "id": "M18_SYN_F1",
      "finding": "The historical event-20161 inventory is internally self-consistent for its declared population, but it is not a live certification: all 38 caller names still resolve, 21/21 trigger bindings remain mapped, yet 22/38 caller definitions have changed by empirical md5(prosrc) comparison.",
      "classification": "MEASURED_HISTORICAL_INTEGRITY_PLUS_CURRENT_DRIFT",
      "evidence": ["M18_COVER_Q1","M18_COVER_Q2","M18_ARQ_Q3","M18_ARQ_Q4"]
    },
    {
      "id": "M18_SYN_F2",
      "finding": "Current lexical topology shows selective evolution: 70/76 historical callee tokens remain in current bodies and six do not; changed bodies expose newer cached-v2/context/handoff paths. This is structural evidence, not runtime execution proof.",
      "classification": "MEASURED_CURRENT_LEXICAL_EVOLUTION",
      "evidence": ["M18_INNOV_Q3","M18_INNOV_Q6"]
    },
    {
      "id": "M18_SYN_F3",
      "finding": "Coverage cannot be promoted from historical to live without qualification: 6/39 historical callee tokens have multiple current schema candidates, and 64 current IG-pattern functions are outside the historical caller set, including 23 path-shape candidates; none of those candidates is automatically a caller.",
      "classification": "MEASURED_CURRENT_COVERAGE_RISK_WITH_CLASSIFICATION_LIMIT",
      "evidence": ["M18_COVER_Q3","M18_COVER_Q6","M18_INNOV_Q4"]
    },
    {
      "id": "M18_SYN_F4",
      "finding": "A performance improvement is not demonstrated. pg_stat function timing is unavailable under track_functions=none; pre-cutoff readiness stage durations exist, but 5.13 versus 5.13.1 differs in revision, time window, screen population, exact-zero prevalence and sample size. On overlapping screens 5.13.1 frequently has larger positive stage times, which is directional evidence only, not a causal regression proof.",
      "classification": "MEASURED_PERFORMANCE_UNRESOLVED",
      "evidence": ["M18_PERF_Q4","M18_PERF_Q6","M18_PERF_Q9","M18_PERF_Q10","M18_INNOV_Q5"]
    },
    {
      "id": "M18_SYN_F5",
      "finding": "The CP2 42501 is an authority/readback-path issue rather than demonstrated functional failure: the current read-only principal has no EXECUTE on either currentness-function variant but has SELECT on the evidence tables. Receipt 38 remains historical SOAK authority, not a current CP2 or performance receipt.",
      "classification": "MEASURED_AUTHORITY_BOUNDARY",
      "evidence": ["M18_AUTH_Q1","M18_AUTH_Q2","M18_AUTH_Q4","M18_AUTH_Q6","M18_PERF_Q2"]
    },
    {
      "id": "M18_SYN_F6",
      "finding": "The P0 event itself carries acceptance_declared=false and provenance/currentness drift notes, so treating its LIVE_PG_PROC labels as timeless live authority would contradict the source's own provenance limits.",
      "classification": "MEASURED_HISTORICAL_PROVENANCE_LIMIT",
      "evidence": ["M18_INNOV_Q1","M18_INNOV_Q2"]
    },
    {
      "id": "M18_SYN_F7",
      "finding": "GDE narrows the high-value risk families to stale-currentness promotion, post-snapshot path evolution, identity qualification, wrong authority path and cohort equivalence. No role produced evidence sufficient to calibrate BARINEL or prove a single functional root cause.",
      "classification": "METHOD_RESULT_WITH_EVIDENCE_LIMIT",
      "evidence": ["ARCH_CS1","PERF_CS2","AUTH_CS1","COVER_CS1","INNOV_CS1"]
    }
  ],
  "apparent_contradictions_resolved": [
    {
      "topic": "Historically self-consistent inventory vs current structural drift",
      "disposition": "NOT_AN_ACTUAL_CONTRADICTION",
      "reason": "The claims apply to different observation times; historical integrity does not imply current identity or topology equivalence.",
      "evidence": ["M18_COVER_Q1","M18_ARQ_Q3","M18_INNOV_Q3"]
    },
    {
      "topic": "All 21 trigger bindings still mapped vs six historical callee tokens missing from current function bodies",
      "disposition": "NOT_AN_ACTUAL_CONTRADICTION",
      "reason": "Trigger binding identity and internal function-body call relations are different topology layers.",
      "evidence": ["M18_ARQ_Q4","M18_INNOV_Q3"]
    },
    {
      "topic": "SOAK receipt verified vs performance/current CP2 unresolved",
      "disposition": "NOT_AN_ACTUAL_CONTRADICTION",
      "reason": "Receipt 38 certifies historical SOAK quality conditions, not stage latency or current CP2 functional authority.",
      "evidence": ["M18_AUTH_Q2","M18_PERF_Q2"]
    },
    {
      "topic": "5.13.1 frequently slower on overlapping screens vs causal regression not proven",
      "disposition": "NOT_AN_ACTUAL_CONTRADICTION",
      "reason": "Observed direction is compatible with multiple causes because revision, time, sample size, screen mix and zero-duration semantics are not controlled.",
      "evidence": ["M18_PERF_Q9","M18_PERF_Q10","M18_INNOV_Q5"]
    },
    {
      "topic": "Function EXECUTE denied vs evidence remains readable",
      "disposition": "NOT_AN_ACTUAL_CONTRADICTION",
      "reason": "EXECUTE on fn_input_readiness_run_is_current and SELECT on evidence tables are distinct privileges.",
      "evidence": ["M18_AUTH_Q4","M18_AUTH_Q6"]
    }
  ],
  "actual_unresolved_contradictions": [],
  "causal_model": {
    "proven_root_cause": false,
    "supported_risk_families": [
      "Historical snapshot promoted beyond its observation time",
      "Post-snapshot function/path evolution",
      "Unqualified or ambiguous callee identity",
      "Unauthorized CP2 readback path",
      "Performance cohort/revision mismatch"
    ],
    "not_proven": [
      "A single Curator defect",
      "A single Validator defect",
      "A causal performance regression in 5.13.1",
      "Runtime execution of current complement/path-shape candidates",
      "Canonical historical definition_md5 construction method"
    ],
    "negative_falsifiers": [
      "Most historical caller names did not disappear",
      "Broad trigger rebinding is not observed in the 21 historical bindings",
      "Zero function stats do not prove zero usage",
      "SOAK verification does not prove performance",
      "Name-pattern complement candidates are not promoted to callers",
      "42501 is not classified as functional failure"
    ]
  },
  "candidate_repairs": [
    {
      "action": "Qualify the six ambiguous callee names by schema/object identity and classify the six changed lexical edges plus 23 path-shape candidates by actual references/lifecycle provenance.",
      "status": "PROPOSED_NOT_IMPLEMENTED"
    },
    {
      "action": "Construct a same-screen, same-path matched performance cohort with explicit treatment of exact-zero durations before accepting any optimization claim.",
      "status": "PROPOSED_NOT_IMPLEMENTED"
    },
    {
      "action": "Reconstruct CP2 through authorized SELECT-only evidence sources and historical receipt 38 without EXECUTE elevation.",
      "status": "PROPOSED_NOT_IMPLEMENTED"
    }
  ],
  "chosen_repair": {
    "state": "VERIFY_FIRST",
    "implemented": false,
    "reason": "Structural/currentness and performance risks are demonstrated, but a causal functional defect and a safe production repair are not.",
    "next_safe_step": "Targeted identity/reference classification plus matched performance and authorized CP2 readback; only then decide whether code/runtime repair is justified."
  },
  "rejected_alternatives": [
    "Treat the 38-row historical snapshot as complete live coverage",
    "Add all 64 current name-pattern functions to the caller denominator",
    "Infer runtime execution from lexical references",
    "Treat 5.13.1 aggregate timing as a causal benchmark without cohort control",
    "Elevate EXECUTE to bypass 42501",
    "Invent BARINEL probabilities without a qualified spectrum",
    "Apply a production repair from this diagnostic run"
  ],
  "omissions_searched": [
    "post-snapshot caller-definition drift",
    "trigger rebinding",
    "callee schema ambiguity",
    "current complement/path-shape candidates",
    "historical/current provenance boundaries",
    "performance timing source availability",
    "exact-zero duration semantics",
    "revision and screen-population confounding",
    "authority and privilege boundaries",
    "external versus SQL identity domains"
  ],
  "unresolved": [
    "Canonical historical definition_md5 construction method",
    "Runtime execution of new path-shape candidates",
    "Historical schema identity for six currently ambiguous callee tokens",
    "Whether the six changed lexical edges materially change runtime behavior",
    "Semantic meaning of exact-zero durations across revisions",
    "Matched causal performance effect of 5.13.1",
    "Equivalent qualified CP2 functional evidence under authorized SELECT-only path"
  ],
  "constraints_preserved": [
    "READ_ONLY diagnostic work",
    "No production/runtime edits",
    "P0 historical cutoff preserved in claims",
    "Current observations explicitly separated from P0 evidence",
    "Five role reports frozen before synthesis",
    "No role report read another role report before freeze",
    "No cross-method result used as M18 input",
    "No autonomous independent-agent claim",
    "No external evaluation"
  ],
  "non_isolation_risk": "Five specialist reports were executed sequentially as role-bound passes in one shared model context. Their source observations and frozen artifacts are distinct and none used another role report as input before freeze, but cognitive independence comparable to separate autonomous agents is not demonstrated.",
  "performance_cost": {
    "role_queries": 34,
    "transport_elapsed_ms": "NOT_MEASURED",
    "possible_source_reuse": "NOT_QUANTIFIED"
  },
  "final_method_status": "B_D_FIVE_ROLE_REPORTS_AND_SYNTHESIS_MATERIAL_ONLY_NOT_YET_GOVERNED_DONE"
}
