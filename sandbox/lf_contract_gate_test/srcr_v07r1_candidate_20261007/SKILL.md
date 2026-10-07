# SYSTEMIC_ROOT_CAUSE_REPAIR_LF — V0.7R1 CANDIDATE

Status: EXPERIMENTAL_CANDIDATE / READ_ONLY
Profile Pack ID: SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_7R1_CANDIDATE
Baseline preserved: SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_7_CANDIDATE @ 83d140517ec69faa245269de6c1d53fc873e3ced
Benchmark target: LF_REPAIR_DYNAMIC_V3_2026
Runtime activation: FORBIDDEN
Production mutation: FORBIDDEN
Canonical promotion: FORBIDDEN until independent benchmark acceptance

## Objective

Diagnose and specify the minimum sufficient durable repair for recurrent or architecturally material failures by dynamically selecting investigation modules, reasoning strategies and repair operators from observed case signals.

V0.7R1 preserves V0.7 diagnosis, module selection, topology, repair operators and RAW output shape. It changes only closure discipline: a deterministic terminality/completeness gate prevents SYSTEMIC_REPAIR_SPEC while material evidence, wiring, second-order recurrence or applicable operability ownership remains open. It does not add the R4 universal overlay as a new diagnostic pass.

CASE -> SIGNAL TRIAGE -> MANDATORY CORE -> DYNAMIC MODULES -> REPAIR TOPOLOGY MAP -> ADAPTIVE SEARCH STRATEGY -> REPAIR OPERATORS -> SECOND-ORDER IMPACT -> FALSIFICATION -> IMPLEMENTABLE REPAIR SPEC

## Non-negotiable invariants

1. V0.6 remains immutable historical baseline.
2. No new transversal capability is created merely because a repair module needs composition.
3. Existing LF capabilities are reused before proposing new architecture.
4. Selection is by typed case signals, never by product/module name alone.
5. Multiple modules/strategies/operators may be selected for one case.
6. A material front cannot be silently skipped. Each front is REQUIRED, REUSE_AS_IS or NOT_APPLICABLE with reason/evidence.
7. Component existence is not physical wiring.
8. Declared behavior is not observed execution.
9. Reachability must be proven before code/config is promoted to root cause.
10. Repair targets the earliest preventable boundary that removes the failure class with acceptable blast radius.
11. A local fix cannot close when the same failure class remains reachable through another consumer/path/state/version.
12. No SYSTEMIC_REPAIR_SPEC while any material GAP, UNKNOWN, EVIDENCE_REQUIREMENT or DESIGN_BLOCKING item remains unresolved, including evidence needed to prove physical wiring, blast radius, rollback, compatibility, acceptance or terminality.
13. Repair design, implementation, activation and post-implementation verification are separate governed phases.
14. No external research substitutes LF authority.
15. Never invent WOW. Novelty must be evidence-backed and materially change diagnosis or repair.
16. Terminal status is decided only after the V0.7R1 mechanical completeness gate; diagnostic confidence alone cannot override an open material item.
17. OPERABILITY_MAINTENANCE_OWNERSHIP is a closure front only when the repair touches persistent runtime/data state, background work, triggers, events, leases, queues, durable cleanup or ongoing maintenance. When applicable it must be RESOLVED or NOT_APPLICABLE_WITH_PROOF before SYSTEMIC_REPAIR_SPEC.

## Existing transversal capabilities to reuse

- CAPABILITY_SELECTOR
- TARGETED_EVIDENCE_ACQUISITION
- CURRENTNESS_AUTHORITY
- DECISION_CONTEXT_ASOF
- CAUSAL_EFFECT_LINEAGE
- CAPABILITY_VERSION_COMPATIBILITY
- CONSUMER_ADMISSION
- CONTROL_EQUIVALENCE_JUDGE
- EXECUTION_INVALIDATION_PROPAGATION
- REVERSIBLE_CANDIDATE_VERIFICATION
- INDEPENDENT_ASSURANCE
- LF_CONTRACT_CHECK
- PRIVACY_MINIMALITY_GUARD
- PERFORMANCE_EXACT_SOURCE_BENCHMARK
- VISUAL_EVIDENCE_GATE
- TYPED_EVIDENCE_REGISTRY
- EVIDENCE_LEDGER
- FINAL_EVIDENCE

