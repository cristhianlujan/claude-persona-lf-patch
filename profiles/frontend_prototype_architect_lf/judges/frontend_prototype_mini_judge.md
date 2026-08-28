# Frontend Prototype Architect LF Mini Judge

## Purpose
Validate that Frontend Prototype Architect produced either a faithful implementation advisory, a real independently verified static sandbox artifact, or a correctly governed routing/block state. Schema validity alone is never semantic completion.

## Required checks
1. Product Direction authority exists in the governed context and its exact source ref/SHA/currentness/verdict are independently resolved when implementation proceeds.
2. UI Architect authority exists in the governed context and its exact source ref/SHA/currentness/verdict are independently resolved when implementation proceeds.
3. Output validates against the schema for its mode: `html_sandbox_output`, `frontend_missing_input`, or `frontend_scope_block`.
4. `prototype_decision.execution_mode` is explicit for `HTML_SANDBOX_SPEC`.
5. `ADVISORY_SPEC_ONLY` never claims artifact creation and never receives artifact PASS.
6. `CREATE_AND_VERIFY_ARTIFACT` has non-empty `files_to_create` including `index.html`.
7. Every declared artifact exists on disk under an allowed sandbox path and is covered by `artifact_evidence`.
8. Artifact SHA-256 and byte count are recomputed from readback bytes; candidate-declared flags/hashes are not trusted.
9. `index.html` passes deterministic static HTML parse validation after readback.
10. Prototype is static HTML/CSS by default; no backend/API/database/auth/tracking/payment/deployment/runtime/real-data scope is introduced.
11. Accessibility baseline is present.
12. Every applicable interactive/data region covers `idle/default`, `loading`, `empty`, `error`, `success` and `disabled/unavailable` when relevant, or explicitly marks a state not applicable with reason.
13. Observable acceptance criteria are bound to changed components.
14. For incremental requests, current delta is distinguished from preserved context and stale prior behavior is not repeated.
15. Score criteria contain evidence refs; a numeric score is not evidence.
16. Missing Product/UI/Shell authority is resolved from context before redirecting; already-resolved values are not requested again.
17. `FRONTEND_MISSING_INPUT_STATE` uses `RETURN_TO_ORCHESTRATOR` and one typed `resolution_target`; the worker never directly invokes or names a target profile as an execution hop.
18. `SHELL_CHANGE_REQUIRED` routes only to `RETURN_TO_ORCHESTRATOR / LF_SHELL_GOVERNANCE`.
19. Backend/runtime/production ownership is returned to the orchestrator rather than implemented locally.
20. Real/sensitive-data requests that cannot use safe fixtures fail closed with `BLOCK_PIPELINE / NONE`.

## Provenance rule
A source ref, boolean or syntactically valid SHA supplied by the candidate does not prove provenance. The deterministic validator must open the referenced current workspace source and recompute the digest. A nonexistent ref, stale verdict/currentness, mismatched digest or ambiguous authority is FAIL.

## Artifact rule
A plan such as `files_to_create=["index.html"]` plus `html_structure`/`css_structure` does not prove implementation. `PASS_ARTIFACT_VERIFIED` requires external readback evidence from the actual files.

## Routing rule
ACT-0001/Router remains the owner of the next-hop selection. The Frontend worker emits only a typed routing intent. It must not call Product Director, UI Architect, Shell governance, backend/runtime owners or the final user directly to resolve a material decision.

Required routing states:
- unresolved Product -> `FRONTEND_MISSING_INPUT_STATE / RETURN_TO_ORCHESTRATOR / PRODUCT_DIRECTION`;
- unresolved UI -> `FRONTEND_MISSING_INPUT_STATE / RETURN_TO_ORCHESTRATOR / UI_ARCHITECT`;
- protected Shell change -> `BLOCKED_FRONTEND_SCOPE / SHELL_CHANGE_REQUIRED / RETURN_TO_ORCHESTRATOR / LF_SHELL_GOVERNANCE`;
- backend/runtime ownership -> `BLOCKED_FRONTEND_SCOPE / RETURN_TO_ORCHESTRATOR / BACKEND_OR_RUNTIME_OWNER`;
- production/deployment -> `BLOCKED_FRONTEND_SCOPE / RETURN_TO_ORCHESTRATOR / PRODUCTION_GOVERNANCE`;
- unsafe real/sensitive data -> `BLOCKED_FRONTEND_SCOPE / BLOCK_PIPELINE / NONE`.

## Semantic authority
The judge evaluates properties/rubric criteria, not one exact answer. Equivalent advisory or static implementations may pass when they preserve authoritative Product/UI intent and satisfy observable criteria.

## Automatic FAIL conditions
- `PASS_ARTIFACT_VERIFIED` without real artifact readback.
- Empty `files_to_create` or empty HTML/CSS structures.
- Missing/nonexistent/stale upstream ref or SHA mismatch.
- Candidate-provided `exists/readback/currentness/verdict` accepted without independent resolution.
- Missing `index.html` in artifact mode.
- HTML file unreadable or structurally unparsable.
- Artifact evidence does not cover every declared file.
- Backend/API/database/auth/deployment/runtime/production scope introduced.
- Product scope, CTA, claims or hierarchy changed without upstream authority.
- Applicable interaction states absent without justification.
- Generic acceptance criteria or score evidence.
- Current authoritative delta ignored.
- Missing-input state with an untyped/free-form next hop.
- Direct profile-to-profile invocation instead of returning to orchestrator.
- Shell change redirected anywhere other than `LF_SHELL_GOVERNANCE`.
- `BLOCK_PIPELINE` paired with a non-`NONE` resolution target.

## Verdicts
- `PASS_ARTIFACT_VERIFIED`
- `ADVISORY_COMPLETE`
- `RETURN_TO_ORCHESTRATOR`
- `RETURN_TO_WORKER_FOR_SELF_REPAIR`
- `BLOCK_FRONTEND_SCOPE`

## Research basis
- Internal LF: ACT-0001, EKB GOV-025/GOV-026/GOV-032 and governed profile-update flow.
- Independent Carril B audit: contract accepted empty spec, fictitious/stale upstream and nominal score evidence.
- Quality principle: artifact/source facts must be independently resolved from actual workspace bytes; internal consistency of candidate declarations is insufficient.
