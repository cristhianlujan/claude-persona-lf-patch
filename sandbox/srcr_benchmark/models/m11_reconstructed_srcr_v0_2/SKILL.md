# M11_RECONSTRUCTED_SRCR_V0_2

## Status

EXPERIMENTAL_CANDIDATE. Benchmark only. No runtime activation, profile binding, production mutation or control activation.

This version is a new benchmark candidate. It does not replace or mutate `M11_RECONSTRUCTED_SRCR_V0_1`.

## Objective

Find the deepest evidence-backed systemic root cause and produce the smallest durable repair that prevents recurrence, while minimizing false positives, unnecessary rereads, duplicated authority and repair surface.

V0.2 preserves the useful core of v0.1 and adds explicit mechanisms for adaptive reasoning, reachability proof, observable verification, transport/receiver parity, second-order failure search, repair atomization and context-efficiency.

## Non-negotiable benchmark rules

- Use only the visible case input, this frozen method spec and tools/sources allowed by the case.
- Never inspect oracle/expected findings before the candidate RAW is frozen.
- Never consume another benchmark variant's conclusions, findings, scores or summaries.
- Never promote DECLARED/HISTORICAL evidence to FACT without current readback.
- Never infer wiring from component existence.
- Never call a code smell a root cause until reachability/materiality is demonstrated or explicitly marked UNKNOWN.
- Never treat a semantic rule as enforced end-to-end merely because it exists upstream; if a downstream consumer depends on it, its value/identity/currentness must be transportable or resolvable and receiver-verifiable.
- Never create a parallel authority when an existing governed capability can own the responsibility.
- Never trade coverage for speed. Context efficiency means fewer redundant reads, not less evidence.

## Evidence classes

Every material statement must be internally classified as:

- `FACT` — directly observed current evidence.
- `HISTORICAL` — valid older evidence whose currentness is not proven.
- `DECLARED` — contract/documentation/intended behavior.
- `INFERRED` — evidence-backed inference not yet directly observed.
- `UNKNOWN` — evidence missing or contradictory.

## Phase 0 — Freeze input and evidence cut

Record the case input exactly as provided and, when applicable:

- input SHA / case identity;
- exact Git head or equivalent source revision;
- authoritative DB/readback cut;
- method revision;
- permitted tool surface.

Do not silently change the evidence cut between hypotheses.

## Phase 1 — Adaptive module selection

Select only the reasoning modules justified by the case, while always keeping the mandatory core.

### Mandatory core

1. authority/currentness;
2. physical wiring/consumer reachability;
3. causal boundary;
4. falsification;
5. repair/reuse/rollback.

### Optional modules

Activate when evidence warrants them:

- identity/version drift;
- lifecycle/terminality;
- concurrency/idempotency;
- permissions/security boundary;
- consumer compatibility/drain;
- derived-contract parity;
- semantic-to-transport parity / receiver executability;
- provenance/source-manifest;
- performance/context efficiency;
- migration/cutover;
- UI/visual evidence;
- data cardinality/empty-vs-missing;
- retry/replay/resume.

Output `module_selection[]` with the reason each optional module was activated or skipped.

## Phase 2 — Source-pack first, currentness first

Before re-reading large source surfaces, look for an existing current source pack, receipt, inventory, manifest or prior-art bundle that already contains the needed evidence.

Reuse is allowed only if currentness is demonstrable for the present case/evidence cut.

For each reused artifact record:

- locator;
- revision/digest when available;
- why it is current enough;
- which facts it satisfies;
- what still requires a fresh read.

If currentness is uncertain, re-read the minimum authoritative source needed.

Track:

- `reused_sources[]`;
- `fresh_reads[]`;
- `avoided_rereads[]`.

Efficiency is never a reason to omit a material source.

## Phase 3 — Build the physical system map

For each material flow map:

`INTENT -> AUTHORITY -> DECISION -> TRANSPORT -> CONSUMER -> EXECUTION -> EFFECT -> READBACK`

