# UI Architect V14 — resolved authority dispatch sentinel

Status: CANDIDATE_READ_ONLY / POST_MERGE_RUNTIME_RETEST_REQUIRED

## Binding
- Operation: `ACTUALIZACION_PERFIL_LF`
- Execution: `EXEC-ACTUALIZACION-PERFIL-UI-ARCHITECT-20260828-007`
- Base main: `601e535074d63d46e4732636f95fd5208598410e`
- Branch: `lf/ui-v14-resolved-dispatch-sentinel-20260828`

## V13 post-merge evidence
- Canary A request `66a5bca6-a5d0-4e96-91e8-ad29b7fbafcc`, run `33199675142`, exact main `601e535074d63d46e4732636f95fd5208598410e`: authentic `MODEL_RUNTIME / ZERO_COST_ONLY`, queue `SUCCEEDED`, behavior FAIL. Input explicitly resolved `Resumen/payment_summary` as canonical and top strip as redundant, but RAW emitted a contradictory Missing-Input-like object with `self_verdict=PASS` and `pipeline_action=RETURN_TO_ORCHESTRATOR`.
- Canary B request `a88630b4-0d56-4c30-b361-1ed7ff4f44b5`, run `33199680352`, exact same main: PASS. It emitted the exact unfenced unresolved-authority short-circuit and did not guess a survivor.
- EKB before V14 write: GOV-023 frequency 8; GOV-032 frequency 11.

## Minimal correction
V14 changes only runtime-critical dispatch salience in `profiles/ui_architect/SKILL.md`:
- explicit named `canonical + redundant` pair selects RESOLVED before any Missing Input rule;
- for that resolved pair `RETURN_TO_ORCHESTRATOR`, `NEEDS_INPUT`, and `blocked=true` are forbidden;
- resolved checkout must begin with `worker=ui_architect` and `output_type=PRODUCTION_UI_SPEC`;
- unresolved branch remains conditional on absence of a named canonical+redundant pair and keeps the exact V13 short-circuit.

No Router, Shell, adapter, schema, validator, runtime infrastructure, Supabase schema, production state, `VALIDATED`, runtime enablement, or automatic promotion change is included.

## Closure boundary
No behavioral closure is claimed. Required: exact-head CI, merge/readback, then fresh post-merge resolved and unresolved zero-cost MODEL_RUNTIME canaries both structurally and semantically PASS.
