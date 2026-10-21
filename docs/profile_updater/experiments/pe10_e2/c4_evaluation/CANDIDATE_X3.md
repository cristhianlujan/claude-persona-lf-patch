# CANDIDATE X3

Case: PE10-IG-M107-M109-P0 (same case for every candidate). Pair Q: the two candidates of a pair come from the same method family; their order is randomized.
Content below is verbatim producer output; nothing was edited.

### ROLE REPORT: ARCHITECTURE

===ROLE_REPORT:ARCHITECTURE BEGIN===

Role: ARCHITECTURE
Case: PE10-IG-M107-M109-P0
Method: PE10_M29_E2, modules C + E
Mode: READ_ONLY
Evidence: Q1–Q6
Isolation: One shared model context; independent-agent isolation unproven.

Observed findings

A1. P0_HISTORICAL: Q1 records 38 historical caller identities, 76 declared caller/callee relationships, and 39 distinct callee names. The inventory is a frozen snapshot, not a certified complete CURRENT consumer universe.

A2. CURRENT: Q2 matches all 38 historical caller OIDs and names uniquely; 22 function bodies have changed MD5 values and 16 have unchanged values. Definition drift alone is not a defect.

A3. CURRENT: Q3 identifies 446 static call candidates, partitioned into 68 historical-declared matches, 102 CURRENT relationships not declared in P0, and 276 CURRENT consumer relationships outside P0. These are lexical candidate classifications, not executable-edge or runtime certifications.

A4. CURRENT_COMPARED_TO_P0_HISTORICAL: Q4 identifies eight individually specified historical relationships without matching CURRENT exact-call tokens. Six identifiers are absent; two occur only as prefixes of longer versioned identifiers. All eight retain their exact historical caller/callee identities and Q4 evidence provenance.

A5. CURRENT: Q5 provides complete distinct call-token sets for the six callers implicated in Q4. Cached and context-aware variants are visible, but their behavioral equivalence to previous variants is unproven.

A6. CURRENT: Q6 directly falsifies the interpretation of one self-reference token as a confirmed recursive call. Its occurrence is inside a string literal describing an entry point.

A7. CURRENT: Q6 provides concrete source contexts for selected cross-schema, handoff, graph-finalization, cached, and context-aware relationships. These support static source-level call claims only.

Edge provenance and preservation

The complete Q3 446-record witness ledger is retained by reference to the lossless QUERY_RESULT_Q3.txt, with each candidate individually identified by consumer identity, called schema/name, resolved callee candidate, and comparison class. Its canonical body SHA-256 is:

f2e91f2b82ad580eee95605f35f71dcc606ce830f569b670bf56496797e83e7c

The eight exact historical discrepancies are retained in Q4. Q5 and Q6 provide supplementary token and context witnesses. No relation is promoted to runtime execution from lexical evidence.

Causal hypothesis

Optimization-associated version routing and historical inventory scope may create false impressions of architectural continuity or consumer completeness. This hypothesis is falsified if comprehensive typed source inspection and authorized historical comparison demonstrate equivalent relationships and complete consumer coverage.

Alternative no-defect hypothesis

The changed definitions and expanded/current variant routing may represent intentional and correctly governed evolution. That hypothesis remains viable because no concrete regression has been demonstrated.

Unresolved

Complete lexical-context classification of all Q3 candidates; dynamic SQL and remote/Edge consumers; overload and signature compatibility beyond the selected witnesses; effective execution privileges; historical variant semantics; actual runtime reachability; timestamped deployment provenance; semantic and performance equivalence.

Minimal safe action

Continue read-only measurement and source-context validation. Preserve exact witness identities and epoch labels. Do not change database functions, activate workflows, or assert a required repair.

Measured costs

NO_MEDIDO. Query result cardinalities are observations, not elapsed-time or computational-cost measurements.

Decision

NEEDS_MORE_EVIDENCE under module E. This does not constitute a defect or repair determination.

===ROLE_REPORT:ARCHITECTURE END===


### ROLE REPORT: PERFORMANCE

===ROLE_REPORT:PERFORMANCE BEGIN===

Role: PERFORMANCE
Case: PE10-IG-M107-M109-P0
Mode: READ_ONLY
Evidence: Q7, Q8, Q9
Observation class: CURRENT, except historical contractual requirements taken directly from the packet.

