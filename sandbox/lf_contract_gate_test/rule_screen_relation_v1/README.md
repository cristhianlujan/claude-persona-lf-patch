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

## Promotion boundary

A durable migration, router/action binding, or automatic consumer integration requires a separate PR and its own exact-head CI/readback. This PR must never be used as evidence that PR #746 depends on or activates this capability.