A new capability may be proposed only when:
(a) the responsibility is demonstrably transversal across multiple consumers,
(b) equivalent current capability composition cannot satisfy it,
(c) duplicated implementations already exist or would otherwise be created,
(d) ownership, contract and validation boundary are clear.

## Phase 0 — Freeze evidence cut

Freeze:
- exact input/case identity;
- exact source revision(s);
- database/readback timestamp or authority cut;
- profile/method revision;
- allowed tool surfaces;
- relevant prior evidence packs and their currentness.

Do not silently change the evidence cut between hypotheses.

## Phase 1 — Typed signal triage

Produce `case_signals[]`. Signals are domain-agnostic and evidence-backed.

Signal families:
- AUTHORITY_CONTRADICTION
- CURRENTNESS_DRIFT
- IDENTITY_VERSION_DRIFT
- CONTRACT_MISMATCH
- TRANSPORT_CONTINUITY_RISK
- RECEIVER_ENFORCEMENT_RISK
- STATE_LIFECYCLE_DEFECT
- TERMINALITY_DEFECT
- CONSUMER_DIVERGENCE
- MULTI_CONSUMER_IMPACT
- DEPENDENCY_CYCLE
- DEPENDENCY_PROPAGATION
- CONCURRENCY_RACE
- RETRY_REPLAY_RESUME
- PARTIAL_FAILURE_RECOVERY
- ROLLBACK_RESIDUE
- SECURITY_PERMISSION_BOUNDARY
- PRIVACY_MINIMALITY
- DATA_CARDINALITY
- MISSING_VS_EMPTY
- UI_VISUAL
- PERFORMANCE_CONTEXT_COST
- DUPLICATE_AUTHORITY
- DUPLICATE_COMPONENT
- UNNECESSARY_COMPONENT
- REPEATED_LOCAL_FIX
- MULTI_LOCATION_FAILURE
- EVIDENCE_CONTRADICTION
- UNKNOWN_MATERIAL_PATH

Each signal includes:
- signal_code
- status: OBSERVED | ESTABLISHED | HYPOTHESIS | UNKNOWN
- evidence_refs
- materiality
- potentially_affected_fronts

## Phase 2 — Mandatory core

Always evaluate:

1. authority/currentness;
2. physical reachability/wiring;
3. causal boundary / first bad boundary;
4. repair/reuse/elimination decision;
5. falsification;
6. rollback/recovery applicability;
7. acceptance/readback.

Mandatory core may be LIGHTWEIGHT when the case is deterministic, but it is never omitted.

## Phase 3 — Dynamic diagnostic modules

Select only modules justified by case signals. Emit `module_selection[]` with SELECTED/SKIPPED and reason.

Modules:
- CONTRACT_TRANSPORT
- STATE_LIFECYCLE
- AUTHORITY_BINDING
- IDENTITY_VERSION
- CONSUMER_COMPATIBILITY
- DEPENDENCY_PROPAGATION
- CONCURRENCY_REPLAY
- RECOVERY_ROLLBACK
- SECURITY_PRIVACY
- UI_VISUAL
- PERFORMANCE_CONTEXT
- MIGRATION_CUTOVER
- DATA_SHAPE_CARDINALITY
- PROVENANCE_LINEAGE
- OBSERVABILITY_READBACK

Selection must be explainable from signals. Product names such as INPUT_GOVERNANCE, STORY_CREATOR or PROFILE_UPDATER are not selection rules.

## Phase 4 — Repair Topology Map

Build a bounded graph for the failure class:

INTENT -> AUTHORITY -> DECISION -> CONTRACT/DATA -> TRANSPORT -> CONSUMER -> EXECUTION -> STATE/EFFECT -> READBACK -> TERMINALITY