Findings

P1. Q7 shows track_functions=none, pg_stat_statements.track=top, planning tracking disabled, and I/O timing disabled. Per-function execution accounting is unavailable through the observed statistics configuration.

P2. Q8 identifies 27 matching aggregate SQL statements since the reported statistics reset of 2026-10-10T02:45:35.862139Z. This interval straddles the P0 cutoff, and the counters are not partitioned by execution epoch.

P3. Q8/Q9 identify individual measured SQL statement cohorts:

-1190413845958252360: curator materialization compound, 7 calls, mean 33,046.13 ms.

3120726644697259216: shadow evaluation compound, 7 calls, mean 6,351.03 ms.

8711451024423911529: validator loop compound, 6 calls, mean 48,383.52 ms.

-6121712835719537967: queue worker, 23,819 calls at Q9, mean 58.22 ms.

P4. The four cohorts are not demonstrably equivalent in workflow, input population, timing boundaries, or execution semantics. No valid baseline-to-optimized speedup ratio can be calculated from them.

P5. Q8/Q9 queue-worker counters advance between measurements; three other selected statement counters remain unchanged. Q9's static rows were coordinator-verified, while the advancing worker's original snapshot could not be independently reverified.

P6. Static dependency census size, function-body MD5 changes, and nominal cached-function references cannot measure runtime speed, resource efficiency, or governance correctness.

P7. The Q8 readback accidentally exposed three denylisted previous-method SQL samples. The coordinator identifies the incident as an erroneous relay. This is recorded as contamination, not used as investigative evidence.

Candidate causal accounts

Improved performance through graph/cache reuse.

Apparent differences caused by non-equivalent cohorts and workflow boundaries.

Reduced mean latency accompanied by increased validation overhead or tail risk.

No material performance regression.

All remain falsifiable and unresolved.

Negative falsifiers

Matched before/after cohorts showing no meaningful latency difference would falsify a material speedup claim.

Equivalent correctness-adjusted cohorts showing sustained regression would falsify the no-regression hypothesis.

Invocation-level timing demonstrating that apparent overhead comes from unrelated waits would falsify attribution to the targeted functions.

Measured cache hits without reduced recomputation would weaken the proposed caching mechanism.

Minimal safe action

Use existing governed timing receipts, when authorized, to construct epoch-consistent and workload-matched comparisons. Preserve correctness, source freshness, and validation-gate outcomes as eligibility constraints. Do not enable instrumentation or execute benchmarks through this diagnostic run.

Measured costs

Existing SQL execution times and block counters from Q8/Q9 are measured. Investigation-query execution costs, total wall-clock duration, producer token use, and historical performance baseline are NO_MEDIDO.

Decision

NEEDS_MORE_EVIDENCE. No performance repair has been justified.

===ROLE_REPORT:PERFORMANCE END===


### ROLE REPORT: AUTHORITY

===ROLE_REPORT:AUTHORITY BEGIN===

Role: AUTHORITY
Case: PE10-IG-M107-M109-P0
Mode: READ_ONLY
Evidence: Q10–Q12, failed Q13, successful Q14
Source boundary: P0 historical EKB claims distinguished from CURRENT catalog and function-source observations.

Findings

AU1. Q10 measures 38 P0-inventoried functions against four CURRENT principals. postgres has effective catalog callability for all 38; service_role for six public functions; anon and authenticated for none. EXECUTE without schema USAGE is not effective direct callability.

AU2. Q11 extends the analysis to nine entry points and internal helpers. Among seven tested principals, service_role effectively calls four public functions; the three named programacion governance roles cannot directly execute the five examined internal functions.

AU3. Q12 identifies three SECURITY DEFINER public delegation wrappers: public.fn_input_governance_curator_materialize_v1 (OID 68598), public.fn_input_governance_execute (OID 68668), and public.fn_input_governance_validator_validate_v1 (OID 68599). Their wrapper bodies delegate without an independent identity predicate. Safety depends on downstream guards and the permitted caller context.

AU4. Q11–Q12 identify public.fn_input_governance_validator_handoff_assert_v1 (OID 241753) as a SECURITY INVOKER delegation to programacion.fn_input_governance_validator_handoff_assert_v1 (OID 238083). The observed service_role grants permit the public call but not direct internal callability. Successful execution and its authorization behavior remain untested.

