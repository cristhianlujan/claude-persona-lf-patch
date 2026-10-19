-- PE10 M17: base B five frozen role-bound passes + synthesis; no false autonomous-agent claim.
-- Governed Train only. Nothing updates besides M17 action_spec / canonical receipt and status.
DO $m17_close$
DECLARE
 v_exec text;v_raw text:=$m17_raw${
  "schema": "PE10_METHOD_RAW_V2",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M17",
  "base_code": "B",
  "algorithm_codes": [],
  "method_catalog": "PE10_METHOD_V1",
  "source_cutoff": "2026-10-15T00:00:00Z",
  "original_preserved": {
    "ref": "chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M17.json",
    "sha256": "105a7dddfb5ba49ee5b29e3c63f1c215f820fd7505ef0bd1c9a8a67ec1ad93f5"
  },
  "role_bound_single_context": true,
  "autonomous_agent_claim": false,
  "external_evaluation": "NOT_PERFORMED",
  "producer": "B base: 5 role-bound separate frozen research passes + synthesizer only after freeze; all within one shared context, no independent autonomous agents claimed",
  "role_reports": [
    {
      "role": "ARCHITECTURE",
      "git_blob_sha": "037627c35260541fb26ec928c3f58d9d8c430958",
      "reference": "https://github.com/cristhianlujan/claude-persona-lf-patch/blob/3dea196657b4697694a564da94df7a39011439cf/docs/profile_updater/experiments/pe10_methods32_p0/M17_roles/ARCHITECTURE_RAW_V1.json#git_blob_sha=037627c35260541fb26ec928c3f58d9d8c430958",
      "method_code": "PE10_M17",
      "query_ids": [
        "M17_ARQ_Q1",
        "M17_ARQ_Q2",
        "M17_ARQ_Q3",
        "M17_ARQ_Q4",
        "M17_ARQ_Q5"
      ],
      "query_count": 5,
      "negative_ids": [
        "ARCH_N1_LEXICAL_NOT_EXECUTION",
        "ARCH_N2_SIX_EXTERNAL_NOT_ADD_TO_38",
        "ARCH_N3_TIME_SCOPE_NOT_LIVE"
      ],
      "negative_passed": 3,
      "negative_count": 3,
      "findings_count": 3,
      "cognitive_independence_claim": false,
      "role_bound_only": true
    },
    {
      "role": "PERFORMANCE",
      "git_blob_sha": "77ff870b20a97e797f08ce1a228d69215cdd5d11",
      "reference": "https://github.com/cristhianlujan/claude-persona-lf-patch/blob/4c02efa6e65e4155bab826a8b4d5bff9268c087f/docs/profile_updater/experiments/pe10_methods32_p0/M17_roles/PERFORMANCE_RAW_V1.json#git_blob_sha=77ff870b20a97e797f08ce1a228d69215cdd5d11",
      "method_code": "PE10_M17",
      "query_ids": [
        "M17_PERF_Q1",
        "M17_PERF_Q2",
        "M17_PERF_Q3",
        "M17_PERF_Q4",
        "M17_PERF_Q5"
      ],
      "query_count": 5,
      "negative_ids": [
        "PERF_NO_ZERO_USAGE_INFERENCE",
        "PERF_SOURCE_NO_EXECUTION_DURATIONS",
        "PERF_UNKNOWN_DURATION_REMAINS_NULL",
        "PERF_ZERO_DURATION_NOT_METRIC",
        "PERF_QUALIFIED_CLOCK_POSITIVE",
        "PERF_RECEIPT_NO_P90_METRIC"
      ],
      "negative_passed": 6,
      "negative_count": 6,
      "findings_count": 4,
      "cognitive_independence_claim": false,
      "role_bound_only": true
    },
    {
      "role": "AUTHORITY",
      "git_blob_sha": "1b4928c262eb106cfaa9efb77a23bf51311a7e35",
      "reference": "https://github.com/cristhianlujan/claude-persona-lf-patch/blob/0d40747bffba2155f5e3891db0daba2d76e3683c/docs/profile_updater/experiments/pe10_methods32_p0/M17_roles/AUTHORITY_RAW_V1.json#git_blob_sha=1b4928c262eb106cfaa9efb77a23bf51311a7e35",
      "method_code": "PE10_M17",
      "query_ids": [
        "M17_AUTH_Q1",
        "M17_AUTH_Q2",
        "M17_AUTH_Q3",
        "M17_AUTH_Q4",
        "M17_AUTH_Q5"
      ],
      "query_count": 5,
      "negative_ids": [
        "AUTH_EKB_TWO_HISTORIC",
        "AUTH_M911_QUALIFIED_RECEIPT",
        "AUTH_CURRENT_ROLE_RO",
        "AUTH_CURRENT_NOT_P0",
        "AUTH_NO_PROD_MUTATION_ASSERT"
      ],
      "negative_passed": 5,
      "negative_count": 5,
      "findings_count": 4,
      "cognitive_independence_claim": false,
      "role_bound_only": true
    },
    {
      "role": "COVERAGE",
      "git_blob_sha": "625f277b0b76c5b54e290d134126759a11c0ff02",
      "reference": "https://github.com/cristhianlujan/claude-persona-lf-patch/blob/00956e82aee18d4c1b768865a23bf35ce8409597/docs/profile_updater/experiments/pe10_methods32_p0/M17_roles/COVERAGE_RAW_V1.json#git_blob_sha=625f277b0b76c5b54e290d134126759a11c0ff02",
      "method_code": "PE10_M17",
      "query_ids": [
        "M17_COVER_Q1",
        "M17_COVER_Q2",
        "M17_COVER_Q3",
        "M17_COVER_Q4",
        "M17_COVER_Q5",
        "M17_COVER_Q6"
      ],
      "query_count": 6,
      "negative_ids": [
        "COVER_38_UNIQUE_DEDUPE",
        "COVER_HASH_SYNTAX_NOT_METHOD",
        "COVER_CALLERS_RECONCILED",
        "COVER_EXTERNALS_RECONCILED",
        "COVER_NULL_COUNTEREXAMPLE",
        "COVER_BAD_DENOMINATOR_REJECT",
        "COVER_NULL_DENOMINATOR_REJECT",
        "COVER_VALID_DENOMINATOR_PASS"
      ],
      "negative_passed": 8,
      "negative_count": 8,
      "findings_count": 5,
      "cognitive_independence_claim": false,
      "role_bound_only": true
    },
    {
      "role": "INNOVATION",
      "git_blob_sha": "510994ab39a5ba3d20220d19bc3dccbdab4d7fb1",
      "reference": "https://github.com/cristhianlujan/claude-persona-lf-patch/blob/9bb0a4348784ea317077970590678b5b6b9eb76f/docs/profile_updater/experiments/pe10_methods32_p0/M17_roles/INNOVATION_RAW_V1.json#git_blob_sha=510994ab39a5ba3d20220d19bc3dccbdab4d7fb1",
      "method_code": "PE10_M17",
      "query_ids": [
        "M17_INNOV_Q1",
        "M17_INNOV_Q2",
        "M17_INNOV_Q3",
        "M17_INNOV_Q4",
        "M17_INNOV_Q5",
        "M17_INNOV_Q6"
      ],
      "query_count": 6,
      "negative_ids": [
        "INNOV_TRI_TEMPORAL_ORDER",
        "INNOV_SOURCE_LABEL_NOT_NOW",
        "INNOV_NO_PREDETERMINED_ACCEPTANCE",
        "INNOV_P0_NO_RUNTIME_ACTIVATION",
        "INNOV_RECEIPT_VERIFIED_NOT_PERF"
      ],
      "negative_passed": 5,
      "negative_count": 5,
      "findings_count": 4,
      "cognitive_independence_claim": false,
      "role_bound_only": true
    }
  ],
  "synthesis_ref": {
    "path": "docs/profile_updater/experiments/pe10_methods32_p0/M17_SYNTHESIS_V1.json",
    "source_commit": "49b96283b26742f6b58de3316b1bff0265ec86c9",
    "git_blob_sha": "543e420ea189b49f412fa464dc9a5116324d7e97"
  },
  "synthesis": {
    "schema": "PE10_M17_SYNTHESIS_V1",
    "case_ref": "PE10-IG-M107-M109-P0",
    "method_code": "PE10_M17",
    "base_code": "B",
    "algorithm_codes": [],
    "source_cutoff": "2026-10-15T00:00:00Z",
    "role_code": "SYNTHESIZER",
    "source_scope": "READ_ONLY_P0_HISTORICAL_AND_EXPLICIT_CURRENT_ROLE",
    "role_bound_single_context": true,
    "autonomous_agent_claim": false,
    "synthesis_inputs": [
      {
        "role": "ARCHITECTURE",
        "path": "docs/profile_updater/experiments/pe10_methods32_p0/M17_roles/ARCHITECTURE_RAW_V1.json",
        "git_blob_sha": "037627c35260541fb26ec928c3f58d9d8c430958",
        "source_commit": "3dea196657b4697694a564da94df7a39011439cf",
        "evidence_ref": "https://github.com/cristhianlujan/claude-persona-lf-patch/blob/3dea196657b4697694a564da94df7a39011439cf/docs/profile_updater/experiments/pe10_methods32_p0/M17_roles/ARCHITECTURE_RAW_V1.json#git_blob_sha=037627c35260541fb26ec928c3f58d9d8c430958",
        "readbacks": 5,
        "negative_tests": 3,
        "passed": 3,
        "role_output_frozen": true
      },
      {
        "role": "PERFORMANCE",
        "path": "docs/profile_updater/experiments/pe10_methods32_p0/M17_roles/PERFORMANCE_RAW_V1.json",
        "git_blob_sha": "77ff870b20a97e797f08ce1a228d69215cdd5d11",
        "source_commit": "4c02efa6e65e4155bab826a8b4d5bff9268c087f",
        "evidence_ref": "https://github.com/cristhianlujan/claude-persona-lf-patch/blob/4c02efa6e65e4155bab826a8b4d5bff9268c087f/docs/profile_updater/experiments/pe10_methods32_p0/M17_roles/PERFORMANCE_RAW_V1.json#git_blob_sha=77ff870b20a97e797f08ce1a228d69215cdd5d11",
        "readbacks": 5,
        "negative_tests": 6,
        "passed": 6,
        "role_output_frozen": true
      },
      {
        "role": "AUTHORITY",
        "path": "docs/profile_updater/experiments/pe10_methods32_p0/M17_roles/AUTHORITY_RAW_V1.json",
        "git_blob_sha": "1b4928c262eb106cfaa9efb77a23bf51311a7e35",
        "source_commit": "0d40747bffba2155f5e3891db0daba2d76e3683c",
        "evidence_ref": "https://github.com/cristhianlujan/claude-persona-lf-patch/blob/0d40747bffba2155f5e3891db0daba2d76e3683c/docs/profile_updater/experiments/pe10_methods32_p0/M17_roles/AUTHORITY_RAW_V1.json#git_blob_sha=1b4928c262eb106cfaa9efb77a23bf51311a7e35",
        "readbacks": 5,
        "negative_tests": 5,
        "passed": 5,
        "role_output_frozen": true
      },
      {
        "role": "COVERAGE",
        "path": "docs/profile_updater/experiments/pe10_methods32_p0/M17_roles/COVERAGE_RAW_V1.json",
        "git_blob_sha": "625f277b0b76c5b54e290d134126759a11c0ff02",
        "source_commit": "00956e82aee18d4c1b768865a23bf35ce8409597",
        "evidence_ref": "https://github.com/cristhianlujan/claude-persona-lf-patch/blob/00956e82aee18d4c1b768865a23bf35ce8409597/docs/profile_updater/experiments/pe10_methods32_p0/M17_roles/COVERAGE_RAW_V1.json#git_blob_sha=625f277b0b76c5b54e290d134126759a11c0ff02",
        "readbacks": 6,
        "negative_tests": 8,
        "passed": 8,
        "role_output_frozen": true
      },
      {
        "role": "INNOVATION",
        "path": "docs/profile_updater/experiments/pe10_methods32_p0/M17_roles/INNOVATION_RAW_V1.json",
        "git_blob_sha": "510994ab39a5ba3d20220d19bc3dccbdab4d7fb1",
        "source_commit": "9bb0a4348784ea317077970590678b5b6b9eb76f",
        "evidence_ref": "https://github.com/cristhianlujan/claude-persona-lf-patch/blob/9bb0a4348784ea317077970590678b5b6b9eb76f/docs/profile_updater/experiments/pe10_methods32_p0/M17_roles/INNOVATION_RAW_V1.json#git_blob_sha=510994ab39a5ba3d20220d19bc3dccbdab4d7fb1",
        "readbacks": 6,
        "negative_tests": 5,
        "passed": 5,
        "role_output_frozen": true
      }
    ],
    "source_pieces_frozen_before_synthesis": true,
    "no_new_sql_in_synthesis": true,
    "readbacks_total": 27,
    "negative_tests_total": 27,
    "negative_tests_passed": 27,
    "findings": [
      {
        "finding": "Historical caller graph has 38 unique SQL caller references with 76 lexical edges and 21 trigger bindings; this does not certify runtime execution.",
        "classification": "MEASURED_ASOF",
        "evidence": [
          "M17_ARQ_Q1",
          "M17_ARQ_Q2",
          "M17_COVER_Q1"
        ]
      },
      {
        "finding": "Six external records are a separate identity/lifecycle domain and cannot simply be added to SQL caller count.",
        "classification": "MEASURED_ASOF",
        "evidence": [
          "M17_ARQ_Q4",
          "M17_COVER_Q3"
        ]
      },
      {
        "finding": "Verified historical SOAK receipt 38 covers 13 screens, 47 families, zero false PASS and zero D4 but is not an E2E or current CP2 authorization receipt.",
        "classification": "MEASURED_SCOPE",
        "evidence": [
          "M17_AUTH_Q2",
          "M17_PERF_Q3"
        ]
      },
      {
        "finding": "Current readonly principal and permissions readback cannot establish historical P0 EXECUTE grants; EKB 42501 is not a functional CP2 failure.",
        "classification": "MEASURED_CURRENT_WITH_HISTORICAL_LIMIT",
        "evidence": [
          "M17_AUTH_Q1",
          "M17_AUTH_Q4",
          "M17_AUTH_Q5"
        ]
      },
      {
        "finding": "Historical event source, verified SOAK receipt, and last EKB observation occur at distinct timestamps before P0; evidence should be versioned per claim.",
        "classification": "MEASURED_TEMPORAL_PROVENANCE",
        "evidence": [
          "M17_INNOV_Q5"
        ]
      },
      {
        "finding": "No qualified E2E latency cohort or runtime execution trace was found within the inspected source fields. Zero rows with track_functions none does not show zero calls or speed.",
        "classification": "MEASURED_SOURCE_LIMIT_NOT_ABSENCE_PROOF",
        "evidence": [
          "M17_PERF_Q1",
          "M17_PERF_Q2",
          "M17_PERF_Q3"
        ]
      },
      {
        "finding": "Synthetic SQL valid, wrong and NULL denominator cases fail/accept as expected; these are guard tests, not proof of business rules or applied repair.",
        "classification": "SYNTHETIC_POSITIVE_NEGATIVE",
        "evidence": [
          "M17_COVER_Q5",
          "M17_COVER_Q6",
          "M17_PERF_Q4"
        ]
      }
    ],
    "apparent_contradictions_resolved": [
      {
        "topic": "Historically verified SOAK vs unknown current CP2/performance",
        "disposition": "NOT_AN_ACTUAL_CONTRADICTION",
        "reason": "Different subject and measurement contracts; verified screening history does not certify functional CP2 or E2E time",
        "evidence": [
          "M17_AUTH_Q2",
          "M17_PERF_Q3"
        ]
      },
      {
        "topic": "Snapshot labeled LIVE_PG_PROC vs current execution unknown",
        "disposition": "NOT_AN_ACTUAL_CONTRADICTION",
        "reason": "The label belongs to pre-cutoff event time, not today's runtime",
        "evidence": [
          "M17_INNOV_Q1",
          "M17_INNOV_Q2",
          "M17_AUTH_Q3"
        ]
      },
      {
        "topic": "Present role EXECUTE readback vs historical privilege warning",
        "disposition": "NOT_AN_ACTUAL_CONTRADICTION",
        "reason": "Different temporal bases; query current grants cannot reconstruct P0 permission state",
        "evidence": [
          "M17_AUTH_Q1",
          "M17_AUTH_Q4",
          "M17_AUTH_Q5"
        ]
      }
    ],
    "actual_unresolved_contradictions": [],
    "causal_model": {
      "proven_root_cause": false,
      "alternatives": [
        "Source-time inventory promoted to current topology",
        "SOAK latest projection versus historical verified receipt mismatch",
        "CP2 privilege/currentness issue separated from functional behavior",
        "Queue or stage cost cannot be compared without cohort timestamps"
      ],
      "negative_falsifiers": [
        "Functional error must remain distinct from privilege 42501",
        "No runtime trace inferred from lexical graph",
        "No speed/zero usage from missing statistics",
        "No production change implied by administrative method closure"
      ]
    },
    "candidate_repairs": [
      {
        "action": "Qualified source-timestamp/identity readback for every claim",
        "status": "PROPOSED_NOT_IMPLEMENTED"
      },
      {
        "action": "Authorized CP2 equivalent SELECT with no elevation",
        "status": "PROPOSED_NOT_IMPLEMENTED"
      },
      {
        "action": "Observe same-clock e2e and stage distributions before performance repair",
        "status": "PROPOSED_NOT_IMPLEMENTED"
      }
    ],
    "chosen_repair": {
      "state": "VERIFY_FIRST",
      "implemented": false,
      "reason": "Historical risks and qualified source scope but causal functional fault remains unproven",
      "next_safe_step": "Time-qualified authorized readback of CP2 and traces; only then decide whether any repair is justified"
    },
    "rejected_alternatives": [
      "Activate candidate closure operation directly",
      "Treat all cached textual mentions as runnable call paths",
      "Treat complete historical caller count as complete live coverage",
      "Assume performance gain without clocks",
      "Escalate readonly connector privileges"
    ],
    "omissions_searched": [
      "timestamp source mismatch",
      "missing/NULL counts",
      "external vs SQL identity domains",
      "authority/role currentness",
      "dynamic vs static edges",
      "verified SOAK vs functional CP2",
      "source read-once concept",
      "alternative no-defect cause"
    ],
    "unresolved": [
      "Canonical historical hash construction UNKNOWN",
      "Source-complete P0 runtime trace UNKNOWN",
      "Equivalent qualified CP2 read status UNKNOWN",
      "E2E stage elapsed metrics and denominator UNKNOWN",
      "No proven domain defect"
    ],
    "constraints_preserved": [
      "No runtime edits",
      "P0 historical cutoff preserved",
      "Original specialist outputs immutable",
      "No cross-method evidence",
      "No external scoring",
      "Not falsely claiming autonomous independent agents"
    ],
    "non_isolation_risk": "Five role-bound research passes were executed sequentially in one shared model context. Sources and frozen report artifacts per role are distinct, but cognitive independence comparable to separate agents is not demonstrated.",
    "performance_cost": {
      "role_queries": 27,
      "transport_elapsed_ms": "NOT_MEASURED",
      "possible_reused_source_reads": "NOT_QUANTIFIED"
    },
    "final_method_status": "B_FIVE_ROLE_REPORTS_AND_SYNTHESIS_MATERIAL_ONLY_NOT_YET_GOVERNED_DONE"
  },
  "source_queries_total": 27,
  "negative_tests_total": 27,
  "negative_tests_passed": 27,
  "synthesis_claims": 7,
  "synthesis_reconciled_apparent_contradictions": 3,
  "final_method_state": "B_ROLE_REPORTS_SYNTHESIZED_NO_DOMAIN_REPAIR",
  "causal_defect_proven": false,
  "solution_state": "VERIFY_FIRST",
  "runtime_modified": false,
  "independence_constraint": {
    "frozen_before_synthesis": true,
    "report_results_from_one_model_context": true,
    "independent_agents": false,
    "leakage_risk": "Shared model cognition not isolated; no role report used as query input to another; synthesizer only reads frozen reports"
  },
  "limits": [
    "Historical P0 sources at distinct event/receipt/EKB times",
    "Current grants and actor do not establish historical P0 permissions",
    "Synthetic counterexamples not a benchmark",
    "No complete runtime invocation population",
    "Domain decision not equivalent to administrative checkpoint DONE"
  ]
}
$m17_raw$;
 v_doc jsonb;v_spec jsonb:=$m17_spec${"status":"READY","action_kind":"VERIFY_QUERY_ONCE","recipe_mode":"READBACK_EXACT","requires_material_execution":true,"contract_family":"PE10_METHOD_EXECUTION_EVIDENCE","precision":"PE10_METHOD_V1_MATERIAL_EVIDENCE","assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"checkpoint_identity":"PE10_M17","base_code":"B","role_reports_frozen":5,"synthesis_completed":true,"read_only_sql_queries":27,"role_negative_tests_passed":27,"apparent_contradictions_reconciled":3,"role_bound_same_context":true,"independent_agents_claimed":false,"source_event_id":20161,"git_raw_source_verified":true,"runtime_modified":false}},"evidence_ref":"https://github.com/cristhianlujan/claude-persona-lf-patch/blob/303240b84e86fba7c0ea83ce96bfec730a4ecae2/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M17_RAW_V2.json#git_blob_sha=ba0f0962fcad168c2ecac7cbde12fa657e16c68f","verification_queries":["SELECT id,created_at,payload->'scope_guards' FROM public.lf_eventos WHERE id=20161","SELECT id,created_at,payload->>'verification_status' FROM programacion.provenance_receipts WHERE id=38","SELECT codigo,primera_vez FROM transversal.error_knowledge WHERE codigo IN('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001')"],"expected":"B method five distinct role-bound frozen reports with original query and negative evidence, then one synthesis. Shared model context declared; no autonomous agent independence asserted; not a product repair.","forbidden":["TREAT_SINGLE_LENS_AS_FIVE_AGENTS","CLAIM_INDEPENDENT_AUTONOMOUS_SESSIONS","SYNTHESIZE_BEFORE_FROZEN_REPORTS","PROMOTE_P0_TO_CURRENT","SKIP_TRAIN","TOUCH_OTHER_CHECKPOINTS"],"target":{"checkpoint":"PE10_M17","declared_events":[20161],"declared_objects":["public.lf_eventos","programacion.provenance_receipts","transversal.error_knowledge","programacion.engineering_work_checkpoints"],"evidence_artifacts":[{"path":"cristhianlujan/claude-persona-lf-patch:docs/profile_updater/experiments/pe10_methods32_p0/PE10_M17_RAW_V2.json","role":"EVIDENCE","purpose":"PE10_M17_B_FIVE_ROLE_REPORTS_SYNTHESIS_AGGREGATE","target_kind":"EXACT_EXISTING_FILE"}]}}$m17_spec$::jsonb;
 v_ref text:='https://github.com/cristhianlujan/claude-persona-lf-patch/blob/303240b84e86fba7c0ea83ce96bfec730a4ecae2/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M17_RAW_V2.json#git_blob_sha=ba0f0962fcad168c2ecac7cbde12fa657e16c68f';v_old text:='chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M17.json#sha256=105a7dddfb5ba49ee5b29e3c63f1c215f820fd7505ef0bd1c9a8a67ec1ad93f5';v_blob text;
 v_prior int;v_roles int;v_queries int;v_tests int;v_reconcile int;v_ekb int;v_n int;
 v_contract jsonb;v_obs jsonb;v_result jsonb;v_assertion jsonb;v_transition jsonb;v_receipt text;
 v_msg text;v_ctx text;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
 AND target_code LIKE '%lf_pe10_m17_b_role_governed_close_v1'
 AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'M17_NOT_TRAIN_EXECUTOR'; END IF;
 IF (SELECT status FROM programacion.engineering_work_items WHERE id=1133)<>'IN_PROGRESS'
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>16
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>16
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND checkpoint_code='PE10_M17'
 AND id=1641 AND status='PENDING' AND evidence_ref=v_old
 AND assertion_receipt IS NULL AND completed_at IS NULL)<>1
 OR (SELECT count(*) FROM programacion.pe10_method_variants WHERE method_code='PE10_M17'
 AND base_code='B' AND case_ref='PE10-IG-M107-M109-P0'
 AND algorithm_codes=ARRAY[]::text[])<>1
 OR (SELECT count(*) FROM programacion.engineering_plan_units WHERE work_item_id=1133
 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32'
 AND unit_metadata#>>'{action_specs_v1,PE10_M17,status}'='BLOCK_PENDING_MATERIAL_RESEARCH_AND_VALIDATION')<>1
 THEN RAISE EXCEPTION 'M17_PRESTATE_OR_B_CONTRACT_NOT_QUALIFIED'; END IF;
 SELECT count(*) INTO v_prior FROM programacion.engineering_work_checkpoints c
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
('PE10_M15','1e43cfc81056ee40c1f94f56438bac1e34ce5cb6331112c9c602b438fb1f8319'),
('PE10_M16','6306d3bc3720167c6d7d6f39543ceb019ca005b3214a4bf336af03765a0bd377')
 ) x(code,sha) ON x.code=c.checkpoint_code AND x.sha=c.assertion_receipt_sha256
 WHERE c.work_item_id=1133 AND c.status='DONE' AND c.assertion_receipt->>'passed'='true'
 AND c.assertion_contract_sha256=c.assertion_receipt->>'contract_sha256';
 IF v_prior<>16 THEN RAISE EXCEPTION 'M17_PRIOR_16_RECEIPTS_CHANGED'; END IF;

 v_blob:=encode(extensions.digest(convert_to('blob '||octet_length(convert_to(v_raw,'UTF8'))::text,'UTF8')
 ||decode('00','hex')||convert_to(v_raw,'UTF8'),'sha1'),'hex');
 IF v_blob<>'ba0f0962fcad168c2ecac7cbde12fa657e16c68f' THEN RAISE EXCEPTION 'M17_RAW_GIT_BLOB_NOT_VERIFIED'; END IF;
 v_doc:=v_raw::jsonb;
 IF v_doc->>'schema'<>'PE10_METHOD_RAW_V2'
 OR v_doc->>'case_ref'<>'PE10-IG-M107-M109-P0'
 OR v_doc->>'method_code'<>'PE10_M17'
 OR v_doc->>'base_code'<>'B'
 OR v_doc->'algorithm_codes'<>'[]'::jsonb
 OR v_doc->>'source_cutoff'<>'2026-10-15T00:00:00Z'
 OR v_doc#>>'{original_preserved,sha256}'<>'105a7dddfb5ba49ee5b29e3c63f1c215f820fd7505ef0bd1c9a8a67ec1ad93f5'
 OR v_doc->>'external_evaluation'<>'NOT_PERFORMED'
 OR v_doc->>'autonomous_agent_claim'<>'false'
 OR v_doc->>'role_bound_single_context'<>'true'
 OR v_doc#>>'{independence_constraint,independent_agents}'<>'false'
 OR v_doc#>>'{independence_constraint,frozen_before_synthesis}'<>'true'
 OR v_doc#>>'{synthesis,role_code}'<>'SYNTHESIZER'
 OR v_doc#>>'{synthesis,source_pieces_frozen_before_synthesis}'<>'true'
 OR v_doc#>>'{synthesis,no_new_sql_in_synthesis}'<>'true'
 OR v_doc#>>'{synthesis,chosen_repair,state}'<>'VERIFY_FIRST'
 OR v_doc->>'final_method_state'<>'B_ROLE_REPORTS_SYNTHESIZED_NO_DOMAIN_REPAIR'
 THEN RAISE EXCEPTION 'M17_B_ROLE_AUTHENTICITY_OR_SYNTHESIS_NOT_QUALIFIED'; END IF;

 -- Exact author-assigned role and Git blob matching for all five frozen reports:
 WITH expected(role,sha,nqueries,nneg) AS (VALUES
 ('ARCHITECTURE','037627c35260541fb26ec928c3f58d9d8c430958',5,3),
('PERFORMANCE','77ff870b20a97e797f08ce1a228d69215cdd5d11',5,6),
('AUTHORITY','1b4928c262eb106cfaa9efb77a23bf51311a7e35',5,5),
('COVERAGE','625f277b0b76c5b54e290d134126759a11c0ff02',6,8),
('INNOVATION','510994ab39a5ba3d20220d19bc3dccbdab4d7fb1',6,5)
 ),actual AS (
 SELECT x->>'role' role,x->>'git_blob_sha' sha,
 (x->>'query_count')::int nqueries,(x->>'negative_count')::int nneg,
 (x->>'negative_passed')::int passed, x->>'reference' evidence_uri,
 x->>'role_bound_only' role_bound,x->>'cognitive_independence_claim' independent
 FROM jsonb_array_elements(v_doc->'role_reports') x
 )
 SELECT count(*),coalesce(sum(a.nqueries),0),coalesce(sum(a.nneg),0)
 INTO v_roles,v_queries,v_tests
 FROM expected e JOIN actual a USING(role,sha,nqueries,nneg)
 WHERE a.passed=a.nneg AND a.role_bound='true' AND a.independent='false'
 AND position(a.sha in a.evidence_uri)>0;
 IF v_roles<>5 OR v_queries<>27 OR v_tests<>27
 OR jsonb_array_length(v_doc->'role_reports')<>5
 OR v_doc->>'source_queries_total'<>'27'
 OR v_doc->>'negative_tests_total'<>'27'
 OR v_doc->>'negative_tests_passed'<>'27'
 OR v_doc#>>'{synthesis,readbacks_total}'<>'27'
 OR v_doc#>>'{synthesis,negative_tests_total}'<>'27'
 OR v_doc#>>'{synthesis,negative_tests_passed}'<>'27'
 OR jsonb_array_length(v_doc#>'{synthesis,synthesis_inputs}')<>5
 OR jsonb_array_length(v_doc#>'{synthesis,findings}')<>7
 OR v_doc#>>'{synthesis_ref,git_blob_sha}'<>'543e420ea189b49f412fa464dc9a5116324d7e97'
 THEN RAISE EXCEPTION 'M17_FIVE_REPORTS_AND_EVIDENCE_MANIFEST_FAILED'; END IF;

 SELECT count(*) INTO v_reconcile FROM jsonb_array_elements(v_doc#>'{synthesis,apparent_contradictions_resolved}') x
 WHERE x->>'disposition'='NOT_AN_ACTUAL_CONTRADICTION'
 AND jsonb_typeof(x->'evidence')='array'
 AND jsonb_array_length(x->'evidence')>=2;
 IF v_reconcile<>3 OR jsonb_array_length(v_doc#>'{synthesis,apparent_contradictions_resolved}')<>3
 OR jsonb_array_length(v_doc#>'{synthesis,actual_unresolved_contradictions}')<>0
 OR length(coalesce(v_doc#>>'{synthesis,non_isolation_risk}',''))<60
 OR v_doc#>>'{synthesis,autonomous_agent_claim}'<>'false'
 THEN RAISE EXCEPTION 'M17_SYNTHESIS_RECONCILIATION_OR_ISOLATION_RISK_OMITTED'; END IF;

 SELECT count(*) INTO v_ekb FROM transversal.error_knowledge WHERE codigo IN (
 'IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001')
 AND primera_vez<TIMESTAMPTZ '2026-10-15T00:00:00Z';
 IF v_ekb<>2
 OR (SELECT count(*) FROM public.lf_eventos WHERE id=20161
 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'
 AND jsonb_array_length(payload->'sql_callers')=38
 AND jsonb_array_length(payload->'trigger_bindings')=21
 AND jsonb_array_length(payload->'external_inventory')=6
 AND payload->'usage_stats'->>'track_functions'='none')<>1
 OR (SELECT count(*) FROM programacion.provenance_receipts WHERE id=38
 AND created_at<TIMESTAMPTZ '2026-10-15T00:00:00Z'
 AND payload->>'verification_status'='VERIFIED' AND payload->>'screens_total'='13'
 AND payload->>'families_total'='47'
 AND payload->>'known_false_pass_signals'='0'
 AND payload->>'unresolved_d4'='0')<>1
 THEN RAISE EXCEPTION 'M17_HISTORICAL_P0_SOURCES_DIFFER'; END IF;

 UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10_M17}',v_spec,true)
 WHERE work_item_id=1133 AND plan_code='PEVO-PE10-METHODS32-P0' AND unit_code='METHODS32';
 GET DIAGNOSTICS v_n=ROW_COUNT;
 IF v_n<>1 THEN RAISE EXCEPTION 'M17_ACTION_SPEC_UPDATE_COUNT_FAILED'; END IF;
 v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M17',
 programacion.fn_engineering_checkpoint_action_spec_v3('PEVO-PE10-METHODS32-P0','METHODS32','PE10_M17'));
 IF v_contract->>'status'<>'READY' OR v_contract->>'mode'<>'EXPLICIT_PASS_WHEN_SUBSET'
 THEN RAISE EXCEPTION 'M17_ASSERTION_CONTRACT_NOT_READY:%',coalesce(v_contract::text,'NULL'); END IF;
 v_obs:=jsonb_build_object('checkpoint_identity','PE10_M17','base_code','B',
 'role_reports_frozen',v_roles,'synthesis_completed',true,
 'read_only_sql_queries',v_queries,'role_negative_tests_passed',v_tests,
 'apparent_contradictions_reconciled',v_reconcile,
 'role_bound_same_context',true,'independent_agents_claimed',false,
 'source_event_id',20161,'git_raw_source_verified',true,'runtime_modified',false);
 v_result:=jsonb_build_object('status','PASS','observed',v_obs,'evidence_ref',v_ref,
 'validation_kind','M17_B_FIVE_ROLE_BOUND_REPORTS_AND_SYNTHESIS_MATERIAL_ONLY',
 'independent_autonomous_agents',false,'product_repair_applied',false);
 v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M17',v_result,v_exec);
 IF v_assertion->>'passed'<>'true'
 OR coalesce(v_assertion->>'assertion_receipt_sha256','') !~ '^[a-f0-9]{64}$'
 THEN RAISE EXCEPTION 'M17_CANONICAL_RECEIPT_NOT_PASSED'; END IF;
 v_receipt:=v_assertion->>'assertion_receipt_sha256';
 v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
 'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M17','DONE',v_ref,v_exec,
 'M17 B 5 frozen role-bound reports plus synthesis verified; no autonomous-agent independence claim');
 IF v_transition#>>'{transition,status}'<>'APPLIED'
 THEN RAISE EXCEPTION 'M17_STATUS_TRANSITION_NOT_CANONICAL'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=1133 AND checkpoint_code='PE10_M17'
 AND status='DONE' AND completed_at IS NOT NULL AND evidence_ref=v_ref
 AND assertion_receipt_sha256=v_receipt AND assertion_receipt->>'passed'='true'
 AND assertion_contract_sha256=assertion_receipt->>'contract_sha256')<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>17
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>15
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133
 AND checkpoint_code='PE10_M18' AND status='PENDING')<>1
 THEN RAISE EXCEPTION 'M17_POST_TRAIN_GOVERNED_READBACK_FAILED'; END IF;
EXCEPTION WHEN OTHERS THEN
 GET STACKED DIAGNOSTICS v_msg=MESSAGE_TEXT,v_ctx=PG_EXCEPTION_CONTEXT;
 RAISE EXCEPTION 'M17_TRAIN_ERROR state=% msg=% context=%',SQLSTATE,left(v_msg,290),left(v_ctx,150) USING ERRCODE=SQLSTATE;
END $m17_close$;