For each material node/edge capture:
- exact identity/version;
- owner/authority;
- producer and consumer;
- physical reachability evidence;
- applicable invariant;
- current status;
- failure behavior;
- recovery/rollback behavior;
- affected upstream/downstream nodes;
- confidence/evidence refs.

Produce:
- `repair_topology.nodes[]`
- `repair_topology.edges[]`
- `repair_topology.first_bad_boundary`
- `repair_topology.escape_control`
- `repair_topology.affected_fronts[]`
- `repair_topology.blast_radius[]`

Blast radius is derived from demonstrated reachability/dependency/consumer relationships, never guessed from naming proximity.

## Phase 5 — Adaptive reasoning strategy

Select the minimum strategy set needed to resolve the case.

Available strategy families:

### DIRECT_CAUSAL_REPAIR
Use when the failure class, boundary and repair are deterministically established.

### GRAPH_HYPOTHESIS_SEARCH
Use when multiple causal chains or cross-surface explanations are plausible.

### TREE_SEARCH
Use when several repair alternatives require branching comparison.

### VERIFIER_GUIDED_SEARCH
Use when candidate hypotheses can be cheaply falsified by deterministic/read-only probes.

### MULTI_FIX_COORDINATION
Use when multiple affected fronts must be repaired coherently.

### PARALLEL_SEARCH
Use when materially distinct search paths can be evaluated independently.

### MULTI_LOCATION_SEARCH
Use when failure evidence indicates more than one physical location/path.

### HOSTILE_CHALLENGER
Use when ambiguity, systemic blast radius or irreversible downstream consequences are material.

### EXTERNAL_CURRENT_PRACTICE_RESEARCH
Use only when architecture/technique can materially improve beyond LF internal authority. Freeze the pre-research baseline first.

Emit `strategy_selection[]` containing:
- strategy
- trigger_signals
- why_selected
- stop_condition
- estimated evidence cost
- actual calls/queries/reads when executed

## Phase 6 — Hypothesis and localization

For each surviving hypothesis record:
- symptom explained;
- suspected first bad boundary;
- supporting evidence;
- reachability evidence;
- contradicting evidence;
- falsifier;
- affected fronts if true.

Localization must identify the earliest evidence-backed preventable boundary, not merely the file or component where the symptom is visible.

## Phase 7 — Repair operators

Do not create one monolithic method per defect family. Compose repair from operators:

- KEEP_AS_IS
- LOCAL_PATCH
- MOVE_CONTROL_UPSTREAM
- REWIRE
- CHANGE_CONTRACT
- CHANGE_TRANSPORT
- CHANGE_STATE_TRANSITION
- REBIND_AUTHORITY
- REBIND_VERSION
- INVALIDATE_STALE_DERIVED_STATE
- MIGRATE_COMPATIBILITY
- DRAIN_CONSUMERS
- ADD_FAIL_CLOSED_GUARD
- ADD_RECEIVER_VERIFICATION
- ADD_IDEMPOTENCY
- ADD_DEDUPE
- ADD_RECOVERY
- REUSE_EXISTING
- MERGE_WITH_EXISTING
- ELIMINATE
- CONTAIN
- ROLLBACK
- NO_CHANGE

Each selected operator must bind to:
- exact target boundary;
- reason;
- dependencies/preconditions;
- affected consumers;
- compatibility consequence;
- acceptance test;
- negative test;
- rollback/readback.

## Phase 8 — Alternative search

When material ambiguity exists, compare at least:
A_LOCAL_MINIMAL
B_SYSTEMIC_PREVENTIVE
C_REUSE_SIMPLIFY_ELIMINATE

Additional alternatives may be added when evidence warrants.

Compare:
- recurrence prevention;
- blast radius;
- bypass resistance;
- compatibility;
- idempotency;
- recoverability;
- new dependencies;
- operational complexity;
- evidence cost;
- runtime/context cost.

## Phase 9 — Second-order impact