For every edge answer:

- does it physically exist?
- what proves reachability?
- which exact consumer/version/release uses it?
- which authority governs it?
- what happens if it is stale, absent or contradictory?
- which material invariants must survive the transport boundary?
- how does the receiving side prove it received/resolved the exact governed value, identity, scope and currentness it depends on?

Component existence alone is not wiring.

## Phase 3B — Transport / receiver parity gate

When a material decision crosses a component, process, agent, API, queue, file, pack, handoff or persistence boundary, compare four surfaces explicitly:

1. **semantic authority** — what the governing skill/contract/policy/judge requires;
2. **transport contract** — what the schema/payload/ref/receipt is required to carry or resolve;
3. **receiver enforcement** — what the downstream consumer actually validates before acting;
4. **observed lifecycle** — whether a real or controlled handoff reaches the expected receiver and next state/readback.

For every downstream-required invariant classify it as one of:

- `TRANSPORTED_AND_VERIFIED`;
- `RESOLVED_FROM_GOVERNED_AUTHORITY_AND_VERIFIED`;
- `DECLARED_UPSTREAM_ONLY`;
- `OPTIONAL_OR_UNENFORCED_IN_TRANSPORT`;
- `RECEIVER_NOT_PROVEN`;
- `UNKNOWN`.

Typical invariants include, when material to the case:

- authority/source reference;
- identity/version;
- currentness/exact revision;
- lineage/provenance;
- scope/applicability;
- lifecycle/terminal state;
- evidence ceiling / confidence ceiling;
- consumer/receiver binding;
- idempotency/dedupe identity.

Do not require every invariant to be copied literally into the payload. A resolvable governed reference plus receiver-side currentness verification can be superior to duplication. The requirement is **provable continuity**, not payload inflation.

A producer-side validator does not prove downstream enforcement. A schema field does not prove receiver use. A receiver implementation does not prove the actual handoff occurred. Preserve these distinctions.

If the transport contract is versioned, verify compatibility/migration behavior; do not silently break existing consumers to strengthen enforcement.

Record:

- `transport_parity[]`;
- `receiver_binding`;
- `receiver_execution_evidence`;
- `next_state_readback`;
- `contract_compatibility_risks[]`.

## Phase 4 — Reachability gate

Any causal claim based on code/config must pass one of these:

- direct caller/callee proof;
- runtime/readback proof;
- binding/dispatch proof;
- persisted execution proof;
- controlled probe demonstrating the path.

If none exists, classify the item as `DORMANT_OR_UNPROVEN` and do not elevate it to systemic root cause.

Record `reachability_proofs[]`.

## Phase 5 — Divergent hypotheses

Generate multiple materially different hypotheses before selecting a cause.

Each hypothesis must state:

- symptom explained;
- suspected first bad boundary;
- authority involved;
- supporting facts;
- reachability evidence;
- evidence that would falsify it;
- expected downstream manifestations if true.

Do not choose a root cause yet.

## Phase 6 — Observable verifier / probe-before-promote

When a material hypothesis can be tested safely with read-only, sandbox or rollback evidence, test it before promoting it.

Preferred probe classes:

- compare authority resolver vs runtime output;
- mutate candidate input in rollback-only scope;
- exact-head parity/readback;
- stale/current source replay;
- missing vs empty vs wrong-cardinality cases;
- negative consumer/path invocation;
- duplicate/retry/replay;
- permission/bypass attempt;
- validator false-PASS/false-ready test;
- remove/alter a downstream-required transport field/ref and verify fail-closed behavior;
- execute or simulate the handoff to the actual receiver and verify the next state/readback.

If a safe probe is possible but not executed, explain why.

Record `observable_probes[]` with expected vs observed result.

## Phase 7 — Cross-surface causal graph

Connect hypotheses sharing:

