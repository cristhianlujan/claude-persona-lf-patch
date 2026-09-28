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
        +-- bind operation_code + contract_code + canonical contract digest
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

## Exact contract binding

The evaluator computes `contract_digest_sha256` from each exact resolved contract record. It does **not require** the legacy `contract_sha` column to be populated.

This is intentional: live readback shows active LF contracts where `contract_sha` is absent. Contract Check must not force canonical authority to satisfy an invented completeness rule. Structural validation of declared source SHA, when required, belongs to `Operation Definition Integrity` / authority-specific integrity controls.

Term evaluations remain bound to the exact contractual content through their individual `term_digest` values. If a contract term changes after evaluation, the digest mismatch blocks the check.

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

Read-only authority inspection found four active JSON shape combinations across current LF contracts. The evaluator supports array, object, scalar, and null section values without changing the source contract schema.

The regression fixture includes the current `GITHUB_CONTRACT_GATE_LF` array/object/array/array shape plus a second object-shaped contract with `contract_sha=null`. This exercises the `1 Contract Check / N contracts` architecture and the live missing-SHA condition without wiring the candidate to CI.

## Thin carrier V1

`contract_check_carrier_v1.py` is the transport-only CLI wrapper for this core.

Its only responsibilities are:

- read one already-built Contract Check packet from stdin or an explicit JSON file;
- invoke `contract_check_core_v1.evaluate(packet)` without modifying the packet;
- emit the structured result as JSON;
- map `PASS` to exit `0`, `BLOCK` to exit `2`, and malformed carrier/input packets to exit `3`.

The carrier MUST NOT resolve contracts, discover applicability, call PASE, invoke sibling controls, fetch evidence, read GitHub/Supabase, persist receipts, or perform lifecycle closure. Those are external responsibilities.

This carrier is intentionally not wired into `.github/workflows/lf-contract-check.yml` in this change. Workflow cutover remains a later ordered step after the carrier is independently proven.

## Rollout

The core and thin carrier remain inactive with respect to the legacy workflow.

No required-check change, Supabase mutation, runtime activation, deployment, or production change is part of this stage. Workflow wiring and migration away from the legacy `scripts/lf_contract_check.py` remain separate ordered changes.
