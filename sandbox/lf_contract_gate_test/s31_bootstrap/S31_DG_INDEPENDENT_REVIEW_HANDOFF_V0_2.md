# S31-DG Independent Semantic Review Handoff v0.2

## Review identity

- Review case: `S31-DG-IR-002`
- Review mode: `INDEPENDENT_CHAT_CONTEXT`
- Reviewer must not be the producer.
- Producer context must not be supplied to the independent reviewer beyond this frozen handoff/bundle.
- Do not repair artifacts during review.
- Do not authorize runtime activation, Golden, merge, production, or behavioral promotion.

## Frozen bundle

Review only this immutable bundle:

`github://cristhianlujan/claude-persona-lf-patch@5f4881503fa3988d6455fa41cb3efc84c2967db4/sandbox/lf_contract_gate_test/s31_bootstrap/s31_dg_independent_review_bundle_v0_4.json`

Expected Git blob SHA:

`5c196fa5cae47f32d174e7c1b0f9eb981efecc06`

The bundle freezes the source candidate snapshot at:

`20145a2cb5b246f6d3e90987d1af355aa419f2d4`

Base/currentness reference in the bundle:

`main@6ac06b6aff7a9a22e80a848d7fc32b5787892992`

Do not substitute branch HEAD, PR merge SHA, a later source snapshot, or prior DG bundles.

## Prior independent result that must remain visible

`S31-DG-IR-001` returned `BLOCK_PIPELINE` with:

- `SOURCE_MISMATCH`
- `AUTHORITY_LEAK`
- `EVIDENCE_INFLATION`

The exact prior negative evidence and the producer repair trace are frozen inside IR-002. Producer deterministic PASS is repair evidence only; it is **not** semantic proof.

## Mandatory review scope

Review only lanes `S31-D`, `S31-E`, `S31-F`, and `S31-G` as frozen in the bundle.

### S31-D — Authority / Typed Context

Verify semantically that:

1. Authority and runtime-schema source currentness cannot pass from syntactically valid refs/digests alone.
2. The resolver is mandatory for governed currentness.
3. Fake, unresolved, stale, mismatched, or self-resolved currentness fails closed.
4. Source refs, source SHA, current run, and CURRENT status are cross-bound to the independently resolved receipt.
5. Cross-run authority still requires explicit declaration.
6. The shared kernel remains provider/framework neutral and does not move provider transport into LF authority.

Adversarially attempt at minimum:

- fake currentness ref;
- valid-looking SHA-256 for the wrong receipt;
- stale currentness receipt;
- source-ref/source-digest mismatch;
- producer as resolver;
- undeclared cross-run authority.

### S31-E — Capability Registry

Verify semantically that:

1. The versioned repository manifest remains the authority; a DB/catalog projection is not authority.
2. Registry metadata cannot grant execution/promotion authority.
3. `lifecycle` is the single frozen field contract; legacy `lifecycle_state` cannot silently re-enter.
4. Inventory required fields and manifest-schema required fields are deterministically identical.
5. Lifecycle dimensions remain separate, canonical lifecycle vocabulary remains unresolved, and self-certification remains false.
6. Source digests are cryptographic SHA-256 bindings and currentness is independently resolver-bound.

Adversarially attempt at minimum:

- `lifecycle_state` substitution;
- required-field drift;
- weak digest;
- stale/unresolved currentness;
- owner/producer as resolver;
- duplicate dependency identity.

### S31-F — Evidence / Receipt / Lifecycle

Verify semantically that:

1. Claim ceiling cannot exceed the evidence level.
2. STRUCTURAL evidence cannot become SEMANTIC/BEHAVIORAL by self-declared flags.
3. Every non-structural level requires independently resolved execution, authority-currentness, and provenance receipts.
4. All resolver bindings are immutable SHA-256 bindings and producer self-resolution fails closed.
5. Resolved receipts are cross-bound to the envelope run/SHA/execution identity/authority source/provenance refs.
6. Owner receipts are preserved without rewrite.
7. Capability-specific extensions have an explicit carrier despite root `additionalProperties=false`.

Adversarially attempt at minimum:

- fake ref;
- correct-format but wrong SHA-256;
- 8-character/weak digest;
- producer self-resolver;
- stale authority receipt;
- false provenance receipt;
- missing owner receipt;
- extension preservation failure;
- STRUCTURAL → BEHAVIORAL inflation.

### S31-G — Runtime Port / Output Authority Boundary

Verify semantically that:

1. Runtime execution consumes governed typed context but cannot decide authority/currentness/Card applicability/promotion/Golden/production.
2. Silent fallback remains forbidden.
3. Provider/framework remains replaceable behind the port.
4. The typed output contract forbids any authority grant inside `runtime_receipt`.
5. Recursive validation catches nested authority flags/effects, not only top-level fields.
6. Raw business/model output is not interpreted as Control Plane authority.

Adversarially attempt at minimum:

- `production_authorized=true` under runtime receipt;
- `golden_authorized=true` under a nested object;
- `authority_grants_allowed=true`;
- `authority_effects=[ENABLE_PRODUCTION]`;
- arbitrary non-empty authority effect;
- silent provider fallback.

## Independent quality boundary

Use the Quality Pack references frozen in the bundle. Do not treat producer test results as semantic proof. Resolve the frozen artifacts independently and apply the canonical evidence/currentness/no-self-certification boundary.

## Required output

Return one independent semantic review receipt for `S31-DG-IR-002` containing at least:

- `receipt_version`
- `execution_mode=INDEPENDENT_CHAT_CONTEXT`
- `semantic_status=EXECUTED_INDEPENDENT_CONTEXT`
- `review_case_id=S31-DG-IR-002`
- `reviewer_is_producer=false`
- `producer_context_available=false`
- exact `source_bundle.artifact_ref`
- exact bundle Git blob SHA `5c196fa5cae47f32d174e7c1b0f9eb981efecc06`
- quality-review verdict and score breakdown
- evidence map per D/E/F/G
- blocking codes and repair actions if any
- remaining risks
- routing / next gate
- per-lane verdicts

A PASS may mean only that this exact frozen candidate satisfies the independent semantic review contract. It does not authorize runtime, Golden, merge, production, or behavioral promotion.
