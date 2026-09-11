# Governed Profile Execution Provenance + Semantic Gate

Status: CANDIDATE_READ_ONLY / FAIL_CLOSED / ZERO_COST_ONLY

## Purpose

Prevent a governed flow from claiming that a repository profile executed when the result was reconstructed, summarized, fixture-generated or produced directly by a downstream composer/generator; and prevent a semantically incomplete subset of obligations from obtaining downstream PASS.

## Required flow

```text
Router / orchestrator
-> exact PERFIL resolution
-> profile source read
-> literal input
-> enumerable authority sources
-> PROFILE_SEMANTIC_OBLIGATION_MANIFEST_V1
-> bind manifest SHA before worker execution
-> trusted zero-cost RuntimeAdapter
-> real MODEL_RUNTIME execution
-> RAW output capture
-> independent RuntimeAttestationVerifier
-> PROFILE_EXECUTION_RECEIPT_V1
-> Python derives PROFILE_SEMANTIC_CHECK_BUNDLE_V2 from manifest + exact RAW
-> deterministic checks resolve everything derivable without a model
-> unresolved semantic quality only -> governed independent Quality Pack in INDEPENDENT_CHAT_CONTEXT
-> GPT/Claude independent review is bound to the exact producer RAW and execution receipt
-> historical provider-specific mini-judge remains compatibility-only for legacy evidence
-> complete semantic PASS
-> downstream recipient
```

A static fixture, expected answer, manually reconstructed response or summarized worker decision is not proof of profile execution. A manually selected subset of semantic checks is not proof of complete semantic coverage.

## Pre-execution obligation authority

`semantic_obligation_manifest.py` defines `PROFILE_SEMANTIC_OBLIGATION_MANIFEST_V1`.

The manifest must exist before model execution and is bound into the runtime request/receipt by SHA-256. It requires:

- exact execution id and profile code;
- exact aggregate profile-source digest;
- exact literal-input digest;
- at least the mandatory `PROFILE_CONTRACT` and `EXECUTION_INPUT` authority types;
- stable obligation IDs;
- an enumerable `required_obligation_ids` set for every authority source;
- 1:1 correspondence between the union of required IDs and the obligations in the manifest;
- exact evidence pointers into the future RAW output;
- deterministic check type/rule parameters.

Additional enumerable authority sources may be `DECISION_SET` or `UPSTREAM_CONSTRAINTS`.

If a governing source cannot enumerate its required obligations, it is not eligible to claim complete semantic PASS through this gate. The correct result is fail-closed, not a partial manual bundle.

## Deterministic bundle derivation

After RAW capture, Python reconstructs `PROFILE_SEMANTIC_CHECK_BUNDLE_V2` directly from the pre-bound manifest and exact RAW output. `check_id == obligation_id` is mandatory.

Final downstream validation independently rebuilds the expected bundle and compares its canonical digest. It blocks when a caller:

- omits an obligation;
- inserts an unknown obligation;
- changes a rule or check type;
- changes the evidence pointer;
- swaps the manifest after execution;
- supplies a bundle not deterministically derived from the manifest;
- cannot resolve a required evidence pointer.

This closes GOV-034 at the bundle-coverage boundary: PASS is over the complete enumerable obligation set, not over a caller-selected subset.

## Deterministic-first execution invariant

Every execution must use the cheapest authoritative producer for each field. IDs, hashes, routing, contract/default values, Card/Authority/Typed Context projections, deterministic scoring, repetition/formatting and final guards/materialization belong to deterministic code. A model receives only interpretation, selection, reasoning or content that cannot be derived from resolved authority.

Sending a field to a model when the same value is already authoritatively derivable is redundant model work and must be treated as an optimization finding. Runtime reviews should expose deterministic coverage plus model input/output tokens and cold/warm/generation/total latency whenever the provider supplies those measurements. Reducing latency must not weaken Quality, Depth, authority binding or fail-closed validation.

## Semantic quality boundary

