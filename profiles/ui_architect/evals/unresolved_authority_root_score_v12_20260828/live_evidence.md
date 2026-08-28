# UI Architect V12 — unresolved authority + root score-tail evidence

Status: CANDIDATE_READ_ONLY / RUNTIME_RETEST_REQUIRED

## Governance binding
- Operation: `ACTUALIZACION_PERFIL_LF`
- Execution: `EXEC-ACTUALIZACION-PERFIL-UI-ARCHITECT-20260828-007`
- Asset: `PERFIL-UI-ARCHITECT`
- Base merged main: `e240f1020372a4fcf049a013c4e1178d4e8b41da`
- Branch: `lf/ui-v12-unresolved-authority-root-score-20260828`

## Post-V11 runtime findings
Both fresh post-PR #293 canaries completed successfully at the runtime/transport layer on exact merged `main@e240f1020372a4fcf049a013c4e1178d4e8b41da`, but behavioral closure failed.

### Canary A — resolved authority
- request: `2f0a2d4f-10cb-417e-8719-d3082d224e9f`
- run: `33193420331`
- semantic survivor/removal direction: PASS;
- `payment_summary` preserved and `top_amount_strip` targeted for removal;
- action evidence binding present;
- remaining structural failure: `score` was not completely closed before `handoff_to_next`, leaving root tail malformed/nested.

### Canary B — explicitly unresolved authority
- request: `01ffc626-220b-4f6c-b50b-615f71b0da9b`
- run: `33193426630`
- expected: complete unfenced Missing Input State with `pipeline_action=RETURN_TO_ORCHESTRATOR`;
- actual: model guessed `payment_summary` as canonical, produced a Production UI Spec, and wrapped JSON in Markdown fences;
- result: semantic fail + output-byte-rule fail.

## V12 minimal remediation
V12 remains profile-local and changes only high-salience runtime instructions:
- add an absolute first-pass short-circuit for inputs that explicitly declare survivor authority unresolved;
- forbid resolving that case from familiar component names, profile examples, remembered/default hierarchy, or role labels;
- require the exact complete Missing Input State and immediate stop on the unresolved path;
- make score closure explicit before root `handoff_to_next`;
- require normalized production transition `}},"handoff_to_next"` when `evidence_by_criterion` is the final score member;
- classify `score.handoff_to_next` and `score.self_verdict` as invalid nesting.

No Router, Shell, adapter, runtime infrastructure, policy, Supabase schema, production state, `VALIDATED`, or automatic promotion change is included.

## Closure boundary
This evidence does not claim behavioral closure. P1 closes only after exact-head CI, merge/readback, and two fresh post-merge zero-cost `MODEL_RUNTIME` canaries both pass semantically and structurally.
