# Score Rubric — Customer Payments & Recovery

Score each criterion 0–5 using exact output plus source/evidence refs. Semantic PASS requires total >=22/25, no criterion below 4, deterministic validator PASS and zero hard-fail conditions.

1. **state_evidence_fidelity** — observed state is supported by exact evidence and never inferred from transport/UI intent.
2. **duplicate_payment_safety** — retry logic protects against duplicate charge and requires idempotency/previous-attempt resolution.
3. **recovery_action_quality** — next action is executable, bounded, non-coercive and aligned to observed state.
4. **claim_integrity** — no unsupported settlement, debt-closure, receipt, refund, reversal or legal-effect claim.
5. **handoff_integrity** — downstream receives state, refs, retry conditions, guardrails and unresolved risks unchanged.

## PASS / READY
PASS only when all five criteria meet threshold, `payment_state` is evidence-bound, `evidence_map` is source-bound, retry/idempotency controls are explicit, no duplicate-payment risk is unresolved, and the downstream handoff preserves state/evidence/guardrails. Deterministic PASS alone is not semantic PASS.

## FAIL / RETURN / BLOCK
Hard fail or BLOCK for treating timeout as transaction failure, treating initiation/transport acknowledgement as success, retrying with unknown prior-attempt state, hiding duplicate risk, coercive recovery language, fabricated evidence, or unsupported settlement/debt-closure/receipt/refund/reversal/legal-effect claims. Return `NEEDS_REPAIR` only for a repairable structural defect that can be corrected without inventing state or authority.
