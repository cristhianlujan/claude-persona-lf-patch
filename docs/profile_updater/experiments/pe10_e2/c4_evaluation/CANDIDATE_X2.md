# CANDIDATE X2

Case: PE10-IG-M107-M109-P0 (same case for every candidate). Pair P: the two candidates of a pair come from the same method family; their order is randomized.
Content below is verbatim producer output; nothing was edited.

### ROLE REPORT: ARCHITECTURE

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


### ROLE REPORT: PERFORMANCE

===ROLE_REPORT:PERFORMANCE BEGIN===

Scope: Timing semantics, instrumentation completeness, execution-phase costs, workload comparability, and performance claims.

Evidence: QUERY_RESULT Q9–Q14. Q9 establishes measurement fields; Q10–Q14 provide observed timing data and timestamp reconciliation.

Observed performance cohort: 80 PRE_CUTOFF and two CURRENT completed INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX runs, each with six VALIDATE_V2 chunks and 47 processed families.

Measurement integrity: All 42 individually inspected chunk durations in Q13 agree with timestamp-derived durations. However, 16 of 80 historical comparable runs record zero Validator elapsed time despite positive SQL time, and 53 of 80 record elapsed time less than total SQL time. A run-level elapsed duration is not an authoritative substitute for summed chunk SQL time.

CURRENT per-run witnesses:

Run 933: six chunks; 47 families; 205,179 ms SQL time; 21,231 ms recorded resume waits; 229,436 ms recorded Validator elapsed.

Run 944: six chunks; 47 families; 111,121 ms SQL time; 10,355 ms recorded resume waits; 124,635 ms recorded Validator elapsed.

PRE_CUTOFF comparison: Among 80 structurally comparable runs, median summed SQL time is 78,027 ms. CURRENT median is 158,150 ms for two runs. These are descriptive values only.

Important negative evidence: Both CURRENT runs contain complete chunk timings. The discrepancy cannot be explained by missing timing rows within those two runs. Conversely, matching family counts and chunk counts do not prove equal computational work.

Competing explanations: Database contention, proposal volume, assertion workload, changed function definitions, caching, instrumentation semantics, and workload composition. No cause has been isolated.

BARINEL: Not calibrated; no valid pass/fail execution spectra tied to competing performance faults.

Performance repair status: No execution optimization justified. The demonstrated measurement-integrity issue requires an analysis-level exclusion rule for invalid historical elapsed baselines, not a speculative production code change.

Costs: SQL statement execution costs and coordinator costs remain NO_MEDIDO. Stored application durations are not query costs.

Unresolved: Workload-normalized timings, proposal and assertion cardinalities, execution plans, per-family distributions, environmental conditions, and independent baseline replication.

Safe next step: Preserve raw timing witnesses; compare workload cardinalities and execution plans under authorized read-only access before considering any optimization.

Blindness limitation: Strict independent-role isolation is not attested in this shared conversation context.

===ROLE_REPORT:PERFORMANCE END===


### ROLE REPORT: AUTHORITY

===ROLE_REPORT:AUTHORITY BEGIN===

Scope: CURRENT effective function privileges, schema privileges, role memberships, SECURITY DEFINER boundaries, view access, relation privileges, and row-level security.

Evidence: QUERY_RESULT Q15R, Q16–Q24. QUERY_ERROR Q15 is retained as a query-construction failure and supplies no authorization evidence.

Function grant census: Among 14 selected functions, three have PUBLIC EXECUTE but none has a complete unrestricted PUBLIC function-and-schema grant path.

Effective role/function census: Q16 tested 140 combinations across ten roles and fourteen functions. Ten combinations have both effective schema USAGE and function EXECUTE. The positive pairs are individually preserved in Q16; the remaining pairs are negative for direct invocation under the tested role identities.

Application entry points: authenticated can directly invoke two lf_ops contract functions. service_role can directly invoke three examined public governance wrappers. Five programacion functional roles can directly invoke the examined semantic probe.

Schema trust: None of the ten examined non-owner roles has CREATE on the six tested schemas. The selected privileged functions have configured search paths, but complete name-resolution safety remains unproven.

Privileged helper: programacion.fn_input_effective_rule_links_v1(integer,text), OID 142747, is owned by postgres and marked SECURITY DEFINER. Authenticated and service roles have EXECUTE on the function but lack USAGE on programacion.

View access: lf_ops.v_b2b_backoffice_login_contract, OID 49429, has a catalog-confirmed dependency on function OID 49427. Neither authenticated nor service_role has an effective direct SELECT path to this view.

Relation access: All 26 inspected lf_ops and lf_design relations are owned by postgres, have RLS enabled without FORCE RLS, and lack direct authenticated SELECT. All 26 carry the deny_direct_client_access policy for anon and authenticated, with both policy expressions set to false.

Material authority hypothesis: Two authenticated-callable SECURITY INVOKER contract functions directly reference tables unavailable to the authenticated role. This is a source-and-catalog-supported functional-access concern, not a demonstrated executed failure.

Negative falsifiers: No unrestricted PUBLIC function/schema path was found among the selected functions. No authenticated direct access to the 26 examined relations was found. No authenticated direct SELECT on the identified view was found. No unauthorized data disclosure or privilege escalation was demonstrated.

Constraints: Preserve least privilege, explicit owner boundaries, client-data restrictions, RLS, and the distinction between authorized wrapper invocation and internal function EXECUTE.

Unresolved: Intended contract-function caller identity; actual authenticated invocation outcome; role context inside nested queries; untested consumers and grants; complete function-resolution safety; and whether the callable-but-unusable interface is an actual supported-use defect.

Decision: MEASURE_FIRST. Do not broaden grants, disable RLS, or convert contract functions to SECURITY DEFINER without a demonstrated contract-specific need and independent security review.

Costs: NO_MEDIDO.

Blindness limitation: Strict role independence cannot be independently attested in this shared conversation.

===ROLE_REPORT:AUTHORITY END===


### ROLE REPORT: COVERAGE

===ROLE_REPORT:COVERAGE BEGIN===

Scope: CURRENT executable dependency surfaces outside the original function-body caller inventory, including DML triggers, SQL rules, scheduled commands, queue dispatch, event triggers, foreign tables, and queue-entry authorization.

Evidence: QUERY_RESULT Q25–Q31, Q32R, Q33, and Q34R. QUERY_ERROR Q32 and QUERY_ERROR Q34 are retained as failed query attempts and contribute no catalog findings.

DML-trigger inventory: Q25 identified 16 enabled triggers across four programacion tables, targeting 11 distinct functions. These are trigger-to-function edges, not ordinary function-body calls. No matching SQL rules were found under Q25's specified lexical search criteria.

Scheduled-job inventory: Q27 identified 11 CURRENT cron jobs: nine configured active and two inactive. Job ID 45, ig-direct-sql-worker-v1, is configured active every 30 seconds and invokes programacion.fn_input_governance_queue_worker_v1() as postgres.

Recorded execution: Q30 identified 26,075 succeeded and one failed scheduler execution records for job 45. Scheduler success cannot be equated with completed governance work.

Worker source: Q28 confirmed the queue worker, OID 242617, is SECURITY DEFINER, owned by postgres, and directly invokes programacion.fn_input_governance_direct_step_v1, OID 242597. It uses a transaction-scoped advisory lock, FOR UPDATE SKIP LOCKED, step limits, and stored error outcomes.

Dispatcher source: Q29 confirmed direct calls to governance readback, Curator materialization, Validator handoff continuation, and auxiliary receipt emitters. The source requires verified handoff evidence for eligible Validator continuation and explicitly returns promotion_authorized=false and production_authorized=false.

Queue-request inventory: Q31 preserved eight individual requests, all DONE. Six had governance result BLOCKED, and two had READY. All eight linked readiness runs were COMPLETED. The two READY requests link to runs 933 and 944; queue completion, run completion, governance readiness, and production authorization remain separate states.