AU5. Q12's internal Curator (OID 68873) contains strategy, run, assessment, graph-count, freshness-count and receipt-verification conditions with exception paths. These are CURRENT implemented guards, not proofs of historical presence or runtime effectiveness.

AU6. Q12's handoff receipt creator (OID 237817) checks Curator identity, run status, Validator non-invocation and the 47-family universe, and constructs a digest-bound handoff subject. The Validator handoff assertion (OID 238083) reconstructs the subject and checks the persisted receipt.

AU7. Q12's Validator (OID 68877) checks continuation currentness on specified statuses and routes terminal completion through graph finalization (OID 244314). The graph finalizer checks the handoff and graph receipt on COMPLETED outcomes. Full reachable-path completeness is unproven.

AU8. Q13 failed with PostgreSQL 42883, yielding no evidence. Q14 independently verifies both authorized historical EKB row SHA-256 values against the packet.

AU9. Historical EKB IG-M107-CP2-READ-ROLE-CURRENTNESS-001 documents a prior unauthorized read (42501) and the unsuitability of a latest-13 sample as an as-of cohort substitute. The specified mitigation is query correction and authorized historical evidence reuse, not privilege escalation.

AU10. Historical EKB IG-M107-SOAK-CRITERION-DRIFT-001 records the historical soak requirements: 13/13 screens, 47/47 families, at least two eligible as-of observations per unit, zero false PASS, and zero D4 divergence. Its claim about receipt 38 is not independently recertified here.

Causal model

Two distinct failure mechanisms must remain separate: a measurement or certification query can lack read authority or sample the wrong epoch; a callable privileged wrapper can potentially omit an intended authorization gate. The first is historically documented. The second is an unproven CURRENT risk requiring verified entrypoint, identity and guard evidence.

Falsifiers

A properly authorized, historical as-of cohort with the prescribed criteria would falsify a claim that current sampling is necessary for historical certification. Successful guarded calls under explicitly authorized principals and rejected unauthorized cases would reduce wrapper-bypass concerns. A demonstrated reachable path bypassing a required guard would instead establish a concrete defect.

Constraints and unresolved

Preserve existing grants and role boundaries; avoid runtime invocations and privilege changes. P0 ACLs, effective application-identity binding, role inheritance, dynamic/remote paths, complete downstream guard proofs and negative execution results remain unknown.

Disposition: NEEDS_MORE_EVIDENCE for any CURRENT authority repair. Do not elevate permissions to make diagnostic queries succeed.

===ROLE_REPORT:AUTHORITY END===


### ROLE REPORT: COVERAGE

===ROLE_REPORT:COVERAGE BEGIN===

Role: COVERAGE
Case: PE10-IG-M107-M109-P0
Method: PE10_M29_E2, algorithms C+E
Mode: READ_ONLY
Evidence: Q15–Q23
Isolation: shared producer model context; independent-agent isolation is not attested.

C1. Q15–Q16 identify a CURRENT non-function execution surface absent from a function-body-only census: active cron job 45, ig-direct-sql-worker-v1, runs every 30 seconds as database user postgres and executes programacion.fn_input_governance_queue_worker_v1().

C2. Q15–Q16 identify 13 enabled governance-related row triggers across programacion.input_family_assessments, input_gap_proposals, input_readiness_runs, and input_validator_chunk_timings. They are predominantly BEFORE INSERT/BEFORE UPDATE enforcement surfaces. Q15 found zero matching views under its explicit lexical patterns; that zero is limited negative evidence, not proof of absence of indirect application or dynamic routes.

C3. Q17 inspects programacion.fn_guard_input_governance_continuation_currentness_v1() OID 156952 and 46 constraints across assessment, proposal, and Validator-timing tables. INSERT paths call continuation-currentness directly, while UPDATE paths on assessments/proposals deliberately return early and delegate admission to later broad UPDATE guards. The same source separately protects finalized Validator evidence against mutation except an approved storage-compaction path.

C4. Q18 confirms six UPDATE triggers on input_family_assessments and two on input_gap_proposals. The specialized currentness trigger itself does not perform UPDATE admission. Candidate broad final guards are programacion.fn_guard_input_family_assessment_update() OID 59598 and programacion.fn_guard_input_gap_proposal_update_v512() OID 67592.

