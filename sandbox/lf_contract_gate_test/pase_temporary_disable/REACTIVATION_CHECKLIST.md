# PASE reactivation checklist

Do not remove the temporary disable guards until all items have current evidence:

1. Single ordinary PR entrypoint is structurally valid.
2. PASE applicability plan is deterministic and current.
3. Owner -> owner runner -> carrier resolution is canonical and complete.
4. Every required control is qualified against exact head.
5. MIGRATION_SOURCE_PARITY executes only through the approved orchestrator path when applicable.
6. POST-PASE routing, reconciliation, authority readback, final evidence and closure gate pass end-to-end.
7. No ZIP artifact is used as terminal authority.
8. Exact-head negative and failure-path tests pass.
9. GitHub workflow wiring produces no duplicate entrypoints or parallel engines.
10. Reactivation itself is reviewed as a dedicated PR with readback after merge.

## Contract-to-solution and local/integration split (candidate, not yet active)

The scoped candidate contract is `docs/pase/PASE_VALIDATION_SCOPE_REUSE_V1.md` and its dedicated late integration work item is [F09-X17 (#2049)](https://github.com/cristhianlujan/claude-persona-lf-patch/issues/2049). This section does not authorize changing the temporary guards.

Before claiming readiness, provide exact current proof that:

11. Every REQUIRED rule on pending PASE units has an **existing admitted validator/capability**, explicit input, positive + negative qualification and concrete failure route; any missing solution is a tracked BLOCKED work item, not PASS.
12. Each control tests **only its functional scope**. A predecessor is a scheduler prerequisite, not a source of inherited validators or PASS. Transport, coordination, causal bindings and historical as-of consistency are **not local judge responsibilities**.
13. Late cross-layer integration is represented by one governed F09-X17 unit (or an approved exact equivalent) before F09-016, reusing CONSUMER_ADMISSION, CAUSAL_EFFECT_LINEAGE, DECISION_CONTEXT_ASOF, CURRENTNESS_AUTHORITY and existing receipts. No new orchestrator or duplication of domain judges.
14. F09-013 keeps performance/transport measurement, F09-015 keeps observability, F09-016 aggregates local + cross-layer terminal verdicts; F10 keeps final readback. No old PASS is imported.
15. The late unit and contract binding are canonically registered with independent readback before they are treated as active; the presence of this document/issue alone is not evidence of compliance.
