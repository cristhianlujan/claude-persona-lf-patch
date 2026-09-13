# S30 → S31 Dependency Decoupling Handoff v0.1

Status: INPUT / PRIORITY CANDIDATE
Source owner: S30
Target owner: S31
Priority recommendation: HIGH / CROSS-CUTTING
Promotion authority: NONE
Runtime / scheduler / production authority: NONE

## 1. Why this handoff exists

After S30 completed its non-production governance freeze at `main@c6c2650bd34664b855d9cfe34ed864a5f93a1290`, later S26/shared work advanced `main` without changing S30-owned business logic. A naive currentness interpretation treated repository HEAD drift as if it could invalidate S30. That is the coupling defect to remove.

The observed incident proves that LF needs currentness and compatibility at the **consumed contract/capability boundary**, not at the whole-monorepo SHA boundary.

This handoff MUST NOT mutate or invalidate any frozen S31 independent-review bundle already issued. Consume it as a priority input for the next mutable S31 work package/frontier.

## 2. Observed delta

Reference comparison:

- S30 freeze base: `c6c2650bd34664b855d9cfe34ed864a5f93a1290`
- observed current main: `77222b36028407659c3ff6f18e398ec77ec8fe46`
- commits ahead: 25
- no S30-owned path changed in that comparison

Material shared/S26 changes included:

- `.github/workflows/lf-github-reconcile-v3.yml`
- `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_lane_router.py`
- `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_github_reconcile_pooler_fallback.py`
- `services/profile_runtime_api/**`
- several governed Supabase migrations, including S26 CI repins, rule-router work and mode normalization

The shared GitHub reconciliation transport gained a governed Edge-402 → PostgreSQL Pooler fallback, and the CI lane router gained explicit reconciliation-workflow ownership. Those are operational/shared implementation changes, not S30 strategy-business changes.

## 3. Evidence that S30 itself did not change

The three S30 self-governance currentness surfaces are byte-identical between the S30 freeze base and observed current main:

| Surface | Git blob SHA at freeze | Git blob SHA at observed main |
|---|---|---|
| `gobernanza/contratos/s30_self_governance_gate_v1.json` | `b0b43c48a20dc22eeb4d030e7f7022dcf215f36b` | `b0b43c48a20dc22eeb4d030e7f7022dcf215f36b` |
| `gobernanza/judges/validate_s30_self_governance_gate.py` | `484a79fedcf5379992fcadc59d085c80fc73e004` | `484a79fedcf5379992fcadc59d085c80fc73e004` |
| `.github/workflows/validate-lf-packs.yml` | `3d23c86eb8ec847ddee65185fbf72b4702ed474f` | `3d23c86eb8ec847ddee65185fbf72b4702ed474f` |

The canonical S30 gate already states:

`EVALUATE_RECEIPT_ONLY_WHEN_S30_GATE_PATHS_CHANGED_AND_BIND_TO_EVENT_BASE`

and the workflow already has an explicit unrelated-change path that emits:

`S30_CI_AUTO_SKIPPED_UNRELATED_SHARED_WORKFLOW_CHANGE`

Therefore the defect is not that S30 lacks all isolation. The defect is that this pattern is not yet generalized as a canonical LF dependency/currentness capability and can still be misapplied outside the narrow S30 gate.

## 4. Architectural finding S31 should prioritize

LF needs an explicit four-layer boundary:

1. **Exclusive business/domain logic** — owned by the strategy/domain; never invalidated by unrelated operational implementation changes.
2. **Reusable shared capabilities** — Executor, idempotency, leases/fencing, monotonic checkpoints, effect guard, evidence, typed readers, currentness resolver, etc.
3. **Shared governance/control plane** — Router, EKB, authority, lifecycle, policy contracts, audit, capability registry.
4. **Replaceable operational infrastructure** — GitHub CI, Supabase transport, Edge Function, Pooler, scheduler, n8n, provider/runtime framework.