- authority;
- identity/release;
- consumer;
- transition;
- currentness;
- provenance;
- lifecycle state;
- enforcement point;
- transport boundary;
- receiver binding;
- rollback/recovery boundary.

Prefer one demonstrated discontinuity over many unrelated local explanations only when the evidence truly collapses them.

## Phase 8 — First bad boundary

Trace:

`intent -> decision -> transport -> execution -> effect -> verification`

Classify relevant points as:

- `FIRST_BAD_BOUNDARY`;
- `ESCAPE_CONTROL`;
- `DOWNSTREAM_SYMPTOM`;
- `LATE_DETECTOR`.

Repair should target the earliest preventable boundary that can stop recurrence without creating unnecessary blast radius.

## Phase 9 — Falsification

Attack each surviving root-cause candidate with:

- counterfactual;
- bypass;
- replay/duplicate;
- concurrency;
- partial failure;
- stale evidence;
- hidden consumer;
- second execution path;
- transport omission/downgrade;
- receiver mismatch;
- elimination;
- existing reusable capability.

Downgrade or discard failed hypotheses.

## Phase 10 — Second-order search

After a provisional repair exists, assume the immediate bug is fixed and ask what would still remain wrong.

Mandatory second-order checks:

- currentness/provenance: will old evidence still authorize the new state?
- other consumers: can another caller bypass the repair?
- replay/resume: can stale or duplicated state recreate the failure?
- version/binding: can an older identity still execute?
- lifecycle: can closure/status become inconsistent again?
- derived contracts: is the repaired value still copied elsewhere?
- transport parity: can an upstream rule change without changing what the receiver is forced to consume/verify?
- contract versioning: can older payloads silently bypass the strengthened invariant?
- observability: will readback prove the exact repaired decision and the receiver/next state?

Record `second_order_risks[]`.

A repair is incomplete when it fixes the immediate path but leaves the same failure class reachable through one of these checks.

## Phase 11 — SHOULD_EXIST / reuse assessment

Before adding or preserving any component classify it as:

- `KEEP_AS_IS`;
- `REPAIR`;
- `REUSE_EXISTING`;
- `MERGE_WITH_EXISTING`;
- `ELIMINATE`;
- `NEEDS_EVIDENCE`.

Explicitly search for an existing transversal owner/capability before proposing a new one.

## Phase 12 — Alternative search

Compare at least three genuinely different repair classes when material:

- `A_LOCAL_MINIMAL` — immediate fix;
- `B_SYSTEMIC_PREVENTIVE` — earliest durable boundary;
- `C_REUSE_SIMPLIFY_ELIMINATE` — reduce architecture or duplicate authority.

Compare:

- recurrence prevention;
- bypass resistance;
- blast radius;
- idempotency;
- rollback;
- consumer compatibility;
- transport/receiver parity;
- currentness/provenance;
- operating/context cost;
- evidence needed for closure.

## Phase 13 — Repair atomization

Convert the selected repair into independent micro-units.

Each `repair_unit` must include:

- objective;
- exact impacted boundary/component;
- dependencies/preconditions;
- change class (`CODE`, `CONTRACT`, `BINDING`, `DATA`, `VALIDATOR`, `DOC`, `TEST`, `NO_CHANGE`);
- acceptance test;
- negative test;
- rollback;
- readback proving completion;
- consumers affected;
- whether activation/cutover is explicitly out of scope.

For transport/receiver changes, acceptance must distinguish at minimum:

- producer validates;
- transport contains/resolves the governed invariant;
- receiver rejects missing/stale/incompatible input;
- real/controlled handoff reaches the intended receiver;
- next-state readback proves the expected effect;
- previous supported contract version either remains compatible or fails via an explicit governed migration rule.

Avoid giant all-or-nothing repairs when the same result can be achieved with reversible units.

## Phase 14 — Context-efficiency review

Before closure, audit whether the reasoning unnecessarily reread or duplicated information.

Ask:

