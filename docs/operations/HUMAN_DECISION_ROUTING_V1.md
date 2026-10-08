# HUMAN_DECISION_ROUTING_V1

## Purpose

Create one transversal human-decision routing capability shared by Input Governance, Story Creator, Programming and future agents.

This is not a Programming-specific patch and does not make Story Creator the authority for other stages.

## Architectural position

```text
IG ------------------\
Story Creator --------+--> HUMAN_DECISION_ROUTING --> authorized reviewer
Programming ----------+              |                    |
other producers ------/              |                    v
                                     +------------- decision receipt
                                                       |
                 +---------------------+-----------------+------------------+
                 v                     v                                    v
                IG                  Story                              Programming
             continues            continues                             continues
```

The producer owns detection and evidence. HUMAN_DECISION_ROUTING owns durable request lifecycle, queue consolidation and decision receipt routing. The original consumer owns what the decision means for its stage.

## Reuse and rehome

Existing assets are not deleted:

- Input Governance keeps `programacion.input_gap_proposals` as its native diagnostic/proposal source.
- Story Creator P0 keeps historical `private.lf_p0_human_review_*` evidence and decisions while its generic routing semantics are rehomed.
- Programming keeps `programacion.human_decisions` for its current execution-bound approval use cases until a governed adapter is cut over.

None of those stage-bound stores becomes generic upstream authority.

## Canonical generic contract

A decision request must bind at minimum:

- producer_code
- subject_type
- subject_key
- subject_ref
- required_authority_ref
- required_reviewer_role
- allowed_actions
- evidence_refs
- currentness_sha256
- impact
- request_sha256
- lifecycle status

A decision receipt must bind at minimum:

- request_id
- decision_code
- decision_payload
- reviewer_identity
- reviewer_role
- authority_ref
- authority_receipt_ref
- authority_receipt_sha256
- observed_currentness_sha256
- receipt_sha256

A human decision never turns a deterministic validator FAIL into PASS.

The producer/consumer must map the receipt to an explicit continuation action such as:

- REVALIDATE
- REPAIR_REQUIRED
- REJECT
- NOT_APPLICABLE_WITH_AUTHORITY

## Lifecycle

```text
OPEN
  | decision receipt
  v
DECIDED

OPEN --superseded currentness--> SUPERSEDED
OPEN --explicit cancellation----> CANCELLED
OPEN --expiry--------------------> EXPIRED (derived, not destructive)
```

Only one OPEN request is allowed per producer + subject_type + subject_key.

A new request for the same subject with changed currentness supersedes the old request and preserves history.

## Authority boundary

HUMAN_DECISION_ROUTING does not invent reviewer authority.

The request must point at a governed authority reference. The decision ingress must be authenticated by the authority-specific adapter and provide an authority receipt.

Important domain separation:

- software-governance decisions must never use the LF product profile `B2B_ADMIN_LF`;
- LF product permissions must never authorize CI/CD, Programming or PASE governance decisions;
- the existing `LF_GOVERNANCE_SUPER_ADMIN_V1` contract is currently candidate/read-only and must not be treated as write authority until its own governance state permits it.

## Consumer adapters

### Input Governance

Source:
`programacion.input_gap_proposals`

Eligible source state:
`status=HUMAN_DECISION_REQUIRED AND validator_outcome=PASS`

The adapter creates a generic request without changing the proposal into canonical product authority. IG remains blocked until a compatible decision receipt is consumed.

### Story Creator

Source:
`private.lf_p0_human_review_challenges_v1`

Historical P0 evidence remains intact. A Story adapter projects an active specialized challenge into the generic routing contract. The generic queue does not re-render P0 evidence.

### Programming

Source:
`PROGRAMMING_SIMPLE_EXECUTOR_V1` when a current validation receipt is FAIL and the admitted rule mode is `HUMAN_DECISION`.

The request subject must bind:

- run_id
- plan_code
- unit_code
- checkpoint_code
- validation_code
- failure receipt SHA-256

Programming may continue only from the decision receipt for that exact failure/currentness binding.

## Non-goals

This capability does not:

- decide business semantics;
- authenticate every human identity by itself;
- replace producer-specific evidence;
- convert a human exception into validator PASS;
- activate production;
- delete Story Creator historical review data;
- create a parallel visual-review renderer;
- infer reviewer authority.

## Cutover gates

Before any consumer is switched to this capability:

1. generic request/receipt storage exists;
2. duplicate-active-request negative test passes;
3. currentness/supersession negative test passes;
4. wrong reviewer role negative test passes;
5. wrong authority reference negative test passes;
6. stale currentness decision negative test passes;
7. decision action outside allowed_actions negative test passes;
8. producer adapter positive + negative tests pass;
9. consumer receipt interpretation test passes;
10. legacy stage-bound store is preserved until its replacement consumer is proven.

## Initial implementation status

The first migration creates the generic durable contract and queue only.

It deliberately does not cut over IG, Story Creator or Programming and does not expose a general unauthenticated decision-write API.

Consumer adapters are the next controlled batch.


## Producer adapters V1

The first producer adapters project source-owned state into the transversal ledger without changing producer authority.

### Input Governance

`fn_lf_human_decision_open_ig_v1` accepts only a proposal whose native source state is:

- `proposal_kind=HUMAN_DECISION_REQUIRED`
- `status=HUMAN_DECISION_REQUIRED`
- `validator_outcome=PASS`

The adapter computes currentness from the validated proposal payload, source/evidence references and curator/validator digests. It does not update `programacion.input_gap_proposals`.

### Story Creator P0

`fn_lf_human_decision_open_story_p0_v1` accepts only an ACTIVE, unexpired challenge from the existing P0 queue. It reuses the challenge's `required_reviewer_role` and `reviewer_actions`, preserving P0 evidence and convergence metadata.

It does not replace or mutate the P0 challenge/decision stores.

### Programming

`fn_lf_human_decision_open_programming_v1` accepts only an active RUNNING unit whose current required checkpoint has an exact current FAIL receipt and an admitted validation rule in `HUMAN_DECISION` mode.

The generic currentness binding is the exact Programming failure receipt SHA-256.

### Consumption

Read-only consumer adapters expose the current generic routing record back to IG, Story P0 and Programming. They do not mutate producer state.

## Current cutover blocker

Producer cutover remains disabled because a generic receipt's `authority_receipt_ref` and `authority_receipt_sha256` must be verified by an authority-specific ingress.

A service-role insert or syntactically valid receipt reference is not human authorization.

The next architecture layer is therefore:

```text
human identity
      ↓
authority-specific authentication
      ↓
verified authority receipt
      ↓
generic HUMAN_DECISION_ROUTING receipt
      ↓
producer-specific consume adapter
```

Until that verifier/ingress is materialized and proven for a given authority, adapters may open and inspect routing requests but producers must not automatically advance from a human decision.
