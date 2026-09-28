# S36 WP4 — historical adversarial integration regression

## Status / boundary

`S36 WP4` is a historical integration-regression lane, **not an end-to-end owner** of a generic “adversarial/agent-security assurance” capability.

Its reusable checks must resolve to existing domain/transversal owners. The lane must not create a parallel security platform, test matrix, policy engine, reviewer operation or authority engine.

Canonical LF test stores remain `lf_test_suites`, `lf_test_suite_cases`, `lf_test_runs`, `lf_test_assertion_results`, `lf_test_artifacts`, and `lf_test_requirement_bindings`.

## Owner decomposition

| WP4 invariant / attack | Canonical owner or destination | WP4 role |
| --- | --- | --- |
| Producer = reviewer / reviewer identity missing / non-independent review mode | `INDEPENDENT_ASSURANCE` inventory identity → semantic `INDEPENDENT_REVIEW` → `REVISION_INDEPENDIENTE_ESTRATEGIA_LF` | integration regression only |
| Requested authority missing / requested authority not granted | `POLICY_CONSUMPTION` for frozen applicable policy/capability context + `ROUTER_DOWNSTREAM_AUTHORITY` before downstream effect | integration regression only |
| Provenance spoofing / fake refs / hash mismatch | Existing Evidence Lineage / Quality Pack adversarial harnesses | reuse existing owner harness |
| Malformed evidence | Existing Evidence Lineage / Quality Pack adversarial harnesses | reuse existing owner harness |
| Stale/currentness attacks | `CURRENTNESS_AUTHORITY` plus owner-specific currentness tests | reuse existing owner harness |
| Receipt replay | Existing Evidence Lineage adversarial harness + `EVIDENCE_ANTIREPLAY` where applicable | reuse existing owner harness |
| Idempotency/replay abuse | owner-specific idempotency/replay contracts | reuse existing owner harness |
| Route/orchestrator bypass | Router/policy/owner-specific routing controls | reuse existing owner harness |
| Required-step bypass | operation owner step contract | owner-specific; transversal generic remains NOT_COVERED |
| Invalid state transition | lifecycle/policy owner suite | owner-specific; transversal generic remains NOT_COVERED |

## Legacy integration guard

`./s36_wp4_identity_authority_guard.py` remains temporarily as a compatibility integration regression. It contains two different invariant families and therefore must not be promoted as one new capability:

1. reviewer independence;
2. requested-vs-granted authority.

The historical reviewer mode `S36_ASSURANCE` is a compatibility alias only. It must not be used as evidence that S36 is the canonical reviewer owner.

## Deterministic execution evidence

```text
python sandbox/lf_contract_gate_test/s36_wp4_adversarial/test_s36_wp4_identity_authority_guard.py
```

Historical observed producer result:

```text
S36_WP4_IDENTITY_AUTHORITY_EXECUTED=1 TEST_COUNT=6 RESULT=PASS
```

A PASS proves only the guard inputs satisfied those two local invariants. It does not prove a global security verdict, Assurance completeness, Qualification, test coverage, runtime authorization or production authorization.

## Explicit open coverage states

| Coverage item | State | Reason |
| --- | --- | --- |
| REQUIRED_STEP_BYPASS_TRANSVERSAL_DYNAMIC | NOT_COVERED | owner-specific step contracts exist; no safe owner-neutral semantic model is established |
| INVALID_STATE_TRANSITION_TRANSVERSAL_NEGATIVE | NOT_COVERED | lifecycle suites are owner-specific; no safe owner-neutral dynamic target is established |
| LIVE_DESTRUCTIVE_AUTHORITY_ESCALATION | BLOCKED | destructive runtime/production privilege testing is not authorized by this historical lane |

## Migration rule

1. Keep the legacy guard as compatibility regression while consumers still reference it.
2. New reviewer-independence coverage belongs to the existing Independent Review owner.
3. New requested/granted/downstream authority coverage belongs to Policy Consumption / Router Downstream Authority as applicable.
4. Preserve S36 paths/codes as lineage until consumer readback permits retirement.
5. Do not create `ADVERSARIAL_SECURITY`, `AGENT_SECURITY_ASSURANCE` or another umbrella merely to replace the S36 umbrella.

## Result-class discipline

`PASS` proves only the executed invariant. `FAIL` means an observed invariant violation. `BLOCK` means an applicable test cannot safely/validly proceed. `NOT_COVERED` is an explicit missing surface. Owner defects return to the owner; this lane must not repair owner semantics to make its regression pass.

## EKB

- `S36-ASSURANCE-BOUNDARY-CONTAMINATION-001`
- `S36-TRANSVERSAL-NEGATIVE-PATH-COVERAGE-GAP-001`
