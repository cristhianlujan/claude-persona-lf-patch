# Frontend Prototype Architect LF Mini Judge

## Purpose
Validate that Frontend Prototype Architect produced either a faithful implementation advisory or a real, independently verified static sandbox artifact. Schema validity alone is never semantic completion.

## Required checks
1. Product Direction authority exists in the governed context and its exact source ref/SHA/currentness/verdict are independently resolved.
2. UI Architect authority exists in the governed context and its exact source ref/SHA/currentness/verdict are independently resolved.
3. Output validates against `schemas/html_sandbox_output.schema.json`.
4. `prototype_decision.execution_mode` is explicit.
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

## Provenance rule
A source ref, boolean or syntactically valid SHA supplied by the candidate does not prove provenance. The deterministic validator must open the referenced current workspace source and recompute the digest. A nonexistent ref, stale verdict/currentness, mismatched digest or ambiguous authority is FAIL.

## Artifact rule
A plan such as `files_to_create=["index.html"]` plus `html_structure`/`css_structure` does not prove implementation. `PASS_ARTIFACT_VERIFIED` requires external readback evidence from the actual files.

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
