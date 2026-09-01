# Governed Profile Execution Provenance + Semantic Gate

Status: CANDIDATE_READ_ONLY / FAIL_CLOSED / ZERO_COST_ONLY

## Purpose

Prevent a governed flow from claiming that a repository profile executed when the result was reconstructed, summarized, fixture-generated or produced directly by a downstream composer/generator; and prevent a semantically incomplete subset of obligations from obtaining downstream PASS.

## Required flow

```text
Router / orchestrator
-> exact PERFIL resolution
-> resolve Router-bound adapters
-> Input Governance agent when adapter metadata requires it
-> live governance_receipt with decision=PASS
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
-> deterministic checks
-> only unresolved atomic SEMANTIC_RELATION checks to local mini-judge
-> PROFILE_SEMANTIC_JUDGE_RECEIPT_V2
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

## Semantic mini-judge boundary

The local Qwen runtime is **not** authorized as the primary reasoning worker for profile quality. GPT-5.6 Sol / the stronger primary worker produces the candidate RAW output.

Python must resolve exact checks (`REQUIRED_SUBSTRING`, `FORBIDDEN_SUBSTRING`, `EXACT_VALUE`) before invoking a model. Only `SEMANTIC_RELATION` checks are sent to Qwen, one compact rule/evidence/question tuple at a time.

The authorized zero-cost semantic classifier is the pinned Qwen2.5-VL-7B Q4_K_M runtime on a public standard `ubuntu-latest` runner. It may only classify `COMPLIES`, `CONTRADICTS` or `UNCERTAIN`; it must not rewrite or repair the worker output. `UNCERTAIN` blocks.

Known mandatory live regressions include:

- GOV-032 inversion: an already duplicated amount must not be duplicated again;
- explicit context authority ignored;
- correct duplicate removal (positive control);
- unsupported invented card suffix (`4242`).

## Downstream boundary

`SEMANTIC_JUDGE` is the only provenance-only recipient.

`COMPOSER`, `IMAGE_GENERATOR`, `TOOL_PAYLOAD`, `INTERNAL_AGENT` and `FINAL_USER` require all of:

1. valid `PROFILE_EXECUTION_RECEIPT_V1`;
2. the pre-execution obligation manifest whose SHA is bound in that receipt;
3. exact RAW output binding;
4. deterministically derived check bundle covering all required obligation IDs;
5. valid `PROFILE_SEMANTIC_JUDGE_RECEIPT_V2`;
6. all checks `COMPLIES`;
7. verified Qwen runtime evidence for semantic checks.

Missing manifest, partial bundle, semantic FAIL or `UNCERTAIN` => `BLOCK_PIPELINE`.

## Zero-cost policy

Operational execution is strictly `ZERO_COST_ONLY`.

No provider may be used if invoking it can create incremental monetary charges, including token/API billing, paid hosted inference, credits or subscription add-ons. If a zero-cost real runtime is unavailable, the pipeline blocks. There is no fallback to paid inference, fixtures or a direct generator.

The OpenAI Responses adapter remains quarantined reference/test code only. Its offline regression performs no API calls and must not be selected operationally.

## Request and receipt binding

`PROFILE_RUNTIME_REQUEST_V1` binds operation code, execution id, exact profile identity, source references/hashes, literal input and, when supplied, the pre-execution obligation-manifest digest. For every Router-bound adapter that declares `input_governance_receipt_required=true`, it also binds the live PASS receipt and its digest before the model call. The request digest therefore proves both governance and the manifest were fixed before the worker response.

The execution receipt binds profile identity, source digest, input digest, RAW digest, runtime attestation, independent verifier evidence, the same obligation-manifest digest and, when required, the same governance receipt digest. It cannot self-authorize downstream use.

The semantic receipt separately binds the obligation-manifest digest, exact check-bundle digest and per-check results.

## Fail closed

Block on paid provider, missing RAW, malformed hashes, mismatched request/source/input/profile binding, absent independent verifier, failed attestation verification, test doubles in operational mode, invalid receipt digest, self-authorization, missing/stale/non-PASS Input Governance receipt for a requiring adapter, missing pre-bound obligation manifest, incomplete obligation coverage, non-derived bundle, any `CONTRADICTS`, any `UNCERTAIN`, malformed model response or unverified local semantic runtime evidence.

## Regression

```bash
python sandbox/lf_contract_gate_test/profile_execution_runtime/run_tests.py
python sandbox/lf_contract_gate_test/profile_execution_runtime/run_semantic_mini_judge_tests.py
```

The live semantic smoke runs in the authorized Story Agent Evidence Verifier workflow with the pinned zero-cost local model. CI must not make billable model calls.
