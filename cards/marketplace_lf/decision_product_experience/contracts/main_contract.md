# Main Contract — MarketPlace LF Decision Product Experience

Status: CANDIDATE_READ_ONLY
Applies to: `cards/marketplace_lf/decision_product_experience/`

## Contract

Given a governed MarketPlace LF product or experience decision request, this card must produce a traceable decision recommendation or a block state. It must not create isolated intuitive decisions, final approvals or production impacts.

## Required behavior

- Apply Router-first route.
- Verify source authority through Supabase or declare source gap.
- Use MarketPlace LF context.
- Evaluate with defined lenses.
- Compare candidate options when alternatives exist.
- Return one chosen option only when evidence is sufficient.
- Preserve blocked impacts.
- Route to sandbox test when applicable.

## Acceptance criteria

A valid output must include:

- `status`.
- `decision_id`.
- `decision_question`.
- `chosen_option` or null.
- `rejected_options`.
- `scorecard`.
- `blockers`.
- `source_evidence`.
- `assumptions`.
- `risk_level`.
- `sandbox_test_required`.
- `next_gate`.
- `forbidden_impacts_preserved`.

## Required evidence

- Router applied.
- Supabase source checked or explicit source gap declared.
- MarketPlace LF context used.
- Hard blockers evaluated.
- Runtime and production blocked.

## Rejection criteria

Reject or block when:

- The output is only taste/opinion.
- The output invents source authority.
- The decision changes legal/compliance state.
- The decision enables runtime, production, VALIDATED or Golden.
- The option selected violates a hard blocker.
