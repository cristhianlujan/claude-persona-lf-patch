# Main Contract — Systemic Root Cause Repair LF

## Contract
Produce a structured, evidence-grounded systemic repair specification for recurrent or architecturally material failures.

## Required semantic conditions
1. `symptom`, `immediate_cause`, and `systemic_root_cause` are distinct.
2. `causal_chain` links observed failure to the first bad control and escape control.
3. `systemic_root_cause` explains recurrence, not just the latest occurrence.
4. Exact current authority is resolved from live execution evidence, not only declared source/code.
5. Every material declared-vs-live contradiction is represented in `authority_contradictions` as a blocking finding until reconciled.
6. `should_exist_assessment` identifies real consumers, impact of removal, and a native/already-existing alternative before preserving or adding a component.
7. When ambiguity is material, at least three materially distinct alternatives are compared.
8. The selected alternative includes explicit tradeoffs and falsification results, including undeclared/unversioned caller when authority is material.
9. The selected repair is the minimum sufficient origin repair that removes the failure class.
10. `invariant` and `hard_guard` are testable and fail closed.
11. Acceptance includes historical recurrence regressions and current-case proof.
12. Residual risks and unresolved authority are explicit and do not absorb known contradictions.
13. Final acceptance requires the canonical evidence-bound semantic quality gate on the exact candidate revision. External audit is optional and cannot block merely because it has not run.

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
- `authority_contradictions`
- `repair_level`
- `should_exist_assessment`
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
Prose-only diagnosis, first-plausible-fix output, local repair presented as systemic without recurrence explanation, self-certification used to bypass the canonical semantic gate, unsupported authority, hidden or residualized declared-vs-live contradiction, missing `¿DEBE EXISTIR?` analysis, missing falsification, or a hard guard that cannot be tested.