The primary execution mode and the final semantic review are independent concerns. `GPT_NATIVE`, `CLAUDE_NATIVE`, and `REMOTE_API` are explicit execution modes; none may silently substitute for another.

Python resolves exact checks (`REQUIRED_SUBSTRING`, `FORBIDDEN_SUBSTRING`, `EXACT_VALUE`) and every other deterministically derivable field before any semantic reviewer is invoked. Native-first execution uses the already-governed Quality Pack in `INDEPENDENT_CHAT_CONTEXT`, with a fresh GPT/Claude independent review bound to the exact producer execution receipt, RAW output, obligation manifest and check bundle.

The historical provider-specific semantic mini-judge remains supported only for legacy evidence compatibility. It is not a mandatory downstream dependency for new native-first runs and must never force a Qwen/model download or remote fallback when the execution contract selects a native mode.

Executor provenance is fail-closed. Before execution and again after attestation, the runtime must prove:

- `executor_mode` matches the registered `adapter_id`;
- the runtime attestation declares the same `executor_mode`;
- `runtime_attestation.provider` is allowed for that exact adapter;
- `model_id` is present and compatible with the registered adapter/provider family.

Any mismatch blocks before downstream quality, Composer or promotion.

## Downstream boundary

`SEMANTIC_JUDGE` is the only provenance-only recipient.

`COMPOSER`, `IMAGE_GENERATOR`, `TOOL_PAYLOAD`, `INTERNAL_AGENT` and `FINAL_USER` require all of:

1. valid `PROFILE_EXECUTION_RECEIPT_V1`;
2. the pre-execution obligation manifest whose SHA is bound in that receipt;
3. exact RAW output binding;
4. deterministically derived check bundle covering all required obligation IDs;
5. a valid semantic-quality proof selected by the provider-agnostic gate: either a native `INDEPENDENT_CHAT_CONTEXT` Quality Pack binding for current native-first runs, or a legacy `PROFILE_SEMANTIC_JUDGE_RECEIPT_V2` only when validating historical provider-specific evidence;
6. all applicable deterministic checks compliant and semantic review PASS;
7. exact execution/quality provenance readback for the selected mode.

Missing manifest, partial bundle, executor provenance mismatch, semantic FAIL or unresolved uncertainty => `BLOCK_PIPELINE`.

## Zero-cost policy

Operational execution is strictly `ZERO_COST_ONLY`.

No provider may be used if invoking it can create incremental monetary charges, including token/API billing, paid hosted inference, credits or subscription add-ons. If a zero-cost real runtime is unavailable, the pipeline blocks. There is no fallback to paid inference, fixtures or a direct generator.

The OpenAI Responses adapter remains quarantined reference/test code only. Its offline regression performs no API calls and must not be selected operationally.

## Request and receipt binding

`PROFILE_RUNTIME_REQUEST_V1` binds operation code, execution id, exact profile identity, source references/hashes, literal input and, when supplied, the pre-execution obligation-manifest digest. The request digest therefore proves the manifest was fixed before the worker response.

The execution receipt binds profile identity, source digest, input digest, RAW digest, runtime attestation, independent verifier evidence and the same obligation-manifest digest. It cannot self-authorize downstream use.

The semantic receipt separately binds the obligation-manifest digest, exact check-bundle digest and per-check results.

## Fail closed

Block on paid provider, missing RAW, malformed hashes, mismatched request/source/input/profile binding, absent independent verifier, failed attestation verification, test doubles in operational mode, invalid receipt digest, self-authorization, missing pre-bound obligation manifest, incomplete obligation coverage, non-derived bundle, any `CONTRADICTS`, any `UNCERTAIN`, malformed model response or unverified local semantic runtime evidence.

## Regression

```bash
python sandbox/lf_contract_gate_test/profile_execution_runtime/run_tests.py
python sandbox/lf_contract_gate_test/profile_execution_runtime/run_semantic_mini_judge_tests.py
```

The live semantic smoke runs in the authorized Story Agent Evidence Verifier workflow with the pinned zero-cost local model. CI must not make billable model calls.