Assume the immediate defect is fixed. Search for remaining paths that recreate the same failure class:

- stale currentness/provenance;
- hidden consumers;
- alternate caller/path;
- old identity/version;
- retry/replay/resume;
- concurrency;
- partial failure;
- derived copies/contracts;
- rollback residue;
- transport downgrade;
- receiver mismatch;
- observability gap;
- non-exigible/disabled controls accidentally reintroduced.

Any demonstrated second-order path that recreates the failure class prevents closure.

## Phase 10 — Probe before promote

When safe and within scope, use read-only, sandbox or rollback-only probes before promoting a material hypothesis.

Examples:
- authority resolver vs runtime readback;
- exact-version/currentness comparison;
- missing/empty/cardinality negative;
- consumer/path negative;
- retry/replay;
- compatibility replay;
- receiver rejection of stale/missing invariant;
- rollback residue verification.

Record expected vs observed result.

## Phase 11 — Repair atomization

Produce reversible `repair_units[]`.

Each unit:
- objective;
- exact target;
- change_class;
- operator(s);
- dependencies;
- consumers affected;
- acceptance;
- negative test;
- rollback;
- readback;
- activation/cutover status.

Do not mix unrelated cleanup into the repair.

## Phase 12 — Falsification and hostile challenge

Falsify:
- counterfactual;
- bypass;
- replay/duplicate;
- concurrency;
- partial failure;
- stale evidence;
- hidden consumer;
- second execution path;
- transport omission;
- receiver mismatch;
- rollback failure;
- elimination/reuse alternative.

For high materiality or unresolved competing hypotheses, execute HOSTILE_CHALLENGER before closure.

## Phase 13 — Efficiency and evidence discipline

Reuse current source packs/receipts/manifests when currentness is proven.
Read fresh only evidence capable of changing the decision.
Track:
- reused_sources;
- fresh_reads;
- avoided_rereads;
- calls/queries;
- duplicate_reads;
- retries;
- latency/duration when available;
- token telemetry when provider execution exposes it.

Efficiency never justifies missing material evidence.

## Phase 14 — Mechanical terminality completeness gate

Run this gate after Phase 13 and immediately before emitting `status`.

This gate is a closure control, not a second diagnostic method and not the R4 universal overlay. It performs zero new searches, reads, queries or diagnostic calls. It uses only evidence already collected by V0.7 and the existing required output surfaces. The required RAW output keys remain unchanged from V0.7.

### 14.1 Build the internal closure set

Derive `material_open_items` from already-known items in:
- `unknowns[]`;
- unresolved or unexecuted `observable_probes[]`;
- material `repair_topology` nodes/edges without sufficient evidence;
- reachable `second_order_risks[]` that remain uncontained;
- material `residual_risks[]`;
- missing physical-wiring/readback evidence in `evidence_map[]`;
- `blocking_codes[]`;
- applicable operability/maintenance ownership.

Classify an item as material when its resolution can change any of:
- root cause or first bad boundary;
- selected repair/operator;
- demonstrated blast radius or affected consumer/path;
- compatibility/transition;
- rollback/recovery;
- acceptance/readback;
- terminality;
- proof that the repair/control is physically wired on the failing path.

Material open states are:
- GAP
- UNKNOWN
- EVIDENCE_REQUIREMENT
- DESIGN_BLOCKING

Do not downgrade an open item merely because the probable repair is already known.

### 14.2 Operability / maintenance ownership applicability

Evaluate `OPERABILITY_MAINTENANCE_OWNERSHIP` only when evidence shows persistent runtime/data effects, background work, trigger/event/lease/queue lifecycle, durable cleanup, recurring reconciliation, or another ongoing maintenance responsibility.

When applicable, closure requires evidence already in the run showing:
- who/what owns cleanup or ongoing operation;
- what state/readback proves cleanup or healthy continuation;
- how retry/replay is prevented from recreating residue where applicable;
- how retirement/rollback is handled where applicable.

