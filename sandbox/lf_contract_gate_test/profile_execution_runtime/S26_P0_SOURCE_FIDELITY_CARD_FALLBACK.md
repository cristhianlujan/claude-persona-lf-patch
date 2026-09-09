# S26 P0 — Source Fidelity + Governed Card Fallback

Status: CANDIDATE_P0_IMPLEMENTED_ON_PR_BRANCH
Scope: S26 profile execution runtime candidate only. No main/production promotion.

## Problem closed by this candidate

Two independent gaps were observed:

1. A downstream packet/payload could be internally consistent while already diverging from the real source authority. The Run F visual case exposed this: the source visual had 10 table columns, while the downstream semantics preserved only 5 exact columns and introduced 5 replacements.
2. `LF_PROFILE_EXECUTION_CONTRACT_V1` required a non-empty `card_refs_and_hashes`, so the absence of a specialized Card could become an artificial blocker even when the governed Core was sufficient.

## P0 policy

### A. Source fidelity

For transformations of an existing source, separate immutable semantics from mutable presentation.

Immutable examples:
- data fields / table columns
- identifiers and bindings
- business states
- actions
- factual claims / prices / legal text when marked authoritative

Mutable examples:
- layout
- spacing
- responsive strategy
- overflow strategy
- visual hierarchy

The runtime may improve presentation aggressively, but it must not silently add, remove, rename or mutate immutable semantic entities.

A bound source-fidelity contract requires:
- `SOURCE_FIDELITY` in `required_checks`
- `source_fidelity` in `required_evidence`
- source ref + source SHA
- immutable entities with stable IDs and semantic signatures
- explicit mutable dimensions
- `critical_ambiguity=false`

### B. Card resolution ladder

Card absence is not itself a blocker.

Resolution order:
1. `EXACT` — exact applicable Card(s)
2. `COMPOSED` — compatible reusable Card(s)
3. `GENERIC_SAFE` — no usable Card; execute against the governed Core
4. block only when `critical_authority_missing=true` or another existing hard gate fails

`GENERIC_SAFE` requires:
- empty `card_refs_and_hashes`
- bound `core_policy_ref`
- bound `core_policy_sha256`
- explicit `fallback_reason`
- explicit unresolved capabilities list (may be empty)
- `critical_authority_missing=false`

Historical contracts with non-empty Cards remain backward-compatible; no frozen Run D/E/F evidence is rewritten or requalified by this change.

## Human escalation rule

Human review is exceptional, not normal routing.

Escalate only when an unresolved condition can change protected semantics or authority, for example:
- source authority cannot be established
- critical source content is ambiguous
- regulated/factual claim cannot be verified
- destructive/irreversible action requires approval

Missing specialization, visual uncertainty that can be resolved by a second automated pass, or absence of an exact Card must not automatically escalate to a human.

## Regression evidence

`run_native_execution_contract_tests.py` now covers:
- 11 historical execution-contract cases unchanged
- `GENERIC_SAFE` pass with no Card and governed Core
- no-Card without resolution => fail
- critical authority missing => fail
- source-fidelity binding without required check/evidence => fail
- source semantic reordering/presentation-only change => pass
- Run F header mismatch fixture: 5 source entities missing + 5 invented => fail before Composer
- same-ID semantic mutation => fail

Expected local result: `PROFILE_EXECUTION_CONTRACT_TESTS_PASS 18/18`.

## Research basis

Validated against current public documentation on 2026-09-09:

- JSON Schema object validation: `required` plus `additionalProperties: false` supports strict runtime shape enforcement without relying on erased compile-time types. https://json-schema.org/understanding-json-schema/reference/object
- Pact contract testing: consumer/provider behavior is safer when interfaces are tested against explicit shared contracts instead of relying only on broad integration review. https://docs.pact.io/
- Open Policy Agent: default-deny is useful for security, but its own FAQ notes it can be less suitable for incremental operational improvement because all allowed behavior must be enumerated up front. This supports fail-closed for critical authority, not for mere Card absence. https://www.openpolicyagent.org/docs/faq
- Playwright ARIA snapshots: runtime accessible structure can be compared against an expected snapshot, supporting post-render semantic verification independently from screenshot quality. https://playwright.dev/docs/aria-snapshots

## Next S26 gate

Do not declare Golden from this code change alone.

Required next evidence:
1. CI/readback of the branch with the expanded 18-case regression suite.
2. A fresh governed execution that binds a source-fidelity contract before UI Architect/Composer.
3. Independent semantic/visual review on that fresh execution.
4. Preserve Run F as historical negative evidence; do not mutate it to manufacture a pass.
