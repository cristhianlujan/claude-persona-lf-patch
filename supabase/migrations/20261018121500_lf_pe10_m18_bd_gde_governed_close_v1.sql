-- PE10 M18: base B + algorithm D (GDE/BARINEL/information gain), five frozen role-bound passes + synthesis.
-- Governed Train only. Administrative evidence closure; no product/runtime repair.
DO $m18_close$
DECLARE
 v_exec text;
 v_raw text:=$m18_raw${
  "schema": "PE10_METHOD_RAW_V2",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M18",
  "base_code": "B",
  "algorithm_codes": [
    "D"
  ],
  "method_catalog": "PE10_METHOD_V1",
  "source_cutoff": "2026-10-15T00:00:00Z",
  "original_preserved": {
    "ref": "chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M18.json",
    "sha256": "ea756fb0573ff82a29d1d9c9bdeff65c2ab0723420859e43b11ac0930179e379"
  },
  "role_bound_single_context": true,
  "autonomous_agent_claim": false,
  "cross_method_inputs_used": false,
  "external_evaluation": "NOT_PERFORMED",
  "producer": "B+D: five separately frozen role-bound research passes, each applying GDE/BARINEL/information-gain rules without fabricated probabilities, followed by synthesizer after freeze; one coordinated shared context, no independent autonomous-agent claim",
  "role_reports": [
    {
      "role": "ARCHITECTURE",
      "git_blob_sha": "4d8b77869d4cf6e89ae18462eb8b4c0f9905aa7e",
      "source_commit": "ca54c5382d1010eb180cc352f0f386bc10df8e59",
      "path": "docs/profile_updater/experiments/pe10_methods32_p0/M18_roles/ARCHITECTURE_RAW_V1.json",
      "query_count": 5,
      "negative_count": 3,
      "gde_conflict_sets": 2,
      "barinel_status": "NOT_CALIBRATED",
      "role_output_frozen": true,
      "cognitive_independence_claim": false
    },
    {
      "role": "PERFORMANCE",
      "git_blob_sha": "1e756ac669f0d61b12ae231b7e873d9c86893761",
      "source_commit": "7847646440754522d6469e4561514e8cef484954",
      "path": "docs/profile_updater/experiments/pe10_methods32_p0/M18_roles/PERFORMANCE_RAW_V1.json",
      "query_count": 10,
      "negative_count": 4,
      "gde_conflict_sets": 2,
      "barinel_status": "NOT_CALIBRATED",
      "role_output_frozen": true,
      "cognitive_independence_claim": false
    },
    {
      "role": "AUTHORITY",
      "git_blob_sha": "fa0d63ee65ec597ba423d0821cb4245714d0b70b",
      "source_commit": "1da3740a6dcab3b0415c5b08659e2d6e9b0f2b1f",
      "path": "docs/profile_updater/experiments/pe10_methods32_p0/M18_roles/AUTHORITY_RAW_V1.json",
      "query_count": 6,
      "negative_count": 4,
      "gde_conflict_sets": 2,
      "barinel_status": "NOT_CALIBRATED",
      "role_output_frozen": true,
      "cognitive_independence_claim": false
    },
    {
      "role": "COVERAGE",
      "git_blob_sha": "410c86ef7c0566840781e615b85c76805a7e0057",
      "source_commit": "c6620c7ac22b71b9f304dfd673da402a46f25008",
      "path": "docs/profile_updater/experiments/pe10_methods32_p0/M18_roles/COVERAGE_RAW_V1.json",
      "query_count": 7,
      "negative_count": 4,
      "gde_conflict_sets": 2,
      "barinel_status": "NOT_CALIBRATED",
      "role_output_frozen": true,
      "cognitive_independence_claim": false
    },
    {
      "role": "INNOVATION",
      "git_blob_sha": "77af141dc562d929ebb355073731eb372f549f3e",
      "source_commit": "de25f49f94aab4a320d8f3d3e14f61b7d6ec6c87",
      "path": "docs/profile_updater/experiments/pe10_methods32_p0/M18_roles/INNOVATION_RAW_V1.json",
      "query_count": 6,
      "negative_count": 4,
      "gde_conflict_sets": 3,
      "barinel_status": "NOT_CALIBRATED",
      "role_output_frozen": true,
      "cognitive_independence_claim": false
    }
  ],
  "synthesis_ref": {
    "path": "docs/profile_updater/experiments/pe10_methods32_p0/M18_SYNTHESIS_V1.json",
    "source_commit": "10968a004600a6b0f24593a1dcc92c102111e26c",
    "git_blob_sha": "e8f836006e7b5a2af8bd081fd6624fbfc0251666"
  },
  "synthesis": {
    "schema": "PE10_M18_SYNTHESIS_V1",
    "case_ref": "PE10-IG-M107-M109-P0",
    "method_code": "PE10_M18",
    "base_code": "B",
    "algorithm_codes": [
      "D"
    ],
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
        "evidence": [
          "M18_COVER_Q1",
          "M18_COVER_Q2",
          "M18_ARQ_Q3",
          "M18_ARQ_Q4"
        ]
      },
      {
        "id": "M18_SYN_F2",
        "finding": "Current lexical topology shows selective evolution: 70/76 historical callee tokens remain in current bodies and six do not; changed bodies expose newer cached-v2/context/handoff paths. This is structural evidence, not runtime execution proof.",
        "classification": "MEASURED_CURRENT_LEXICAL_EVOLUTION",
        "evidence": [
          "M18_INNOV_Q3",
          "M18_INNOV_Q6"
        ]
      },
      {
        "id": "M18_SYN_F3",
        "finding": "Coverage cannot be promoted from historical to live without qualification: 6/39 historical callee tokens have multiple current schema candidates, and 64 current IG-pattern functions are outside the historical caller set, including 23 path-shape candidates; none of those candidates is automatically a caller.",
        "classification": "MEASURED_CURRENT_COVERAGE_RISK_WITH_CLASSIFICATION_LIMIT",
        "evidence": [
          "M18_COVER_Q3",
          "M18_COVER_Q6",
          "M18_INNOV_Q4"
        ]
      },
      {
        "id": "M18_SYN_F4",
        "finding": "A performance improvement is not demonstrated. pg_stat function timing is unavailable under track_functions=none; pre-cutoff readiness stage durations exist, but 5.13 versus 5.13.1 differs in revision, time window, screen population, exact-zero prevalence and sample size. On overlapping screens 5.13.1 frequently has larger positive stage times, which is directional evidence only, not a causal regression proof.",
        "classification": "MEASURED_PERFORMANCE_UNRESOLVED",
        "evidence": [
          "M18_PERF_Q4",
          "M18_PERF_Q6",
          "M18_PERF_Q9",
          "M18_PERF_Q10",
          "M18_INNOV_Q5"
        ]
      },
      {
        "id": "M18_SYN_F5",
        "finding": "The CP2 42501 is an authority/readback-path issue rather than demonstrated functional failure: the current read-only principal has no EXECUTE on either currentness-function variant but has SELECT on the evidence tables. Receipt 38 remains historical SOAK authority, not a current CP2 or performance receipt.",
        "classification": "MEASURED_AUTHORITY_BOUNDARY",
        "evidence": [
          "M18_AUTH_Q1",
          "M18_AUTH_Q2",
          "M18_AUTH_Q4",
          "M18_AUTH_Q6",
          "M18_PERF_Q2"
        ]
      },
      {
        "id": "M18_SYN_F6",
        "finding": "The P0 event itself carries acceptance_declared=false and provenance/currentness drift notes, so treating its LIVE_PG_PROC labels as timeless live authority would contradict the source's own provenance limits.",
        "classification": "MEASURED_HISTORICAL_PROVENANCE_LIMIT",
        "evidence": [
          "M18_INNOV_Q1",
          "M18_INNOV_Q2"
        ]
      },
      {
        "id": "M18_SYN_F7",
        "finding": "GDE narrows the high-value risk families to stale-currentness promotion, post-snapshot path evolution, identity qualification, wrong authority path and cohort equivalence. No role produced evidence sufficient to calibrate BARINEL or prove a single functional root cause.",
        "classification": "METHOD_RESULT_WITH_EVIDENCE_LIMIT",
        "evidence": [
          "ARCH_CS1",
          "PERF_CS2",
          "AUTH_CS1",
          "COVER_CS1",
          "INNOV_CS1"
        ]
      }
    ],
    "apparent_contradictions_resolved": [
      {
        "topic": "Historically self-consistent inventory vs current structural drift",
        "disposition": "NOT_AN_ACTUAL_CONTRADICTION",
        "reason": "The claims apply to different observation times; historical integrity does not imply current identity or topology equivalence.",
        "evidence": [
          "M18_COVER_Q1",
          "M18_ARQ_Q3",
          "M18_INNOV_Q3"
        ]
      },
      {
        "topic": "All 21 trigger bindings still mapped vs six historical callee tokens missing from current function bodies",
        "disposition": "NOT_AN_ACTUAL_CONTRADICTION",
        "reason": "Trigger binding identity and internal function-body call relations are different topology layers.",
        "evidence": [
          "M18_ARQ_Q4",
          "M18_INNOV_Q3"
        ]
      },
      {
        "topic": "SOAK receipt verified vs performance/current CP2 unresolved",
        "disposition": "NOT_AN_ACTUAL_CONTRADICTION",
        "reason": "Receipt 38 certifies historical SOAK quality conditions, not stage latency or current CP2 functional authority.",
        "evidence": [
          "M18_AUTH_Q2",
          "M18_PERF_Q2"
        ]
      },
      {
        "topic": "5.13.1 frequently slower on overlapping screens vs causal regression not proven",
        "disposition": "NOT_AN_ACTUAL_CONTRADICTION",
        "reason": "Observed direction is compatible with multiple causes because revision, time, sample size, screen mix and zero-duration semantics are not controlled.",
        "evidence": [
          "M18_PERF_Q9",
          "M18_PERF_Q10",
          "M18_INNOV_Q5"
        ]
      },
      {
        "topic": "Function EXECUTE denied vs evidence remains readable",
        "disposition": "NOT_AN_ACTUAL_CONTRADICTION",
        "reason": "EXECUTE on fn_input_readiness_run_is_current and SELECT on evidence tables are distinct privileges.",
        "evidence": [
          "M18_AUTH_Q4",
          "M18_AUTH_Q6"
        ]
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
  },
  "source_queries_total": 34,
  "negative_tests_total": 19,
  "gde_conflict_sets_total": 11,
  "barinel_calibrated": false,
  "information_gain_mode": "ORDINAL_DISCRIMINATION_COST",
  "synthesis_claims": 7,
  "synthesis_reconciled_apparent_contradictions": 5,
  "final_method_state": "B_D_ROLE_REPORTS_SYNTHESIZED_NO_DOMAIN_REPAIR",
  "causal_defect_proven": false,
  "solution_state": "VERIFY_FIRST",
  "runtime_modified": false,
  "independence_constraint": {
    "frozen_before_synthesis": true,
    "report_results_from_one_model_context": true,
    "independent_agents": false,
    "leakage_risk": "Shared model cognition not isolated; role reports were frozen before synthesis and did not consume peer reports, but cognitive independence comparable to separate autonomous agents is not demonstrated."
  },
  "limits": [
    "Historical P0 and explicit current readbacks are separated by claim",
    "Historical definition_md5 construction remains unknown",
    "Lexical structure is not runtime execution proof",
    "Performance cohorts are not causally equivalent",
    "BARINEL probabilities not calibrated",
    "No product/runtime repair was applied"
  ]
}
$m18_raw$;
 v_doc jsonb;
 v_spec jsonb:=$m18_spec${"status":"READY","action_kind":"VERIFY_QUERY_ONCE","recipe_mode":"READBACK_EXACT","requires_material_execution":true,"contract_family":"PE10_METHOD_EXECUTION_EVIDENCE","precision":"PE10_METHOD_V1_MATERIAL_EVIDENCE","assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"checkpoint_identity":"PE10_M18","base_code":"B","algorithm_D_executed":true,"role_reports_frozen":5,"synthesis_completed":true,"read_only_sql_queries":34,"role_negative_tests":19,"gde_conflict_sets":11,"barinel_calibrated":false,"information_gain_mode":"ORDINAL_DISCRIMINATION_COST","role_bound_same_context":true,"independent_agents_claimed":false,"source_event_id":20161,"git_raw_source_verified":true,"runtime_modified":false}},"evidence_ref":"https://github.com/cristhianlujan/claude-persona-lf-patch/blob/b9475431e2a79796263d9b200db410ea705711ac/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M18_RAW_V2.json#git_blob_sha=16405fe79d60b9a5cc1720c61d03c5e4783794a2","verification_queries":["SELECT id,created_at,payload->>'sql_caller_count',jsonb_array_length(payload->'trigger_bindings'),jsonb_array_length(payload->'external_inventory') FROM public.lf_eventos WHERE id=20161","SELECT id,created_at,payload->>'verification_status',payload->>'screens_total',payload->>'families_total' FROM programacion.provenance_receipts WHERE id=38","SELECT codigo,primera_vez FROM transversal.error_knowledge WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001')","SELECT count(*) FILTER (WHERE created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z') FROM programacion.input_readiness_runs"],"expected":"B+D method with five frozen role-bound reports, 34 read-only observations, 19 falsifiers/negative checks, 11 GDE conflict sets, BARINEL correctly not calibrated, ordinal information-gain selection, synthesis after freeze, no product repair.","forbidden":["CLAIM_INDEPENDENT_AUTONOMOUS_SESSIONS","FABRICATE_BARINEL_PROBABILITIES","PROMOTE_LEXICAL_REFERENCE_TO_RUNTIME_PROOF","PROMOTE_P0_TO_CURRENT","SKIP_TRAIN","TOUCH_OTHER_CHECKPOINTS","APPLY_DOMAIN_REPAIR"],"target":{"checkpoint":"PE10_M18","declared_events":[20161],"declared_objects":["public.lf_eventos","programacion.provenance_receipts","transversal.error_knowledge","programacion.input_readiness_runs","programacion.engineering_work_checkpoints"],"evidence_artifacts":[{"path":"cristhianlujan/claude-persona-lf-patch:docs/profile_updater/experiments/pe10_methods32_p0/PE10_M18_RAW_V2.json","role":"EVIDENCE","purpose":"PE10_M18_B_D_FIVE_ROLE_REPORTS_SYNTHESIS_AGGREGATE","target_kind":"EXACT_EXISTING_FILE"}]}}$m18_spec$::jsonb;
 v_ref text:='https://github.com/cristhianlujan/claude-persona-lf-patch/blob/b9475431e2a79796263d9b200db410ea705711ac/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M18_RAW_V2.json#git_blob_sha=16405fe79d60b9a5cc1720c61d03c5e4783794a2';
 v_old text:='chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M18.json#sha256=ea756fb0573ff82a29d1d9c9bdeff65c2ab0723420859e43b11ac0930179e379';
 v_blob text;
 v_prior_snapshot jsonb;
 v_after_snapshot jsonb;
 v_roles int;
 v_queries int;
 v_neg int;
 v_gde int;
 v_ekb int;
 v_pre_runs int;
 v_contract jsonb;
 v_obs jsonb;
 v_result jsonb;
 v_assertion jsonb;
 v_transition jsonb;
 v_receipt text;
 v_n int;
 v_msg text;
 v_ctx text;
BEGIN
 SELECT execution_id INTO v_exec
 FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF'
   AND target_type='MIGRATION'
   AND target_code LIKE '%lf_pe10_m18_bd_gde_governed_close_v1'
   AND status='IN_PROGRESS'
 ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN
   RAISE EXCEPTION 'M18_NOT_TRAIN_EXECUTOR';
 END IF;

 IF (SELECT status FROM programacion.engineering_work_items WHERE id=1133)<>'IN_PROGRESS'
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>17
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>15
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1133 AND checkpoint_code='PE10_M18' AND id=1642
       AND status='PENDING' AND evidence_ref=v_old
       AND assertion_receipt IS NULL AND completed_at IS NULL)<>1
 OR (SELECT count(*) FROM programacion.pe10_method_variants
     WHERE method_code='PE10_M18' AND base_code='B'
       AND case_ref='PE10-IG-M107-M109-P0'
       AND algorithm_codes=ARRAY['D']::text[])<>1
 OR (SELECT count(*) FROM programacion.engineering_plan_units
     WHERE work_item_id=1133 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32'
       AND unit_metadata#>>'{action_specs_v1,PE10_M18,status}'='BLOCK_PENDING_MATERIAL_RESEARCH_AND_VALIDATION')<>1
 THEN
   RAISE EXCEPTION 'M18_PRESTATE_OR_METHOD_CONTRACT_NOT_QUALIFIED';
 END IF;

 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1133 AND sequence_no<18
       AND status='DONE'
       AND completed_at IS NOT NULL
       AND assertion_receipt->>'passed'='true'
       AND assertion_contract_sha256=assertion_receipt->>'contract_sha256')<>17
 THEN
   RAISE EXCEPTION 'M18_PRIOR_17_CANONICAL_RECEIPTS_NOT_QUALIFIED';
 END IF;

 SELECT jsonb_agg(jsonb_build_object(
          'checkpoint_code',checkpoint_code,
          'status',status,
          'evidence_ref',evidence_ref,
          'assertion_receipt_sha256',assertion_receipt_sha256,
          'completed_at',completed_at
        ) ORDER BY sequence_no)
 INTO v_prior_snapshot
 FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=1133 AND sequence_no<18;

 v_blob:=encode(
   extensions.digest(
     convert_to('blob '||octet_length(convert_to(v_raw,'UTF8'))::text,'UTF8')
     ||decode('00','hex')||convert_to(v_raw,'UTF8'),
     'sha1'
   ),
   'hex'
 );
 IF v_blob<>'16405fe79d60b9a5cc1720c61d03c5e4783794a2' THEN
   RAISE EXCEPTION 'M18_RAW_GIT_BLOB_NOT_VERIFIED expected=16405fe79d60b9a5cc1720c61d03c5e4783794a2 observed=%',v_blob;
 END IF;

 v_doc:=v_raw::jsonb;
 IF v_doc->>'schema'<>'PE10_METHOD_RAW_V2'
 OR v_doc->>'case_ref'<>'PE10-IG-M107-M109-P0'
 OR v_doc->>'method_code'<>'PE10_M18'
 OR v_doc->>'base_code'<>'B'
 OR v_doc->'algorithm_codes'<>'["D"]'::jsonb
 OR v_doc->>'source_cutoff'<>'2026-10-15T00:00:00Z'
 OR v_doc#>>'{original_preserved,sha256}'<>'ea756fb0573ff82a29d1d9c9bdeff65c2ab0723420859e43b11ac0930179e379'
 OR v_doc->>'external_evaluation'<>'NOT_PERFORMED'
 OR v_doc->>'autonomous_agent_claim'<>'false'
 OR v_doc->>'cross_method_inputs_used'<>'false'
 OR v_doc->>'role_bound_single_context'<>'true'
 OR v_doc#>>'{independence_constraint,independent_agents}'<>'false'
 OR v_doc#>>'{independence_constraint,frozen_before_synthesis}'<>'true'
 OR v_doc#>>'{synthesis,role_code}'<>'SYNTHESIZER'
 OR v_doc#>>'{synthesis,source_pieces_frozen_before_synthesis}'<>'true'
 OR v_doc#>>'{synthesis,no_new_sql_in_synthesis}'<>'true'
 OR v_doc#>>'{synthesis,barinel,status}'<>'NOT_CALIBRATED'
 OR v_doc#>>'{synthesis,information_gain_mode}'<>'ORDINAL_DISCRIMINATION_COST'
 OR v_doc#>>'{synthesis,chosen_repair,state}'<>'VERIFY_FIRST'
 OR v_doc->>'barinel_calibrated'<>'false'
 OR v_doc->>'information_gain_mode'<>'ORDINAL_DISCRIMINATION_COST'
 OR v_doc->>'final_method_state'<>'B_D_ROLE_REPORTS_SYNTHESIZED_NO_DOMAIN_REPAIR'
 OR v_doc->>'runtime_modified'<>'false'
 THEN
   RAISE EXCEPTION 'M18_B_D_AUTHENTICITY_OR_SYNTHESIS_NOT_QUALIFIED';
 END IF;

 WITH expected(role,sha,nqueries,nneg,ngde) AS (VALUES
   ('ARCHITECTURE','4d8b77869d4cf6e89ae18462eb8b4c0f9905aa7e',5,3,2),
   ('PERFORMANCE','1e756ac669f0d61b12ae231b7e873d9c86893761',10,4,2),
   ('AUTHORITY','fa0d63ee65ec597ba423d0821cb4245714d0b70b',6,4,2),
   ('COVERAGE','410c86ef7c0566840781e615b85c76805a7e0057',7,4,2),
   ('INNOVATION','77af141dc562d929ebb355073731eb372f549f3e',6,4,3)
 ), actual AS (
   SELECT x->>'role' role,
          x->>'git_blob_sha' sha,
          (x->>'query_count')::int nqueries,
          (x->>'negative_count')::int nneg,
          (x->>'gde_conflict_sets')::int ngde,
          x->>'barinel_status' barinel_status,
          x->>'role_output_frozen' frozen,
          x->>'cognitive_independence_claim' independent
   FROM jsonb_array_elements(v_doc->'role_reports') x
 )
 SELECT count(*),coalesce(sum(a.nqueries),0),coalesce(sum(a.nneg),0),coalesce(sum(a.ngde),0)
 INTO v_roles,v_queries,v_neg,v_gde
 FROM expected e JOIN actual a USING(role,sha,nqueries,nneg,ngde)
 WHERE a.barinel_status='NOT_CALIBRATED'
   AND a.frozen='true'
   AND a.independent='false';

 IF v_roles<>5 OR v_queries<>34 OR v_neg<>19 OR v_gde<>11
 OR jsonb_array_length(v_doc->'role_reports')<>5
 OR v_doc->>'source_queries_total'<>'34'
 OR v_doc->>'negative_tests_total'<>'19'
 OR v_doc->>'gde_conflict_sets_total'<>'11'
 OR v_doc#>>'{synthesis,readbacks_total}'<>'34'
 OR v_doc#>>'{synthesis,negative_tests_total}'<>'19'
 OR v_doc#>>'{synthesis,gde_conflict_sets_total}'<>'11'
 OR jsonb_array_length(v_doc#>'{synthesis,synthesis_inputs}')<>5
 OR jsonb_array_length(v_doc#>'{synthesis,findings}')<>7
 OR jsonb_array_length(v_doc#>'{synthesis,apparent_contradictions_resolved}')<>5
 OR jsonb_array_length(v_doc#>'{synthesis,actual_unresolved_contradictions}')<>0
 OR v_doc#>>'{synthesis_ref,git_blob_sha}'<>'e8f836006e7b5a2af8bd081fd6624fbfc0251666'
 OR length(coalesce(v_doc#>>'{synthesis,non_isolation_risk}',''))<80
 THEN
   RAISE EXCEPTION 'M18_FIVE_REPORTS_D_METHOD_AND_SYNTHESIS_MANIFEST_FAILED';
 END IF;

 SELECT count(*) INTO v_ekb
 FROM transversal.error_knowledge
 WHERE codigo IN (
   'IG-M107-SOAK-CRITERION-DRIFT-001',
   'IG-M107-CP2-READ-ROLE-CURRENTNESS-001'
 )
 AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z';

 SELECT count(*) INTO v_pre_runs
 FROM programacion.input_readiness_runs
 WHERE created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z';

 IF v_ekb<>2
 OR (SELECT count(*) FROM public.lf_eventos
     WHERE id=20161
       AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'
       AND jsonb_array_length(payload->'sql_callers')=38
       AND jsonb_array_length(payload->'trigger_bindings')=21
       AND jsonb_array_length(payload->'external_inventory')=6
       AND payload->'usage_stats'->>'track_functions'='none')<>1
 OR (SELECT count(*) FROM programacion.provenance_receipts
     WHERE id=38
       AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'
       AND payload->>'verification_status'='VERIFIED'
       AND payload->>'screens_total'='13'
       AND payload->>'families_total'='47'
       AND payload->>'known_false_pass_signals'='0'
       AND payload->>'unresolved_d4'='0')<>1
 OR v_pre_runs<>255
 OR (SELECT count(*) FROM programacion.input_readiness_runs
     WHERE created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'
       AND status='COMPLETED' AND contract_revision='5.13')<>86
 OR (SELECT count(*) FROM programacion.input_readiness_runs
     WHERE created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'
       AND status='COMPLETED' AND contract_revision='5.13.1')<>20
 THEN
   RAISE EXCEPTION 'M18_MATERIAL_P0_OR_PRE_CUTOFF_SOURCE_DRIFT';
 END IF;

 UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10_M18}',v_spec,true)
 WHERE work_item_id=1133
   AND plan_code='PEVO-PE10-METHODS32-P0'
   AND unit_code='METHODS32';
 GET DIAGNOSTICS v_n=ROW_COUNT;
 IF v_n<>1 THEN
   RAISE EXCEPTION 'M18_ACTION_SPEC_UPDATE_COUNT_FAILED';
 END IF;

 v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
   'PEVO-PE10-METHODS32-P0',
   'METHODS32',
   'PE10_M18',
   programacion.fn_engineering_checkpoint_action_spec_v3(
     'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M18'
   )
 );
 IF v_contract->>'status'<>'READY'
 OR v_contract->>'mode'<>'EXPLICIT_PASS_WHEN_SUBSET'
 THEN
   RAISE EXCEPTION 'M18_ASSERTION_CONTRACT_NOT_READY:%',coalesce(v_contract::text,'NULL');
 END IF;

 v_obs:=jsonb_build_object(
   'checkpoint_identity','PE10_M18',
   'base_code','B',
   'algorithm_D_executed',true,
   'role_reports_frozen',v_roles,
   'synthesis_completed',true,
   'read_only_sql_queries',v_queries,
   'role_negative_tests',v_neg,
   'gde_conflict_sets',v_gde,
   'barinel_calibrated',false,
   'information_gain_mode','ORDINAL_DISCRIMINATION_COST',
   'role_bound_same_context',true,
   'independent_agents_claimed',false,
   'source_event_id',20161,
   'git_raw_source_verified',true,
   'runtime_modified',false
 );

 v_result:=jsonb_build_object(
   'status','PASS',
   'observed',v_obs,
   'evidence_ref',v_ref,
   'validation_kind','M18_B_D_FIVE_ROLE_BOUND_REPORTS_GDE_IG_SYNTHESIS_MATERIAL_ONLY',
   'independent_autonomous_agents',false,
   'barinel_probabilities_fabricated',false,
   'product_repair_applied',false
 );

 v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
   'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M18',v_result,v_exec
 );
 IF v_assertion->>'passed'<>'true'
 OR coalesce(v_assertion->>'assertion_receipt_sha256','') !~ '^[a-f0-9]{64}$'
 THEN
   RAISE EXCEPTION 'M18_CANONICAL_RECEIPT_NOT_PASSED';
 END IF;
 v_receipt:=v_assertion->>'assertion_receipt_sha256';

 v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
   'PEVO-PE10-METHODS32-P0',
   'METHODS32',
   'PE10_M18',
   'DONE',
   v_ref,
   v_exec,
   'M18 B+D: five frozen role-bound reports, GDE conflict sets, BARINEL correctly uncalibrated, ordinal information gain and synthesis verified; no domain repair'
 );
 IF v_transition#>>'{transition,status}'<>'APPLIED' THEN
   RAISE EXCEPTION 'M18_STATUS_TRANSITION_NOT_CANONICAL';
 END IF;

 SELECT jsonb_agg(jsonb_build_object(
          'checkpoint_code',checkpoint_code,
          'status',status,
          'evidence_ref',evidence_ref,
          'assertion_receipt_sha256',assertion_receipt_sha256,
          'completed_at',completed_at
        ) ORDER BY sequence_no)
 INTO v_after_snapshot
 FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=1133 AND sequence_no<18;

 IF v_after_snapshot<>v_prior_snapshot
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1133 AND checkpoint_code='PE10_M18'
       AND status='DONE' AND completed_at IS NOT NULL
       AND evidence_ref=v_ref
       AND assertion_receipt_sha256=v_receipt
       AND assertion_receipt->>'passed'='true'
       AND assertion_contract_sha256=assertion_receipt->>'contract_sha256')<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>18
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>14
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1133 AND checkpoint_code='PE10_M19' AND status='PENDING')<>1
 THEN
   RAISE EXCEPTION 'M18_POST_TRAIN_GOVERNED_READBACK_FAILED';
 END IF;
EXCEPTION WHEN OTHERS THEN
 GET STACKED DIAGNOSTICS v_msg=MESSAGE_TEXT,v_ctx=PG_EXCEPTION_CONTEXT;
 RAISE EXCEPTION 'M18_TRAIN_ERROR state=% msg=% context=%',
   SQLSTATE,left(v_msg,290),left(v_ctx,150)
 USING ERRCODE=SQLSTATE;
END $m18_close$;
