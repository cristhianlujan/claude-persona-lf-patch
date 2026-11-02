# LF — Applicability of Router/direct semantic consistency

Status: PROPOSED in PR. Applies to new V3 receipts after promotion, not retroactively to archived evidence.

## Single authorized operational path
`ACT-0001 → EJECUCION_PERFIL_LF → selected profile` is the only operational execution path.
Profiles may use their declared tools. A direct model/profile execution is **not** an alternative production path.
Direct comparison may exist only as a separately authorized, evidence-bound diagnostic; never manufacture a second production route just to satisfy a check.

## Check applicability (the check key is still required)
All V3 checks must be present. For `router_direct_consistency`:

| Scenario | Root field | Check result | Check applicability | Outcome |
| --- | --- | --- | --- | --- |
| Router-only, no authorized comparable direct evidence | `NOT_TESTED` | `not_applicable` | `ROUTER_ONLY` | Not PASS, not FAIL; do not block solely for absent direct run |
| Valid independently authorized Router/direct diagnostic pair, matching | `PASS` | `true` | `AUTHORIZED_COMPARISON` | Requires two distinct execution refs in the check's `source_refs` |
| Material divergence (paired) | `FAIL` | `false` | `AUTHORIZED_COMPARISON` | Block semantic closure |
| Claimed PASS without real pair; contradictory fields | any | invalid | invalid | Fail closed |

Both allowed positive cases require a concrete nonempty `reason` and nonempty `source_refs`. In the paired case require `router_execution_ref` and `direct_execution_ref` both in `source_refs`, distinct and traceable. Runtime shape validation does **not** prove authenticity; the independent reviewer must verify these refs.

The remaining applicable checks must all be true with current source proof. Candidate/scope digests, genuine reviewer independence, model-call evidence, `unsupported_claims=[]`, `blocking_codes=[]`, counterfactuals and prior clean `output_validate` are unchanged requirements. `BLOCKED_SOURCE_INSUFFICIENT` remains valid for missing material sources unrelated to the absence of a direct comparator.

## Do not rewrite history
Existing RAWs, historic check11 receipts, source migrations, EKB and steps 70/80 are not rewritten. The current `EXEC-PROFILE-GATE2-458E10677E34F812D924F11F` is still 9/11 and must receive a **fresh independent** V3 verdict that correctly handles check applicability. A code/schema check does not create independent semantic evidence.

## Affected current code
- Native Python step70 consumer and bridge validator
- Edge continuation V3 receipt check
- Read-only FAIL feedback normalization
- Product Director, UI Architect and Gamification V3 judges and profile operating instructions
- Negative and positive regression tests

## Negative/positive canaries
1. Router-only N/A explicit with refs + 11 other passing checks: structural admission allowed, provided independent evidence is genuine.
2. Router-only root NOT_TESTED but check11 result=true: reject (fabricated PASS).
3. Root PASS without both authentic distinct refs: reject.
4. Genuine paired mismatch: reject.
5. Check9 false, unsupported claims or fake reviewer independence: reject.
6. No new direct production route, no test-only evidence promoted to a production semantic PASS.
