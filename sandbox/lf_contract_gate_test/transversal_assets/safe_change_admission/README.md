# SAFE_CHANGE_ADMISSION

Transversal LF capability for read-only classification of proposed changes. It separates recommendation from execution permission and never executes the proposed effect.

## Estado

- Owner: `SUPER_ADMIN`.
- Capability code: `SAFE_CHANGE_ADMISSION`.
- Version/currentness authority: `public.lf_capability_registry` + `public.lf_capability_current`.
- Required entry guard: `ORCHESTRATOR_EXECUTION_GUARD_V1`.
- Classification surface: `public.lf_safe_change_admission_classify_v1(jsonb)`.
- Dependency evidence authority: `TYPED_EVIDENCE_REGISTRY`.
- Optional material-independence proof: `INDEPENDENT_ASSURANCE`.

## Propósito

Evaluate a change proposal using four domain-agnostic dimensions:

1. evidence;
2. authority;
3. materiality;
4. reversibility.

It returns exactly one governed classification:

- `AUTOMATIZABLE`
- `RECOMENDADA`
- `REQUIERE_DECISION`
- `UNKNOWN`
- `VERIFY_NO_CHANGE`

The result also carries `execution_permission`. Recommendation and confidence are evidence for classification, never implicit permission.

## Contrato genérico

The classifier accepts a JSON object with:

- `consumer_ref`: opaque trace label only; the classifier never branches on consumer/domain identity.
- `evidence.items[]`: typed evidence objects validated by `TYPED_EVIDENCE_REGISTRY`.
- `evidence.independence`: optional request to reuse `INDEPENDENT_ASSURANCE`; when required, `UNPROVEN` or `BLOCKED` fails closed.
- `authority`: explicit `SUFFICIENT`, `INSUFFICIENT` or `UNKNOWN`, plus an authority reference when sufficient.
- `materiality`: `change_required`, `scope_bounded`, and `LOW|MEDIUM|HIGH`.
- `reversibility`: state plus negative, rollback and readback proof flags.
- `recommendation`: `FAVORABLE|UNFAVORABLE` and confidence.

`UNKNOWN` always returns `NO_EXECUTION_PERMISSION`.

## AUTOMATIZABLE

`AUTOMATIZABLE` is possible only when all of these are true together:

- typed evidence is valid;
- a material change is required;
- scope is bounded;
- authority is sufficient and provider-bound by reference;
- reversibility is demonstrated;
- negative proof exists;
- rollback proof exists;
- readback proof exists;
- recommendation is favorable;
- when independent assurance is explicitly required, it is proven `INDEPENDENT`.

Only this classification returns `DOWNSTREAM_EXECUTION_ELIGIBLE`. This is admission eligibility for a downstream governed executor; it is not execution by this capability.

## Recomendación ≠ permiso

A favorable recommendation, including high confidence, cannot produce execution permission without sufficient authority and the full automation conjunction.

`RECOMENDADA` explicitly returns `NO_EXECUTION_PERMISSION`.

`REQUIERE_DECISION` explicitly returns `NO_EXECUTION_PERMISSION`.

## Superficies canónicas

- `public.lf_safe_change_admission_classify_v1(jsonb)`
- `public.lf_capability_registry`
- `public.lf_capability_version_registry`
- `public.lf_capability_current`
- `public.fn_lf_capability_bind_from_orchestrator_v1`
- `TYPED_EVIDENCE_REGISTRY`
- `INDEPENDENT_ASSURANCE`

## Integración downstream — no ownership

Consumers resolve CURRENT and bind `SAFE_CHANGE_ADMISSION` through the existing guarded capability binder. They pass domain facts as data; they must not copy the classifier or add domain branches inside the provider.

The consumer remains owner of its proposed effect and its downstream execution lifecycle. `SAFE_CHANGE_ADMISSION` owns only classification/admission semantics.

## No responsabilidades

This capability does not:

- execute changes;
- mutate application runtime;
- deploy or activate production;
- own Input Governance;
- own Story Creator or another domain consumer;
- replace `TYPED_EVIDENCE_REGISTRY`;
- replace `INDEPENDENT_ASSURANCE`;
- create a new evidence, assurance, workflow, approval or execution engine;
- convert confidence into permission.

## Fail-closed / límites

Malformed or missing evidence, unknown authority, dependency-currentness drift, contradictory reversibility claims, or unproven required independence return `UNKNOWN` with no execution permission.

A consumer label is opaque trace data. Adding a new consumer must not require a provider code branch.

## Validación y readback

Terminal validation for T-ADMIT must demonstrate:

- `SAFE_CHANGE_ADMISSION` is ACTIVE/CURRENT and owner `SUPER_ADMIN`;
- exact dependency versions/manifests are bound in its manifest;
- a high-confidence favorable proposal without sufficient authority is not `AUTOMATIZABLE`;
- a real non-IG consumer can classify without provider changes;
- IG/M5.8 binds CURRENT through `fn_lf_capability_bind_from_orchestrator_v1` without copying provider logic;
- the classifier has no business/runtime side effects;
- exactly one terminal T-ADMIT state is persisted.

## No duplicación

Do not create a second safe-admission capability, evidence registry, independent-review stack, binder, workflow or domain-specific classifier. Extend this capability only through `SUPER_ADMIN` governance.

## EKB

Relevant reusable lessons include:

- `PASE-UNIT-SOURCE-PACK-FIRST-001`
- `TRANSVERSAL-CAPABILITY-DIRECT-ENTRY-BYPASS-001`
- `T-INDEP-PARALLEL-REVIEW-STACK-001`
- `T-INDEP-OPERATION-REVISION-REQUALIFICATION-001`
- `STORY-CREATOR-INDEPENDENT-ASSURANCE-THIN-ADAPTER-001`
- `GOV-FULL-REGRESSION-TRANSVERSAL-README-CONTRACT-001`

## Currentness

This document describes the semantic boundary, not a permanent lifecycle assertion. Consumers must resolve live `lf_capability_current` and the exact dependency current pointers for every material admission decision.
