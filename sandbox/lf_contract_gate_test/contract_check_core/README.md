# Contract Check Core V1

Status: `SHADOW_CANDIDATE`

## Purpose

Provide one deterministic Contract Check capability for **N contracts that have already been resolved by another capability**.

This core does not select contracts. It receives an exact contract set plus evidence-backed evaluations for each declared contractual term and returns one aggregate `PASS` or `BLOCK` verdict.

```text
PASE / Contract Resolution
        |
        | exact resolved contract set
        v
CONTRACT_CHECK_CORE_V1
        |
        +-- bind operation_code + contract_code + contract_sha
        +-- derive exact term identity/digest from declared contract sections
        +-- require one evidence-backed evaluation per applicable term
        +-- block missing, duplicated, tampered, failed or triggered terms
        +-- aggregate N contract results
        |
        v
     PASS / BLOCK
```

## Boundary

Contract Check owns only the contractual verdict over contracts already selected upstream.

It MUST NOT:

- decide whether Contract Check applies to the pass;
- select or rank contracts;
- resolve dynamic applicability of contracts;
- decide the order of controls;
- execute Migration Parity, Validate Packs, Assurance, P0, Runtime, DB Regression, or sibling controls;
- own repository-path admission, currentness, receipts, EKB persistence, lifecycle closure, or generic observability;
- create, mutate, promote, materialize, or deprecate contracts/operations/policies/assets;
- call GitHub or Supabase.

`Operation Definition Integrity` is a separate transversal structural capability. This candidate does not duplicate its operation/step/judge/policy invariants.

## Input contract

Schema: `lf-contract-check-input/v1`.

Required top-level fields:

- `operation_code`: operation whose already-resolved contracts are being checked.
- `phase`: `ENTRY` or `CLOSURE`.
- `contracts`: exact resolved contract records.
- `evaluations`: typed, evidence-backed results for the contractual terms.

Current LF contract authority stores contractual semantics in four heterogeneous JSON sections:

- `required_before_write`
- `allowed`
- `blocked`
- `required_after_write`

The core does **not invent an interpretation** for those heterogeneous values. Instead, it derives a deterministic identity and SHA-256 digest for every declared top-level term and requires an evidence-backed verdict bound to that exact term digest.

For list sections, each list item is a term (`section[index]`). For object sections, each top-level key is a term (`section.key`). This preserves current LF contract shapes without introducing a parallel contract authority.

## Phase behavior

`ENTRY` evaluates:

- `required_before_write`
- `allowed`
- `blocked`

`CLOSURE` evaluates all four sections, including `required_after_write`.

Allowed term verdicts:

- required/allowed/after-write: `SATISFIED`, `FAILED`, `NOT_APPLICABLE`;
- blocked: `CLEAR`, `TRIGGERED`, `NOT_APPLICABLE`.

Every term verdict must carry at least one nonblank `evidence_ref`. `NOT_APPLICABLE` additionally requires a rationale. Missing evidence, missing term coverage, duplicate evaluations, term-digest drift, `FAILED`, or `TRIGGERED` fail closed.

## Why this is one Contract Check

The capability accepts a list of resolved contracts, not one hard-coded GitHub contract. A single execution can therefore validate one or many contracts for the same operation while keeping contract selection outside the boundary.

## Live-shaped compatibility

The regression fixture includes the current `GITHUB_CONTRACT_GATE_LF` contract shape (`required_before_write` as array, `allowed` as object, `blocked` as array, `required_after_write` as array) plus a second contract using object-shaped sections. This exercises the `1 Contract Check / N contracts` architecture without wiring the candidate to live CI.

## Rollout

This candidate remains inactive.

No workflow wiring, required-check change, Supabase mutation, runtime activation, deployment, merge, or production change is part of this PR. Consumer wiring and any migration away from the legacy `scripts/lf_contract_check.py` are separate changes after direct readback and compatibility proof.
