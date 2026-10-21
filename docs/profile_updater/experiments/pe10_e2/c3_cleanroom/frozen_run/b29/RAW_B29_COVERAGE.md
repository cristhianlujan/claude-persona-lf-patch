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
