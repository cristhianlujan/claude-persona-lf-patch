# UI Architect V13 — bounded flat serialization

Status: CANDIDATE_READ_ONLY / RUNTIME_RETEST_REQUIRED

## Binding
- Operation: `ACTUALIZACION_PERFIL_LF`
- Execution: `EXEC-ACTUALIZACION-PERFIL-UI-ARCHITECT-20260828-007`
- Asset: `PERFIL-UI-ARCHITECT`
- Base main: `a9633935ec46d816553afc6dcf91cc19cd50c441`
- Branch: `lf/ui-v13-bounded-flat-resolved-spec-20260828`

## Post-V12 runtime evidence
### Canary B — explicit unresolved authority
- request `6df7920a-3a43-4716-9b07-e95948423fd4`
- run `33196818237`
- exact main `a9633935ec46d816553afc6dcf91cc19cd50c441`
- result: PASS — complete unfenced Missing Input State, `RETURN_TO_ORCHESTRATOR`, no guessed survivor.

### Canary A — explicit resolved authority
- request `9adcb086-af9c-47b5-a434-585f461662a9`
- run `33196811439`
- exact main `a9633935ec46d816553afc6dcf91cc19cd50c441`
- transport/runtime provenance: SUCCEEDED / MODEL_RUNTIME / ZERO_COST_ONLY
- behavior: FAIL — Markdown fenced output, recursive `amount_text` nesting, contract-incomplete output within the 2048-token cap.

EKB before V13 write:
- GOV-023 recurrence incremented to 7.
- GOV-032 recurrence incremented to 10.

## V13 root-cause correction
V13 does not add another layer. It reduces prompt complexity in the same profile:
- compacts `SKILL.md` while preserving routing, authority triage, output modes, semantic guardrails and lifecycle boundaries;
- keeps V12 explicit-unresolved-authority hard short-circuit;
- makes component serialization flat: `children` is forbidden and `visual_hierarchy` is a flat rank/component list;
- adds a bounded canonical serialization for the governed `payment_summary` survivor / `top_amount_strip` redundant case;
- keeps one remediation action and target+survivor evidence binding for one duplicate finding;
- retains root-tail and score-closure sentinels;
- keeps output within the 2048-token runtime budget.

No Router, Shell, adapter, runtime infrastructure, policy, Supabase schema, production state, `VALIDATED`, runtime enablement, or automatic promotion change is included.

## CI exact-head binding
The final V13 branch commit intentionally co-locates this governed evidence change with the `LF_OPERATION_CONTRACT_RECEIPT` for execution 007. This prevents the push-scoped contract gate from observing a governed-path-only commit without its receipt. No runtime/profile semantics are changed by this CI binding note.

## Closure boundary
No behavioral closure is claimed here. Required: exact-head CI, merge/readback, then two fresh post-merge zero-cost MODEL_RUNTIME canaries (resolved and explicitly unresolved authority), both semantically and structurally PASS.
