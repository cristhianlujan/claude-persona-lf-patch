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
-> MODEL_RUNTIME execution
-> RAW output capture
-> PROFILE_EXECUTION_RECEIPT_V1
-> output validation / semantic judge
-> downstream recipient
```

A static fixture, expected answer, manually reconstructed response or summarized worker decision is not proof of profile execution.

## Receipt binding
The receipt binds `EJECUCION_PERFIL_LF`, exact profile identity, source digest, literal input digest, RAW output digest, runtime attestation and a self digest. It cannot authorize itself for downstream use.

## Fail closed
Block on missing receipt, non-model origin, missing RAW capture, mismatched hashes, incomplete runtime attestation, invalid receipt digest or self-authorization.

## Boundary
This gate does not fake a model-provider call. A real runtime must supply model execution and attestation. When unavailable, the correct state is `BLOCK_PIPELINE`; direct fallback to a generator is forbidden.

## Regression

```bash
python sandbox/lf_contract_gate_test/profile_execution_runtime/run_tests.py
```

Expected: `PROFILE_RUNTIME_GATE_TESTS_PASS 6/6`.
