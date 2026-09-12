# UI Architect V12 — explicit authority + score closure evidence

Status: CANDIDATE_READ_ONLY / RUNTIME_RETEST_REQUIRED

## Governance binding
- Operation: `ACTUALIZACION_PERFIL_LF`
- Execution: `EXEC-ACTUALIZACION-PERFIL-UI-ARCHITECT-20260828-007`
- Asset: `PERFIL-UI-ARCHITECT`
- Post-V11 merged main: `e240f1020372a4fcf049a013c4e1178d4e8b41da`
- Branch: `lf/ui-v12-authority-score-closure-20260828`

## Post-PR #293 runtime evidence
Both requests were fresh zero-cost `MODEL_RUNTIME` executions on exact merged `main@e240f1020372a4fcf049a013c4e1178d4e8b41da` using the pinned Qwen2.5-VL 3B runtime.

### Canary A — authority resolved
- request: `2f0a2d4f-10cb-417e-8719-d3082d224e9f`
- run: `33193420331`
- technical status: `SUCCEEDED`
- semantic direction: PASS; `payment_summary` preserved and only `top_amount_strip` targeted for removal;
- evidence binding: PASS; `evidence_component_ids` contains target + survivor;
- Markdown fences: PASS; zero fences;
- structural result: FAIL; after `score.evidence_by_criterion.handoff_quality`, the output closes `evidence_by_criterion` but does not close `score` before emitting `handoff_to_next`, so the root envelope is malformed / root-tail placement is not valid.

### Canary B — authority explicitly unresolved
- request: `01ffc626-220b-4f6c-b50b-615f71b0da9b`
- run: `33193426630`
- technical status: `SUCCEEDED`
- semantic result: FAIL; input explicitly states no governed context identifies the authoritative survivor and says not to guess, but runtime invents `payment_summary` as canonical and removes `top_amount_strip`;
- fail-closed result: FAIL; expected complete Missing Input State with `pipeline_action=RETURN_TO_ORCHESTRATOR`;
- serialization result: FAIL; response is wrapped in Markdown `json` fences despite the zero-fence contract.

## V12 minimal remediation
V12 is profile-local and changes only runtime salience/serialization:
1. explicit unresolved-authority language is evaluated before any hierarchy inference, example, remediation or scoring rule and immediately short-circuits to Missing Input State;
2. explicit unresolved authority outranks labels, names, assumed hierarchy and familiar checkout patterns;
3. the full positive Production UI Spec example is removed from the runtime-critical gate to reduce copy-through / malformed-envelope priming;
4. `SCORE CLOSURE SENTINEL` requires closing the final criterion, `evidence_by_criterion`, and `score` before root `handoff_to_next`;
5. final self-repair rejects handoff/verdict nested under `score`, root-tail nesting, malformed JSON and fences.

No Router, Shell, adapter, runtime infrastructure, policy, Supabase schema, production state, `VALIDATED`, or automatic promotion change is included.

## Closure boundary
This evidence does not claim behavioral closure. P1 closes only after exact-head deterministic/CI checks, merge/readback, and two fresh post-merge zero-cost `MODEL_RUNTIME` canaries both pass:
- Canary A: semantic survivor + target/evidence binding + valid JSON root structure + zero fences;
- Canary B: complete unfenced Missing Input State + `RETURN_TO_ORCHESTRATOR` + no guessed survivor.
