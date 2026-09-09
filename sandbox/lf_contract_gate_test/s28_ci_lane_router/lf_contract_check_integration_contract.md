# S28 CI lane isolation — integration contract

## Problem
`protect-main` requires the `lf-contract-check` status for every PR. The current DEEP path runs LF migration source parity for every non-FAST_P0_DOCS change, so an unrelated migration-lane drift can block S30, profiles, UI, or other independent work.

## Required behavior
Keep the same required status context `lf-contract-check`. Do not weaken the ruleset and do not convert an applicable failure into PASS.

The canonical preflight must classify changed paths with `scripts/lf_ci_lane_router.py` and expose at least:
- `migration_parity_required`
- `input_governance_migration_parity_required`
- `ci_router_self_test_required`
- `s30_policy_lane`
- `deep_shared_required`

Then:
- `Enforce LF migration source parity after checkpoint` runs only when `migration_parity_required == true`.
- `Enforce Input Governance migration source parity` runs only when `input_governance_migration_parity_required == true`.
- A skipped non-applicable lane is reported as `NOT_APPLICABLE`, never `PASS`.
- Any migration-owned file or migration-parity validator change keeps migration parity mandatory and fail-closed.
- Unknown paths remain `DEEP_SHARED`; they cannot silently enter a fast lane.
- Changes to the lane router/workflow require the deterministic lane-router self-test.

## Bootstrap constraint
This candidate does not modify the required workflow yet. Integration into `.github/workflows/lf-contract-check.yml` is a separate bounded patch after this classifier passes its own canary. That prevents changing the mandatory gate before its applicability logic is independently proven.

## Acceptance matrix
| Change | Migration parity | Input Governance parity | Shared deep |
|---|---|---|---|
| S30 policy-only | NOT_APPLICABLE | NOT_APPLICABLE | false |
| general migration | REQUIRED | as classified | false/other lanes |
| Input Governance migration | REQUIRED | REQUIRED | false/other lanes |
| migration parity validator | REQUIRED | as classified | false |
| unknown surface | NOT_APPLICABLE | NOT_APPLICABLE | true |
| CI lane-router source | NOT_APPLICABLE | NOT_APPLICABLE | self-test required |
| S30 + migration mixed PR | REQUIRED | as classified | other lanes preserved |