If that evidence is material and absent, add an internal material open item and return NEEDS_MORE_EVIDENCE. Do not create a new transversal capability merely to satisfy this front.

### 14.3 Mechanical decision

Apply in this order:

1. If safety/governance/currentness contradiction requires fail-closed blocking -> BLOCK_PIPELINE.
2. If repair is positively proven unnecessary and no material open item remains -> NO_REPAIR_REQUIRED.
3. If `material_open_items` is non-empty -> NEEDS_MORE_EVIDENCE.
4. If any demonstrated second-order recurrence path is reachable and uncontained -> NEEDS_MORE_EVIDENCE.
5. If applicable OPERABILITY_MAINTENANCE_OWNERSHIP is not RESOLVED or NOT_APPLICABLE_WITH_PROOF -> NEEDS_MORE_EVIDENCE.
6. If root cause, first bad boundary, topology/blast radius, coherent repair, executable rollback or executable acceptance are not sufficiently evidence-bound -> NEEDS_MORE_EVIDENCE.
7. Only otherwise -> SYSTEMIC_REPAIR_SPEC.

The deterministic reference implementation for this decision is `terminality_gate_v1.py`. Its purpose is to make the terminal rule testable; it does not replace semantic diagnosis.

## Terminal states

### SYSTEMIC_REPAIR_SPEC
Allowed only when the Phase 14 gate returns SYSTEMIC_REPAIR_SPEC. In particular:
- root cause and first bad boundary are established;
- all material fronts are resolved;
- no material GAP, UNKNOWN, EVIDENCE_REQUIREMENT or DESIGN_BLOCKING item remains;
- repair topology and blast radius are evidence-bound;
- selected operators form an implementable coherent repair;
- second-order search finds no reachable uncontained recurrence path;
- applicable operability/maintenance ownership is resolved or proven not applicable;
- rollback and acceptance are executable;
- independent quality gate requirements are satisfied.

### NEEDS_MORE_EVIDENCE
Use whenever a material open item remains, including missing evidence that can change cause, repair, blast radius, compatibility, rollback, acceptance, terminality, physical wiring/readback, second-order containment or applicable operability ownership.

### NO_REPAIR_REQUIRED
Use only with positive current evidence proving ALREADY_RESOLVED or NOT_MATERIAL.

### BLOCK_PIPELINE
Use when safety/governance/currentness contradiction prevents trustworthy repair design.

## Required output

- status
- profile_pack_id
- evidence_cut
- case_signals[]
- module_selection[]
- capability_reuse[]
- strategy_selection[]
- facts[]
- declared_behavior[]
- inferred[]
- unknowns[]
- repair_topology
- hypotheses[]
- observable_probes[]
- first_bad_boundary
- escape_control
- systemic_root_cause
- should_exist_assessment
- alternatives[]
- selected_alternative
- repair_operators[]
- second_order_risks[]
- repair_units[]
- implementation_delta[]
- compatibility_plan
- transition_plan
- rollback_plan
- acceptance_tests[]
- residual_risks[]
- evidence_map[]
- efficiency_receipt
- wow_discovery
- blocking_codes[]
- next_gate

## WOW rule

WOW exists only when evidence demonstrates a materially non-obvious improvement, such as:
- several symptoms collapse to one upstream boundary;
- a hidden consumer/path invalidates the obvious repair;
- an existing capability eliminates proposed architecture;
- an invariant disappears across transport/receiver;
- physical execution contradicts declared authority;
- a second-order path falsifies an apparently complete repair;
- rollback cannot restore exact prior binding/state;
- a smaller repair is proven to remove the full failure class.

No novelty is required for PASS.

## Candidate boundary

This candidate may be benchmarked and independently reviewed.
It preserves the V0.7 RAW output shape and diagnostic architecture; only terminality/completeness behavior is tightened.
It may not replace V0.6/V0.7, be bound to runtime, activate controls, mutate production, or be promoted to canonical until matched-evidence regression and independent assurance produce an explicit governed acceptance.
