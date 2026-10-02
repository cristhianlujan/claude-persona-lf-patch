# INDEPENDENT_ASSURANCE

Transversal LF inventory identity: `INDEPENDENT_ASSURANCE` / `TRANSVERSAL_INDEPENDENT_ASSURANCE`.

Effective semantic responsibility: **`INDEPENDENT_REVIEW`**.

`INDEPENDENT_ASSURANCE` remains the current inventory code for compatibility/currentness. Do not create a second capability merely to rename it; a durable rename, if later required, belongs to an explicit governed cutover.

## Estado

- Estado operativo esperado: `ACTIVO`
- Inventory status requerido: `ACTIVE_SHARED_ENFORCEMENT`
- Currentness authority: `public.lf_activos`
- Owner transversal: `SUPER_ADMIN`
- Canonical reviewer operation: `REVISION_INDEPENDIENTE_ESTRATEGIA_LF`
- Router action: `STRATEGY_INDEPENDENT_REVIEW`
- Live operation type: `INDEPENDENT_REVIEW`

## Propósito

Produce an independent, execution-bound review verdict and durable review evidence when a governing contract requires a reviewer distinct from the producer.

Its responsibility ends at the review handoff. It does not own the downstream Qualification state transition/materialization.

## Cuándo consumirlo

Consume only when a qualification, claim or closure explicitly requires independent evaluation rather than self-review by the producer.

Before use, resolve `INDEPENDENT_ASSURANCE` in `public.lf_activos` and confirm that it is not archived, remains `ACTIVO`, has `owner_name=SUPER_ADMIN`, and has `metadata.transversal_inventory.inventory_status=ACTIVE_SHARED_ENFORCEMENT`.

## Cómo consumirlo

1. Resolve the current inventory identity `INDEPENDENT_ASSURANCE`; do not create a parallel reviewer capability.
2. Route the review through ACT-0001 to `STRATEGY_INDEPENDENT_REVIEW` / `REVISION_INDEPENDIENTE_ESTRATEGIA_LF`.
3. Bind exact producer/reviewer identity, qualification/subject identity, source revision, suite fingerprint, REVIEW_REQUIRED case and evidence references.
4. Execute the six governed reviewer steps: route binding, target currentness, semantic review, judge record, reviewer readback and report output.
5. The reviewer output is a durable review receipt/evidence package plus `next_gate`; it must not directly declare Qualification current or materialize Qualification state.
6. If downstream Qualification materialization is required, hand off through the separate `QUALIFICATION_FRAMEWORK` contract and read back its result independently.

## Superficies canónicas

- `REVISION_INDEPENDIENTE_ESTRATEGIA_LF`
- Router action `STRATEGY_INDEPENDENT_REVIEW`
- reviewer-operation RPCs/step/judge surfaces bound to that operation

The live operation is explicitly typed `INDEPENDENT_REVIEW`. Its final governed step emits `review_receipt`, `evidence_refs` and `next_gate`.

`public.lf_finalize_qualification_independent_review_v1` is intentionally excluded from this canonical-surface list because it belongs to the downstream `QUALIFICATION_FRAMEWORK` handoff described below.

## Integración downstream — no ownership

`public.lf_finalize_qualification_independent_review_v1` is a downstream **Qualification Framework dependency**, not a canonical physical asset owned by Independent Review.

Independent Review may provide the evidence/receipt consumed by that finalizer. The finalizer's responsibilities — test/suite materialization, qualification state transition and qualification-current readback — remain owned by `QUALIFICATION_FRAMEWORK`.

## No responsabilidades

This capability does not own or imply:

- operation test coverage or coverage completeness;
- global coverage-debt monotonicity;
- test/suite result materialization;
- Qualification state transition or `qualification_current`;
- lifecycle/stateful regression suites;
- Card-specific E2E assurance;
- generic adversarial/security testing;
- Router applicability decisions;
- runtime, scheduler, orchestrator or production activation.

## Fail-closed / límites

- Reviewer execution must be distinct from the producer when independence is required.
- Missing/stale revision, suite fingerprint, qualification binding, reviewer identity, judge receipt or evidence must block.
- A review PASS is only the review verdict for the bound review case. It is not Qualification PASS, Assurance PASS, changeset safety, deployment approval or production authorization.
- Independent Review must not mutate Strategy snapshots or perform business writes.

## Qualification handoff invariant

```text
producer evidence
      ↓
INDEPENDENT_REVIEW
      ↓
review_receipt + evidence_refs + next_gate
      ↓
QUALIFICATION_FRAMEWORK
      ↓
materialization / qualification state / currentness
```

The two stages must remain independently traceable. A downstream finalizer call does not make the finalizer an Independent Review asset.

## Validación y readback

- Verify active/current asset identity and `owner_name=SUPER_ADMIN` before consumption.
- Verify Router action and operation are current and operational.
- Verify all six reviewer steps remain governed and that the report output carries `review_receipt`, `evidence_refs` and `next_gate`.
- Verify the Qualification finalizer remains downstream and separately owned.
- Preserve source revision, execution identities, evidence references and exact reviewer receipt.
- Do not turn a local reviewer test into a global closure claim.

## No duplicación

Do not create a second independent-review capability, operation, table, runner, reviewer writer or route. Extend the existing governed operation through `SUPER_ADMIN` and preserve lineage. Execution units such as `T-INDEP / PAULO-035` may materialize and test an approved extension, but do not become the capability owner.

## EKB

- `S36-ASSURANCE-BOUNDARY-CONTAMINATION-001`
- `INDEPENDENT-REVIEW-LEGACY-RPC-BYPASS-001`
- `INDEPENDENT-REVIEW-FINALIZER-RESULT-CONTRACT-MISMATCH-001`
- `STRATEGY-QUALIFICATION-INDEPENDENT-REVIEW-BOOTSTRAP-DEADLOCK-001`
- `GOV-FULL-REGRESSION-TRANSVERSAL-README-CONTRACT-001`

## Currentness

This README describes the ownership boundary, not a permanent lifecycle assertion. Consumers must read the live inventory and operation contract for every material decision. The canonical owner for this transversal capability is `SUPER_ADMIN`; execution units or consumers must not reinterpret executor identity as capability ownership.
