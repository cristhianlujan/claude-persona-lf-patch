# Judge — UI Architect Mini-Judge V4

Status: CANDIDATE_READ_ONLY / SANDBOX

## Purpose
Validate that UI Architect produced an executable UI artifact and that no PASS is produced from structural scoring alone when semantic correctness is material.

## Gate order
1. Validate selected output mode/schema.
2. For `PRODUCTION_UI_SPEC`, run `validators/validate_ui_architect_output.py`.
3. If deterministic validation fails, stop with `PRODUCTION_UI_SPEC_DETERMINISTIC_GATE_FAILED`.
4. For existing-screen remediation or meaning-changing actions, run `judges/ui_architect_semantic_judge.md` against raw input/upstream authority.
5. Only then evaluate rubric/verdict/handoff.

## Required checks
1. Required JSON fields are present for the selected output mode.
2. If output mode is Production UI Spec, `deliverable_created` follows Component Tree format.
3. V4 validator is total on malformed input and returns structured rejection instead of crashing.
4. Existing-screen actions satisfy `contracts/existing_screen_review.md` including component bindings and execution/check objects.
5. Score uses exactly the canonical five criteria.
6. Every criterion has structured evidence references and substantive evidence summary.
7. PASS-like verdict is bound to >=20/25, Layout precision >0, Handoff quality >0.
8. Semantic judge evaluates issue evidence -> selected decision -> issue resolved + adjacent constraints preserved.
9. Meaning-changing COPY/RISK/STATE changes have source authority.
10. LF safety remains fail-closed.
11. Router/direct same-input decisions are materially equivalent unless context differs.
12. Handoff is implementation-ready without invention.

## Production UI Spec automatic fail
Fail if any applies:
- Component Tree missing or malformed.
- deterministic validator rejects.
- score vocabulary is stale or incomplete.
- score evidence is nominal (`ok`, `PASS`, criterion restatement) or points to absent refs.
- PASS-like verdict violates threshold binding.
- existing-screen review omits remediation actions.
- action target is not present in Component Tree/evidence bindings.
- category/operation/check semantics are structurally incompatible.
- human decision/implementation/acceptance text is generic despite valid machine bindings.

Required blocking codes when applicable:
- `PRODUCTION_UI_SPEC_DETERMINISTIC_GATE_FAILED`
- `EXISTING_SCREEN_REMEDIATION_NOT_EXECUTABLE`
- `SCORE_VERDICT_BINDING_FAILED`
- `SCORE_EVIDENCE_NOT_GROUNDED`

## Semantic automatic fail
The deterministic validator is not semantic authority. The semantic judge must fail when any applies:
- visible evidence does not support the diagnosed issue;
- selected decision does not resolve the issue or worsens it;
- adjacent authoritative constraints are dropped;
- new business state/copy is stronger than source authority;
- LF safety is violated;
- Router/direct same-input decisions materially diverge.

Known required semantic negatives:
- remove `payment_summary` while leaving duplicate `top_amount_strip`;
- `Pago registrado` -> `Deuda cancelada` without closure authority;
- move CTA farther away when method↔CTA separation is the issue;
- introduce `Liquidación garantizada al pagar`;
- remove visible `Simulación referencial sujeta a validación` from Ruta when upstream requires it.

Required semantic blocking codes:
- `FAIL_SEMANTIC_DECISION`
- `FAIL_UNSUPPORTED_CLAIM`
- `FAIL_ADJACENT_CONSTRAINT_NOT_PRESERVED`
- `FAIL_LF_SAFETY`
- `FAIL_ROUTER_DIRECT_DIVERGENCE`

## Focused UI Decision Spec
Validate against `schemas/ui_focused_decision.schema.json`.
Automatic fail if output is prose, a concept name, ingredient list, rationale-only, or vague recommendation rather than a selected executable value.

## Missing Input State
Validate against `schemas/ui_missing_input.schema.json`. Do not invent high-risk product decisions or ask the final user from an automated worker run.

## Verdict boundary
This mini-judge may emit a candidate PASS only after deterministic and applicable semantic gates pass. It must not describe its own same-session semantic check as independent audit.

Allowed operational verdict vocabulary for the UI artifact:
- `PASS_TO_QUALITY_PACK_CANDIDATE`
- `NEEDS_INPUT`
- `NEEDS_ADJUSTMENT`
- `BLOCKED`

Independent semantic audit uses the separate semantic-judge verdict vocabulary and remains a later gate.