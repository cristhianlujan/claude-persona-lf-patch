# INDEPENDENT_ASSURANCE

Transversal LF inventory identity: `INDEPENDENT_ASSURANCE` / `TRANSVERSAL_INDEPENDENT_ASSURANCE`.

Effective semantic responsibility: **`INDEPENDENT_REVIEW`**.

`INDEPENDENT_ASSURANCE` remains the current inventory code for compatibility/currentness. Do not create a second capability merely to rename or generalize it.

## Estado

- Owner vigente: `SUPER_ADMIN` (D-V2.2 / `lf_eventos#19472`).
- Estado operativo esperado: `ACTIVO`.
- Inventory status requerido: `ACTIVE_SHARED_ENFORCEMENT`.
- Inventory identity authority: `public.lf_activos`.
- Version/currentness authority: `public.lf_capability_registry` + `public.lf_capability_current`.
- Canonical reviewer operation: `REVISION_INDEPENDIENTE_ESTRATEGIA_LF`.
- Router action vigente para la especialización Strategy: `STRATEGY_INDEPENDENT_REVIEW`.
- Live operation type: `INDEPENDENT_REVIEW`.
- Real-oracle measure: `public.lf_independent_assurance_measure_v1`.

## Propósito

Produce an independent, execution-bound review verdict and durable review evidence when a governing contract requires a reviewer distinct from the producer.

T-INDEP adds a separate **measurement responsibility inside the same capability identity**: prove whether the proposed reviewer/oracle is materially independent from its producer before a consumer treats it as an independent oracle.

The measurement is read-only. It does not execute the review, qualify a subject, activate runtime, or create a second review operation.

## Criterio de independencia real

The measurable contract is:

```text
producer_root + reviewer_root
        ↓
transitive dependency closure (pg_proc, bounded depth)
        ↓
shared dependencies − adjudicated exceptions
        ↓
DEPENDENCY: INDEPENDENT / NOT_INDEPENDENT
        +
provider-bound data references
        ↓
DATA: INDEPENDENT / NOT_INDEPENDENT / UNPROVEN
        +
producer author identity vs reviewer author identity
        ↓
AUTHOR: INDEPENDENT / NOT_INDEPENDENT / UNPROVEN
        ↓
overall state
```

Overall rules:

- `INDEPENDENT`: zero unresolved shared transitive dependencies **and** disjoint data sources **and** distinct producer/reviewer author identities are all proven.
- `NOT_INDEPENDENT`: any proven dimension is shared/non-independent.
- `UNPROVEN`: no dimension proves non-independence, but data or author evidence is missing.
- `BLOCKED`: malformed input, missing/non-unique roots, invalid exception declarations, or another fail-closed input error.

An exception is valid only when it is explicitly adjudicated and is actually present in the measured shared dependency set. Unknown exceptions block; they cannot be used to launder overlap.

### Measurement limits

`PG_PROC_STATIC_CLOSURE_V1` remains the backward-compatible same-schema mode. When producer and reviewer live in different schemas, both roots must be supplied explicitly as `schema.function`; the same capability then uses `PG_PROC_STATIC_CLOSURE_QUALIFIED_V1` to traverse local calls plus explicitly schema-qualified cross-schema calls. It does **not** claim to resolve dynamic SQL, Edge/runtime call graphs, or unqualified cross-schema calls resolved only through `search_path`; those remain provider-bound evidence and otherwise `UNPROVEN`.

## Cuándo consumirlo

Consume the measurement whenever a flow claims that a validator, reviewer, holdout or oracle is materially independent from the producer.

T-INDEP materializes the criterion; `M4.4` is the IG consumer that must use it. A consumer must not translate a distinct operation name or a distinct execution id into “independent” without this material test.

For the review lifecycle itself, consume Independent Review only when a qualification, claim or closure explicitly requires independent evaluation rather than self-review by the producer.

Before material consumption:

1. Resolve `INDEPENDENT_ASSURANCE` in `public.lf_activos`; require non-archived, `ACTIVO`, `VIGENTE`, `ACTIVE_SHARED_ENFORCEMENT`.
2. Resolve `INDEPENDENT_ASSURANCE` in `public.lf_capability_current` and bind the exact manifest through `public.fn_lf_capability_bind_from_orchestrator_v1` when the governed consumer executes it.
3. Run `public.lf_independent_assurance_measure_v1` with exact roots and provider-bound data/author context when available. Use unqualified roots only for the legacy same-schema mode; for cross-schema producer/reviewer pairs, pass both roots as `schema.function`.
4. Fail closed on `UNPROVEN` whenever the governing contract requires positive independence.

## Cómo consumir el review existente

