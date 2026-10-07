# CARD — Material Front Coverage V5 R4 Passive

Status: CANDIDATO / READ_ONLY
Card ID: CARD-LF-MATERIAL-FRONT-COVERAGE-V05-R4-PASSIVE
Runtime: DISABLED
Automatic impact: BLOCKED
Control level: TRANSVERSAL_FAIL_CLOSED

## 1. Responsibility

MATERIAL_FRONT_COVERAGE owns only:

1. explicit coverage of every applicable material-front family;
2. evidence-bound front classification;
3. distinction between defect, gap, evidence requirement and duplicate;
4. reopening when new evidence changes coverage;
5. deterministic closure gating.

It is a **passive coverage gate**. It consumes the evidence already produced by the governing profile and does not launch searches, database queries, file reads, external research, diagnostic modules, or repair probes on its own. If evidence is insufficient, it emits the minimum evidence requirement and returns control to the governing profile.

It does **not** own diagnostic method selection, dynamic investigation modules, repair operators, root-cause search, blast-radius search, second-order search, hostile-challenge strategy, or capability selection when the consuming profile already owns them.

For SRCR V0.7, those responsibilities remain with SRCR V0.7 and its reusable capabilities.

## 2. Why this boundary exists

A blind holdout over SRCR V0.7 showed:

- SRCR V0.7 already found all 5/5 canonical defects;
- adding the universal MFC layer improved facet recall from 18/20 to 20/20 and material-front recall from 9/22 to 14/22;
- adding a second provider-bound method layer added no oracle-verified facets;
- adding gap refiners increased false positives materially.

Therefore V5 R3 keeps the proven coverage/closure responsibility and removes duplicated method architecture from the Card.

Mechanism tests from prior V5 revisions remain development evidence only. They cannot be used to claim novelty over SRCR V0.7.

## 3. Mandatory universal front ledger

Before any closure claim, materialize exactly one row for each applicable universal family:

1. ARCHITECTURE_TOPOLOGY
2. CONTROLS_GUARDS_ENFORCEMENT
3. POLICIES_CONTRACTS_AUTHORITY
4. CONTEXT_INPUT_TRANSPORT
5. WIRING_REACHABILITY_ROUTING
6. IDENTITY_VERSION_CURRENTNESS
7. COMPATIBILITY_TRANSITION_MIGRATION
8. STATE_LIFECYCLE_TERMINALITY
9. RECOVERY_ROLLBACK_IDEMPOTENCY_REPLAY
10. CONSUMERS_DEPENDENCY_BLAST_RADIUS
11. OBSERVABILITY_EVIDENCE_READBACK
12. SECURITY_PRIVACY_PERMISSIONS
13. PERFORMANCE_COST_CAPACITY
14. TESTING_ASSURANCE_FALSIFICATION
15. OPERABILITY_MAINTENANCE_OWNERSHIP

The governing profile may add domain-specific fronts. It may not silently remove a universal family.

Each row must include:

- front_code
- applicability_question
- classification
- evidence_refs
- currentness_ref when drift is possible
- method_receipt_refs when MATERIAL
- decision_axes
- decision_link_refs for every CAN_CHANGE axis
- finding_refs
- reinspection_triggers

## 4. Front classification

Each applicable front ends in exactly one:

- MATERIAL
- N_A_PROVED
- LOW_RISK_CLOSED

UNKNOWN, NOT_CHECKED, missing evidence, or unresolved contradiction are transitional only.

### 4.1 MATERIAL

Use MATERIAL when current evidence shows the front can change at least one decision axis:

- root_cause
- repair_topology
- blast_radius
- acceptance_criteria
- rollback_recovery
- terminality_lifecycle

A front may be classified MATERIAL only when at least one decision axis marked CAN_CHANGE has a direct evidence link proving why that axis can change.

Required for MATERIAL:
- `decision_link_refs[axis]` for every CAN_CHANGE axis;
- at least one linked verified DEFECT/GAP or executed method receipt;
- no reliance on topic similarity, generic risk, restriction, or unexecuted hypothesis alone.

If the front is relevant but the decision link is not yet proven, keep it UNRESOLVED and emit an EVIDENCE_REQUIREMENT.

A MATERIAL front is not complete until the caller/profile supplies evidence that its chosen diagnostic method was actually executed.

This Card validates the method receipt; it does not choose the method.

