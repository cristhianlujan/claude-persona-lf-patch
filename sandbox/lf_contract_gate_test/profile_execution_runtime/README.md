# Governed Profile Execution Provenance Gate

Status: CANDIDATE_READ_ONLY / FAIL_CLOSED

## Purpose
Prevent a governed flow from claiming that a repository profile executed when the result was actually reconstructed, summarized, fixture-generated or produced directly by a downstream composer/generator.

## Required flow

```text
Router
-> exact PERFIL resolution
-> profile source read
-> literal input
-> trusted RuntimeAdapter
-> MODEL_RUNTIME execution
-> RAW output capture
-> independent RuntimeAttestationVerifier
-> PROFILE_EXECUTION_RECEIPT_V1
-> output validation / semantic judge
-> downstream recipient
```

A static fixture, expected answer, manually reconstructed response or summarized worker decision is not proof of profile execution.

## Provider-agnostic runner

`profile_runtime_runner.py` materializes the execution boundary. The host injects two distinct capabilities:

- `RuntimeAdapter`: invokes the configured model runtime and returns RAW output plus an attestation bound to the exact request.
- `RuntimeAttestationVerifier`: independently verifies that attestation and binds verification evidence to the exact request and response hashes.

Operational mode rejects adapters or verifiers marked as test doubles.

## OpenAI Responses runtime

`openai_responses_runtime.py` provides the first operational provider implementation:

- `OpenAIResponsesAdapter` calls `POST https://api.openai.com/v1/responses` with `store=true`;
- the exact LF execution/profile/source/input/request hashes are written into provider response metadata;
- RAW is the provider `output[]` array, without a reconstructed summary;
- `OpenAIResponsesReadbackVerifier` independently calls `GET /responses/{response_id}` and verifies response id, model, status, provider metadata, created time and RAW output hash;
- the verifier emits a provider-readback evidence digest before the generic runner creates `PROFILE_EXECUTION_RECEIPT_V1`.

The API base is fixed to the official OpenAI endpoint; it is not configurable to an arbitrary host.

Default runtime model: `gpt-5.6-terra` with reasoning effort `medium`. Both are configurable at execution time.

### Credentials and optional runtime configuration

Required server-side environment variable:

```bash
OPENAI_API_KEY=...
```

Optional:

```bash
OPENAI_PROFILE_RUNTIME_VERIFY_API_KEY=...   # separate readback credential; falls back to OPENAI_API_KEY
OPENAI_PROFILE_RUNTIME_MODEL=gpt-5.6-terra
OPENAI_PROFILE_RUNTIME_REASONING_EFFORT=medium
OPENAI_ORGANIZATION=...
OPENAI_PROJECT=...
```

Secrets must never be committed to GitHub or stored in profile source files.

## Live execution

`run_openai_profile.py` loads canonical profile files, preserves the literal input and runs the generic provenance pipeline with operational test doubles disabled.

Example:

```bash
python sandbox/lf_contract_gate_test/profile_execution_runtime/run_openai_profile.py \
  --profile-code PERFIL-UI-ARCHITECT \
  --profile-slug ui_architect \
  --source profiles/ui_architect/SKILL.md=profiles/ui_architect/SKILL.md \
  --input-file /path/to/input.txt
```

Repeat `--source REF=PATH` for every canonical source required by the profile. A live call consumes OpenAI API usage. CI does not execute this live command and does not spend provider tokens.

Without a valid credential/provider readback, execution blocks. There is no fallback to static fixtures or direct image generation.

## Request binding

`PROFILE_RUNTIME_REQUEST_V1` binds:

- `operation_code = EJECUCION_PERFIL_LF`;
- execution id and exact profile identity;
- sorted source references and per-source content hashes;
- aggregate profile-source digest;
- literal user input and its digest;
- a canonical request digest.

A runtime response must repeat the request/profile/source/input bindings. The independent verifier must return the same request digest, the canonical response digest and a SHA-256 evidence digest.

## Receipt binding

The receipt binds exact profile identity, source digest, literal input digest, RAW output digest, runtime attestation, independent verifier id/evidence and a self digest. It cannot authorize itself for downstream use.

## Fail closed

Block on missing credential, provider transport/error, incomplete provider response, missing RAW, malformed hashes, mismatched request/source/input/profile binding, readback id/model/metadata/output mismatch, absent independent verifier, failed attestation verification, test doubles in operational mode, invalid receipt digest or self-authorization.

## Regression

Generic runner regression:

```bash
python sandbox/lf_contract_gate_test/profile_execution_runtime/run_tests.py
```

Expected: `PROFILE_RUNTIME_GATE_TESTS_PASS 16/16`.

OpenAI provider contract regression (offline; no API call):

```bash
python sandbox/lf_contract_gate_test/profile_execution_runtime/run_openai_provider_tests.py
```

Expected: `OPENAI_PROFILE_RUNTIME_TESTS_PASS 10/10`.

The main LF contract check continues to invoke the generic regression intrinsically. The provider-specific suite is deterministic and does not require a secret; a live smoke test is only meaningful once a real `OPENAI_API_KEY` is supplied to the server/runtime.
