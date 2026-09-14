# S31 CURRENTNESS_AUTHORITY cutover

This integration layer makes `CURRENTNESS_AUTHORITY` the policy authority for Git Broker currentness without weakening the broker's exact-main atomicity guard.

## Broker semantics

1. Resolve `refs/heads/main` once to an exact `current_revision`.
2. Evaluate the declared broker-control material graph with `lf_broker_currentness_bridge_v1.py`.
3. `BROKER_BASE_CURRENT`: keep the requested base.
4. `BROKER_REBIND_CURRENT`: use `effective_base_revision=current_revision` only when the material-aware authority proves the old base is unaffected.
5. The staging source must still be a descendant of the effective base.
6. The canonical S30 prewrite receipt must already be rehydrated to that effective base; the cutover helper never rewrites or self-certifies the receipt.
7. `STALE_AFFECTED`, bounded-validation requirements, unknown dependency state, source-lineage mismatch, or receipt mismatch all fail closed.
8. The existing exact-main check inside the protected broker remains as an atomic dispatch guard. It is not the currentness policy authority after this cutover.

## Qualification semantics

The live qualification subsystem is already material-scoped and does not depend on the global Git `main` SHA:

- `lf_strategy_revision_sha256_v1` hashes the strategy revision while excluding lifecycle/progress/close bookkeeping fields.
- `lf_operation_revision_sha256_v1` hashes the governed operation registry, active contracts, active steps, judges, and router bindings.
- `lf_required_test_suite_fingerprint_v1` hashes only required applicable bindings and each bound suite revision.
- `lf_qualification_current_v1` requires a matching subject revision, matching required-suite fingerprint, matching classification fingerprint for strategies, and passed current suite revisions.

Therefore S31 does **not** relabel every `EXACT_REVISION` binding or mass-invalidate existing qualification receipts. The qualification cutover is architectural: exact revision means the exact **material subject/suite revision**, not an exact repository `main` SHA.

## S36 assurance handoff boundary

S36 should automate regression/assurance over these stabilized invariants, including unrelated-main rebound, material-change block, dependency-unknown fail-closed, source ancestry, receipt rehydration, durable source-attestation verification, and qualification independence from unrelated repository drift.