### 4.2 N_A_PROVED

Requires positive evidence that the front is outside current scope and remains outside scope after the proposed repair.

Silence, absence of observed errors, or an empty query is not sufficient unless authority proves why emptiness is conclusive.

### 4.3 LOW_RISK_CLOSED

Requires all six decision axes to be NO_CHANGE_PROVEN.

Precedence:

- any CAN_CHANGE => MATERIAL
- otherwise any UNRESOLVED => RETURN_TO_EVIDENCE_ACQUISITION while budget remains
- all six NO_CHANGE_PROVEN => LOW_RISK_CLOSED

CAN_CHANGE dominates UNRESOLVED.

## 5. Evidence type classification

Every newly emitted item must be classified as exactly one of:

### DEFECT

A demonstrated incorrect state, behavior, contract, authority, transition, side effect, or receiver effect.

Requires:
- positive evidence of the incorrect condition;
- exact subject/scope binding;
- no unresolved dependence on a future probe;
- at least one verification origin from `OBSERVED_LIVE | CANONICAL_AUTHORITY | EXECUTED_TEST | RECEIVER_READBACK`.

`CASE_ASSERTION`, prompt text, symptom description, or benchmark premise may seed a hypothesis but cannot by themselves establish a DEFECT.

### GAP

A demonstrated missing required control, contract, authority, coverage element, or implementation element.

Requires:
- evidence that the requirement exists;
- evidence that the required element is absent;
- at least one verification origin independent of `CASE_ASSERTION`.

A case/prompt premise alone cannot prove absence.

A GAP may be material, but it is not automatically a distinct physical defect if it describes the same failure already recorded.

### EVIDENCE_REQUIREMENT

A probe/readback/test is still needed before deciding whether a defect or gap exists.

Examples:
- trigger bodies have not yet been inspected;
- classifier behavior has not yet been probed;
- receiver enforcement has not yet been read back;
- the case asserts a defect but no live/canonical/test/readback evidence has independently verified it.

EVIDENCE_REQUIREMENT is never counted as a verified defect.

### DUPLICATE

A newly described item is semantically the same physical failure as an already recorded DEFECT/GAP and does not establish an independent causal boundary or effect.

DUPLICATE carries:
- canonical_finding_id
- additional_evidence_refs
- duplicate_reason

It is never counted as a new defect.

## 6. Canonical finding identity

Before counting a new DEFECT or GAP, compare it against existing findings using:

- same subject/scope;
- same earliest bad boundary;
- same violated invariant or authority;
- same observed incorrect effect;
- same repair implication.

If these are materially the same, collapse to DUPLICATE and attach new evidence to the canonical finding.

Different wording, different front labels, or a second evidence source do not create a new defect.

A finding is distinct only if it proves a different bad boundary, invariant violation, material effect, or repair obligation.

## 7. Method receipt boundary

The consuming profile owns method selection.

For every MATERIAL front, this Card requires at least one method receipt containing:

- method_or_capability
- execution_id
- subject_revision
- scope
- evidence_refs
- observed_result
- limitations
- executed=true

If the receipt is missing:
- emit EVIDENCE_REQUIREMENT;
- keep the front MATERIAL;
- block closure.

If the provider limitation covers the requested claim:
- treat the claim as UNPROVEN;
- do not infer PASS.

Registry status such as CURRENT/ACTIVE is not proof that a method was executed.

## 8. Passive cost discipline

The Card must not increase diagnostic effort merely to populate its ledger.

During a coverage pass it may:
- reuse already collected evidence;
- validate existing method receipts;
- classify fronts and findings;
- identify the smallest missing evidence needed for closure.

It may not:
- execute extra database queries;
- read additional files;
- launch subagents;
- invoke diagnostic capabilities;
- broaden search scope.

Any such work belongs to the governing profile after a RETURN_TO_EVIDENCE_ACQUISITION decision.

Therefore the incremental probe/read cost of the Card itself is expected to be approximately zero.

## 9. Reopening

Reopen affected fronts when:

- authority/currentness changes;
- a new consumer/path/state appears;
- repair changes topology;
- new evidence contradicts prior closure;
- rollback/readback reveals residue;
- a finding changes any six-axis decision assessment.

Every coverage reevaluation increments coverage_iteration.

The Card does not own the caller's search strategy or dynamic module reselection.

## 10. Terminal precedence

Evaluate exactly:

