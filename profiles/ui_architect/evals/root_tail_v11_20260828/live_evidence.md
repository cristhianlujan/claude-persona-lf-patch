# UI Architect V11 — root-tail closure evidence

Status: CANDIDATE_READ_ONLY / RUNTIME_RETEST_REQUIRED

## Governance binding
- Operation: `ACTUALIZACION_PERFIL_LF`
- Execution: `EXEC-ACTUALIZACION-PERFIL-UI-ARCHITECT-20260828-007`
- Asset: `PERFIL-UI-ARCHITECT`
- Base merged main: `a42682ecfa465fb7969ff26adf73bdc0add3da0c`
- Branch: `lf/ui-v11-root-tail-closure-20260828`

## Post-V10 runtime evidence
Both post-PR #292 canaries were fresh zero-cost `MODEL_RUNTIME` executions on exact merged `main@a42682ecfa465fb7969ff26adf73bdc0add3da0c` using the pinned Qwen2.5-VL 3B runtime.

### Canary B — unresolved authority
- request: `c3848f7d-55ef-41d0-89db-b496317661ce`
- run: `33190953272`
- result: PASS
- returned an unfenced complete Missing Input State;
- did not guess the survivor;
- used `pipeline_action=RETURN_TO_ORCHESTRATOR`.

### Canary A — resolved authority
- request: `14663c45-478e-4e7f-a54e-decb5bb5a74c`
- run: `33190946118`
- semantic direction: PASS;
- `payment_summary` remained visible/canonical;
- only `top_amount_strip` was targeted for removal;
- `evidence_component_ids=[top_amount_strip,payment_summary]` was present and correctly bound;
- Markdown fences/backticks were eliminated;
- remaining structural failure: `score`, `handoff_to_next`, and `self_verdict` were emitted inside `deliverable_created` instead of as root siblings.

## V11 minimal remediation
V11 changes only profile-local serialization salience:
- close `deliverable_created` immediately after its last deliverable field;
- emit root tail in fixed order: `score -> handoff_to_next -> self_verdict`;
- explicitly forbid `deliverable_created.score`, `deliverable_created.handoff_to_next`, and `deliverable_created.self_verdict`;
- require pre-output self-repair when any root-tail field is nested;
- preserve all V10 survivor, evidence-binding, unfenced-output, and missing-input behavior.

No Router, Shell, adapter, runtime infrastructure, policy, Supabase schema, production state, `VALIDATED`, or automatic promotion change is included.

## Closure boundary
This evidence does not claim behavioral closure. P1 closes only after exact-head CI, merge/readback, and two fresh post-merge zero-cost `MODEL_RUNTIME` canaries both pass, including root-tail placement for resolved authority.
