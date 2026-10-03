# M11_RECONSTRUCTED_SRCR_V0_1

## Status

EXPERIMENTAL_FROZEN_CANDIDATE. Benchmark only. No runtime activation, profile binding, production mutation or control activation.

## Objective

Find the deepest evidence-backed systemic root cause of a problem while avoiding symptom-only repair, parallel authorities, invented wiring/currentness, unnecessary new components, premature closure, and fabricated novelty.

## Core method

M11 combines only mechanisms that showed useful behavior in prior controlled experiments:

1. **Graph exploration** — generate independent hypotheses for immediate cause, systemic cause, authority, state, identity/currentness, wiring, transition, rollback and SHOULD_EXIST.
2. **Independent surface analysis** — inspect source/config, authority/policy, runtime/consumer, persisted state, observability/readback, recovery and historical/EKB evidence independently before synthesis.
3. **Causal graph synthesis** — connect apparently separate symptoms when they share identity, authority, transition, currentness, consumer, state, enforcement point or recovery boundary.
4. **First bad boundary search** — trace `intent -> decision -> transport -> execution -> effect -> readback` and locate the earliest boundary where declared governance stops governing physical execution.
5. **Verifier-guided falsification** — try to destroy each material hypothesis before accepting it.
6. **Alternative search** — compare local repair, upstream preventive repair, and reuse/elimination/simplification.
7. **Hostile challenger** — assume the conclusion is wrong and search for the strongest contradicting evidence before closure.

## Evidence classes

Every material statement must be tagged internally as one of:

- `FACT`: directly observed current evidence.
- `HISTORICAL`: valid historical evidence that may be stale.
- `DECLARED`: contract/documentation/intended behavior.
- `UNKNOWN`: not yet demonstrated.

Never promote `DECLARED` or `HISTORICAL` to `FACT` without current readback.

## Phase 0 — Freeze inputs

Use the case input exactly as provided. Do not rewrite, normalize, enrich, omit or reorder case facts in a way that changes semantics. Do not inspect the oracle/expected findings before the candidate output is complete and frozen.

## Phase 1 — Build the physical system map

For every material flow, map:

`PRODUCER -> CONTRACT/DATA -> TRANSPORT -> AUTHORITY -> CONSUMER -> EFFECT -> READBACK`

For every edge answer:

- Does it exist?
- Is it physically wired?
- What authority enforces it?
- What fails if the edge is absent/stale?
- How is the exact consumer/version/release proven?

Component existence alone is not wiring.

## Phase 2 — Divergent hypothesis generation

Generate multiple independent hypotheses. Each must include:

- hypothesis_id
- symptom explained
- causal assumption
- suspected first bad boundary
- supporting evidence
- evidence that could falsify it

Do not choose a root cause yet.

## Phase 3 — Cross-surface causal graph

Connect hypotheses that share:

- identity/release
- authority
- transition
- consumer
- currentness
- state
- enforcement point
- rollback/recovery boundary

Prefer a single demonstrated systemic discontinuity over several unrelated local explanations when the evidence supports it.

## Phase 4 — First bad boundary

Trace each candidate chain:

`intent -> decision -> transport -> execution -> effect -> verification`

Classify:

- `FIRST_BAD_BOUNDARY`
- `ESCAPE_CONTROL`
- `DOWNSTREAM_SYMPTOM`

Prefer repair at the first preventable boundary, not only at a downstream detector.

## Phase 5 — Falsification

Attack every material root-cause candidate with:

- **contrafactual**: if repaired, can the same failure class still happen?
- **bypass**: can another path evade the proposed control?
- **replay/duplicate**: can stale or duplicate state reproduce the failure?
- **concurrency**: do parallel executions invalidate the repair?
- **partial failure**: what happens between decision and effect?
- **staleness/currentness**: does old evidence still authorize new effects?
- **elimination**: should the problematic component exist at all?
- **existing capability**: does an existing transversal capability already own the responsibility?

Failed hypotheses are discarded or downgraded.

## Phase 6 — SHOULD_EXIST assessment

Before repairing a component, classify it as one of:

- `KEEP_AS_IS`
- `REPAIR`
- `REUSE_EXISTING`
- `MERGE_WITH_EXISTING`
- `ELIMINATE`
- `NEEDS_EVIDENCE`

Never preserve a component merely because it already exists.

## Phase 7 — Alternatives

For every material repair compare at least three genuinely different classes:

- **A local/minimal** — fixes the immediate point.
- **B systemic/preventive** — fixes the earliest boundary that can prevent recurrence.
- **C simplification/reuse/elimination** — removes architecture or reuses an existing capability.

Compare prevention, bypass resistance, complexity, blast radius, idempotency, recoverability, new dependencies, operating cost and required evidence.

## Phase 8 — Hostile challenger

Run this challenge before closure:

> Assume the selected conclusion is wrong. Find the strongest available evidence that disproves it.

Search specifically for:

- contradictory authority
- hidden consumer
- uninspected wiring
- stale state
- missing transition
- second execution path
- existing capability that makes the proposal unnecessary
- claims that exceed the evidence

If a material contradiction survives, return to the relevant phase.

## WOW rule

A `WOW_DISCOVERY` exists only when evidence proves at least one of:

- cross-phase discontinuity
- declared authority contradicts physical effect
- consumer executes a different identity/version than declared
- control is placed after the effect it should have prevented
- multiple symptoms collapse to one systemic cause
- existing capability allows elimination of proposed architecture
- the existence of a component is itself causal
- rollback cannot identify/restore the exact prior binding/state

If none exists, return `NO_NEW_MATERIAL_GAP`. Never fabricate novelty.

## Terminal states

Only these terminal states are allowed:

- `SYSTEMIC_REPAIR_SPEC`: cause, authority, wiring, transition, repair, rollback and acceptance are sufficiently evidence-bound.
- `NEEDS_MORE_EVIDENCE`: missing evidence could materially change authority, enforcement, wiring, transition, rollback or acceptance.
- `NO_REPAIR_REQUIRED`: current evidence shows the alleged gap does not exist or is already resolved.

## Required normalized output

Preserve the full original candidate output. The comparison layer may additionally extract:

- case_id
- status
- symptom
- facts[]
- declared_behavior[]
- unknowns[]
- hypotheses[]
- causal_graph[]
- first_bad_boundary
- escape_control
- systemic_root_cause
- authority
- physical_wiring
- should_exist_assessment
- alternatives[A,B,C]
- selected_alternative
- falsification_results[]
- wow_discovery
- new_vs_v06[]
- false_positive_risks[]
- missing_evidence[]
- regression_against_v06[]
- implementation_delta[]
- rollback[]
- acceptance_tests[]
- evidence_map[]

## Benchmark invariants

1. Do not invent authority.
2. Do not invent wiring.
3. Do not invent currentness.
4. Do not convert documentation into observed behavior.
5. Do not repair downstream when recurrence can be prevented upstream.
6. Do not create a second authority when a valid existing authority already owns the responsibility.
7. Do not preserve components automatically.
8. Do not label a reformulation as WOW.
9. Do not force `SYSTEMIC_REPAIR_SPEC` when material evidence is missing.
10. Do not use the oracle before candidate freeze.
11. Do not modify this M11 version during RC-001..RC-080.
12. Any method change creates a new model version and a separate benchmark candidate.
