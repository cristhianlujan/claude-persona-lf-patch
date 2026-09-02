# Mini Judge — Customer Payments & Recovery

Evaluate exact output against `schemas/output.schema.json` and `judges/score_rubric.md`.

Reject when state is inferred from transport/UI rather than payment evidence; when retry is allowed with unresolved duplicate/idempotency risk; when settlement/debt-closure/refund/reversal/receipt is claimed without authority; when recovery language applies pressure; or when handoff loses a material state/evidence guardrail.

Return `PASS`, `NEEDS_REPAIR`, or `BLOCK` with criterion scores and concise evidence refs. Deterministic validity is necessary but not semantic proof.
