# INDEPENDENT_ASSURANCE

Transversal LF inventory identity: `INDEPENDENT_ASSURANCE` / `TRANSVERSAL_INDEPENDENT_ASSURANCE`.

Effective semantic responsibility: **`INDEPENDENT_REVIEW`**.

`INDEPENDENT_ASSURANCE` remains the current inventory code for compatibility/currentness. Do not create a second capability merely to rename it; a durable rename, if later required, belongs to an explicit governed cutover.

## Estado

- Estado operativo esperado: `ACTIVO`
- Inventory status requerido: `ACTIVE_SHARED_ENFORCEMENT`
- Currentness authority: `public.lf_activos`
- Owner transversal: `SUPER_ADMIN`
- Live operation type: `INDEPENDENT_REVIEW`
- Current live specialization: `STRATEGY` → `STRATEGY_INDEPENDENT_REVIEW` / `REVISION_INDEPENDIENTE_ESTRATEGIA_LF`
- Subject-agnostic extension executor: `T-INDEP / PAULO-035`

The Strategy route is a **specialization**, not the generic caller contract. A non-Strategy consumer must never hardcode `STRATEGY_INDEPENDENT_REVIEW` merely because it needs independent review.

## Propósito

Produce an independent, execution-bound review verdict and durable review evidence when a governing contract requires a reviewer distinct from the producer.

Its responsibility ends at the review handoff. It does not own the downstream Qualification state transition/materialization.

## Cuándo consumirlo

Consume only when a qualification, claim or closure explicitly requires independent evaluation rather than self-review by the producer.

Before use, resolve `INDEPENDENT_ASSURANCE` in `public.lf_activos` and confirm that it is not archived, remains `ACTIVO`, has `owner_name=SUPER_ADMIN`, and has `metadata.transversal_inventory.inventory_status=ACTIVE_SHARED_ENFORCEMENT`.

Every consumer must declare one consumption mode in its governed metadata (`capability_consumption_v1`):

- `PREFLIGHT_ONLY`: checks inventory/currentness/contract availability. It never produces a closure-satisfying PASS and must not be used to justify `DONE`.
- `CLOSURE_REQUIRED`: the consumer cannot close until the exact independent-review receipt and its authority/readback evidence are durable and the declared required checkpoints are `DONE` with evidence.

## Cómo consumirlo

1. Declare `capability_code=INDEPENDENT_ASSURANCE` and exactly one mode: `PREFLIGHT_ONLY` or `CLOSURE_REQUIRED`.
2. Resolve the current inventory identity; do not create a parallel reviewer capability.
3. Resolve the subject specialization from the current transversal contract/runtime. Consumers must not hardcode another subject's route or operation.
4. If the exact subject type has no supported specialization, fail closed with `BLOCK_UNSUPPORTED_SUBJECT_REQUIRES_OWNER_EXTENSION`; extension belongs to `INDEPENDENT_ASSURANCE` under `SUPER_ADMIN` and must preserve the existing engine/lineage.
5. For `CLOSURE_REQUIRED`, bind exact subject identity/revision, producer identity, reviewer identity and evidence references; reviewer identity must be independent from the producer according to the current independence criterion.
6. Execute the governed reviewer phases and persist `review_receipt`, `evidence_refs` and terminal authority readback. A structural/local PASS alone is never sufficient.
7. If downstream Qualification materialization is actually required by the consumer contract, hand off separately through `QUALIFICATION_FRAMEWORK` and read back its result independently. Qualification is not implicitly required for every independent review.

## Superficies canónicas

- Generic capability identity: `INDEPENDENT_ASSURANCE`
- Generic consumption declaration: `capability_consumption_v1`
- Current Strategy specialization: `REVISION_INDEPENDIENTE_ESTRATEGIA_LF` / `STRATEGY_INDEPENDENT_REVIEW`
- Reviewer-operation RPCs/step/judge surfaces bound to the current supported specialization

The live Strategy operation is explicitly typed `INDEPENDENT_REVIEW`. Its final governed step emits `review_receipt`, `evidence_refs` and `next_gate`.

