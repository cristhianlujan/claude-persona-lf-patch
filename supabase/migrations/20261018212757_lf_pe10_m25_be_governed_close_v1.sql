DO $m25$
DECLARE
  v_exec text;
  v_raw text:=$raw${
  "schema": "PE10_METHOD_RAW_V2",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M25",
  "base_code": "B",
  "algorithm_codes": [
    "E"
  ],
  "method_catalog": "PE10_METHOD_V1",
  "source_cutoff": "2026-10-15T00:00:00Z",
  "original_preserved": {
    "ref": "chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M25.json",
    "sha256": "b0809de7b913badea7b7b34e223ec85ed91bd9d7a7443e23e414956a25c22ed7"
  },
  "role_bound_single_context": true,
  "autonomous_agent_claim": false,
  "cross_method_inputs_used": false,
  "external_evaluation": "NOT_PERFORMED",
  "role_reports": [
    {
      "role": "ARCHITECTURE",
      "path": "docs/profile_updater/experiments/pe10_methods32_p0/M25_roles/ARCHITECTURE_RAW_V1.json",
      "git_blob_sha": "d28c5e4800c403b53c665867c59b8a5c74da7760",
      "query_count": 8,
      "successful_query_count": 7,
      "query_error_count": 1,
      "negative_count": 3,
      "decision_state": "VERIFY_FIRST",
      "role_output_frozen": true
    },
    {
      "role": "PERFORMANCE",
      "path": "docs/profile_updater/experiments/pe10_methods32_p0/M25_roles/PERFORMANCE_RAW_V1.json",
      "git_blob_sha": "42e9e4a74415e2ab0916d49828deae4516020ef5",
      "query_count": 6,
      "successful_query_count": 6,
      "query_error_count": 0,
      "negative_count": 3,
      "decision_state": "NEEDS_MORE_EVIDENCE",
      "role_output_frozen": true
    },
    {
      "role": "AUTHORITY",
      "path": "docs/profile_updater/experiments/pe10_methods32_p0/M25_roles/AUTHORITY_RAW_V1.json",
      "git_blob_sha": "7323a2571023ea150207cd23c3618d4e15e6ad48",
      "query_count": 10,
      "successful_query_count": 10,
      "query_error_count": 0,
      "negative_count": 3,
      "decision_state": "VERIFY_FIRST",
      "role_output_frozen": true
    },
    {
      "role": "COVERAGE",
      "path": "docs/profile_updater/experiments/pe10_methods32_p0/M25_roles/COVERAGE_RAW_V1.json",
      "git_blob_sha": "3ccf5f11c8106da549f74b93a8d9e9c9b7671873",
      "query_count": 8,
      "successful_query_count": 7,
      "query_error_count": 1,
      "negative_count": 3,
      "decision_state": "VERIFY_FIRST",
      "role_output_frozen": true
    },
    {
      "role": "INNOVATION",
      "path": "docs/profile_updater/experiments/pe10_methods32_p0/M25_roles/INNOVATION_RAW_V1.json",
      "git_blob_sha": "d74165e48b6776d7ffe564a8324f684f6e6e317d",
      "query_count": 5,
      "successful_query_count": 5,
      "query_error_count": 0,
      "negative_count": 4,
      "decision_state": "NO_ACTION_SUPPORTED",
      "role_output_frozen": true
    }
  ],
  "synthesis_ref": {
    "path": "docs/profile_updater/experiments/pe10_methods32_p0/M25_SYNTHESIS_V1.json",
    "source_commit": "28904afc66ccc1e1d79336fc277666a581726e2c",
    "git_blob_sha": "a3e06cf340da73a8f2571f09236df8536a41ba84"
  },
  "synthesis": {
    "schema": "PE10_M25_SYNTHESIS_V1",
    "case_ref": "PE10-IG-M107-M109-P0",
    "method_code": "PE10_M25",
    "definition_version": "PE10_METHOD_V1",
    "base_code": "B",
    "algorithm_codes": [
      "E"
    ],
    "synthesizer_contract": {
      "inputs": "Only the five separately frozen M25 role RAW files listed in frozen_role_inputs.",
      "role_bound_single_context": true,
      "independent_agents_claimed": false,
      "shared_context_non_isolation_risk": "The producers and synthesizer were role-bound sequential passes in one coordinated model context. Blob freezing prevents later rewriting but does not create independent-agent isolation.",
      "cross_method_results_used": false,
      "voting_used": false,
      "reconciliation_rule": "Contradictions are resolved by evidence scope, authority and readback limitations, not majority."
    },
    "frozen_role_inputs": [
      {
        "role_code": "ARCHITECTURE",
        "blob_sha": "d28c5e4800c403b53c665867c59b8a5c74da7760",
        "path": "docs/profile_updater/experiments/pe10_methods32_p0/M25_roles/ARCHITECTURE_RAW_V1.json",
        "url": "https://github.com/cristhianlujan/claude-persona-lf-patch/blob/pe10/m25-b-e-evidence-decision-20261018/docs/profile_updater/experiments/pe10_methods32_p0/M25_roles/ARCHITECTURE_RAW_V1.json"
      },
      {
        "role_code": "PERFORMANCE",
        "blob_sha": "42e9e4a74415e2ab0916d49828deae4516020ef5",
        "path": "docs/profile_updater/experiments/pe10_methods32_p0/M25_roles/PERFORMANCE_RAW_V1.json",
        "url": "https://github.com/cristhianlujan/claude-persona-lf-patch/blob/pe10/m25-b-e-evidence-decision-20261018/docs/profile_updater/experiments/pe10_methods32_p0/M25_roles/PERFORMANCE_RAW_V1.json"
      },
      {
        "role_code": "AUTHORITY",
        "blob_sha": "7323a2571023ea150207cd23c3618d4e15e6ad48",
        "path": "docs/profile_updater/experiments/pe10_methods32_p0/M25_roles/AUTHORITY_RAW_V1.json",
        "url": "https://github.com/cristhianlujan/claude-persona-lf-patch/blob/pe10/m25-b-e-evidence-decision-20261018/docs/profile_updater/experiments/pe10_methods32_p0/M25_roles/AUTHORITY_RAW_V1.json"
      },
      {
        "role_code": "COVERAGE",
        "blob_sha": "3ccf5f11c8106da549f74b93a8d9e9c9b7671873",
        "path": "docs/profile_updater/experiments/pe10_methods32_p0/M25_roles/COVERAGE_RAW_V1.json",
        "url": "https://github.com/cristhianlujan/claude-persona-lf-patch/blob/pe10/m25-b-e-evidence-decision-20261018/docs/profile_updater/experiments/pe10_methods32_p0/M25_roles/COVERAGE_RAW_V1.json"
      },
      {
        "role_code": "INNOVATION",
        "blob_sha": "d74165e48b6776d7ffe564a8324f684f6e6e317d",
        "path": "docs/profile_updater/experiments/pe10_methods32_p0/M25_roles/INNOVATION_RAW_V1.json",
        "url": "https://github.com/cristhianlujan/claude-persona-lf-patch/blob/pe10/m25-b-e-evidence-decision-20261018/docs/profile_updater/experiments/pe10_methods32_p0/M25_roles/INNOVATION_RAW_V1.json"
      }
    ],
    "role_states": {
      "ARCHITECTURE": "VERIFY_FIRST",
      "PERFORMANCE": "NEEDS_MORE_EVIDENCE",
      "AUTHORITY": "VERIFY_FIRST",
      "COVERAGE": "VERIFY_FIRST",
      "INNOVATION": "NO_ACTION_SUPPORTED"
    },
    "reconciliation": [
      {
        "id": "M25-SYN-RC01",
        "apparent_conflict": "Innovation selects NO_ACTION_SUPPORTED while Architecture, Authority and Coverage select VERIFY_FIRST.",
        "resolution": "The scopes differ. Innovation rejects runtime/product repair on P0; the other roles request evidence-only verification of currentness, authority and totality. These are compatible: no runtime action, but verify before any current-state closure.",
        "preserved_uncertainty": "Current equivalence and material consumer coverage remain unknown."
      },
      {
        "id": "M25-SYN-RC02",
        "apparent_conflict": "Performance selects NEEDS_MORE_EVIDENCE while the proposed integrated state is VERIFY_FIRST.",
        "resolution": "VERIFY_FIRST is the procedural next state, not a performance verdict. The performance conclusion remains NEEDS_MORE_EVIDENCE until an intervention boundary, complete clocks and matched workload cohort exist.",
        "preserved_uncertainty": "No improvement or regression magnitude is inferred from positive-only or unmatched medians."
      },
      {
        "id": "M25-SYN-RC03",
        "apparent_conflict": "All 38 caller names and 21 trigger names still resolve, yet Architecture reports 22 hash mismatches and six absent lexical edge names.",
        "resolution": "Name/OID existence tests continuity only; it does not establish canonical body-hash equality, route equivalence or runtime invocation. Historical hash serialization is also unknown.",
        "preserved_uncertainty": "The six lexical changes may be replacement, dynamic resolution, rename or removal."
      },
      {
        "id": "M25-SYN-RC04",
        "apparent_conflict": "Receipt 38 is VERIFIED/PASS, while the case still cannot close.",
        "resolution": "Receipt 38 authoritatively verifies historical SOAK_OBSERVATION_HISTORY_V2 criteria. It does not attest a causal performance improvement, post-cut inventory totality, current route equivalence or material actor independence.",
        "preserved_uncertainty": "Historical soak adequacy is preserved; current and performance claims remain separate."
      },
      {
        "id": "M25-SYN-RC05",
        "apparent_conflict": "Curator and Validator identity/component fields differ, but Authority withholds an independence conclusion.",
        "resolution": "Distinct stored labels/components are supporting evidence, not proof of separate effective principals, inputs, execution paths or non-collusion.",
        "preserved_uncertainty": "Material independence requires canonical execution provenance."
      },
      {
        "id": "M25-SYN-RC06",
        "apparent_conflict": "Bounded current complements contain 53 name-pattern objects and 18 lexical candidates outside P0, but Coverage does not call them missing consumers.",
        "resolution": "These searches identify candidates only. Pattern/lexical occurrence cannot prove runtime materiality or define the total universe; P0 also includes eight names outside the selected pattern.",
        "preserved_uncertainty": "The authoritative current universe and exclusion rules are not yet attested."
      }
    ],
    "integrated_findings": [
      {
        "id": "M25-SYN-F01",
        "claim": "P0 supports no demonstrated runtime/product defect: historical soak receipt 38 is verified and its negative criteria are zero.",
        "support": [
          "M25-ARQ-F04",
          "M25-COV-F06",
          "M25-INN-F01"
        ],
        "confidence": "HIGH_WITHIN_P0_SCOPE"
      },
      {
        "id": "M25-SYN-F02",
        "claim": "P0 does not support a causal claim of integral performance improvement or regression.",
        "support": [
          "M25-PERF-F01",
          "M25-PERF-F02",
          "M25-PERF-F04",
          "M25-PERF-F05"
        ],
        "confidence": "HIGH"
      },
      {
        "id": "M25-SYN-F03",
        "claim": "Post-cut object/name continuity is strong for the frozen callers/triggers, but present definition/route equivalence and total consumer coverage are not certified.",
        "support": [
          "M25-ARQ-F02",
          "M25-ARQ-F03",
          "M25-COV-F03",
          "M25-COV-F04",
          "M25-COV-F05"
        ],
        "confidence": "HIGH_FOR_LIMITED_CLAIM"
      },
      {
        "id": "M25-SYN-F04",
        "claim": "The read-only boundary is intentional and must not be widened; permission denial is not functional failure.",
        "support": [
          "M25-AUT-F01",
          "M25-AUT-F02"
        ],
        "confidence": "HIGH"
      },
      {
        "id": "M25-SYN-F05",
        "claim": "Nominal identity/component separation is observed, but material Curator/Validator independence is not attested.",
        "support": [
          "M25-AUT-F04"
        ],
        "confidence": "HIGH_FOR_FIELDS_ONLY"
      },
      {
        "id": "M25-SYN-F06",
        "claim": "Existing manifest/context/cache surfaces argue for reuse-first verification and against creating a new runtime mechanism without a proven gap.",
        "support": [
          "M25-INN-F03",
          "M25-INN-F04",
          "M25-INN-F05"
        ],
        "confidence": "MEDIUM_HIGH"
      }
    ],
    "algorithm_application": {
      "E": {
        "state": "VERIFY_FIRST",
        "rationale": "No runtime repair is supported by P0, but present-state closure is also unsupported. A bounded evidence-only verification can discriminate current topology/coverage/authority risks; performance remains explicitly NEEDS_MORE_EVIDENCE until a matched cohort exists.",
        "demonstrated_defect": false,
        "repair_authorized": false,
        "no_action_scope": "No production, runtime, grant, variant-deletion or optimization action.",
        "verification_scope": [
          "Canonical current object/consumer/trigger manifest with documented hash serialization, active-entry mapping, lifecycle and exclusions.",
          "Canonical authority/ledger linkage and material Curator/Validator independence readback.",
          "Matched performance comparison with explicit intervention boundary, equivalent workload and complete clocks."
        ],
        "evidence": [
          "ARCHITECTURE:d28c5e4800c403b53c665867c59b8a5c74da7760",
          "PERFORMANCE:42e9e4a74415e2ab0916d49828deae4516020ef5",
          "AUTHORITY:7323a2571023ea150207cd23c3618d4e15e6ad48",
          "COVERAGE:3ccf5f11c8106da549f74b93a8d9e9c9b7671873",
          "INNOVATION:d74165e48b6776d7ffe564a8324f684f6e6e317d"
        ],
        "potential_falsifiers": [
          "Authoritative current manifest proves body/route/entry equivalence and complete material consumer coverage.",
          "Canonical provenance proves material independence and valid current verification without privilege widening.",
          "Matched complete performance evidence establishes or rejects a material change."
        ],
        "reversal_criteria": {
          "to_REPAIR_REQUIRED": "A governed verification demonstrates a material active defect with an attributable minimal target.",
          "to_NO_ACTION_SUPPORTED": "All currentness, coverage, authority and matched-performance unknowns close without a material defect.",
          "to_NEEDS_MORE_EVIDENCE": "The three verification products cannot be obtained safely or remain underpowered/ambiguous."
        }
      }
    },
    "causal_model": {
      "integrated_hypothesis": "The immediate systemic risk is evidence-scope collapse: valid historical soak evidence, static inventory, nominal identities and descriptive timings can be merged into an unsupported claim of current, causal and independent improvement.",
      "causal_chain": [
        "valid bounded evidence",
        "scope/time/authority collapse",
        "unsupported equivalence or speed claim",
        "premature closure",
        "potential hidden consumer, route or independence risk"
      ],
      "competing_hypotheses": [
        "No current defect exists and only certification is missing.",
        "A current architecture/coverage defect exists outside P0.",
        "A real performance change exists but available cohorts are incomparable.",
        "Duplicate/context variants are intentional compatibility surfaces."
      ]
    },
    "candidate_repairs": [
      {
        "id": "M25-SYN-A0",
        "action": "No runtime repair or privilege change.",
        "risk": "LOW",
        "authorized": true
      },
      {
        "id": "M25-SYN-A1",
        "action": "Evidence-only current manifest and authority/independence receipt through existing canonical surfaces.",
        "risk": "LOW",
        "authorized_as_plan_only": true
      },
      {
        "id": "M25-SYN-A2",
        "action": "Evidence-only matched performance design/replay in an authorized non-production context.",
        "risk": "LOW_TO_MEDIUM",
        "authorized_as_plan_only": true
      },
      {
        "id": "M25-SYN-A3",
        "action": "Modify functions, grants, variants or consumers.",
        "risk": "HIGH",
        "authorized": false
      }
    ],
    "chosen_repair": {
      "immediate": "M25-SYN-A0",
      "next_verification": [
        "M25-SYN-A1",
        "M25-SYN-A2"
      ],
      "note": "This is a diagnostic decision and not an implemented product repair."
    },
    "rejected_alternatives": [
      {
        "id": "M25-SYN-A3",
        "reason": "No material active defect or causal performance target is demonstrated."
      },
      {
        "id": "M25-SYN-X1",
        "action": "Declare current NO_ACTION solely from receipt 38.",
        "reason": "Receipt scope is historical soak, not current equivalence or performance causality."
      },
      {
        "id": "M25-SYN-X2",
        "action": "Treat outside-P0 lexical objects as proven consumers.",
        "reason": "Static text is not runtime evidence."
      },
      {
        "id": "M25-SYN-X3",
        "action": "Widen read-only EXECUTE to reproduce currentness.",
        "reason": "Contradicts validated EKB governance and is unnecessary for evidence planning."
      }
    ],
    "constraints_preserved": [
      "READ_ONLY investigation",
      "No production/runtime mutation",
      "No EXECUTE invocation or grant widening",
      "P0 facts separated from post-cut observations",
      "No cross-method result inputs",
      "Five producer RAWs frozen before synthesis",
      "No independent-agent claim",
      "No READY/DONE/PASS product conclusion"
    ],
    "unresolved": [
      "Canonical historical hash serialization",
      "Current active entry points and route equivalence",
      "Total material current consumer universe and exclusions",
      "Canonical authority linkage and material actor independence",
      "Performance intervention boundary, matched cohort and complete clocks",
      "Runtime intent of duplicate/context/cache variants"
    ],
    "next_safe_step": "Through the existing governed Operation/Migration→Train path, attest this M25 method result only. Do not execute the proposed current-system verifications or any runtime repair as part of M25.",
    "measured_costs": {
      "producer_select_attempts": 37,
      "producer_successful_selects": 35,
      "producer_query_errors": 2,
      "producer_files": 5,
      "production_writes": 0,
      "tokens": "NO_MEDIDO"
    },
    "synthesized_at": "2026-10-18T21:22:58.867Z"
  },
  "source_queries_total": 37,
  "successful_queries_total": 35,
  "query_errors_preserved": 2,
  "negative_tests_total": 16,
  "role_state_counts": {
    "VERIFY_FIRST": 3,
    "NEEDS_MORE_EVIDENCE": 1,
    "NO_ACTION_SUPPORTED": 1,
    "REPAIR_REQUIRED": 0
  },
  "algorithm_E_executed": true,
  "evidence_decision_contract": {
    "allowed_states": [
      "VERIFY_FIRST",
      "REPAIR_REQUIRED",
      "NEEDS_MORE_EVIDENCE",
      "NO_ACTION_SUPPORTED"
    ],
    "integrated_state": "VERIFY_FIRST",
    "evidence_scoped": true,
    "falsifiers_specified": true,
    "reversal_criteria_specified": true,
    "implemented_repair": false
  },
  "final_method_state": "B_E_ROLE_REPORTS_SYNTHESIZED_NO_DOMAIN_REPAIR",
  "causal_defect_proven": false,
  "solution_state": "VERIFY_FIRST",
  "runtime_modified": false,
  "independence_constraint": {
    "frozen_before_synthesis": true,
    "report_results_from_one_model_context": true,
    "independent_agents": false
  }
}
$raw$;
  v_doc jsonb;
  v_spec jsonb:=$spec${"status":"READY","action_kind":"VERIFY_QUERY_ONCE","recipe_mode":"READBACK_EXACT","requires_material_execution":true,"contract_family":"PE10_METHOD_EXECUTION_EVIDENCE","precision":"PE10_METHOD_V1_MATERIAL_EVIDENCE","assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"checkpoint_identity":"PE10_M25","base_code":"B","algorithm_E_executed":true,"role_reports_frozen":5,"synthesis_completed":true,"read_only_sql_queries":37,"successful_read_only_queries":35,"query_errors_preserved":2,"role_negative_tests":16,"verify_first_roles":3,"needs_more_evidence_roles":1,"no_action_supported_roles":1,"repair_required_roles":0,"decision_state":"VERIFY_FIRST","causal_defect_proven":false,"implemented_repair":false,"git_raw_source_verified":true,"runtime_modified":false,"independent_agents_claimed":false}},"evidence_ref":"https://github.com/cristhianlujan/claude-persona-lf-patch/blob/cee72c8755a0255faf5f68bfb632adcd68708e01/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M25_RAW_V2.json#git_blob_sha=35ec549bcacb0a5cc916ea3f3a2b5830e3672d84"}$spec$::jsonb;
  v_ref text:='https://github.com/cristhianlujan/claude-persona-lf-patch/blob/cee72c8755a0255faf5f68bfb632adcd68708e01/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M25_RAW_V2.json#git_blob_sha=35ec549bcacb0a5cc916ea3f3a2b5830e3672d84';
  v_old text:='chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M25.json#sha256=b0809de7b913badea7b7b34e223ec85ed91bd9d7a7443e23e414956a25c22ed7';
  v_blob text;
  v_prior jsonb;
  v_after jsonb;
  v_contract jsonb;
  v_obs jsonb;
  v_result jsonb;
  v_assertion jsonb;
  v_transition jsonb;
  v_receipt text;
  v_roles int;
  v_q int;
  v_ok int;
  v_err int;
  v_neg int;
  v_vf int;
  v_nme int;
  v_nas int;
  v_rr int;
  v_n int;
  v_msg text;
  v_ctx text;
BEGIN
  SELECT execution_id
  INTO v_exec
  FROM public.lf_operation_execution
  WHERE operation_code='ACTUALIZACION_DB_LF'
    AND target_type='MIGRATION'
    AND target_code LIKE '%lf_pe10_m25_be_governed_close_v1'
    AND status='IN_PROGRESS'
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_exec IS NULL THEN
    RAISE EXCEPTION 'M25_NOT_TRAIN_EXECUTOR';
  END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='DONE')<>24
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1133 AND status='PENDING')<>8
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=1133 AND checkpoint_code='PE10_M25' AND id=1649
           AND status='PENDING' AND evidence_ref=v_old AND assertion_receipt IS NULL)<>1
     OR (SELECT count(*) FROM programacion.pe10_method_variants
         WHERE method_code='PE10_M25' AND base_code='B'
           AND algorithm_codes=ARRAY['E']::text[]
           AND definition_version='PE10_METHOD_V1')<>1 THEN
    RAISE EXCEPTION 'M25_PRESTATE_FAILED';
  END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=1133 AND sequence_no<25 AND status='DONE'
        AND assertion_receipt->>'passed'='true'
        AND assertion_contract_sha256=assertion_receipt->>'contract_sha256')<>24 THEN
    RAISE EXCEPTION 'M25_PRIOR_RECEIPTS_FAILED';
  END IF;

  SELECT jsonb_agg(jsonb_build_object(
           'c',checkpoint_code,'s',status,'r',assertion_receipt_sha256,'d',completed_at
         ) ORDER BY sequence_no)
  INTO v_prior
  FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=1133 AND sequence_no<25;

  v_blob:=encode(
    extensions.digest(
      convert_to('blob '||octet_length(convert_to(v_raw,'UTF8'))::text,'UTF8')
      ||decode('00','hex')
      ||convert_to(v_raw,'UTF8'),
      'sha1'
    ),
    'hex'
  );
  IF v_blob<>'35ec549bcacb0a5cc916ea3f3a2b5830e3672d84' THEN
    RAISE EXCEPTION 'M25_BLOB_FAILED';
  END IF;

  v_doc:=v_raw::jsonb;
  IF v_doc->>'method_code'<>'PE10_M25'
     OR v_doc->'algorithm_codes'<>'["E"]'::jsonb
     OR v_doc#>>'{original_preserved,sha256}'<>'b0809de7b913badea7b7b34e223ec85ed91bd9d7a7443e23e414956a25c22ed7'
     OR v_doc->>'algorithm_E_executed'<>'true'
     OR v_doc#>>'{evidence_decision_contract,integrated_state}'<>'VERIFY_FIRST'
     OR v_doc#>>'{evidence_decision_contract,implemented_repair}'<>'false'
     OR v_doc#>>'{synthesis,algorithm_application,E,state}'<>'VERIFY_FIRST'
     OR jsonb_array_length(v_doc#>'{synthesis,frozen_role_inputs}')<>5
     OR v_doc->>'causal_defect_proven'<>'false'
     OR v_doc->>'runtime_modified'<>'false'
     OR v_doc#>>'{independence_constraint,independent_agents}'<>'false' THEN
    RAISE EXCEPTION 'M25_AUTHENTICITY_FAILED';
  END IF;

  SELECT
    count(*),
    sum((x->>'query_count')::int),
    sum((x->>'successful_query_count')::int),
    sum((x->>'query_error_count')::int),
    sum((x->>'negative_count')::int),
    sum(CASE WHEN x->>'decision_state'='VERIFY_FIRST' THEN 1 ELSE 0 END),
    sum(CASE WHEN x->>'decision_state'='NEEDS_MORE_EVIDENCE' THEN 1 ELSE 0 END),
    sum(CASE WHEN x->>'decision_state'='NO_ACTION_SUPPORTED' THEN 1 ELSE 0 END),
    sum(CASE WHEN x->>'decision_state'='REPAIR_REQUIRED' THEN 1 ELSE 0 END)
  INTO v_roles,v_q,v_ok,v_err,v_neg,v_vf,v_nme,v_nas,v_rr
  FROM jsonb_array_elements(v_doc->'role_reports') x
  WHERE x->>'role_output_frozen'='true';

  IF v_roles<>5 OR v_q<>37 OR v_ok<>35 OR v_err<>2 OR v_neg<>16
     OR v_vf<>3 OR v_nme<>1 OR v_nas<>1 OR v_rr<>0 THEN
    RAISE EXCEPTION 'M25_MANIFEST_FAILED';
  END IF;

  UPDATE programacion.engineering_plan_units
  SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10_M25}',v_spec,true)
  WHERE work_item_id=1133
    AND plan_code='PEVO-PE10-METHODS32-P0'
    AND unit_code='METHODS32';
  GET DIAGNOSTICS v_n=ROW_COUNT;
  IF v_n<>1 THEN
    RAISE EXCEPTION 'M25_SPEC_FAILED';
  END IF;

  v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
    'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M25',
    programacion.fn_engineering_checkpoint_action_spec_v3(
      'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M25'
    )
  );
  IF v_contract->>'status'<>'READY'
     OR v_contract->>'mode'<>'EXPLICIT_PASS_WHEN_SUBSET' THEN
    RAISE EXCEPTION 'M25_CONTRACT_FAILED';
  END IF;

  v_obs:=jsonb_build_object(
    'checkpoint_identity','PE10_M25',
    'base_code','B',
    'algorithm_E_executed',true,
    'role_reports_frozen',v_roles,
    'synthesis_completed',true,
    'read_only_sql_queries',v_q,
    'successful_read_only_queries',v_ok,
    'query_errors_preserved',v_err,
    'role_negative_tests',v_neg,
    'verify_first_roles',v_vf,
    'needs_more_evidence_roles',v_nme,
    'no_action_supported_roles',v_nas,
    'repair_required_roles',v_rr,
    'decision_state','VERIFY_FIRST',
    'causal_defect_proven',false,
    'implemented_repair',false,
    'git_raw_source_verified',true,
    'runtime_modified',false,
    'independent_agents_claimed',false
  );
  v_result:=jsonb_build_object(
    'status','PASS',
    'observed',v_obs,
    'evidence_ref',v_ref,
    'validation_kind','M25_B_E_ROLE_SYNTHESIS_MATERIAL_ONLY',
    'product_repair_applied',false
  );

  v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
    'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M25',v_result,v_exec
  );
  IF v_assertion->>'passed'<>'true' THEN
    RAISE EXCEPTION 'M25_RECEIPT_FAILED';
  END IF;
  v_receipt:=v_assertion->>'assertion_receipt_sha256';

  v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
    'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M25','DONE',v_ref,v_exec,
    'M25 B+E material evidence verified; decision VERIFY_FIRST; no domain repair'
  );
  IF v_transition#>>'{transition,status}'<>'APPLIED' THEN
    RAISE EXCEPTION 'M25_TRANSITION_FAILED';
  END IF;

  SELECT jsonb_agg(jsonb_build_object(
           'c',checkpoint_code,'s',status,'r',assertion_receipt_sha256,'d',completed_at
         ) ORDER BY sequence_no)
  INTO v_after
  FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=1133 AND sequence_no<25;

  IF v_after<>v_prior
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=1133 AND checkpoint_code='PE10_M25'
           AND status='DONE' AND completed_at IS NOT NULL
           AND evidence_ref=v_ref
           AND assertion_receipt_sha256=v_receipt
           AND assertion_receipt->>'passed'='true'
           AND assertion_contract_sha256=assertion_receipt->>'contract_sha256')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=1133 AND status='DONE')<>25
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=1133 AND status='PENDING')<>7
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=1133 AND checkpoint_code='PE10_M26' AND status='PENDING')<>1 THEN
    RAISE EXCEPTION 'M25_POST_FAILED';
  END IF;
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_msg=MESSAGE_TEXT,v_ctx=PG_EXCEPTION_CONTEXT;
  RAISE EXCEPTION 'M25_TRAIN_ERROR state=% msg=% context=%',
    SQLSTATE,left(v_msg,290),left(v_ctx,150)
    USING ERRCODE=SQLSTATE;
END
$m25$;
