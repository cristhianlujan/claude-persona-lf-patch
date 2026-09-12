# LF Work Package Bootstrap v0.1

Status: CANDIDATE / BOOTSTRAP ONLY
Strategy owner: S31
Purpose: govern S31 work before the final LF Work Package contract exists.

## 1. Design intent

This bootstrap evolves from the existing LF Task Packet and S30 pre-execution assurance. It is intentionally usable before complete standardization. S31 must execute under this contract and use observed defects, friction and evidence to improve later versions.

The bootstrap is not Golden, does not authorize production, does not authorize main merge, and does not mutate S30/S26 internals.

## 2. Required identity

- work_package_id
- strategy_id
- lane_id
- capability_id
- version
- owner
- worker
- judge

## 3. Currentness and source authority

- base_main_sha
- source_snapshot_refs
- source_snapshot_sha256
- authority_refs
- currentness_policy
- cross_run_references

Material work MUST stop when the base/currentness evidence is stale, ambiguous or missing.

## 4. Ownership and collision control

- active_writer_scope
- read_only_sources
- allowed_dependencies
- forbidden_cross_lane_writes
- collision_checks

Principle: ONE_CAUSAL_CHAIN_ONE_ACTIVE_WRITER.

S31 may read S30, S26, Learning Engine and Story Creator sources. S31 work packages MUST write only S31-owned paths unless an explicit interface-change handoff transfers work to the owning strategy.

## 5. Scope contract

- allowed_tools
- allowed_read_scope
- allowed_write_scope
- forbidden_actions

Default S31 forbidden actions:

- mutate S30 internals
- mutate S26 internals
- mutate Learning Engine internals
- mutate Story Creator internals
- enable production
- enable runtime fleet-wide
- promote Golden
- merge main
- rewrite unrelated migrations
- silently broaden scope

## 6. Capability binding

- required_capabilities
- capability_versions
- compatibility_requirements
- adapter_requirements
- unresolved_capabilities

Unknown capability bindings are fail-closed when material to execution.

## 7. Pre-execution assurance

Before material work:

1. resolve exact base/currentness;
2. resolve source authority;
3. resolve applicable EKB/governance rules;
4. confirm ownership and collision-free write scope;
5. resolve required schemas/contracts;
6. resolve required tools/functions/adapters;
7. confirm evidence provider/readback path;
8. enumerate acceptance/failure/blocking assertions;
9. define negative/fail-closed path;
10. only then allow material work.

## 8. Assertions

Every package requires:

- acceptance_assertions
- failure_assertions
- blocking_assertions
- invalidation_conditions

Assertions must be machine-checkable where practical.

## 9. Evidence contract

- required_evidence
- evidence_refs
- evidence_digests
- claim_ceiling
- producer_receipt
- judge_receipt
- readback_receipt

A PASS cannot exceed the strongest demonstrated evidence layer.

## 10. Frontier and continuity

- current_stage
- next_gate
- blockers
- safe_parallel_work
- handoff_target
- handoff_contract

A handoff must transfer a consumable artifact/state. It must not ask the next worker to recreate an artifact already claimed as produced.

## 11. Closure

Closure requires binary verification of all package assertions and readback of required outputs. Declared completion percentages are informational only unless recomputed from the closure ledger.

## 12. Bootstrap evolution rule

A new field or rule may be added to the Work Package only when justified by at least one of:

- observed execution defect;
- repeated ambiguity or rework;
- cross-lane collision;
- missing evidence/currentness control;
- reusable requirement proven across more than one capability/domain;
- external standard needed behind a stable LF abstraction.

Every material contract change must include positive and negative regression coverage before becoming the next bootstrap version.

## 13. S31 initial execution lanes

- S31-A: Canonical Capability Model
- S31-B: LF Work Package Contract evolution
- S31-C: Canonical Cards/Fallback semantics
- S31-D: Shared Authority + Typed Context kernel
- S31-E: Capability Registry
- S31-F: Evidence / Receipt / Lifecycle
- S31-G: Runtime Ports & Adapters
- S31-H: External Standards / PoCs

## 14. Bootstrap result vocabulary

- PASS_TO_MATERIAL_WORK
- PASS_TO_READ_ONLY_PARALLEL
- RETURN_TO_WORKER_FOR_SELF_REPAIR
- BLOCKED_CAUSAL
- FAIL_CLOSED_BEFORE_MATERIAL_WORK
- READY_FOR_INDEPENDENT_JUDGE
- CLOSED_WITH_EVIDENCE

## 15. Promotion boundary

This bootstrap may evolve from v0.1 to later candidate versions during S31. No version becomes LF Work Package v1 or Golden without independent evidence, regression coverage and explicit governance approval.