1. Resolve the current inventory identity `INDEPENDENT_ASSURANCE`; do not create a parallel reviewer capability.
2. For the existing Strategy specialization, route through ACT-0001 to `STRATEGY_INDEPENDENT_REVIEW` / `REVISION_INDEPENDIENTE_ESTRATEGIA_LF`.
3. Bind exact producer/reviewer identity, qualification/subject identity, source revision, suite fingerprint, REVIEW_REQUIRED case and evidence references.
4. Execute the six governed reviewer steps: route binding, target currentness, semantic review, judge record, reviewer readback and report output.
5. The reviewer output is a durable review receipt/evidence package plus `next_gate`; it must not directly declare Qualification current or materialize Qualification state.
6. If downstream Qualification materialization is required, hand off through the separate `QUALIFICATION_FRAMEWORK` contract and read back its result independently.

## Superficies canónicas

- `REVISION_INDEPENDIENTE_ESTRATEGIA_LF`
- Router action `STRATEGY_INDEPENDENT_REVIEW`
- reviewer-operation RPCs/step/judge surfaces bound to that operation
- `public.lf_independent_assurance_measure_v1` for read-only real-oracle independence measurement
- `public.lf_capability_registry` / `public.lf_capability_current` for capability version/currentness

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

The T-INDEP measurement does not create a generic review operation or general-purpose review route. Subject-specific lifecycle generalization, if ever required, is a separate governed change and must preserve the canonical operation rather than duplicating it.

## Fail-closed / límites

- Reviewer execution must be distinct from the producer when independence is required.
- Distinct identity alone is insufficient; material dependency/data/author independence must be proven by the governing contract.
- Missing/stale revision, suite fingerprint, qualification binding, reviewer identity, judge receipt or evidence must block the review lifecycle.
- Missing data/author evidence returns `UNPROVEN` for positive real-oracle independence unless another dimension already proves `NOT_INDEPENDENT`.
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

## T-INDEP operation-revision invariant

T-INDEP must not modify the active `REVISION_INDEPENDIENTE_ESTRATEGIA_LF` registry row, contract, step contracts, judges or active Router binding. `public.lf_operation_revision_sha256_v1` must return the same hash before and after the capability measurement cutover.

If a future change must alter those surfaces, it is a different governed change and must prepare exact operation requalification before apply, per `T-INDEP-OPERATION-REVISION-REQUALIFICATION-001`.

## Validación y readback

- Verify active/current asset identity and capability current pointer before consumption.
- Verify Router action and canonical operation remain current and operational.
- Verify all six reviewer steps remain governed and that the report output carries `review_receipt`, `evidence_refs` and `next_gate`.
- Verify the Qualification finalizer remains downstream and separately owned.
- Verify the measurement returns the exact dependency sets/digests and its limitations.
- Verify a known shared classifier/path returns `NOT_INDEPENDENT`.
- Verify an unbound adjudicated exception returns `BLOCKED`.
- Preserve source revision, execution identities, evidence references and exact reviewer receipt.
- Do not turn a local reviewer test into a global closure claim.

## No duplicación

Do not create a second independent-review capability, operation, table, runner, reviewer writer, route or judge stack. Extend the existing capability identity through its owner and preserve lineage.

## EKB

- `T-INDEP-PARALLEL-REVIEW-STACK-001`
- `T-INDEP-OPERATION-REVISION-REQUALIFICATION-001`
- `S36-ASSURANCE-BOUNDARY-CONTAMINATION-001`
- `INDEPENDENT-REVIEW-LEGACY-RPC-BYPASS-001`
- `INDEPENDENT-REVIEW-FINALIZER-RESULT-CONTRACT-MISMATCH-001`
- `STRATEGY-QUALIFICATION-INDEPENDENT-REVIEW-BOOTSTRAP-DEADLOCK-001`
- `GOV-FULL-REGRESSION-TRANSVERSAL-README-CONTRACT-001`

## Currentness

This README describes the ownership and semantic boundary, not a permanent lifecycle assertion. Consumers must read live inventory, `lf_capability_current` and the operation contract for every material decision.

## Generic subject contract v3

The subject-aware v2 candidate is superseded **before live cutover** because it still whitelists named subject types. Do not apply that whitelist model for new consumers.

The canonical target architecture is `independent_review_subject_contract_v3.json`:

- `subject_type` is an opaque, non-empty identifier; it is data, not a core dispatch branch;
- no generic-core whitelist of domain names is allowed;
- any subject may consume Independent Review when it presents an exact VERIFIED Evidence Ledger receipt bound to its type/ref/SHA/source revision, distinct producer/reviewer identities, `review_required=true`, and a non-empty caller-provided review-dimension contract;
- the reviewer must cover the exact bound dimension set;
- Strategy keeps its legacy route only as a backward-compatible specialization;
- the existing `REVISION_INDEPENDIENTE_ESTRATEGIA_LF` operation, six judges, and Evidence Ledger remain the single review stack.

A rollback-only live probe on 2026-10-08 proved the same generic contract with two unrelated existing subject types (`IG_SCREEN_GRAPH` and `IG_SPEC_TRAVERSAL_PER_RUN`) and negative mismatch/self-review/empty-dimension cases. The probe left no database function or evidence residue.