- could a current governed source pack have replaced repeated reads?
- did multiple artifacts duplicate the same derived fact?
- can the repair remove future recomputation or rereads by persisting a governed receipt/digest/projection?
- does any optimization create a second authority? If yes, reject it.

Record `context_efficiency` with:

- reusable artifact/source;
- rereads avoided;
- evidence still read fresh;
- proposed durable reduction in future context/recomputation;
- safety/currentness condition.

## Phase 15 — Hostile challenger

Assume the selected conclusion is wrong and search for the strongest available contradictory evidence:

- contradictory authority;
- uninspected caller;
- stale source;
- second execution path;
- hidden transition;
- hidden or alternate receiver;
- semantic invariant that disappears at transport;
- capability that makes the repair unnecessary;
- claim that exceeds observed evidence.

If a material contradiction survives, return to the relevant phase.

## WOW rule v0.2

A `WOW_DISCOVERY` must add a materially new, evidence-backed improvement over the obvious/local repair. A reformulation is not WOW.

Qualifying examples:

- multiple symptoms collapse to one proven first bad boundary;
- an existing capability eliminates a proposed component or duplicate authority;
- a governed receipt/projection removes repeated recomputation/rereads while preserving currentness;
- a semantic invariant is proven to disappear across a transport/receiver boundary, and the repair makes it versioned/resolvable and receiver-verifiable without creating a second authority;
- a control is shown to exist after the effect it should prevent;
- declared authority is proven to contradict physical execution;
- exact consumer/version differs from declared identity;
- a repair that looked complete is falsified by a second-order path;
- rollback cannot identify/restore exact prior binding/state.

If none is proven, return `NO_NEW_MATERIAL_GAP` or no WOW. Never fabricate novelty.

## Terminal states

Only:

- `SYSTEMIC_REPAIR_SPEC` — cause, authority, reachability, transport/receiver parity, repair, second-order risks, rollback and acceptance are sufficiently evidence-bound.
- `NEEDS_MORE_EVIDENCE` — missing evidence could materially change cause, reachability, transport/receiver continuity, repair, rollback or closure.
- `NO_REPAIR_REQUIRED` — current evidence shows no material repair is needed.

## Required normalized output

Preserve the full RAW candidate output. A comparison layer may additionally extract:

- case_id
- status
- module_selection[]
- facts[]
- declared_behavior[]
- inferred[]
- unknowns[]
- reused_sources[]
- fresh_reads[]
- avoided_rereads[]
- physical_system_map[]
- transport_parity[]
- receiver_binding
- receiver_execution_evidence
- next_state_readback
- contract_compatibility_risks[]
- reachability_proofs[]
- hypotheses[]
- observable_probes[]
- causal_graph[]
- first_bad_boundary
- escape_control
- systemic_root_cause
- authority
- should_exist_assessment
- alternatives[A,B,C]
- selected_alternative
- falsification_results[]
- second_order_risks[]
- repair_units[]
- implementation_delta[]
- rollback[]
- acceptance_tests[]
- evidence_map[]
- context_efficiency
- wow_discovery
- false_positive_risks[]
- missing_evidence[]

## Benchmark invariants

1. Do not invent authority, wiring, currentness, identity, owner or state.
2. Do not convert documentation into observed behavior.
3. Prove reachability before elevating code/config to root cause.
4. A downstream-required semantic invariant is not considered enforced end-to-end until its continuity through transport/resolution and receiver verification is demonstrated.
5. Probe observable material hypotheses when safe and feasible.
6. Repair the earliest preventable boundary, not only the detector.
7. Search second-order currentness/provenance/consumer/replay/transport consequences before closure.
8. Reuse existing governed capabilities before creating architecture.
9. Reduce rereads/recomputation only when currentness remains demonstrable.
10. Atomize repair with acceptance, negative test, rollback and readback.
11. Do not label a reformulation as WOW.
12. Do not use the oracle before candidate freeze.
13. Do not mutate this version once admitted to the benchmark; any change creates a new candidate version.
