# Score Rubric — Customer Payments & Recovery

Score 0–5. Semantic PASS requires total >=22/25, no criterion <4, deterministic PASS and zero hard-fail conditions.

1. **state_evidence_fidelity** — observed state is supported by exact evidence and never inferred from transport/UI intent.
2. **duplicate_payment_safety** — retry logic protects against duplicate charge and requires idempotency/previous-attempt resolution.
3. **recovery_action_quality** — next action is executable, bounded, non-coercive and aligned to observed state.
4. **claim_integrity** — no unsupported settlement, debt-closure, receipt, refund, reversal or legal-effect claim.
5. **handoff_integrity** — downstream receives state, refs, retry conditions, guardrails and unresolved risks unchanged.

Hard fail: treating timeout as transaction failure, treating initiation as success, retrying with unknown prior-attempt state, or claiming debt closure/payment finality without authority.
