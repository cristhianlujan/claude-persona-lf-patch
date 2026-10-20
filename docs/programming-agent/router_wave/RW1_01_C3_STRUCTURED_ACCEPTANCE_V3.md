# RW1-01_C3 — Structured Acceptance V3

## Scope

- Plan: `LF_ROUTER_ARCHITECTURE_WAVE_V1`
- Unit: `RW1-01`
- Checkpoint: `RW1-01_C3`
- Work item: `1127`
- Asset: `ACT-0001`
- Boundary: acceptance/test contract only. No Router ABI/runtime change, no production mutation, no PE10.

## Reconciliation trigger

A newer round-3 report (2026-10-20) challenged the earlier V2 PASS: V2.1 accepted 12/12 good responses but rejected only 1/12 bad responses on a fresh holdout. The report identified structural gaps K02, K03, K06 and K08 plus security-relevant decisions still encoded in free text.

Live readback performed before this repair showed `RW1-01_C3 = DONE` with assertion receipt SHA-256 `b396d871a13c5a72caf02f9b2e2084c6e483fe75013ffa079dec93e72880c6d5`, based on the earlier V2 verdict. This branch does **not** rewrite that lifecycle state. It repairs the challenged local acceptance contract first and requires governed reconciliation before any lifecycle mutation.

## V3 contract

V3 reuses the frozen V2 corpus and V2 checker as the baseline, then requires deterministic structure for the material continuation decision.

For every resolved goal, `per_goal` is exact and contains:

- exact `goal`;
- selected `mode`;
- exact `permitted_modes` derived from the oracle;
- exact `parts=[goal]`;
- exact `forbidden_subjects`;
- a structured `continuation` bound to the same goal with `effect_authorized=false`.

For `CAPABILITY_GAP`, `discovery_receipt_binding` must bind the receipt to:

- the same `source_search_receipt_ref`;
- the exact request SHA-256;
- the exact case id;
- the same missing capability;
- `valid=true`.

Critical decision fields such as `safe_continuation` are rejected. Human-readable question text may remain display text, but route materiality is governed by the structured discriminator already present in V2.

## Targeted defects

| Finding | Deterministic V3 control |
|---|---|
| K02 action does not correspond to goal | continuation.target_goal must equal per_goal.goal |
| K03 per-goal mode outside permitted modes | mode must be in and equal the oracle-derived permitted mode |
| K06 extra part in per_goal | parts must be exactly [goal], and goal rows must match exactly |
| K08 discovery receipt from another scope | receipt binding must match request SHA-256 + case id |
| Free-text semantic bypass | critical free-text continuation/action fields are rejected |

K05 and K07 are not promoted into blockers because the newer judge described them as ambiguous.

## Acceptance

This V3 package can only establish a local checker-contract result. It cannot by itself certify Router runtime or close/re-close C3.

Required next evidence after CI:

1. freeze exact V3 source blobs;
2. fresh materially separate GPT Native judge;
3. commitment before holdout reveal;
4. RAW1 frozen before prior critique;
5. 12/12 good accepted;
6. >=24/24 bad rejected;
7. >=2 novel falsifiers;
8. governed lifecycle reconciliation only if the newer evidence supports PASS.

No lifecycle mutation is authorized by this document alone.