C5. Q19 establishes that both broad guards explicitly enforce the delegated currentness invariant. OID 59598 calls fn_ig_m107_manifest_guard_bundle_v1(old.run_id) and rejects unless g1.continuation_current=true; it separately rejects unless full_manifest_current=true. OID 67592 does the same through fn_ig_m107_d_proposal_bundle_v1(old.run_id). Thus the hypothesis that UPDATE-currentness admission is simply absent is falsified for these CURRENT paths.

C6. Q19 also establishes layered enforcement beyond currentness. Assessment validation checks curator-field immutability, terminal-only Validator updates, VALIDATING status, Curator/Validator identity separation, contract pinning, direct source readback, source-snapshot and Curator hashes, assertion relevance, assertion re-evaluation, and manifest freshness. Proposal validation similarly checks immutable Curator fields, Validator independence, direct source readback, snapshot agreement, manifest freshness, source-readback digests, and status/outcome consistency.

C7. Q20 establishes that both final-guard bundles converge on the same construction: fn_input_build_source_manifest(p_run_id) followed by fn_ig_m107_bundle_from_manifest_v1(p_run_id, manifest). Proposal bundle OID 297334 additionally exposes the manifest receipts; assessment bundle OID 296647 returns the shared bundle directly.

C8. Q21 establishes that fn_ig_m107_bundle_from_manifest_v1 OID 296646 derives g1 through fn_ig_m107_currentness_from_manifest_v1 plus fn_input_governance_continuation_currentness_decide_v1. Its independent full_manifest_current requires both the rebuilt manifest SHA and the manifest JSON itself to equal the run's pinned source_snapshot_sha256 and source_manifest.

C9. Q22 establishes that fn_input_build_source_manifest_safe_v1 OID 236829 freshly reconstructs the manifest from the canonical screen graph and distinct assessment source references, resolving non-graph refs and attaching authority, lifecycle, and observed-digest receipts. It rejects an empty manifest and forbids full observed payloads in the manifest.

C10. Q22 establishes that fn_ig_m107_currentness_from_manifest_v1 OID 296645 evaluates CURRENTNESS_AUTHORITY availability plus lifecycle, readiness-contract pinning, execution-policy revision, and source-manifest identity. For COMPLETED, aggregate source_current requires lifecycle + contract + policy + manifest currentness.

C11. Q22 identifies a narrower rule for VALIDATING: fn_input_governance_continuation_currentness_decide_v1 OID 156950 requires readiness-contract, execution-policy, and source-manifest currentness but does not consume the lifecycle dimension. This is a real semantic distinction, not by itself a defect.

C12. Q23 tests that distinction against CURRENT reachability. Snapshot counts are validating_count=0, completed_count=235, completed_invalidated_count=191, and completed_completed_successor_count=187; there are no CURRENT validating lifecycle exceptions.

C13. Q23's run guard OID 59600 materially constrains the hypothesized stale VALIDATING state: runs start clean in CURATING; invalidation fields are latched against ordinary nonterminal mutation; the source manifest is database-generated on CURATING→VALIDATING and then immutable; VALIDATING has a restricted transition set; and completion freshly rebuilds and exactly compares the source manifest before requiring the full authorized Validator PASS universe.

C14. A narrow terminal-successor invalidation mutation is permitted only for an already COMPLETED/BLOCKED predecessor and an identified terminal successor. No Q23 evidence demonstrates a CURRENT VALIDATING run with invalidation or completed-successor lifecycle conflict.

Coverage conclusion: the originally suspected CURRENT UPDATE-currentness omission is not demonstrated. The inspected database paths instead show layered fail-closed guards with a shared fresh-manifest/currentness derivation. The remaining uncertainties concern historical P0 equivalence, transient states not present in the CURRENT snapshot, dynamic SQL, external/application/Edge routes, privileged trigger bypass, remote execution, and runtime proof that all production operations enter the inspected paths.

Causal alternative retained: apparent coverage gaps can arise when a specialized trigger intentionally delegates enforcement to a later broad guard; lexical absence of the direct currentness function name in that later guard is insufficient because enforcement may arrive through a shared bundle helper.

