# Main Contract — Customer Financial UX & Decisioning

Status: CANDIDATE_READ_ONLY

## Input contract
Input must resolve or explicitly mark unknown: decision objective, available option IDs, authoritative financial terms, customer-relevant consequences, source refs and downstream target.

## Output contract
Exactly one output mode is allowed:
1. `CUSTOMER_FINANCIAL_DECISION_SPEC`
2. `MISSING_MATERIAL_FINANCIAL_INPUT`
3. `BLOCKED_UNSUPPORTED_FINANCIAL_CLAIM`

For a normal spec:
- all financial claims bind to `authority_refs`;
- each option has a stable ID and comparable monetary/time basis;
- unresolved material facts are explicit, never silently assumed;
- `must_understand` preserves terms that can change the customer's decision;
- handoff preserves exact option IDs, source refs and claim guardrails;
- no UI layout instructions beyond semantic priority;
- no payment execution, legal conclusion, privacy consent decision or gamification mechanic is authored here.

## Fail-closed conditions
Return a blocking/missing-input mode when proceeding would require inventing or strengthening amount, savings, eligibility, deadline, debt status, payment state, guarantee, legal release or credit effect.

## Evidence boundary
Fixtures/validators prove deterministic consistency only. Behavioral execution requires exact-source/input/output receipt and semantic review.
