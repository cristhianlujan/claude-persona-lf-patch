# Contract Resolution Core v1

Status: `SHADOW_CANDIDATE`

## Responsibility

Contract Resolution receives an **already decided** `operation_code` and an authority snapshot of `public.lf_operation_contracts`. It returns **all active contracts for that operation**, preserving each exact contract record and ordering deterministically by `contract_code`.

It does not decide which operation is being executed. It does not decide whether Contract Check applies. It does not rank contracts, infer primary/supplemental roles, evaluate contractual terms, or emit `SATISFIED/CLEAR/...` verdicts.

```text
operation context
    operation_code
         |
         v
Contract Resolution carrier
    + authority contract rows
         |
         v
Contract Resolution core
         |
         v
operation_code + resolved_contracts
         |
         v
Contract Check
```

## Resolution semantics

Active statuses remain compatible with the current authority contract: `ACTIVE_ENFORCEMENT`, `ACTIVE`, `ACTIVO`.

The v1 rule is deliberately `ALL_ACTIVE_CONTRACTS_FOR_OPERATION`. There is no one-of-N selection because the current authority schema has no generic applicability, priority, exclusivity or contract-role columns that would justify ranking. Role-like fields such as `allowed.base_contract_ref` are transported as contract content and are not interpreted by this capability.

Zero active contracts is fail-closed. Duplicate active `contract_code` for the same operation is fail-closed. `contract_sha` is preserved exactly, including `NULL`; this capability does not manufacture source provenance.

## Thin carrier v1

`contract_resolution_carrier_v1.py` is transport only. It accepts one explicit JSON packet from stdin or a file with:

- `schema_version = lf-contract-resolution-request/v1`;
- caller-provided `operation_code`;
- `authority_source = public.lf_operation_contracts`;
- the authority snapshot in `contracts`.

The carrier validates only this transport envelope, invokes the existing core, and emits the core result unchanged. It does **not** infer `operation_code`, query Supabase, attest freshness/provenance, select/rank contracts, evaluate contract terms, decide Contract Check applicability, or execute sibling controls.

Exit codes are deterministic: success `0`, fail-closed missing active contract `2`, malformed carrier/core input `3`.

This preserves the boundary that `operation_code` is caller context. The existing Changeset Governance handoff is not cut over by this carrier; binding that handoff to an already-resolved operation context remains a separate integration step.

## Evidence behind the boundary

The existing Router currently counts every row in `public.lf_operation_contracts` whose `operation_code` matches and whose status is active, and exposes those contract refs. The promoted compact-consumption protocol rehydrates contracts with the same all-active query ordered by `contract_code`.

Read-only live inspection before this candidate found 39 active rows across 35 operations, all currently `ACTIVE_ENFORCEMENT`, with zero duplicate `(operation_code, contract_code)` identities. Four operations currently have two active contracts at the same time. This is evidence that "pick one active contract" would change existing semantics.

## Files

- `contract_resolution_core_v1.py`: pure deterministic resolver, no I/O.
- `test_contract_resolution_core_v1.py`: positive, multi-contract, status, negative and determinism coverage.
- `contract_resolution_carrier_v1.py`: thin stdin/file carrier over the existing core.
- `test_contract_resolution_carrier_v1.py`: transport, boundary and exit-code regression coverage.

## Non-scope

- no Router/PASE redesign;
- no operation-code routing or inference;
- no live Supabase function, query, mutation or provenance attestation;
- no Contract Check term evaluation;
- no Changeset handoff cutover;
- no workflow cutover;
- no merge/deploy/activation.