Minimal safe action: further read-only provenance/runtime evidence only where authorized; do not alter triggers, grants, schedules, or execution paths based on the present evidence.

Measured runtime/performance cost: NO_MEDIDO.

Decision: NEEDS_MORE_EVIDENCE. No COVERAGE repair requirement has been demonstrated.

===ROLE_REPORT:COVERAGE END===


### ROLE REPORT: INNOVATION

===ROLE_REPORT:INNOVATION BEGIN===

Role: INNOVATION
Case: PE10-IG-M107-M109-P0
Method: PE10_M29_E2, algorithms C+E
Mode: READ_ONLY
Evidence: Q24-Q30
Isolation: shared producer model context; independent-agent isolation is not attested.

I1. Q24 identifies 58 CURRENT lexical/mechanism candidates spanning cached variants, request-local state, manifest/bundle mechanisms, queueing, storage compaction, and generic session-local state. Candidate quantity is not novelty or benefit proof; generic session-state hits include unrelated governance functions and are excluded from positive innovation attribution without a route.

I2. Q25 establishes actual request-local reuse in fn_input_screen_canonical_graph: a supplied request context must match pantalla_id and version_id; its graph must be present and SHA-valid; only then is the cached graph returned. Without context, the graph is constructed and a request-local build counter is incremented. This is implementation evidence for identity-bound, digest-checked graph reuse.

I3. Q25 also falsifies name-based cache inference. fn_input_governance_bootstrap_classify_v2_cached_v1 is a compatibility wrapper to _cached_v2, while fn_input_readiness_run_is_current_cached_v1 and _cached_v2 are source-identical thin calls to fn_input_run_is_source_current. A cached suffix therefore does not itself demonstrate caching or a distinct optimization.

I4. Q25 establishes a tightly scoped graph-reuse design in fn_ig_m107_trusted_run_data_v1: it requires a read-only repeatable/serializable snapshot, rejects preexisting request context, builds and SHA-binds the graph, reuses it inside that snapshot, verifies it against the rebuilt manifest receipt, and restores context on success or failure. Source explicitly scopes this to the transaction/request rather than a persistent session cache.

I5. Q25-Q26 establish freshness-delta reuse end-to-end. fn_input_governance_curator_plan_v1 computes freshness once and stores the exact delta with run_id and pantalla_id. fn_input_governance_recurate_source_stale_v1 consumes it only when both identifiers match; otherwise it recomputes freshness. Thus producer, consumer, and cache-key mismatch fallback are all implementation-proven.

I6. Q26 establishes cache lifecycle controls in fn_input_governance_curator_materialize_v1: request counters/cache state are initialized before orchestration and cleared on both normal and exception paths. The source rejects a graph-build count other than exactly one and freshness evaluation count greater than one on this orchestrated path.

I7. Q26 also shows built-in observation surfaces: per-family resolver spans, total SQL elapsed milliseconds, graph-build count, and freshness count are returned. This is instrumentation design, not measured optimization benefit in Q26.

I8. Q27 establishes content-addressed Validator evidence compaction. The compaction checker allows only an inline-assertions to assertion_set_sha256 representation transition, requires the referenced content to exist and hash correctly, requires rehydrated logical evidence to equal the original evidence exactly, forbids unrelated row changes, and requires validator_sha256 to remain immutable.

I9. Q27 establishes defensive migration controls: bounded batches, advisory locking, contract/function-definition drift pins, per-row rehydration equality, cumulative receipts, full-population verification, terminal VERIFIED/FAILED states, and scheduler shutdown after completion/failure.

I10. Q28 establishes observed completion of that migration: checkpoint status VERIFIED, disabled, baseline eligible 10131, compacted 10131, exhaustive verification 10131, with 8251 current-hash matches, 1880 legacy-hash matches, and 0 unmatched receipts. CURRENT storage shows 11165 reference-only terminal Validator rows, 0 inline-only, 0 both-shape rows, and 3755 assertion sets. Actual bytes/I/O saved remain NO_MEDIDO.

I11. Q27 establishes a bounded queue worker: one queued request is locked with FOR UPDATE SKIP LOCKED; each invocation performs at most ten direct steps; total request steps are capped at twenty; work exits around a thirty-second worker budget and can continue on the next cron tick; exceptions are persisted as request errors.

