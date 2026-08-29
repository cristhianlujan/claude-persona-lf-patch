# LF Adapter Quality Standard V2

Status: CANDIDATE_READ_ONLY

## Objective
Bring LF adapters to the evidence and validation standard used by mature LF profiles while keeping adapters lightweight.

## Canonical execution
`ACT-0001 Router -> EJECUCION_PERFIL_LF -> resolve applicable adapter bindings -> load bounded adapter capsule -> execute profile once -> validate -> receipt/readback -> closure`

An adapter is not an independent reasoning worker and does not add another model call.

## Required package elements
Every adapter must define:
- exact activation and non-activation rules;
- authority and precedence;
- bounded inputs and outputs;
- explicit fail-closed states;
- deterministic validation;
- semantic review only where deterministic checks are insufficient;
- adversarial and negative evaluation cases;
- a clear behavioral evidence boundary;
- invocation evidence with adapter code, version, activation reason and source hash;
- a compact runtime capsule;
- a single-model-call constraint.

## Runtime evidence
When an LF adapter applies, the execution receipt should contain `lf_adapter_invocations` as a collection distinct from infrastructure/model adapter metadata. Each entry identifies adapter code, version, invocation id, activation reason, source hash, capsule hash and verdict.

If an applicable adapter is not represented in the execution evidence, the execution cannot close as fully verified.

## Activation rule
Operational adapter activation is resolved by the Router/orchestrator from governed bindings. A profile may depend on an adapter, but it should not independently dispatch an adapter by name.

## Efficiency rule
- no second model call;
- unbound adapters add zero prompt payload;
- examples, authoring docs and judges are not loaded into ordinary runtime prompts;
- runtime capsules target <= 2000 UTF-8 characters unless a documented exception is required.

## Candidate PASS evidence
A V2 candidate should demonstrate valid-case PASS, malformed-case rejection, negative activation cases, exact bound invocation evidence, zero payload for unbound profiles, reproducible Router resolution and no implied runtime/production promotion.
