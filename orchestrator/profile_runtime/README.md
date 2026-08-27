# Profile Execution Provenance Gate

Status: CANDIDATE_READ_ONLY / FAIL_CLOSED

## Purpose

Prevent a governed flow from claiming that a repository profile was executed when the result was actually reconstructed, summarized, fixture-generated or produced directly by a downstream composer/generator.

This capability implements the provenance boundary required by `EJECUCION_PERFIL_LF` between `execute_profile` and any downstream recipient.

## Required flow

```text
Router
-> exact PERFIL resolution
-> profile source read
-> literal input
-> MODEL_RUNTIME execution
-> RAW output capture
-> PROFILE_EXECUTION_RECEIPT_V1
-> profile output validation / semantic judge
-> Composer or downstream recipient
```

A static fixture, expected answer, manually reconstructed response or summarized worker decision is not proof of profile execution.

## Receipt minimum

`PROFILE_EXECUTION_RECEIPT_V1` binds:

- `operation_code = EJECUCION_PERFIL_LF`
- exact `profile_code` and `profile_slug`
- profile source references and source digest
- literal input digest
- RAW output digest
- `execution_origin = MODEL_RUNTIME`
- runtime attestation: provider, model id, run id, attested time
- receipt self-digest

The receipt may not authorize itself for downstream use. Authorization is a separate gate result.

## Fail-closed conditions

Block when:

- receipt is absent;
- origin is a static fixture or reconstructed output;
- RAW output was not captured;
- profile, input, source or RAW output hashes do not match;
- runtime attestation is incomplete;
- receipt hash is invalid;
- receipt tries to set `downstream_authorized=true` itself.

## Important boundary

This module does **not** implement or pretend to implement a model provider call. A real runtime must supply the model execution and attestation. Until that exists, the correct state is blocked rather than manufacturing `profile_output`.

## Test

```bash
python orchestrator/profile_runtime/run_tests.py
```

Expected result:

```text
PROFILE_RUNTIME_GATE_TESTS_PASS 6/6
```