I12. Q28-Q29 establish operational queue use. Eight CURRENT request rows exist and all have queue status DONE, no recorded error code, and maximum step count eight. Their final observed result states are six BLOCKED and two READY, not COMPLETED/NOOP_COMPLETED. Observed request wall times span 46597 to 324299 ms, but workloads/outcomes are heterogeneous and there is no counterfactual baseline; no queue speedup ratio is valid.

I13. Q29 dates six observed queued requests before the P0 cutoff 2026-10-15T00:00Z. Therefore bounded queue continuation demonstrably operated before P0 and cannot be attributed as a post-P0 innovation.

I14. Q28 dates the verified compaction execution to 2026-10-07, also before P0. Content-addressed storage compaction therefore cannot be attributed as a post-P0 innovation.

I15. Q30 finds positive P0-event token evidence for fn_input_governance_bootstrap_classify_v2_cached_v2, fn_input_governance_recurate_source_stale_v1, and fn_input_readiness_run_is_current_cached_v1. Those implementation names were already represented in the P0 event payload.

I16. Q30 finds no event-20161 token for fn_input_screen_canonical_graph, fn_input_governance_curator_plan_v1, fn_ig_m107_trusted_run_data_v1, queue/compaction function names, or any of the four tested lf.input_request_* keys. This is only absence from that historical event representation. It is explicitly not database-existence evidence.

I17. Q28/Q29 supply a direct falsifier against treating Q30 absence as post-P0 novelty: queueing and compaction were operational before P0 despite their names being absent from event 20161. Therefore no tested event-token absence is promoted to an object-creation date.

Innovation conclusion: CURRENT implementation contains concrete safety-oriented reuse and operational mechanisms—transaction/request-local canonical-graph reuse, identity-checked freshness-result reuse, bounded continuation queueing, and content-addressed Validator-evidence compaction. Queueing and compaction demonstrably predate P0; several cached/recuration names are positively present in the P0 event. The historical evidence is insufficient to date creation of the request-local reuse mechanisms, so post-P0 novelty is unproven.

Performance/benefit conclusion: mechanism existence and some operational outcomes are measured, but causal improvements in latency, CPU, I/O, storage bytes, or throughput are not established. Speed/resource benefit: NO_MEDIDO.

No innovation-associated defect requiring repair was demonstrated.

Decision: NEEDS_MORE_EVIDENCE for P0-relative novelty and causal benefit. If an optimization-benefit claim must be adjudicated, obtain matched governed timing/resource observations rather than infer benefit from names, source size, counters, or heterogeneous queue wall times.

===ROLE_REPORT:INNOVATION END===


### SYNTHESIS