Dependency direction must be downward through stable contracts/ports. A strategy must never depend directly on another strategy implementation.

## 5. Concrete S31 capability implications

This incident should be consumed by at least these existing S31 capabilities/lanes:

- `CURRENTNESS_AUTHORITY` / S31-D: currentness must bind to consumed contracts and independently resolved compatibility evidence, not global HEAD equality alone.
- `CAPABILITY_REGISTRY` / S31-E: each consumer declares capability identity, version/range, compatibility contract and implementation binding separately.
- `WORK_PACKAGE` / S31-B: dependency declarations must identify whether a dependency is BUSINESS, CAPABILITY, GOVERNANCE or INFRASTRUCTURE and state its invalidation policy.
- `EVIDENCE_LEDGER` + lifecycle / S31-F: a change may invalidate only the evidence claims that actually depend on the changed contract.
- `RUNTIME_EXECUTION_PORT` / S31-G: provider/transport replacement behind a compatible port must not invalidate business-domain certification.
- S31-A canonical capability model: add explicit distinction between `contract_identity` and `implementation_binding` if not already materialized.

## 6. Required target behavior

S31 should produce a canonical impact/currentness resolution equivalent to:

```text
change observed
    |
    +-- consumer-owned business contract changed --------> consumer revalidation
    |
    +-- consumed capability contract changed
    |       +-- compatible ------------------------------> no full revalidation / bounded check only
    |       +-- breaking --------------------------------> explicit consumer gate
    |
    +-- implementation behind unchanged contract --------> NO consumer invalidation
    |
    +-- unrelated strategy/domain ------------------------> NO consumer invalidation
    |
    +-- dependency unknown/ambiguous ---------------------> fail closed to targeted impact review
```

Global `main` SHA drift by itself MUST NOT be sufficient to reopen a completed strategy.

## 7. Minimum acceptance criteria for S31 closure of this finding

1. A consumer declares exact capability/contract dependencies separately from implementation bindings.
2. Compatibility is version/digest/contract resolved; it is not inferred from repository HEAD equality.
3. Unrelated implementation changes demonstrably return `NO_IMPACT` for the consumer.
4. Backward-compatible contract changes do not force whole-strategy revalidation.
5. Breaking contract changes identify the exact affected consumers and gates.
6. Unknown material dependencies fail closed to a **targeted** impact review, not automatic global invalidation.
7. Evidence invalidation is dependency-scoped and claim-scoped.
8. S26, S30 and future strategies can consume a shared capability without depending on each other's internal paths.
9. Infrastructure/provider transport can be replaced behind a compatible adapter without changing domain truth.
10. Positive and negative regression cases cover implementation-only change, compatible contract change, breaking change, unknown dependency, and unrelated-strategy change.

## 8. Reusable extraction candidates observed from S30

The following S30-developed mechanisms should remain owner-preserved while S31 extracts stable shared contracts/ports:

- C05 idempotency
- lease/fencing
- monotonic checkpoints
- effect reservation / effect guard
- evidence/readback discipline
- pre-execution assurance
- currentness impact gating

Do not copy implementations just to centralize them. First extract stable contracts/ports; migrate ownership only through explicit owner handoff later.

## 9. Interim operating constraint while S31 is unfinished

Until S31 closes this finding, S30 will continue under a bounded compatibility bridge:

- S30 remains frozen/closed unless an S30-owned or explicitly consumed contract changes.
- unrelated S26/shared implementation changes do not reopen S30;
- unknown changes receive targeted impact classification;
- no runtime, scheduler, production or business-effect authority is implied;
- S31 must not mutate S30 internals while generalizing the solution.

## 10. Priority rationale

This is not cosmetic refactoring. Without this boundary, every shared operational improvement risks causing certification churn across strategies. The issue directly affects LF's ability to scale parallel strategies safely. It therefore qualifies under the S31 Work Package bootstrap evolution rule as an observed execution defect, repeated ambiguity/rework risk, missing currentness control, and reusable requirement across multiple domains.