`public.lf_finalize_qualification_independent_review_v1` is intentionally excluded from this canonical-surface list because it belongs to the downstream `QUALIFICATION_FRAMEWORK` handoff described below.

## Integración downstream — no ownership

`public.lf_finalize_qualification_independent_review_v1` is a downstream **Qualification Framework dependency**, not a canonical physical asset owned by Independent Review.

Independent Review may provide evidence/receipt consumed by a Qualification finalizer when qualification is part of the consumer's contract. Test/suite materialization, qualification state transition and qualification-current readback remain owned by `QUALIFICATION_FRAMEWORK`.

A consumer that only requires a durable independent-review verdict and authority readback must not be forced into a Strategy qualification path just to obtain a receipt.

## Soporte de sujetos

Current support is explicit and fail-closed:

- `STRATEGY`: supported by the current live Strategy specialization.
- `STORY_IMPLEMENTATION_PACKAGE`: not yet supported by a live subject-agnostic reviewer specialization. `T-INDEP / PAULO-035` is the execution unit already designated to materialize and test that extension.
- Any other subject: supported only if the current transversal contract/runtime declares an exact specialization; otherwise block.

No caller may reinterpret the Strategy specialization as generic support.

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

- `PREFLIGHT_ONLY` is never closure-satisfying.
- `CLOSURE_REQUIRED` without durable receipt + evidence + authority readback must block closure.
- Unsupported subject specialization must block; it must never fall back to Strategy by name or approximation.
- Reviewer execution must be distinct from the producer when independence is required.
- Missing/stale subject revision, reviewer identity, receipt or evidence must block.
- A review PASS is only the review verdict for the bound review case. It is not Qualification PASS, Assurance PASS, changeset safety, deployment approval or production authorization.
- Independent Review must not perform business writes.

## Qualification handoff invariant

```text
producer evidence
      ↓
INDEPENDENT_REVIEW
      ↓
review_receipt + evidence_refs + authority_readback
      ↓
¿consumer contract requires Qualification?
      ├─ NO → closure consumer may evaluate the review receipt
      └─ SÍ → QUALIFICATION_FRAMEWORK
                ↓
              materialization / qualification state / currentness
```

The stages must remain independently traceable. A downstream finalizer call does not make the finalizer an Independent Review asset.

## Validación y readback

- Verify active/current asset identity and `owner_name=SUPER_ADMIN` before consumption.
- Verify the requested consumption mode is explicit.
- Verify the exact subject specialization is supported; do not infer support from capability name.
- For `CLOSURE_REQUIRED`, verify durable review receipt, exact evidence references and terminal authority readback.
- Verify downstream Qualification only when required by the consumer contract.
- Preserve source revision, execution identities, evidence references and exact reviewer receipt.
- Do not turn a local reviewer test into a global closure claim.

## No duplicación

Do not create a second independent-review capability, operation, table, runner, reviewer writer or route. Extend the existing governed capability through `SUPER_ADMIN` and preserve lineage. Execution units such as `T-INDEP / PAULO-035` may materialize and test an approved extension, but do not become the capability owner.

## EKB

- `S36-ASSURANCE-BOUNDARY-CONTAMINATION-001`
- `INDEPENDENT-REVIEW-LEGACY-RPC-BYPASS-001`
- `INDEPENDENT-REVIEW-FINALIZER-RESULT-CONTRACT-MISMATCH-001`
- `STRATEGY-QUALIFICATION-INDEPENDENT-REVIEW-BOOTSTRAP-DEADLOCK-001`
- `GOV-FULL-REGRESSION-TRANSVERSAL-README-CONTRACT-001`
- `INDEPENDENT-ASSURANCE-CONSUMPTION-MODE-AMBIGUITY-001`

## Currentness

This README describes the ownership and consumption boundary, not a permanent lifecycle assertion. Consumers must read the live inventory and supported-subject contract for every material decision. The canonical owner is `SUPER_ADMIN`; executor or consumer identity must never be reinterpreted as capability ownership.
