# Governed Rule ↔ Screen Relation Capability V1

## Purpose

Provide an independent governed capability for the shared relation `lf_ops.reglas_pantallas`.

This candidate is intentionally independent from PR #746 and from the rule-exploration bridge. It depends only on canonical objects already present on `main`: `lf_ops.reglas`, `lf_ops.pantallas`, `lf_ops.reglas_pantallas`, and the operation-governance substrate.

## Status

`SANDBOX_ROLLBACK_ONLY_CANDIDATE`

The SQL bundle is self-contained: it materializes the candidate operation and helper inside one transaction, executes positive/negative canaries, and rolls everything back. It does **not** create a Supabase migration and does **not** mutate live runtime state.

## Contract

- Exact rule identity by `lf_ops.reglas.codigo`.
- Accepted observed rule states: `CANDIDATO` and `VIGENTE` (both exist in current canonical relations).
- Exact screen identity by `lf_ops.pantallas.id`.
- Screen `activa=true/false` is observed, not used as a new eligibility rule; current canonical relations include both.
- Only idempotent INSERT into `lf_ops.reglas_pantallas`.
- Unique `(regla_id,pantalla_id)` is the canonical duplicate guard.
- No DELETE capability.
- No mutation of rule or screen rows.
- No rule promotion, runtime activation, production activation, or Golden claim.
- No ACT-0001 router binding in this PR.

## Evidence in the rollback bundle

The canary exercises:

1. `CANDIDATO` rule → screen link.
2. `VIGENTE` rule → screen link.
3. Replay/idempotency; relation cardinality remains exactly 1.
4. Missing rule blocks fail-closed.
5. Missing screen blocks fail-closed.
6. Helper source contains no relation DELETE path.
7. Rule and screen snapshots remain byte/JSON-equivalent before/after the link.
8. Final `ROLLBACK` leaves zero candidate operation/function residue.

## PR isolation and update survivability

`EXCLUSIVE_PR` and `UPDATE_SURVIVABILITY` are mandatory gates for this capability.

- The PR delta must remain exclusively under `sandbox/lf_contract_gate_test/rule_screen_relation_v1/`.
- This PR must not repair or modify shared workflows, shared validators, `supabase/migrations/`, router bindings, PR #746 assets, or another producer's files.
- If a shared/transversal repair is required, it belongs in a separate PR with its own lifecycle and evidence.
- Any base SHA, candidate HEAD, reconciliation, or branch-topology change invalidates prior exact-head CI evidence and requires full revalidation.
- A reconciled PR candidate must not remain with a multi-parent candidate HEAD when exact-head lineage gates require a single-parent candidate commit. Re-sealing must occur through a meaningful candidate-local commit; shared lineage validators must not be weakened to make this PR green.
- Re-sealing a candidate HEAD must never be used to hide the full PR delta: changed-file readback must still prove that every PR change remains inside this capability directory.
- After every update, execute the exact Git rollback bundle again and require: create/link success, replay/idempotency, exact readback, negative fail-closed behavior, immutable rule/screen snapshots, final `ROLLBACK`, and zero residue.
- After every update, rerun exact-head CI. Downstream inventory gates are only considered recovered when the same exact HEAD has green upstream workflows; a stale green run is not evidence.
- No merge decision can reuse evidence from an earlier HEAD or base.

## Promotion boundary

A durable migration, router/action binding, or automatic consumer integration requires a separate PR and its own exact-head CI/readback. This PR must never be used as evidence that PR #746 depends on or activates this capability.
