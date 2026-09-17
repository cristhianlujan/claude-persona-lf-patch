# Main Contract — Systemic Root Cause Repair LF

## Contract
Produce a structured, evidence-grounded systemic repair specification for recurrent or architecturally material failures.

## Required semantic conditions
1. `symptom`, `immediate_cause`, and `systemic_root_cause` are distinct.
2. `causal_chain` links observed failure to the first bad control and escape control.
3. `systemic_root_cause` explains recurrence, not just the latest occurrence.
4. When ambiguity is material, at least three materially distinct alternatives are compared.
5. The selected alternative includes explicit tradeoffs and falsification results.
6. The selected repair is the minimum sufficient origin repair that removes the failure class.
7. `invariant` and `hard_guard` are testable and fail closed.
8. Acceptance includes historical recurrence regressions and current-case proof.
9. Residual risks and unresolved authority are explicit.

## Required output
- `status`
- `profile_pack_id`
- `symptom`
- `immediate_cause`
- `systemic_root_cause`
- `causal_chain`
- `first_bad_control`
- `escape_control`
- `recurrence_evidence`
- `repair_level`
- `alternatives`
- `selected_alternative`
- `rejected_alternatives`
- `falsification_results`
- `origin_asset`
- `origin_operation`
- `owner`
- `invariant`
- `hard_guard`
- `acceptance_criteria`
- `historical_regressions`
- `residual_risks`
- `evidence_map`
- `blocking_codes`
- `next_gate`

## Invalid output
Prose-only diagnosis, first-plausible-fix output, local repair presented as systemic without recurrence explanation, self-certification, unsupported authority, missing falsification, or a hard guard that cannot be tested.
