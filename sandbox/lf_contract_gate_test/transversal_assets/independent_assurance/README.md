# INDEPENDENT_ASSURANCE

Transversal LF inventory identity: `INDEPENDENT_ASSURANCE` / `TRANSVERSAL_INDEPENDENT_ASSURANCE`.

Effective semantic responsibility: **`INDEPENDENT_REVIEW`**.

`INDEPENDENT_ASSURANCE` remains the current inventory code for compatibility/currentness. Do not create a second capability merely to rename it; a durable rename, if later required, belongs to an explicit governed cutover.

## Estado

- Estado operativo esperado: `ACTIVO`
- Inventory status requerido: `ACTIVE_SHARED_ENFORCEMENT`
- Currentness authority: `public.lf_activos`
- Owner transversal vigente: `SUPER_ADMIN`
- Canonical reviewer operation: `REVISION_INDEPENDIENTE_ESTRATEGIA_LF`
- Live operation type: `INDEPENDENT_REVIEW`
- Current live specialization: `STRATEGY` through `STRATEGY_INDEPENDENT_REVIEW`
- Generic subject contract: `independent_review_subject_contract_v2.json`
- Extension executor: `T-INDEP / PAULO-035`

The Strategy route is a compatibility specialization, not the generic caller contract. A non-Strategy consumer must never hardcode `STRATEGY_INDEPENDENT_REVIEW` or reinterpret its subject as `STRATEGY` merely to obtain a review receipt.

## Propósito

Produce an independent, execution-bound review verdict and durable review evidence when a governing contract requires a reviewer distinct from the producer.

Its responsibility ends at the review handoff. It does not own downstream Qualification state transition/materialization.

## Cuándo consumirlo

Consume only when a qualification, claim or closure explicitly requires independent evaluation rather than self-review by the producer.

Before use, resolve `INDEPENDENT_ASSURANCE` in `public.lf_activos` and confirm that it is not archived, remains `ACTIVO`, has `owner_name=SUPER_ADMIN`, and has `metadata.transversal_inventory.inventory_status=ACTIVE_SHARED_ENFORCEMENT`.

Every new consumer must resolve the exact subject type through the current transversal subject contract. Unsupported subject types fail closed.

## Cómo consumirlo

1. Resolve the current inventory identity `INDEPENDENT_ASSURANCE`; do not create a parallel reviewer capability.
2. Enter through the governed orchestration/capability binding contract for new consumers. Preserve the existing Strategy route only as backward-compatible specialization.
3. Resolve the exact subject specialization from `independent_review_subject_contract_v2.json` or its promoted successor; do not hardcode another subject's route or operation.
4. Bind exact subject identity/revision, producer identity, reviewer identity and provider-bound evidence references. Reviewer identity must differ from the producer when independence is required.
5. Reuse the canonical reviewer operation `REVISION_INDEPENDIENTE_ESTRATEGIA_LF`, its six governed step ids and existing step judges. Generalization must occur in place; do not create another review operation, route or judge set.
6. Persist `review_receipt`, `evidence_refs`, terminal authority readback and `next_gate`. A structural/local PASS alone is never sufficient.
7. If downstream Qualification materialization is actually required by the consumer contract, hand off separately through `QUALIFICATION_FRAMEWORK` and read back its result independently. Qualification is not implicitly required for every independent review.

## Superficies canónicas

- Capability identity `INDEPENDENT_ASSURANCE`
- Subject contract `independent_review_subject_contract_v2.json`
- Existing reviewer operation `REVISION_INDEPENDIENTE_ESTRATEGIA_LF`
- Existing six step ids: `route_bind`, `target_currentness`, `semantic_review`, `judge_record`, `reviewer_readback`, `report_output`
- Existing `OPERATION_STEP_CONTRACT_JUDGE_ENFORCEMENT`
- Existing Strategy compatibility route `STRATEGY_INDEPENDENT_REVIEW`

`public.lf_finalize_qualification_independent_review_v1` is intentionally excluded from the generic review surface because it belongs to downstream `QUALIFICATION_FRAMEWORK` and is only used when the consumer contract actually requires Qualification.

## Soporte de sujetos

The current contract is explicit and fail-closed:

- `STRATEGY`: existing live specialization remains supported and must regress zero.
- `STORY_IMPLEMENTATION_PACKAGE`: target of the T-INDEP extension. It must use the existing operation/judges, `EVIDENCE_LEDGER + CURRENTNESS_AUTHORITY`, and does not require Strategy Qualification merely to produce a durable independent-review receipt.
- Any other subject: supported only when the current transversal subject contract declares an exact specialization; otherwise block with `BLOCK_UNSUPPORTED_SUBJECT_REQUIRES_OWNER_EXTENSION`.

No caller may infer generic support from the capability name alone.

## Integración downstream — no ownership

Independent Review may provide evidence/receipt consumed by a Qualification finalizer when qualification is part of the consumer's contract. Test/suite materialization, Qualification state transition and Qualification-current readback remain owned by `QUALIFICATION_FRAMEWORK`.

A consumer that only requires a durable independent-review verdict and authority readback must not be forced into a Strategy qualification path just to obtain a receipt.

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

`ASSURANCE_EVALUATOR` is a separate evidence-sufficiency capability. It may consume independent-review evidence but does not own Independent Review.

## Fail-closed / límites

- Unsupported subject specialization must block; it must never fall back to Strategy by name or approximation.
- Reviewer execution must be distinct from the producer when independence is required.
- Missing/stale subject revision, reviewer identity, provider-bound receipt or authority readback must block.
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
- Verify the exact subject specialization is supported; do not infer support from capability name.
- Verify no second `INDEPENDENT_REVIEW` operation, route or judge set was introduced.
- Verify Strategy specialization behavior remains unchanged.
- Verify durable review receipt, exact evidence references and terminal authority readback for closure-required consumers.
- Preserve source revision, execution identities, evidence references and exact reviewer receipt.
- Do not turn a local reviewer test into a global closure claim.

## No duplicación

Do not create a second independent-review capability, operation, table, runner, reviewer writer, route or judge set. Extend the existing governed capability through `SUPER_ADMIN` and preserve lineage. Execution units such as `T-INDEP / PAULO-035` materialize and test the extension but do not become the capability owner.

## EKB

- `S36-ASSURANCE-BOUNDARY-CONTAMINATION-001`
- `INDEPENDENT-REVIEW-LEGACY-RPC-BYPASS-001`
- `INDEPENDENT-REVIEW-FINALIZER-RESULT-CONTRACT-MISMATCH-001`
- `STRATEGY-QUALIFICATION-INDEPENDENT-REVIEW-BOOTSTRAP-DEADLOCK-001`
- `GOV-FULL-REGRESSION-TRANSVERSAL-README-CONTRACT-001`
- `STORY-CREATOR-INDEPENDENT-REVIEW-SUBJECT-GAP-001`
- `T-INDEP-PARALLEL-REVIEW-STACK-001`

## Currentness

This README describes the ownership and consumption boundary, not a permanent lifecycle assertion. Consumers must read the live inventory and promoted subject contract for every material decision.
