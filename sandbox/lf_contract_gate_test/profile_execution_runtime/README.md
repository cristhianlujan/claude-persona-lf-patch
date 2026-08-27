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

`profile_runtime_runner.py` materializes the execution boundary without selecting or calling a paid provider. The host must inject two distinct capabilities:

- `RuntimeAdapter`: invokes the configured model runtime and returns RAW output plus an attestation bound to the exact request.
- `RuntimeAttestationVerifier`: independently verifies that attestation and binds verification evidence to the exact request and response hashes.

Operational mode rejects adapters or verifiers marked as test doubles. The repository intentionally ships no dynamic-import adapter, shell-command adapter, provider API key, or provider-specific implementation; those would create an untrusted self-attestation path or external cost without explicit provider selection.

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

Block on missing receipt, non-model origin, missing RAW capture, malformed hashes, mismatched request/source/input/profile binding, absent independent verifier, failed attestation verification, test doubles in operational mode, invalid receipt digest or self-authorization.

## Boundary

This runner does **not** pretend that a real provider is already connected. Without a trusted operational `RuntimeAdapter` plus an independent attestation verifier, execution remains blocked. Direct fallback to a generator is forbidden.

## Regression

```bash
python sandbox/lf_contract_gate_test/profile_execution_runtime/run_tests.py
```

Expected: `PROFILE_RUNTIME_GATE_TESTS_PASS 16/16`.

The main LF contract check invokes this regression intrinsically, so the boundary remains exercised without changing any GitHub workflow allowlist.

The files remain under the existing LF contract-gate sandbox allowlist; no provider, cost, production runtime or Supabase schema is enabled by this candidate.
