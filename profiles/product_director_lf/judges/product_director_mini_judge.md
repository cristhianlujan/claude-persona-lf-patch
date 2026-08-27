# Product Director LF Mini Judge

## Order of evaluation
1. Run `validators/validate_product_director_output.py` and require deterministic PASS without malformed-input crash.
2. Run the semantic review in `product_director_semantic_judge.md`.
3. Apply the 25-point rubric only after both gates above are satisfied.

## Required checks
- selected decision is concrete and source-bound;
- alternatives/trade-offs are explicit when material;
- preserved constraints and semantic qualifiers survive the handoff;
- acceptance is observable;
- contradictory/insufficient sources block or are explicitly resolved by authority/currentness;
- material claims have upstream authority;
- next worker can proceed without inventing product truth;
- score has concrete evidence per criterion and matches the total.

## Automatic FAIL
Narrative-only output, unresolved source conflict, unsupported claim, generic acceptance, lost qualifier, scope expansion, hidden pressure/overpromise, specialist-work takeover, nominal evidence, or a counterfactual trajectory that reaches the same apparent result by violating source authority.

## Verdicts
- `PASS_TO_QUALITY_PACK`
- `RETURN_TO_WORKER_FOR_SELF_REPAIR`
- `RETURN_TO_ORCHESTRATOR`
- `BLOCK_PIPELINE`

A validator PASS or score >=22 is necessary but never sufficient for semantic PASS.
