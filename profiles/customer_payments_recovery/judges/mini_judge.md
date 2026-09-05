# Mini Judge — Customer Payments & Recovery

Evaluate the exact output against `schemas/output.schema.json`, `contracts/main_contract.md`, source authority/evidence and `judges/score_rubric.md`.

1. Verify schema validity, one allowed output mode, closed `status`/`self_verdict`, source-bound `evidence_map`, and no unsupported extra structure.
2. Verify `payment_state` is supported by authoritative state evidence; block any state inferred only from transport acknowledgement, timeout, UI navigation, customer intent or missing webhook.
3. Verify retry safety: unknown or unresolved previous-attempt state cannot authorize another charge; retry requires an explicit retryable condition plus idempotency/duplicate-payment controls.
4. Verify claim integrity and recovery treatment: block unsupported settlement/debt-closure/receipt/refund/reversal/legal-effect claims and block threat, shame, false urgency or coercive recovery language.
5. Verify handoff and ownership boundaries: preserve payment/reference/evidence/guardrails/unresolved risks unchanged; no provider mutation, payment execution, collections strategy, Router bypass, runtime/production authority or fabricated receipt.

Return `PASS`, `NEEDS_REPAIR`, or `BLOCK` with criterion scores and concise evidence/source refs. Return `NEEDS_REPAIR` only when structure can be corrected without inventing state or authority. Deterministic validity is necessary but not semantic proof.