Queue-entry access: Q33 identified four public queue wrappers directly executable by service_role, with no corresponding direct path for anon or authenticated. The five examined internal programacion queue functions are not directly callable by those application roles under combined function/schema privileges.

Queue-table protection: Q34R established that anon, authenticated, and service_role lack schema USAGE and SELECT/INSERT/UPDATE/DELETE on programacion.ig_direct_requests_v1. The table has RLS enabled and no registered policies; postgres has owner access.

Event triggers and foreign tables: Q32R identified six enabled event triggers related to extension lifecycle or DDL notification, with no direct governance target. It found zero registered foreign tables.

Coverage findings: CURRENT governance execution includes a concrete service-role submission → persistent queue → scheduled postgres worker → privileged dispatcher → governance workflow path. It must be represented separately from P0 historical caller edges and CURRENT lexical function-body references.

Negative falsifiers: No direct application-role queue-table path was found. No direct governance event-trigger target or registered foreign table was found. No production or promotion authorization was evidenced by the dispatcher or eight queue results. No duplicated workflow execution was demonstrated by repeated linked run identities.

Constraints preserved: Historical P0 and CURRENT evidence remain separate. Function-body lexical references, trigger edges, scheduler configuration, scheduler attempts, queue outcomes, and governance readiness are distinct evidence classes. False-positive lexical witnesses and individual caller identities remain preserved in the frozen Architecture report.

Unresolved: Historical P0 scheduler configuration; external application and Edge-function consumers; dynamic SQL beyond inspected sources; upstream service-role authorization; completeness of unexamined database schemas and functions; and causal correspondence between individual cron attempts and individual queue requests.

Decision: MEASURE_FIRST. No proven coverage defect requiring database changes. Retain the newly confirmed dependency classes in any subsequent inventory design.

Costs: NO_MEDIDO.

Blindness limitation: Strict role independence cannot be independently attested in this shared conversation.

===ROLE_REPORT:COVERAGE END===


### ROLE REPORT: INNOVATION

===ROLE_REPORT:INNOVATION BEGIN===

Scope: Evidence-grounded opportunities to improve dependency coverage, provenance, and reconciliation using existing inventory infrastructure, without unmeasured optimization claims or unauthorized writes.

Evidence: QUERY_RESULT Q35–Q43.

Existing infrastructure: The inventory schema contains dedicated object, function, trigger, dependency, snapshot, reconciliation, and refresh-heartbeat structures. The dependency table supports typed relations, evidence types, provenance, endpoint identities, timestamps, and unique dependency keys.

Established classifications: Existing records distinguish static function calls, SQL reads/writes, rewrite dependencies, trigger attachment/execution, constraints, indexes, policies, repository references, and selected external runtime identities.

Positive reconciliation: Dependency 203890 already represents the CURRENT governance worker → direct-step dispatcher call. Dependencies 222378–222383 represent six downstream dispatcher calls. Their duplication is not proposed.

Cron coverage observation: The 11 CURRENT scheduled jobs were inspected. Six commands lexically matched active inventoried functions; five invoke inventory-schema functions excluded by the present object collector. None had an explicitly cron-identified dependency under Q41's tested predicates.

Confirmed collector boundary: The examined catalog refresh excludes the cron namespace; the exact-dependency collector contains no cron-job branch; and both inspected drift/currentness views omit cron-job-to-function reconciliation.

Candidate improvement: A read-only, evidence-typed cron reconciliation report comparing cron.job identities and schema-qualified command targets against existing inventory objects and dependencies. Its initial concrete witness is job 45 → programacion.fn_input_governance_queue_worker_v1().

Preferred implementation principle: Reuse existing inventory identities and classification conventions where appropriate. Preserve job ID, function identity, execution role, configured activation, observed source, and observation timestamp. Distinguish lexical candidates from confirmed source calls and recorded executions.

Rejected alternatives: Parallel dependency database; automatic broad backfill; unconditional insertion of all 11 jobs; duplicate worker/dispatcher edges; speculative confidence probabilities; and collector-wide rewrites before demonstrating a contractual need.

Performance constraint: Existing collectors have change-detection and heartbeat mechanisms. No proposed runtime or storage savings were measured. Any future collector change requires a bounded benchmark.

Integrity constraint: Q42's hand-transcribed digest strings are unverified and cannot serve as independently established integrity anchors.

Historical constraint: CURRENT cron configuration and execution records cannot reconstruct scheduled-job state at P0 on October 4, 2026.

Decision: MEASURE_FIRST. The missing cron coverage class is established relative to comprehensive dependency analysis, but no database repair is required or authorized. The next safe activity is to specify and independently review a read-only reconciliation query or report before considering any inventory integration.

Costs: NO_MEDIDO.

Blindness limitation: Strict role independence cannot be independently attested in this shared conversation.

===ROLE_REPORT:INNOVATION END===


### SYNTHESIS


