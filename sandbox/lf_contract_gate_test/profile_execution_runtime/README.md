# Governed Profile Execution Provenance Gate

Status: CANDIDATE_READ_ONLY / FAIL_CLOSED / ZERO_COST_ONLY

## Purpose
Prevent a governed flow from claiming that a repository profile executed when the result was reconstructed, summarized, fixture-generated or produced directly by a downstream composer/generator.

## Required flow

```text
Router
-> exact PERFIL resolution
-> profile source read
-> literal input
-> trusted zero-cost RuntimeAdapter
-> real MODEL_RUNTIME execution
-> RAW output capture
-> independent RuntimeAttestationVerifier
-> PROFILE_EXECUTION_RECEIPT_V1
-> deterministic contract checks
-> narrow semantic mini-judge when needed
-> downstream recipient
```

A static fixture, expected answer, manually reconstructed response or summarized worker decision is not proof of profile execution.

## Zero-cost policy

Operational execution is strictly `ZERO_COST_ONLY`.

A provider is not authorized if invoking it can create incremental monetary charges, including token/API billing, paid hosted inference, paid credits or subscription add-ons. If a zero-cost real runtime is unavailable, the pipeline blocks. There is no fallback to a paid provider, fixture or direct generator.

The OpenAI Responses adapter added in PR #242 is retained only as quarantined reference/test code. It is **not** an authorized operational provider. The canonical `run_openai_profile.py` entrypoint is a fail-closed tombstone and returns `PAID_PROVIDER_DISABLED_BY_ZERO_COST_POLICY`; it must not issue network requests.

## Provider-agnostic runner

`profile_runtime_runner.py` materializes the execution boundary. The host injects two distinct capabilities:

- `RuntimeAdapter`: invokes the configured real model runtime and returns RAW output plus an attestation bound to the exact request.
- `RuntimeAttestationVerifier`: independently verifies that attestation and binds verification evidence to the exact request and response hashes.

Operational mode rejects adapters or verifiers marked as test doubles.

## Semantic mini-judge boundary

The local Qwen runtime is **not** authorized as the primary reasoning worker for profile quality. Its narrow role is semantic classification after stronger reasoning has already produced the candidate RAW output.

The preferred sequence is:

```text
GPT-5.6 Sol / primary worker
-> original RAW output
-> Python deterministic checks
-> only unresolved atomic SEMANTIC_RELATION checks
-> local zero-cost mini-judge
-> PROFILE_SEMANTIC_JUDGE_RECEIPT_V1
-> PASS => eligible for downstream gate
-> FAIL or UNCERTAIN => BLOCK
```

`semantic_mini_judge.py` defines the atomic check contract. Python must resolve exact checks (`REQUIRED_SUBSTRING`, `FORBIDDEN_SUBSTRING`, `EXACT_VALUE`) before invoking a model. Only `SEMANTIC_RELATION` checks are sent to Qwen, and each model call receives only one compact rule/evidence/question tuple.

The model may only classify `COMPLIES`, `CONTRADICTS` or `UNCERTAIN`. It must not rewrite or repair the worker output. `UNCERTAIN` blocks. The semantic receipt never self-authorizes downstream use.

`github_actions_semantic_judge.py` reuses the pinned public `ubuntu-latest` + llama.cpp + Qwen2.5-VL-3B assets as a text-only zero-cost classifier and independently re-hashes local evidence. It does not require the multimodal projector for text-only semantic checks.

Known mandatory live regressions include:
- the GOV-032 inversion where a duplicated amount was incorrectly duplicated again;
- a context-authority failure where the worker claimed the authoritative survivor was missing despite the input explicitly identifying it;
- a compliant duplicate-removal case;
- an unsupported invented card suffix (`4242`).

## OpenAI reference implementation

`openai_responses_runtime.py` remains in the repository only to preserve the provider contract work and deterministic offline regression coverage. It must not be selected for operational execution while `ZERO_COST_ONLY` is active.

The provider-specific offline suite performs no API calls and therefore remains valid as a contract regression:

```bash
python sandbox/lf_contract_gate_test/profile_execution_runtime/run_openai_provider_tests.py
```

Expected: `OPENAI_PROFILE_RUNTIME_TESTS_PASS 10/10`.

## Request binding

`PROFILE_RUNTIME_REQUEST_V1` binds operation code, execution id, exact profile identity, source references/hashes, literal input and canonical request digest.

## Receipt binding

The execution receipt binds exact profile identity, source digest, literal input digest, RAW output digest, runtime attestation, independent verifier evidence and a self digest. It cannot authorize itself for downstream use.

The semantic receipt separately binds the exact input hash, RAW output hash, atomic check bundle and per-check result. Provenance PASS and semantic PASS are different gates.

## Fail closed

Block on a paid provider, missing zero-cost runtime, missing RAW, malformed hashes, mismatched request/source/input/profile binding, absent independent verifier, failed attestation verification, test doubles in operational mode, invalid receipt digest or self-authorization.

For semantic quality, block on any `CONTRADICTS`, `UNCERTAIN`, malformed model response, unverified local runtime evidence, or deterministic check failure.

## Regression

Generic runner regression:

```bash
python sandbox/lf_contract_gate_test/profile_execution_runtime/run_tests.py
```

Expected: `PROFILE_RUNTIME_GATE_TESTS_PASS 16/16`.

Semantic mini-judge offline regression:

```bash
python sandbox/lf_contract_gate_test/profile_execution_runtime/run_semantic_mini_judge_tests.py
```

Expected: `SEMANTIC_MINI_JUDGE_TESTS_PASS 11/11`.

The live semantic smoke is intentionally isolated to the dedicated PR workflow and uses only the pinned zero-cost local model. CI must not make billable model calls.
