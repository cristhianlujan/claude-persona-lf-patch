===ROLE_REPORT:ARCHITECTURE BEGIN===

Scope: Architecture, dependency identity, version continuity, caller/callee relationships, and source-to-executor boundaries.

Sources: P0 packet; QUERY_RESULT Q1–Q8. All post-cutoff database observations are CURRENT.

Historical source verification: Q2 confirms the source-event payload SHA-256 matches the packet. The P0 inventory contains 38 distinct callers, 76 declared relationships, and 39 distinct callee names.

CURRENT hash comparison: Q3 identifies 23 modified definitions and 15 unchanged definitions, with no missing caller identities among the 38 checked objects. Every historical caller has one matching CURRENT schema/name candidate and retains its historical OID.

CURRENT reverse-consumer census: Q4 provides a complete 446-record candidate ledger with individual consumer identities, OIDs, called schemas, function names, and callee identities. Its categories are 68 HISTORICAL_EDGE_DECLARED, 102 CURRENT_EDGE_NOT_IN_P0, and 276 CURRENT_CONSUMER_OUTSIDE_P0.

The authoritative individual candidate witness inventory for this report is the complete QUERY_RESULT_Q4.txt, Q4 rows 1–446, keyed by consumer_identity, called_schema, and called_name. Every row is retained as an UNREVIEWED static candidate unless specifically qualified below. The summary counts do not replace the individual records.

Eight missing historical direct references: All eight Q5 identities are retained, with their historical positions and callees:

Position 6: bootstrap_classify_v2_cached_v1 → bootstrap_classify_v1_cached_v1, and → semantic_probe_v3

Position 11: curator_materialize_v1 → readiness_run_is_current_cached_v1

Position 16: recurate_source_stale_v1 → bootstrap_classify_v2_cached_v1

Position 17: recurate_v2 → bootstrap_classify_v2

Position 23: shadow_evaluate_v2 → bootstrap_classify_v2, and → semantic_probe_v3

Position 25: validate_v2 → bootstrap_classify_v2

All abbreviated function names above retain their programacion schema from Q5.

Concrete replacement paths: Q6–Q7 identify CURRENT delegation through bootstrap_classify_v2_cached_v2, bootstrap_classify_v2_ctx, curator_plan_v1, and changed Validator assertion helpers. These explain plausible structural refactoring, not proven semantic equivalence.

Individual material outside-inventory witnesses:

Q8, OID 49427: lf_ops.fn_b2b_backoffice_login_contract → programacion.fn_input_effective_rule_links_v1

Q8, OID 275398: lf_ops.fn_screen_contract_v1 → programacion.fn_input_effective_rule_links_v1

Q8, OID 243263: private.fn_lf_ig_human_decision_live_disposition_v1 → programacion.fn_input_governance_bootstrap_classify_v2

Q8, OID 219907: programacion.fn_input_validator_compaction_batch_v1 contains a function-definition hash lookup of programacion.fn_guard_input_family_assessment_update(), not a direct call.

Confirmed lexical false positives:

Q4/Q6: Curator materialization self-reference inside a receipt's entrypoint string.

Q4/Q8: Compaction batch reference to the assessment guard inside a regprocedure literal used by pg_get_functiondef.

Both retain their original Q4 witness identities, with the reason for non-promotion explicitly recorded.

GDE conflict hypotheses:

H1: The original P0 inventory is complete for CURRENT consumers. Contradicted by Q4's additional individual consumer candidates; the current executable universe remains unknown.

H2: Missing historical direct calls indicate broken behavior. Not demonstrated; Q6–Q7 reveal replacement paths.

H3: Preserved entry-point hashes imply preserved downstream behavior. Not demonstrated; Q3 shows downstream definition drift.

H4: Every uniquely resolved lexical reference is executable. Falsified by the two inspected string/metadata cases.

H5: No architecture defect exists and observed differences result from controlled refactoring. Still possible; equivalence and runtime evidence remain missing.

No justified statistical priors or execution spectra are available for BARINEL calibration. Query prioritization used ordinal evidentiary discrimination rather than fabricated entropy values.

Unresolved: Full edge-context classification; effective callable privileges; active cron/trigger reachability; Edge and dynamic consumers; historical source bodies; semantic equivalence of cached/context variants; runtime execution; and query-performance costs.

Minimal safe action: Preserve the complete individual candidate ledger, investigate reachable and high-impact unresolved edges, run authorized read-only privilege and dependency checks, and require independent equivalence evidence before considering changes.

Measured costs: NO_MEDIDO.

Environment limitation: Five sequential role-bound investigations share one context. Provider-level isolation is not independently attested; strict blind-independence state remains CONTAMINATED for attestation purposes.

Repair conclusion: No concrete architecture defect has been demonstrated. No repair is authorized by this report.

===ROLE_REPORT:ARCHITECTURE END===