1. STRUCTURAL_INTEGRITY
2. EVIDENCE_SUFFICIENCY
3. KNOWN_COVERAGE_VIOLATION
4. PASS

### STRUCTURAL_INTEGRITY => MATERIAL_FRONT_COVERAGE_BLOCKED

Examples:
- subject revision mismatch;
- incomplete 15-front ledger;
- missing governed coverage budget;
- malformed finding classification;
- duplicate lacking canonical_finding_id;
- MATERIAL front missing method receipt structure.

### EVIDENCE_SUFFICIENCY => RETURN_TO_EVIDENCE_ACQUISITION

Use only when additional current evidence can still determine:
- applicability;
- six-axis classification;
- whether an EVIDENCE_REQUIREMENT is a true defect/gap;
- whether a method receipt proves the material claim.

### KNOWN_COVERAGE_VIOLATION => MATERIAL_FRONT_COVERAGE_BLOCKED

Examples:
- applicable front unclassified;
- unsupported N_A;
- incomplete LOW_RISK six-axis proof;
- demonstrated MATERIAL front not investigated;
- unconsumed reinspection trigger;
- unresolved contradiction;
- duplicate counted as independent defect.

### PASS

Requires:
- all applicable fronts final;
- every MATERIAL front investigated by caller-selected method with valid receipt;
- every N_A positively proven;
- every LOW_RISK front has six NO_CHANGE_PROVEN axes;
- zero unresolved EVIDENCE_REQUIREMENT capable of changing closure;
- zero duplicate inflation;
- zero unconsumed reinspection trigger;
- subject/currentness binding exact.

## 11. Required output

- status
- status_reason_codes
- subject_id
- subject_revision
- authority_asof
- front_catalog_version
- material_front_ledger
- defects
- gaps
- evidence_requirements
- duplicates
- material_fronts
- n_a_proved_fronts
- low_risk_closed_fronts
- unclassified_fronts
- reopened_fronts
- coverage_iteration
- coverage_budget_ref
- reinspection_triggers
- coverage_digest
- coverage_receipt
- closure_allowed
- evidence_refs

Return exactly one:

- MATERIAL_FRONT_COVERAGE_PASS
- MATERIAL_FRONT_COVERAGE_BLOCKED
- RETURN_TO_EVIDENCE_ACQUISITION

## 12. Hard rules

- No "inspect/review/investigate" text satisfies a MATERIAL front.
- No method selection is invented by this Card.
- No EVIDENCE_REQUIREMENT is counted as a defect.
- No CASE_ASSERTION-only item is counted as DEFECT or GAP.
- No front is MATERIAL without direct decision_link_refs for every CAN_CHANGE axis.
- No restriction, topical relevance, or unexecuted hypothesis alone establishes MATERIAL.
- No duplicate semantic finding is counted twice.
- No front closes without evidence_refs.
- No MATERIAL front closes without executed method receipt.
- No provider is trusted outside its declared limitations.
- No score or confidence compensates for missing material evidence.
- No historical calibration result serves as holdout oracle.
- No synthetic arm is used to claim uplift over SRCR V0.7.

## 13. Holdout interpretation

The real blind holdout for V5 R2 is retained as negative/positive design evidence:

- baseline SRCR V0.7: 5/5 canonical defects, 18/20 facets, 9/22 material fronts, 0 false positives;
- universal closure layer A: 5/5 canonical defects, 20/20 facets, 14/22 material fronts, 2 false positives;
- provider-bound method layer B: no additional oracle facets and higher cost;
- refiner layer C: no additional oracle facets and materially more false positives.

The R3 blind test added another correction:

- RC-078 reformulations remain DUPLICATE unless a distinct bad boundary/effect is proven;
- RC-012 unexecuted probes remain EVIDENCE_REQUIREMENT;
- RC-030 case-premise-only loss may not be promoted to DEFECT without independent live/canonical/test/readback evidence;
- broad front relevance may not be promoted to MATERIAL without decision-link evidence.

R4 must be tested under matched diagnostic budgets. The Card itself is passive, so any extra search/read cost is a protocol violation rather than Card value.

## 14. Result ceiling

PASS proves only material-front coverage completeness for the exact bound subject/evidence cut.

It does not prove:
- root cause correctness;
- repair correctness;
- deployment safety;
- production readiness;
- global system correctness;
- TOP_TIER quality.