{
  "case_id": "PE10-IG-M107-M109-P0",
  "producer": "B18",
  "variant": "PE10_M18_E2",
  "method": "PE10_M18",
  "base": "B",
  "algorithm": "D",
  "status": "RAW_FROZEN_UNGRADED",
  "findings": [
    {
      "id": "S01",
      "finding": "The historical P0 inventory and CURRENT database state are distinct observation scopes.",
      "evidence": {
        "historical_anchor": "public.lf_eventos.id=20161",
        "historical_created_at": "2026-10-04T05:14:40.880842Z",
        "historical_callers": 38,
        "historical_declared_edges": 76,
        "historical_callees": 39,
        "historical_sha256": "5ed03a1274444b49c630124ab26ed183ac964df503ba80b9baa5a0c9d95ae6cd",
        "current_cutoff": "2026-10-15T00:00:00Z",
        "query_ids": ["Q1", "Q2", "Q3"]
      },
      "interpretation": "All 38 historical callers retain their current OIDs, but 23 current definitions differ by MD5 and 15 do not. CURRENT function definitions, schedules, privileges, and execution records cannot be substituted for the historical P0 state.",
      "decision": "PRESERVE_SCOPE_SEPARATION"
    },
    {
      "id": "S02",
      "finding": "The CURRENT reverse-consumer census is broader than the P0 declared graph and contains lexical false positives.",
      "evidence": {
        "lexical_candidate_occurrences": 446,
        "distinct_candidate_consumers": 216,
        "historically_declared_direct_references_observed": 68,
        "additional_occurrences_within_original_38_callers": 102,
        "occurrences_outside_P0_callers": 276,
        "historical_declared_references_not_directly_observed": 8,
        "query_ids": ["Q4", "Q6", "Q7", "Q8"]
      },
      "interpretation": "The eight missing direct references occur in changed caller definitions. Source-level delegation and replacement patterns were observed but behavioral equivalence was not proved. A lexical candidate is not automatically an executable call.",
      "decision": "RETAIN_INDIVIDUAL_WITNESSES"
    },
    {
      "id": "S03",
      "finding": "No causal performance regression is established; historical elapsed-time measurements are unsuitable as execution-duration ground truth.",
      "evidence": {
        "qualified_pre_cutoff_six_chunk_runs": 80,
        "qualified_current_six_chunk_runs": 2,
        "current_run_ids": [933, 944],
        "current_summed_sql_ms": [205179, 111121],
        "current_median_summed_sql_ms": 158150,
        "pre_cutoff_median_summed_sql_ms": 78027,
        "pre_cutoff_zero_reported_elapsed_with_positive_sql": 16,
        "pre_cutoff_elapsed_less_than_summed_sql": 53,
        "query_ids": ["Q9", "Q10", "Q11", "Q12", "Q13", "Q14"]
      },
      "interpretation": "The CURRENT sample is too small and workload comparability is not established. Run-level completion timestamps are not reliable substitutes for measured SQL work. The 42 individually checked chunk durations agreed with their recorded timestamp differences.",
      "decision": "MEASURE_FIRST",
      "repair_required": false
    },
    {
      "id": "S04",
      "finding": "The examined authority model restricts direct table access while allowing selected callable entry functions.",
      "evidence": {
        "selected_functions": 14,
        "tested_role_function_combinations": 140,
        "effective_direct_invocation_combinations": 10,
        "examined_metadata_relations": 26,
        "authenticated_direct_select_on_examined_relations": 0,
        "queue_table_direct_application_role_access": false,
        "query_ids": ["Q15R", "Q16", "Q17", "Q18", "Q19", "Q20", "Q21", "Q22", "Q23", "Q24", "Q33", "Q34R"]
      },
      "interpretation": "No unrestricted PUBLIC function-and-schema invocation path was found among the selected functions. The 26 metadata relations carry deny_direct_client_access policies for anon and authenticated with false expressions. The queue is reachable through selected privileged wrappers, not direct application-role DML.",
      "decision": "PRESERVE_LEAST_PRIVILEGE"
    },
    {
      "id": "S05",
      "finding": "Two authenticated-callable SECURITY INVOKER contracts have a plausible functional-access mismatch.",
      "evidence": {
        "function_oids": [49427, 275398],
        "authenticated_execute": true,
        "security_definer": false,
        "authenticated_select_on_26_examined_relations": false,
        "nested_programacion_helper_oid": 142747,
        "query_ids": ["Q8", "Q15R", "Q16", "Q18", "Q22", "Q23", "Q24"]
      },
      "interpretation": "Both functions are documented as metadata-reading contracts, but their recorded descriptions do not establish that the authenticated database role is a supported consumer. No authenticated runtime invocation or failure was observed.",
      "decision": "VERIFY_CRITICAL",
      "repair_required": false
    },
    {
      "id": "S06",
      "finding": "CURRENT execution coverage extends beyond stored function-body call references.",
      "evidence": {
        "relevant_dml_triggers": 16,
        "distinct_trigger_functions": 11,
        "matching_governance_sql_rules": 0,
        "current_cron_jobs": 11,
        "active_cron_jobs": 9,
        "inactive_cron_jobs": 2,
        "event_triggers": 6,
        "registered_foreign_tables": 0,
        "query_ids": ["Q25", "Q26", "Q27", "Q28", "Q29", "Q30", "Q31", "Q32R", "Q33", "Q34R"]
      },
      "interpretation": "Trigger edges, scheduled commands, stored execution attempts, queue states, view-rule dependencies, and lexical function-body references must remain separate evidence types.",
      "decision": "PRESERVE_TYPED_COVERAGE"
    },
    {
      "id": "S07",
      "finding": "CURRENT cron job 45 is an independently evidenced governance entry path.",
      "evidence": {
        "job_id": 45,
        "job_name": "ig-direct-sql-worker-v1",
        "schedule": "30 seconds",
        "execution_role": "postgres",
        "configured_active": true,
        "scheduler_succeeded_records": 26075,
        "scheduler_failed_records": 1,
        "queue_done_requests": 8,
        "queue_blocked_readbacks": 6,
        "queue_ready_readbacks": 2,
        "query_ids": ["Q27", "Q28", "Q29", "Q30", "Q31"]
      },
      "interpretation": "Scheduler success is not governance readiness. All eight linked readiness runs were COMPLETED, yet six queue readbacks were BLOCKED. All eight returned promotion_authorized=false and production_authorized=false. These observations postdate P0.",
      "decision": "RETAIN_EXECUTION_STATE_DISTINCTIONS"
    },
    {
      "id": "S08",
      "finding": "The existing dependency inventory captures the internal worker chain but omits scheduled-job relationships from the examined collection scope.",
      "evidence": {
        "existing_inventory_tables": 16,
        "existing_inventory_views": 4,
        "dependency_classification_groups": 34,
        "worker_dispatcher_dependency_id": 203890,
        "dispatcher_dependency_ids": [222378, 222379, 222380, 222381, 222382, 222383],
        "cron_jobs_reconciled": 11,
        "cron_commands_matching_inventoried_functions": 6,
        "explicit_cron_dependencies_found": 0,
        "query_ids": ["Q35", "Q36", "Q37", "Q38", "Q39", "Q40", "Q41", "Q42", "Q43"]
      },
      "interpretation": "The examined catalog refresh explicitly excludes cron; the exact-dependency collector has no cron branch; and the examined drift/currentness views do not reconcile cron.job. This is a confirmed coverage boundary relative to a comprehensive execution-dependency graph, not proof of violation of the inventory's own declared contract.",
      "decision": "MEASURE_FIRST",
      "repair_required": false
    }
  ],
  "causal_model": {
    "primary": "A historical function-caller graph is being compared with a CURRENT system whose execution reachability includes wrappers, triggers, scheduled jobs, privileged dispatchers, and stored queue transitions. Apparent omissions or discrepancies may arise from observation-scope mismatch, lexical classification, or collector boundaries rather than runtime defects.",
    "paths": [
      {
        "id": "P01",
        "path": [
          "CURRENT cron.job 45",
          "programacion.fn_input_governance_queue_worker_v1()",
          "programacion.fn_input_governance_direct_step_v1(integer,text)",
          "governance readback / Curator / Validator"
        ],
        "observation": "Scheduled configuration, source-level calls, execution logs, and stored queue outcomes are separately evidenced.",
        "not_proven": "Existence or activation at P0; one-to-one causal mapping between every scheduler attempt and an individual governance run."
      },
      {
        "id": "P02",
        "path": [
          "service_role",
          "public queue submission wrappers",
          "programacion internal SECURITY DEFINER functions",
          "programacion.ig_direct_requests_v1",
          "postgres scheduled worker"
        ],
        "observation": "The privilege and source records support the CURRENT controlled-entry design.",
        "not_proven": "Upstream application identity and authorization of individual submissions."
      },
      {
        "id": "P03",
        "path": [
          "authenticated",
          "lf_ops SECURITY INVOKER contract functions",
          "restricted metadata relations and programacion rule-link helper"
        ],
        "observation": "Callable outer functions coexist with unavailable direct relation privileges.",
        "not_proven": "That authenticated execution is a supported use case or that a concrete authenticated invocation fails."
      },
      {
        "id": "P04",
        "path": [
          "CURRENT source-level dependency",
          "inventory.objects",
          "inventory.dependencies",
          "inventory static analysis / exact collector"
        ],
        "observation": "Internal worker and dispatcher calls are represented, while the examined collectors do not produce cron-job edges.",
        "not_proven": "That cron coverage is required by the inventory's original specification."
      }
    ],
    "diagnostic_method_limits": {
      "GDE_hitting_sets": "NOT_APPLIED: no proven conflicting requirements or defect sets justify a minimal hitting-set repair.",
      "BARINEL": "NOT_APPLIED: no suitable component-level pass/fail spectra.",
      "expected_information_gain": "NOT_NUMERICALLY_ESTIMATED: no calibrated probabilities or measurement costs."
    }
  },
  "candidate_repairs": [
    {
      "id": "CR01",
      "name": "Read-only typed cron-to-function reconciliation",
      "class": "MEASUREMENT_FIRST",
      "action": "Prepare a bounded comparison of CURRENT cron.job rows, parsed candidate function references, matching inventory object identities, and existing dependency records. Report unmatched or ambiguous edges with provenance and no database mutation.",
      "support": ["Q27", "Q38", "Q39", "Q40", "Q41", "Q43"],
      "measured_cost": "NO_MEDIDO",
      "measured_benefit": "NO_MEDIDO",
      "authorized_write": false
    },
    {
      "id": "CR02",
      "name": "Contract-specific authenticated invocation verification",
      "class": "VERIFY_CRITICAL",
      "action": "Define an independently authorized, non-production, side-effect-controlled check of the two lf_ops contracts under the intended role. Resolve supported caller identity before evaluating any change to privileges.",
      "support": ["Q15R", "Q16", "Q18", "Q22", "Q23", "Q24"],
      "measured_cost": "NO_MEDIDO",
      "measured_benefit": "NO_MEDIDO",
      "authorized_write": false
    },
    {
      "id": "CR03",
      "name": "Timing-evidence quality gate",
      "class": "MEASUREMENT_FIRST",
      "action": "Exclude invalid run-level elapsed measures from causal benchmark comparisons; retain verified chunk SQL durations, run identities, workload characteristics, and sample-size limitations.",
      "support": ["Q9", "Q10", "Q11", "Q12", "Q13", "Q14"],
      "measured_cost": "NO_MEDIDO",
      "measured_benefit": "NO_MEDIDO",
      "authorized_write": false
    }
  ],
  "chosen_repair": {
    "id": "CR01",
    "choice_type": "NEXT_SAFE_MEASUREMENT_STEP_NOT_DATABASE_REPAIR",
    "rationale": "The cron entry relationship is concrete, the worker's internal edges are already inventoried, and the inspected collectors and drift views exclude scheduled-job relationships. A read-only reconciliation tests the exact incremental gap without duplicating stored edges or changing production state.",
    "limits": [
      "Do not insert, update, deactivate, or backfill inventory edges.",
      "Do not execute cron jobs or governance functions.",
      "Do not infer P0 scheduler state.",
      "Do not interpret lexical matches as verified runtime calls.",
      "Do not assign unmeasured probability or benefit."
    ],
    "implementation_authorized": false,
    "repair_required": false,
    "measured_cost": "NO_MEDIDO",
    "measured_benefit": "NO_MEDIDO"
  },
  "rejected_alternatives": [
    {
      "candidate": "Grant authenticated SELECT on metadata relations or USAGE on programacion",
      "reason": "Would broaden access against explicit client-deny policies without an established supported-use defect."
    },
    {
      "candidate": "Convert the lf_ops contracts to SECURITY DEFINER",
      "reason": "Would change the authority boundary and potentially expose substantial metadata without contract-specific proof."
    },
    {
      "candidate": "Disable or relax row-level security",
      "reason": "Contradicts the observed least-privilege posture and is not necessary for read-only verification."
    },
    {
      "candidate": "Replace the existing dependency inventory",
      "reason": "Existing object, dependency, trigger, source-evidence, and snapshot structures already support most required classifications."
    },
    {
      "candidate": "Automatically backfill all 11 cron jobs",
      "reason": "Includes inactive jobs, inventory-namespace exclusions, and command-parsing uncertainty; no write authorization exists."
    },
    {
      "candidate": "Reinsert worker-to-dispatcher or dispatcher-to-governance calls",
      "reason": "Existing dependencies 203890 and 222378-222383 already represent the examined relationships."
    },
    {
      "candidate": "Declare a performance regression or optimize the validator immediately",
      "reason": "The CURRENT sample is two qualified runs; workload comparability and reliable run-level elapsed measures are absent."
    },
    {
      "candidate": "Treat all lexical caller references as executable edges",
      "reason": "The source census includes known false positives and cannot prove behavior solely from text occurrence."
    },
    {
      "candidate": "Treat scheduler success, queue DONE, run COMPLETED, and governance READY as one outcome",
      "reason": "Q30-Q31 establish that these are non-equivalent states."
    }
  ],
  "omissions_searched": [
    {
      "class": "Historical P0 declared function callers and callees",
      "result": "38 callers and 76 declared edges preserved as historical evidence; current identity and source differences checked.",
      "query_ids": ["Q1", "Q2", "Q3"]
    },
    {
      "class": "CURRENT reverse function-source consumers",
      "result": "446 lexical occurrences across 216 consumers, including original-caller, outside-inventory, and false-positive categories.",
      "query_ids": ["Q4", "Q6", "Q7", "Q8"]
    },
    {
      "class": "Relevant DML triggers",
      "result": "16 configured triggers and 11 target functions.",
      "query_ids": ["Q25"]
    },
    {
      "class": "SQL rules matching selected governance patterns",
      "result": "Zero under the tested patterns; no global absence claim.",
      "query_ids": ["Q25"]
    },
    {
      "class": "Cron schedule and stored attempts",
      "result": "11 jobs; job 45 has post-P0 execution records and eight DONE queue requests.",
      "query_ids": ["Q26", "Q27", "Q30", "Q31"]
    },
    {
      "class": "DDL event triggers",
      "result": "Six enabled extension/DDL-related event triggers, without a directly identified governance target.",
      "query_ids": ["Q32R"]
    },
    {
      "class": "Foreign tables",
      "result": "Zero registered foreign tables in the tested CURRENT catalog.",
      "query_ids": ["Q32R"]
    },
    {
      "class": "Queue function and table entry privileges",
      "result": "Controlled service-role public wrappers; no direct application-role queue-table access.",
      "query_ids": ["Q33", "Q34R"]
    },
    {
      "class": "Existing inventory classifications",
      "result": "34 populated dependency-class combinations; worker internal edges present.",
      "query_ids": ["Q35", "Q36", "Q37", "Q38"]
    },
    {
      "class": "Cron representation in existing inventory",
      "result": "No explicit cron-job-to-function dependency under tested predicates; inspected collectors and drift views exclude cron-job coverage.",
      "query_ids": ["Q39", "Q40", "Q41", "Q43"]
    },
    {
      "class": "Inventory refresh/currentness evidence",
      "result": "Recent stored stage heartbeats and external currentness snapshots; complete dependency refresh not independently certified.",
      "query_ids": ["Q42"]
    },
    {
      "class": "External application and Edge consumers",
      "result": "Some repository and runtime inventory references were identified, but external runtime coverage and contemporary source equivalence remain unverified.",
      "query_ids": ["Q37", "Q38", "Q42"]
    }
  ],
  "negative_falsifiers": [
    {
      "id": "NF01",
      "observation": "No unrestricted PUBLIC schema-and-function access combination among the examined functions.",
      "query_ids": ["Q15R", "Q16"]
    },
    {
      "id": "NF02",
      "observation": "No authenticated direct SELECT on the 26 examined metadata relations.",
      "query_ids": ["Q22", "Q24"]
    },
    {
      "id": "NF03",
      "observation": "No authenticated direct SELECT on lf_ops.v_b2b_backoffice_login_contract.",
      "query_ids": ["Q20"]
    },
    {
      "id": "NF04",
      "observation": "No anon, authenticated, or service_role direct DML access to ig_direct_requests_v1.",
      "query_ids": ["Q34R"]
    },
    {
      "id": "NF05",
      "observation": "No demonstrated privilege escalation, unauthorized production authorization, or direct queue-table exposure.",
      "query_ids": ["Q16", "Q24", "Q29", "Q31", "Q34R"]
    },
    {
      "id": "NF06",
      "observation": "No proven causal runtime-performance regression.",
      "query_ids": ["Q9", "Q10", "Q11", "Q12", "Q13", "Q14"]
    },
    {
      "id": "NF07",
      "observation": "Worker and dispatcher call edges are not absent from the existing inventory.",
      "query_ids": ["Q38"]
    },
    {
      "id": "NF08",
      "observation": "No historical P0 cron activation is established by the CURRENT scheduler records.",
      "query_ids": ["Q27", "Q30", "Q31"]
    }
  ],
  "constraints_preserved": [
    "READ_ONLY: no database writes, role switching, scheduler invocation, refresh execution, or schema changes by the auditor.",
    "The five frozen role reports are immutable and are the sole substantive input to this synthesis.",
    "P0_HISTORICAL and CURRENT observations are not merged.",
    "Individual material edge identities and their source evidence remain distinct.",
    "Lexical false positives remain classified as non-invocation witnesses.",
    "Function-source calls, catalog dependencies, trigger targets, scheduled commands, recorded scheduler attempts, queue outcomes, and authority privileges are separate evidence classes.",
    "Least privilege, client-deny RLS, and privileged wrapper boundaries are preserved.",
    "Governance readiness is not promotion or production authorization.",
    "No measured performance improvement or estimated information-gain probability is asserted.",
    "No self-score or independent blind-role attestation is claimed.",
    "No GDE hitting set or BARINEL result is invented."
  ],
  "unresolved": [
    {
      "id": "U01",
      "question": "Do the two lf_ops SECURITY INVOKER metadata contracts explicitly support authenticated callers, and what is their observed behavior in that role?",
      "verification": "Contract-specific, independently authorized compatibility test; do not change permissions first.",
      "query_ids": ["Q15R", "Q16", "Q18", "Q22", "Q23", "Q24"]
    },
    {
      "id": "U02",
      "question": "Does other authorized contract documentation identify supported consumers of the two lf_ops contracts?",
      "verification": "The proposed Q44 comment-inspection query was denied before execution because synthesis cannot admit new evidence. Record the question only.",
      "query_id": "Q44",
      "query_status": "DENIED_NOT_EXECUTED"
    },
    {
      "id": "U03",
      "question": "What cron jobs, privileges, and executable functions existed at historical P0?",
      "verification": "Requires independent historical artifacts; CURRENT observations cannot answer."
    },
    {
      "id": "U04",
      "question": "Do external application services correctly authorize service_role submissions and OIDC request identifiers?",
      "verification": "Requires authorized external integration evidence."
    },
    {
      "id": "U05",
      "question": "Are all relevant dynamic SQL, external runtime paths, and unexamined schema consumers captured?",
      "verification": "Requires expanded, separately scoped evidence collection."
    },
    {
      "id": "U06",
      "question": "Does the inventory's governing specification require cron-job dependencies?",
      "verification": "Compare intended coverage contract with observed collector scope before classifying the limitation as a defect."
    },
    {
      "id": "U07",
      "question": "What is the true effect of workload differences on CURRENT versus PRE_CUTOFF validator timing?",
      "verification": "Requires more comparable qualified runs and reliable phase-level measurements."
    },
    {
      "id": "U08",
      "question": "Can the unverified hand-transcribed Q42 digests be independently validated?",
      "verification": "Do not promote them to integrity anchors without source verification."
    },
    {
      "id": "U09",
      "question": "Can strict role blindness and causal independence be attested?",
      "verification": "Not within the shared conversation that generated these frozen reports."
    }
  ],
  "next_safe_step": {
    "action": "Independently review a read-only specification for cron-to-function inventory reconciliation, using CURRENT catalog job identities and existing inventory dependency identities without mutating either source.",
    "secondary_action": "Separately determine the authorized consumer contract for the two lf_ops metadata interfaces before any runtime compatibility check or privilege proposal.",
    "execution": "NOT_AUTHORIZED",
    "database_mutation": false,
    "expected_cost": "NO_MEDIDO",
    "expected_benefit": "NO_MEDIDO",
    "decision_state": "MEASURE_FIRST"
  },
  "provenance": {
    "producer_packet": "PRODUCER_PACKET_B18.md",
    "case_id": "PE10-IG-M107-M109-P0",
    "frozen_reports": [
      "ARCHITECTURE",
      "PERFORMANCE",
      "AUTHORITY",
      "COVERAGE",
      "INNOVATION"
    ],
    "historical_snapshot": {
      "source": "public.lf_eventos.id=20161",
      "created_at": "2026-10-04T05:14:40.880842Z",
      "sha256": "5ed03a1274444b49c630124ab26ed183ac964df503ba80b9baa5a0c9d95ae6cd"
    },
    "reference_digests": {
      "envelope": "93d4f5cba4564ddb0cc46f731375d5d83d81b724e195dfc213b2d98fc9ebc090",
      "overlay": "c450070e7f332a74e5c91115f87df7ad722aa06c81a41b550ba54cf68794bd9b",
      "contract": "0a36c488883b8c0e47a166db6dd859f20df92618cb81307d934af891e047fb5c"
    },
    "ekb_codes": [
      "IG-M107-CP2-READ-ROLE-CURRENTNESS-001",
      "IG-M107-SOAK-CRITERION-DRIFT-001"
    ],
    "query_error_history": [
      {
        "query_id": "Q15",
        "resolution": "Q15R",
        "classification": "QUERY_CONSTRUCTION_ERROR"
      },
      {
        "query_id": "Q32",
        "resolution": "Q32R",
        "classification": "QUERY_CONSTRUCTION_ERROR"
      },
      {
        "query_id": "Q34",
        "resolution": "Q34R",
        "classification": "QUERY_CONSTRUCTION_ERROR"
      },
      {
        "query_id": "Q44",
        "resolution": "NONE",
        "classification": "DENIED_NOT_EXECUTED"
      }
    ],
    "individual_material_edges": [
      {
        "id": "E01",
        "source": "lf_ops.fn_b2b_backoffice_login_contract(text,text,text)",
        "source_oid": 49427,
        "target": "programacion.fn_input_effective_rule_links_v1(integer,text)",
        "target_oid": 142747,
        "edge_type": "CURRENT_SOURCE_REFERENCE",
        "query_ids": ["Q8", "Q18"]
      },
      {
        "id": "E02",
        "source": "lf_ops.fn_screen_contract_v1(text,text,text)",
        "source_oid": 275398,
        "target": "programacion.fn_input_effective_rule_links_v1(integer,text)",
        "target_oid": 142747,
        "edge_type": "CURRENT_SOURCE_REFERENCE",
        "query_ids": ["Q8", "Q18"]
      },
      {
        "id": "E03",
        "source": "private.fn_lf_ig_human_decision_live_disposition_v1",
        "source_oid": 243263,
        "target": "programacion.fn_input_governance_bootstrap_classify_v2",
        "edge_type": "CURRENT_SOURCE_REFERENCE",
        "query_ids": ["Q8"]
      },
      {
        "id": "E04",
        "source": "lf_ops.v_b2b_backoffice_login_contract",
        "source_oid": 49429,
        "source_rule_oid": 49432,
        "target": "lf_ops.fn_b2b_backoffice_login_contract(text,text,text)",
        "target_oid": 49427,
        "edge_type": "PG_REWRITE_NORMAL_DEPENDENCY",
        "query_ids": ["Q19", "Q20", "Q21"]
      },
      {
        "id": "E05",
        "source": "cron.job",
        "source_jobid": 45,
        "source_jobname": "ig-direct-sql-worker-v1",
        "target": "programacion.fn_input_governance_queue_worker_v1()",
        "target_oid": 242617,
        "target_inventory_object_id": 163963,
        "edge_type": "CURRENT_SCHEDULED_COMMAND",
        "query_ids": ["Q27", "Q28", "Q30", "Q41"]
      },
      {
        "id": "E06",
        "source": "programacion.fn_input_governance_queue_worker_v1()",
        "source_oid": 242617,
        "source_inventory_object_id": 163963,
        "target": "programacion.fn_input_governance_direct_step_v1(integer,text)",
        "target_oid": 242597,
        "target_inventory_object_id": 163739,
        "inventory_dependency_id": 203890,
        "edge_type": "CURRENT_DIRECT_CALL_AND_INVENTORIED_CALLS",
        "query_ids": ["Q28", "Q38"]
      },
      {
        "id": "E07",
        "source": "programacion.fn_input_governance_queue_worker_v1()",
        "source_oid": 242617,
        "target": "programacion.ig_direct_requests_v1",
        "target_relation_oid": 242601,
        "inventory_dependency_id": 203780,
        "edge_type": "CURRENT_QUEUE_READ_WRITE_SOURCE_AND_INVENTORY_WRITE",
        "query_ids": ["Q28", "Q34R", "Q38"]
      },
      {
        "id": "E08",
        "source": "programacion.fn_input_governance_direct_step_v1(integer,text)",
        "source_oid": 242597,
        "target": "programacion.fn_input_governance_execute",
        "target_inventory_object_id": 1166,
        "inventory_dependency_id": 222378,
        "edge_type": "CURRENT_DIRECT_CALL_AND_INVENTORIED_CALLS",
        "query_ids": ["Q29", "Q38"]
      },
      {
        "id": "E09",
        "source": "programacion.fn_input_governance_direct_step_v1(integer,text)",
        "source_oid": 242597,
        "target": "programacion.fn_input_governance_validator_validate_handoff_v1",
        "target_inventory_object_id": 156498,
        "inventory_dependency_id": 222379,
        "edge_type": "CURRENT_DIRECT_CALL_AND_INVENTORIED_CALLS",
        "query_ids": ["Q29", "Q38"]
      },
      {
        "id": "E10",
        "source": "programacion.fn_input_governance_direct_step_v1(integer,text)",
        "source_oid": 242597,
        "target": "programacion.fn_ig_timing_receipts_emit_v1",
        "inventory_dependency_id": 222380,
        "edge_type": "CURRENT_DIRECT_CALL_AND_INVENTORIED_CALLS",
        "query_ids": ["Q29", "Q38"]
      },
      {
        "id": "E11",
        "source": "programacion.fn_input_governance_direct_step_v1(integer,text)",
        "source_oid": 242597,
        "target": "programacion.fn_ig_causal_lineage_receipts_emit_v1",
        "inventory_dependency_id": 222381,
        "edge_type": "CURRENT_DIRECT_CALL_AND_INVENTORIED_CALLS",
        "query_ids": ["Q29", "Q38"]
      },
      {
        "id": "E12",
        "source": "programacion.fn_input_governance_direct_step_v1(integer,text)",
        "source_oid": 242597,
        "target": "programacion.fn_ig_validator_timing_receipt_emit_v1",
        "inventory_dependency_id": 222382,
        "edge_type": "CURRENT_DIRECT_CALL_AND_INVENTORIED_CALLS",
        "query_ids": ["Q29", "Q38"]
      },
      {
        "id": "E13",
        "source": "programacion.fn_input_governance_direct_step_v1(integer,text)",
        "source_oid": 242597,
        "target": "programacion.fn_input_governance_curator_materialize_v1",
        "target_inventory_object_id": 809,
        "inventory_dependency_id": 222383,
        "edge_type": "CURRENT_DIRECT_CALL_AND_INVENTORIED_CALLS",
        "query_ids": ["Q29", "Q38"]
      },
      {
        "id": "E14",
        "source": "public.fn_input_governance_queue_submit_v1",
        "source_oid": 242618,
        "target": "programacion.fn_input_governance_queue_submit_v1",
        "target_oid": 242615,
        "edge_type": "CURRENT_SECURITY_DEFINER_WRAPPER_CALL",
        "query_ids": ["Q33"]
      },
      {
        "id": "E15",
        "source": "public.fn_input_governance_queue_read_v1",
        "source_oid": 242619,
        "target": "programacion.fn_input_governance_queue_read_v1",
        "target_oid": 242616,
        "edge_type": "CURRENT_SECURITY_DEFINER_WRAPPER_CALL",
        "query_ids": ["Q33"]
      },
      {
        "id": "E16",
        "source": "public.fn_input_governance_queue_submit_oidc_v1",
        "source_oid": 243556,
        "target": "programacion.fn_input_governance_queue_submit_oidc_v1",
        "target_oid": 243554,
        "edge_type": "CURRENT_SECURITY_DEFINER_WRAPPER_CALL",
        "query_ids": ["Q33"]
      },
      {
        "id": "E17",
        "source": "public.fn_input_governance_queue_poll_oidc_v1",
        "source_oid": 243557,
        "target": "programacion.fn_input_governance_queue_poll_oidc_v1",
        "target_oid": 243555,
        "edge_type": "CURRENT_SECURITY_DEFINER_WRAPPER_CALL",
        "query_ids": ["Q33"]
      },
      {
        "id": "E18",
        "source": "programacion.fn_input_governance_queue_poll_oidc_v1",
        "source_oid": 243555,
        "target": "programacion.fn_input_governance_queue_read_v1",
        "target_oid": 242616,
        "edge_type": "CURRENT_SOURCE_DIRECT_CALL",
        "query_ids": ["Q33"]
      },
      {
        "id": "E19",
        "source": "public.fn_input_governance_curator_materialize_v1",
        "target": "programacion.fn_input_governance_curator_materialize_v1",
        "inventory_dependency_id": 74083,
        "edge_type": "INVENTORIED_CALLS",
        "query_ids": ["Q38"]
      },
      {
        "id": "E20",
        "source": "public.fn_input_governance_execute",
        "target": "programacion.fn_input_governance_execute",
        "inventory_dependency_id": 74107,
        "edge_type": "INVENTORIED_CALLS",
        "query_ids": ["Q38"]
      },
      {
        "id": "E21",
        "source": "public.fn_input_governance_validator_validate_handoff_v1",
        "target": "programacion.fn_input_governance_validator_validate_handoff_v1",
        "inventory_dependency_id": 203868,
        "edge_type": "INVENTORIED_CALLS",
        "query_ids": ["Q38"]
      },
      {
        "id": "E22",
        "source": "programacion.fn_input_governance_validator_validate_handoff_v1",
        "target": "programacion.fn_input_governance_validator_handoff_assert_v1",
        "inventory_dependency_id": 196265,
        "edge_type": "INVENTORIED_CALLS",
        "query_ids": ["Q38"]
      },
      {
        "id": "E23",
        "source": "programacion.fn_input_governance_validator_validate_handoff_v1",
        "target": "programacion.fn_input_governance_validator_validate_v1",
        "inventory_dependency_id": 196266,
        "edge_type": "INVENTORIED_CALLS",
        "query_ids": ["Q38"]
      },
      {
        "id": "E24",
        "source": "programacion.fn_input_live_compare_run_v1",
        "target": "programacion.fn_input_governance_curator_materialize_v1",
        "inventory_dependency_id": 218691,
        "edge_type": "INVENTORIED_CALLS",
        "query_ids": ["Q38"]
      },
      {
        "id": "E25",
        "source": "programacion.fn_input_governance_execute",
        "source_inventory_object_id": 1166,
        "target": "programacion.fn_v09_sha256_jsonb",
        "inventory_dependency_id": 116544,
        "edge_type": "INVENTORIED_LEXICAL_CALL",
        "query_ids": ["Q38"]
      },
      {
        "id": "E26",
        "source": "programacion.fn_input_governance_execute",
        "source_inventory_object_id": 1166,
        "target": "programacion.fn_input_freshness_delta",
        "inventory_dependency_id": 116545,
        "edge_type": "INVENTORIED_LEXICAL_CALL",
        "query_ids": ["Q38"]
      },
      {
        "id": "E27",
        "source": "programacion.fn_input_governance_execute",
        "source_inventory_object_id": 1166,
        "target": "programacion.fn_input_proposal_summary",
        "inventory_dependency_id": 116546,
        "edge_type": "INVENTORIED_LEXICAL_CALL",
        "query_ids": ["Q38"]
      },
      {
        "id": "E28",
        "source": "programacion.fn_input_governance_execute",
        "source_inventory_object_id": 1166,
        "target": "programacion.fn_input_governance_ekb_checkpoint",
        "inventory_dependency_id": 116547,
        "edge_type": "INVENTORIED_LEXICAL_CALL",
        "query_ids": ["Q38"]
      },
      {
        "id": "E29",
        "source": "programacion.fn_input_governance_execute",
        "source_inventory_object_id": 1166,
        "target": "programacion.fn_input_stage_gate_summary_known_current_v1",
        "inventory_dependency_id": 116548,
        "edge_type": "INVENTORIED_LEXICAL_CALL",
        "query_ids": ["Q38"]
      },
      {
        "id": "E30",
        "source": "programacion.fn_input_governance_execute",
        "source_inventory_object_id": 1166,
        "target": "programacion.fn_input_evaluation_outcome_summary_known_current_v1",
        "inventory_dependency_id": 116549,
        "edge_type": "INVENTORIED_LEXICAL_CALL",
        "query_ids": ["Q38"]
      },
      {
        "id": "E31",
        "source": "programacion.fn_input_governance_execute",
        "source_inventory_object_id": 1166,
        "target": "programacion.fn_input_internal_remediation_summary_known_current_v1",
        "inventory_dependency_id": 116550,
        "edge_type": "INVENTORIED_LEXICAL_CALL",
        "query_ids": ["Q38"]
      },
      {
        "id": "E32",
        "source": "programacion.fn_input_governance_execute",
        "source_inventory_object_id": 1166,
        "target": "programacion.fn_input_governance_worker_spec_known_current_v1",
        "inventory_dependency_id": 116551,
        "edge_type": "INVENTORIED_LEXICAL_CALL",
        "query_ids": ["Q38"]
      },
      {
        "id": "E33",
        "source": "programacion.fn_input_governance_execute",
        "source_inventory_object_id": 1166,
        "target": "programacion.fn_input_readiness_run_is_current_cached_v1",
        "inventory_dependency_id": 116552,
        "edge_type": "INVENTORIED_LEXICAL_CALL",
        "query_ids": ["Q38"]
      },
      {
        "id": "E34",
        "source": "programacion.fn_input_governance_execute",
        "source_inventory_object_id": 1166,
        "target": "programacion.fn_input_context_manifest_known_current_v1",
        "inventory_dependency_id": 116553,
        "edge_type": "INVENTORIED_LEXICAL_CALL",
        "query_ids": ["Q38"]
      },
      {
        "id": "E35",
        "source": "programacion.fn_input_governance_execute",
        "source_inventory_object_id": 1166,
        "target": "programacion.fn_input_governance_worker_spec_known_no_current_v1",
        "inventory_dependency_id": 116554,
        "edge_type": "INVENTORIED_LEXICAL_CALL",
        "query_ids": ["Q38"]
      },
      {
        "id": "E36",
        "source": "programacion.fn_input_governance_curator_materialize_v1",
        "source_inventory_object_id": 809,
        "target": "programacion.fn_v09_sha256_jsonb",
        "inventory_dependency_id": 211330,
        "edge_type": "INVENTORIED_LEXICAL_CALL",
        "query_ids": ["Q38"]
      },
      {
        "id": "E37",
        "source": "programacion.fn_input_governance_curator_materialize_v1",
        "source_inventory_object_id": 809,
        "target": "programacion.fn_input_governance_bootstrap_materialize_v2",
        "inventory_dependency_id": 211331,
        "edge_type": "INVENTORIED_LEXICAL_CALL",
        "query_ids": ["Q38"]
      },
      {
        "id": "E38",
        "source": "programacion.fn_input_governance_curator_materialize_v1",
        "source_inventory_object_id": 809,
        "target": "programacion.fn_input_governance_recurate_v2",
        "inventory_dependency_id": 211332,
        "edge_type": "INVENTORIED_LEXICAL_CALL",
        "query_ids": ["Q38"]
      },
      {
        "id": "E39",
        "source": "programacion.fn_input_governance_curator_materialize_v1",
        "source_inventory_object_id": 809,
        "target": "programacion.fn_input_screen_canonical_graph",
        "inventory_dependency_id": 211333,
        "edge_type": "INVENTORIED_LEXICAL_CALL",
        "query_ids": ["Q38"]
      },
      {
        "id": "E40",
        "source": "programacion.fn_input_governance_curator_materialize_v1",
        "source_inventory_object_id": 809,
        "target": "programacion.fn_input_governance_curator_plan_v1",
        "inventory_dependency_id": 211334,
        "edge_type": "INVENTORIED_LEXICAL_CALL",
        "query_ids": ["Q38"]
      },
      {
        "id": "E41",
        "source": "programacion.fn_input_governance_curator_materialize_v1",
        "source_inventory_object_id": 809,
        "target": "programacion.fn_input_governance_curator_handoff_receipt_v1",
        "inventory_dependency_id": 211335,
        "edge_type": "INVENTORIED_LEXICAL_CALL",
        "query_ids": ["Q38"]
      },
      {
        "id": "E42",
        "source": "programacion.fn_input_governance_curator_materialize_v1",
        "source_inventory_object_id": 809,
        "target": "programacion.fn_input_governance_validator_handoff_assert_v1",
        "inventory_dependency_id": 211336,
        "edge_type": "INVENTORIED_LEXICAL_CALL",
        "query_ids": ["Q38"]
      },
      {
        "id": "E43",
        "source": "programacion.fn_input_governance_curator_materialize_v1",
        "source_inventory_object_id": 809,
        "target": "programacion.fn_input_governance_curator_rebind_v1",
        "inventory_dependency_id": 211337,
        "edge_type": "INVENTORIED_LEXICAL_CALL",
        "query_ids": ["Q38"]
      },
      {
        "id": "E44",
        "source": "programacion.fn_input_governance_curator_materialize_v1",
        "source_inventory_object_id": 809,
        "target": "programacion.fn_input_governance_recurate_source_stale_v1",
        "inventory_dependency_id": 211338,
        "edge_type": "INVENTORIED_LEXICAL_CALL",
        "query_ids": ["Q38"]
      },
      {
        "id": "E45",
        "source": "programacion.input_family_assessments.trg_input_family_assessment_00_execution_insert",
        "trigger_oid": 61794,
        "target": "programacion.fn_guard_input_family_execution_insert",
        "target_oid": 61792,
        "edge_type": "CURRENT_DML_TRIGGER_TARGET",
        "query_ids": ["Q25"]
      },
      {
        "id": "E46",
        "source": "programacion.input_family_assessments.trg_input_family_assessment_00_execution_update",
        "trigger_oid": 61795,
        "target": "programacion.fn_guard_input_family_execution_update",
        "target_oid": 61793,
        "edge_type": "CURRENT_DML_TRIGGER_TARGET",
        "query_ids": ["Q25"]
      },
      {
        "id": "E47",
        "source": "programacion.input_family_assessments.trg_input_family_assessment_00a_continuation_currentness_update",
        "trigger_oid": 156953,
        "target": "programacion.fn_guard_input_governance_continuation_currentness_v1",
        "target_oid": 156952,
        "edge_type": "CURRENT_DML_TRIGGER_TARGET",
        "query_ids": ["Q25"]
      },
      {
        "id": "E48",
        "source": "programacion.input_family_assessments.trg_input_family_assessment_00b_semantic_coherence_update",
        "trigger_oid": 67547,
        "target": "programacion.fn_guard_input_validator_semantic_coherence_v512",
        "target_oid": 67546,
        "edge_type": "CURRENT_DML_TRIGGER_TARGET",
        "query_ids": ["Q25"]
      },
      {
        "id": "E49",
        "source": "programacion.input_family_assessments.trg_input_family_assessment_01_semantic_depth_insert",
        "trigger_oid": 62110,
        "target": "programacion.fn_guard_input_family_semantic_depth",
        "target_oid": 62109,
        "edge_type": "CURRENT_DML_TRIGGER_TARGET",
        "query_ids": ["Q25"]
      },
      {
        "id": "E50",
        "source": "programacion.input_family_assessments.trg_input_family_assessment_01_semantic_depth_update",
        "trigger_oid": 62111,
        "target": "programacion.fn_guard_input_family_semantic_depth",
        "target_oid": 62109,
        "edge_type": "CURRENT_DML_TRIGGER_TARGET",
        "query_ids": ["Q25"]
      },
      {
        "id": "E51",
        "source": "programacion.input_family_assessments.trg_input_family_assessment_01a_semantic_depth_v510_insert",
        "trigger_oid": 62837,
        "target": "programacion.fn_guard_input_family_semantic_depth_v510",
        "target_oid": 62836,
        "edge_type": "CURRENT_DML_TRIGGER_TARGET",
        "query_ids": ["Q25"]
      },
      {
        "id": "E52",
        "source": "programacion.input_family_assessments.trg_input_family_assessment_01a_semantic_depth_v510_update",
        "trigger_oid": 62838,
        "target": "programacion.fn_guard_input_family_semantic_depth_v510",
        "target_oid": 62836,
        "edge_type": "CURRENT_DML_TRIGGER_TARGET",
        "query_ids": ["Q25"]
      },
      {
        "id": "E53",
        "source": "programacion.input_family_assessments.trg_input_family_assessment_insert",
        "trigger_oid": 59597,
        "target": "programacion.fn_guard_input_family_assessment_insert",
        "target_oid": 59596,
        "edge_type": "CURRENT_DML_TRIGGER_TARGET",
        "query_ids": ["Q25"]
      },
      {
        "id": "E54",
        "source": "programacion.input_family_assessments.trg_input_family_assessment_update",
        "trigger_oid": 59599,
        "target": "programacion.fn_guard_input_family_assessment_update",
        "target_oid": 59598,
        "edge_type": "CURRENT_DML_TRIGGER_TARGET",
        "query_ids": ["Q25"]
      },
      {
        "id": "E55",
        "source": "programacion.input_gap_proposals.trg_input_gap_proposal_00_continuation_currentness_update",
        "trigger_oid": 156954,
        "target": "programacion.fn_guard_input_governance_continuation_currentness_v1",
        "target_oid": 156952,
        "edge_type": "CURRENT_DML_TRIGGER_TARGET",
        "query_ids": ["Q25"]
      },
      {
        "id": "E56",
        "source": "programacion.input_readiness_runs.trg_input_readiness_run_00_m67_successor_lineage",
        "trigger_oid": 238684,
        "target": "programacion.fn_input_successor_lineage_guard_m67_v1",
        "target_oid": 238683,
        "edge_type": "CURRENT_DML_TRIGGER_TARGET",
        "query_ids": ["Q25"]
      },
      {
        "id": "E57",
        "source": "programacion.input_readiness_runs.trg_input_readiness_run_insert",
        "trigger_oid": 59601,
        "target": "programacion.fn_guard_input_readiness_run",
        "target_oid": 59600,
        "edge_type": "CURRENT_DML_TRIGGER_TARGET",
        "query_ids": ["Q25"]
      },
      {
        "id": "E58",
        "source": "programacion.input_readiness_runs.trg_input_readiness_run_latch_predecessor",
        "trigger_oid": 61696,
        "target": "programacion.fn_input_latch_predecessor_invalidation",
        "target_oid": 61695,
        "edge_type": "CURRENT_DML_TRIGGER_TARGET",
        "query_ids": ["Q25"]
      },
      {
        "id": "E59",
        "source": "programacion.input_readiness_runs.trg_input_readiness_run_update",
        "trigger_oid": 59602,
        "target": "programacion.fn_guard_input_readiness_run",
        "target_oid": 59600,
        "edge_type": "CURRENT_DML_TRIGGER_TARGET",
        "query_ids": ["Q25"]
      },
      {
        "id": "E60",
        "source": "programacion.input_validator_chunk_timings.trg_input_validator_chunk_timing_00_currentness_insert",
        "trigger_oid": 156955,
        "target": "programacion.fn_guard_input_governance_continuation_currentness_v1",
        "target_oid": 156952,
        "edge_type": "CURRENT_DML_TRIGGER_TARGET",
        "query_ids": ["Q25"]
      },
      {
        "id": "E61",
        "source": "extensions.issue_graphql_placeholder",
        "event_trigger_oid": 16575,
        "target": "extensions.set_graphql_placeholder",
        "target_oid": 16574,
        "edge_type": "CURRENT_DDL_EVENT_TRIGGER_TARGET",
        "query_ids": ["Q32R"]
      },
      {
        "id": "E62",
        "source": "extensions.issue_pg_cron_access",
        "event_trigger_oid": 16654,
        "target": "extensions.grant_pg_cron_access",
        "target_oid": 16551,
        "edge_type": "CURRENT_DDL_EVENT_TRIGGER_TARGET",
        "query_ids": ["Q32R"]
      },
      {
        "id": "E63",
        "source": "extensions.issue_pg_graphql_access",
        "event_trigger_oid": 16666,
        "target": "extensions.grant_pg_graphql_access",
        "target_oid": 16572,
        "edge_type": "CURRENT_DDL_EVENT_TRIGGER_TARGET",
        "query_ids": ["Q32R"]
      },
      {
        "id": "E64",
        "source": "extensions.issue_pg_net_access",
        "event_trigger_oid": 16657,
        "target": "extensions.grant_pg_net_access",
        "target_oid": 16553,
        "edge_type": "CURRENT_DDL_EVENT_TRIGGER_TARGET",
        "query_ids": ["Q32R"]
      },
      {
        "id": "E65",
        "source": "extensions.pgrst_ddl_watch",
        "event_trigger_oid": 16576,
        "target": "extensions.pgrst_ddl_watch",
        "target_oid": 16563,
        "edge_type": "CURRENT_DDL_EVENT_TRIGGER_TARGET",
        "query_ids": ["Q32R"]
      },
      {
        "id": "E66",
        "source": "extensions.pgrst_drop_watch",
        "event_trigger_oid": 16577,
        "target": "extensions.pgrst_drop_watch",
        "target_oid": 16564,
        "edge_type": "CURRENT_DDL_EVENT_TRIGGER_TARGET",
        "query_ids": ["Q32R"]
      },
      {
        "id": "E67",
        "source": "programacion.fn_input_validator_compaction_batch_v1",
        "source_oid": 219907,
        "target_text": "programacion.fn_guard_input_family_assessment_update()",
        "target_oid": 59598,
        "edge_type": "LEXICAL_FALSE_POSITIVE_REGPROCEDURE_DEFINITION_HASH_LOOKUP",
        "is_runtime_call": false,
        "query_ids": ["Q8"]
      },
      {
        "id": "E68",
        "source": "private.fn_evaluate_architecture_alerts_v3",
        "target": "private.fn_latest_cron_status_v3",
        "inventory_dependency_id": 74227,
        "edge_type": "INVENTORIED_LEXICAL_CALL_NOT_SCHEDULED_EDGE",
        "query_ids": ["Q39"]
      },
      {
        "id": "E69",
        "source": "private.fn_probe_architecture_control_v3",
        "target": "private.fn_latest_cron_status_v3",
        "inventory_dependency_id": 74237,
        "edge_type": "INVENTORIED_LEXICAL_CALL_NOT_SCHEDULED_EDGE",
        "query_ids": ["Q39"]
      },
      {
        "id": "E70",
        "source": "private.fn_evaluate_architecture_alerts_v4",
        "target": "private.fn_latest_cron_status_v3",
        "inventory_dependency_id": 74247,
        "edge_type": "INVENTORIED_LEXICAL_CALL_NOT_SCHEDULED_EDGE",
        "query_ids": ["Q39"]
      }
    ],
    "material_edge_preservation_limit": "The synthesis retains the material identities explicitly available in the five frozen reports and their cited query evidence. The full 76-edge P0 declaration and 446-occurrence CURRENT lexical census remain authoritative at their original query IDs; they are not reconstructed from aggregate counts or treated as a newly enumerated complete edge list.",
    "integrity_notes": [
      "Q40 reports five of five exact source-body MD5 matches.",
      "Q42 digest values were hand-transcribed and were not independently verified.",
      "Q44 was denied and not executed.",
      "No synthesis-stage evidence was admitted."
    ],
    "final_status": "RAW_FROZEN_UNGRADED"
  }
}