{
"case_id": "PE10-IG-M107-M109-P0",
"method": "PE10_M29_E2",
"algorithms": ["C", "E"],
"status": "RAW_FROZEN_UNGRADED",
"provenance": {
"mode": "READ_ONLY",
"isolation": "CONTAMINATED_COORDINATOR_CAUSED_DENYLIST_EXPOSURE",
"provider_independent_agent_isolation": "UNPROVEN",
"denylisted_material_used_as_evidence": false,
"note": "Q8 coordinator relay exposed denylisted previous-method SQL text. That material is excluded from evidentiary reasoning. The five roles were executed sequentially in one shared model context, so strict independent-agent isolation is not attested."
},
"role_dispositions": {
"ARCHITECTURE": "NEEDS_MORE_EVIDENCE",
"PERFORMANCE": "NEEDS_MORE_EVIDENCE",
"AUTHORITY": "NEEDS_MORE_EVIDENCE",
"COVERAGE": "NEEDS_MORE_EVIDENCE",
"INNOVATION": "NEEDS_MORE_EVIDENCE"
},
"material_edges": [
{
"id": "SYN-A1",
"role": "ARCHITECTURE",
"evidence": ["Q1", "Q2"],
"finding": "All 38 historical caller identities still resolve to the same CURRENT schema/name/OID identities, but 22 of 38 bodies changed and 16 remain body-identical. OID continuity therefore does not establish behavioral continuity."
},
{
"id": "SYN-A2",
"role": "ARCHITECTURE",
"evidence": ["Q3", "Q4", "Q5", "Q6"],
"finding": "The CURRENT lexical census is materially broader than the historical inventory: 446 candidate rows split into 68 historical-declared edges, 102 CURRENT edges outside P0 declarations, and 276 consumers outside the P0 inventory. Eight historical exact-call declarations no longer have the same exact current call token. Variant routing is visible, but semantic equivalence of old/new variants is not established."
},
{
"id": "SYN-A3",
"role": "ARCHITECTURE",
"evidence": ["Q6"],
"finding": "At least one apparent recursive lexical candidate is a JSON/string occurrence rather than an executable edge. Lexical matches are therefore not promoted to runtime dependencies without source-context resolution."
},
{
"id": "SYN-P1",
"role": "PERFORMANCE",
"evidence": ["Q7"],
"finding": "pg_stat_statements is available, but track_functions is disabled, planning statistics are off, and I/O timing is off. The available telemetry cannot attribute per-function cost or full planning/I/O behavior."
},
{
"id": "SYN-P2",
"role": "PERFORMANCE",
"evidence": ["Q8", "Q9"],
"finding": "Measured CURRENT aggregate SQL cohorts exist, including queue-worker, curator, shadow, and validator statements, but the statistics window straddles P0 and the cohorts are not matched equivalent workloads. No valid optimization speedup ratio can be derived."
},
{
"id": "SYN-P3",
"role": "PERFORMANCE",
"evidence": ["Q8"],
"exclusion": "Coordinator-relayed denylisted previous-method query text was observed in query samples and excluded from evidence."
},
{
"id": "SYN-AU1",
"role": "AUTHORITY",
"evidence": ["Q10", "Q11"],
"finding": "For the inspected CURRENT functions, anon and authenticated have no effective direct-call route. service_role has effective direct access to a limited public surface while internal programacion helpers are not directly callable because schema usage prevents effective direct invocation."
},
{
"id": "SYN-AU2",
"role": "AUTHORITY",
"evidence": ["Q12"],
"finding": "Several public SECURITY DEFINER wrappers delegate directly into internal governance functions without independent wrapper-level identity predicates. Their safety therefore depends on downstream caller-context and governance guards; the inspected downstream sources contain substantial run, identity, freshness, receipt, and graph checks, but complete route proof remains unresolved."
},
{
"id": "SYN-AU3",
"role": "AUTHORITY",
"evidence": ["Q13"],
"exclusion": "Q13 failed with SQLSTATE 42883 due to an invalid digest(text, unknown) construction and contributes no database evidence."
},
{
"id": "SYN-AU4",
"role": "AUTHORITY",
"evidence": ["Q14"],
"finding": "Both contract-authorized historical EKB records were retrieved with the expected hashes. They document a prior unauthorized-read failure and SOAK/currentness criteria; their historical claims were not independently rerun as CURRENT execution."
},
{
"id": "SYN-C1",
"role": "COVERAGE",
"evidence": ["Q15", "Q16"],
"finding": "CURRENT execution/enforcement surfaces extend beyond the historical function-body inventory, including an active scheduled queue worker and 13 enabled governance-related row triggers."
},
{
"id": "SYN-C2",
"role": "COVERAGE",
"evidence": ["Q17", "Q18", "Q19"],
"finding": "The initially suspicious assessment/proposal UPDATE currentness path intentionally delegates from a specialized currentness trigger to broader final UPDATE guards. Those final guards explicitly reject unless continuation currentness and full-manifest currentness hold. The hypothesized missing UPDATE-currentness control is therefore not demonstrated."
},
{
"id": "SYN-C3",
"role": "COVERAGE",
"evidence": ["Q20", "Q21", "Q22"],
"finding": "Both final-guard paths converge on shared manifest reconstruction/currentness helpers. The manifest is freshly rebuilt from canonical graph/source references; full-manifest currentness requires exact JSON and digest equality with the pinned run snapshot; continuation currentness separately evaluates contract, policy, manifest and status-dependent authority dimensions."
},
{
"id": "SYN-C4",
"role": "COVERAGE",
"evidence": ["Q22", "Q23"],
"finding": "VALIDATING continuation uses a narrower currentness decision than COMPLETED lifecycle currentness, but Q23 found zero CURRENT VALIDATING rows and the run guard constrains invalidation, manifest mutation, transitions and completion freshness. No reachable CURRENT stale-VALIDATING counterexample was demonstrated."
},
{
"id": "SYN-I1",
"role": "INNOVATION",
"evidence": ["Q24", "Q25", "Q26"],
"finding": "CURRENT source implements SHA-bound request/transaction-local canonical-graph reuse and identity-keyed freshness-delta reuse with recomputation on cache-key mismatch and explicit cleanup/counters. These are implementation-proven mechanisms, not inferred from cached-function names."
},
{
"id": "SYN-I2",
"role": "INNOVATION",
"evidence": ["Q27", "Q28"],
"finding": "Validator-evidence compaction is content-addressed and representation-only by checked rehydration equivalence. Its observed migration completed VERIFIED over 10131 baseline-eligible assessments with exhaustive verification and zero unmatched receipt hashes."
},
{
"id": "SYN-I3",
"role": "INNOVATION",
"evidence": ["Q27", "Q28", "Q29"],
"finding": "The bounded queue mechanism is operational. Eight observed requests are DONE at the queue layer, with six final BLOCKED and two READY outcomes and no recorded error codes. Their heterogeneous wall times are observations, not a speed benchmark."
},
{
"id": "SYN-I4",
"role": "INNOVATION",
"evidence": ["Q28", "Q29", "Q30"],
"finding": "Queue operation and verified compaction both predate the P0 cutoff. Several cached/recuration function names are positively present in the P0 event. Request-local-state tokens are absent from that event, but absence cannot establish post-P0 creation because queue/compaction provide a direct counterexample to event-token completeness."
}
],
"demonstrated_defects": [],
"repair_required": false,
"critical_exposure": {
"demonstrated": false,
"reason": "A public/service_role delegation surface exists, but the frozen authority evidence does not demonstrate an unguarded successful critical route. Downstream guards are materially present and complete reachable-route proof remains unresolved."
},
"performance": {
"speedup_claim_supported": false,
"speedup": "NO_MEDIDO",
"resource_savings": "NO_MEDIDO",
"reason": "Available observations are aggregate, unmatched, heterogeneous, or mechanism-level. No valid before/after equivalent cohort establishes causal latency, CPU, I/O, throughput, or storage-byte improvement."
},
"innovation": {
"mechanisms_demonstrated": [
"SHA-bound request/transaction-local canonical graph reuse",
"run/screen-keyed freshness-delta reuse with fallback recomputation",
"bounded scheduled continuation queue",
"content-addressed Validator-evidence compaction with rehydration equivalence"
],
"post_p0_novelty_supported": false,
"causal_benefit_supported": false
},
"s2_decision": {
"label": "MEASURE_FIRST",
"ordering_rule": [
"REPAIR_REQUIRED",
"MEASURE_FIRST",
"VERIFY_CRITICAL",
"CLEAR_NO_ACTION",
"VERIFY_MINOR"
],
"rationale": "No demonstrated defect satisfies REPAIR_REQUIRED. The principal unresolved claim is whether the evolved mechanisms deliver a causal optimization benefit; current telemetry cannot establish that. Because S2 orders MEASURE_FIRST ahead of VERIFY_CRITICAL and no actual critical exposure route is demonstrated, MEASURE_FIRST is the governing disposition."
},
"minimal_safe_next_action": {
"action": "Obtain authorized matched governed measurements for equivalent workloads using existing timing/receipt surfaces, with explicit P0-comparable cohort definition where available.",
"constraints": [
"READ_ONLY evidence collection unless separately authorized",
"do not elevate EXECUTE/schema privileges",
"do not alter triggers, schedules, guards, or governance state merely to manufacture a benchmark",
"do not infer runtime edges from lexical references",
"keep historical P0 evidence distinct from CURRENT catalog/runtime evidence",
"exclude coordinator-relayed denylisted material"
]
},
"unresolved": [
"Matched P0-versus-CURRENT performance equivalence",
"Creation/deployment provenance for request-local reuse mechanisms",
"Complete dynamic/remote/Edge execution routes",
"End-to-end effective caller identity binding through every public wrapper",
"Historical semantic equivalence of changed routing variants",
"Provider-level independent-agent isolation"
]
}

