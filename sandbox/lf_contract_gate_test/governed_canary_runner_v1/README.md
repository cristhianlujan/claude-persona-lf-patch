# LF Governed Canary Runner v1 — Sandbox Candidate

## Objective

Provide one reusable, sandbox-only canary envelope for LF components. The runner is intentionally domain-agnostic: the owning strategy supplies authoritative preflight, forward, behavioral tests, rollback and post-readback commands; the runner enforces ordering, fail-closed execution and evidence capture.

## Canonical flow

`authority/EKB → manifest validation → preflight → forward → tests → rollback(always) → post-readback → evidence packet → stage conclusion`

A forward attempt can never authorize production, merge, or automatic promotion. A test failure does not skip rollback. A rollback failure outranks a test failure. A post-readback failure outranks a successful test because residue/currentness is unresolved.

## Integration model

Each asset class supplies a small manifest adapter, not a new runner:

- Database/schema/migration: exact forward+rollback versions, ledger/source parity preflight, schema/function fingerprints, zero-residue readback.
- Runtime/worker/profile/agent: candidate endpoint or request-local switch, behavioral suite, deployed/source fingerprint readback, restore baseline.
- API/integration: sandbox target, contract assertions, failure/retry/idempotency suite, restore config and verify.
- Automation/queue: isolated queue/worker identity, delivery/retry assertions, cleanup and no-pending-work readback.
- UI/visual: ephemeral build/config, deterministic render/contract checks, teardown and artifact provenance readback.
- Repository-only: temporary branch/worktree or generated artifact, validators/judges, cleanup; no production deployment.

Unknown impact remains fail-closed and must select a broader/deeper test portfolio before this runner is invoked.

## Evidence ceiling

A PASS means only that the supplied sandbox canary passed its declared contract with rollback and post-readback. It does not mean production-ready, Golden, merge-authorized, or semantically correct beyond the supplied independent authority/tests.

## Required audit conclusion

The owning strategy must append a conclusion containing: execution id, exact source/runtime fingerprint, test portfolio, PASS/FAIL, first bad hop, rollback result, post-readback result, open risks, claim ceiling, and invalidation triggers.

## Initial reference implementation

Strategy 28 / Input Governance IG-006/IG-007 is the first reference consumer because it already has exact-version forward/rollback, independent Validator, semantic equivalence, current/stale controls and zero-residue requirements. The runner must not encode Input Governance-specific logic.

## Promotion boundary

This folder is deliberately under `sandbox/lf_contract_gate_test/**`. Promotion into `gobernanza/**` requires a separate canonical operation with write authority, its own execution binding/receipt, exact-head CI and an exercised E2E consumer. No sandbox PASS can self-promote this component.
