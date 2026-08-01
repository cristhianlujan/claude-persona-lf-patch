# Architecture V7 hardening readback

Date: 2026-08-01

Supabase project: `mhwmirqcgxxukpctffuv`
Repository: `cristhianlujan/claude-persona-lf-patch`

## Applied controls

- `anon` cannot execute `promote_lf_artifact_pass_v3`.
- `authenticated` cannot execute `promote_lf_artifact_pass_v3`.
- `service_role` remains the only API role allowed to execute promotion.
- `anon` cannot execute `sync_lf_artifact_content_from_repository_v3`.
- `anon` cannot execute `get_lf_github_reconciliation_inventory_v3`.
- `anon` and `service_role` cannot execute the architecture monitor directly.
- Effective PASS now requires native GitHub branch protection status `VERIFIED`.
- `VERIFIED_COMPENSATING_CONTROLS` no longer produces effective PASS.
- Promotion requires:
  - `service_role` JWT request context;
  - the latest authoritative reconciliation;
  - the same execution identity for reconciliation and gate tests;
  - native branch protection readback `VERIFIED`;
  - non-future evidence timestamps;
  - token-authenticated reconciliation and gate evidence.
- The canonical closure view now counts the actual native branch protection state.

## Current readback

| Metric | Value |
|---|---:|
| Artifact count | 64 |
| Effective PASS_V3 | 0 |
| Judge count | 13 |
| Judges PASS_V3 | 0 |
| Native branch-protection gaps | 64 |
| Schema drift gaps | 6 |
| Failed latest gate tests | 0 |
| Closure ready | false |
| Canonical status | `NOT_READY` |

The previous `PASS_V6` is no longer accepted by the canonical view.

## Remaining blockers

### GitHub ruleset

`main` still requires a native ruleset with:

- pull request required;
- at least one independent approval;
- required check `lf-contract-check`;
- strict status checks;
- no bypass actors;
- force-push blocked;
- deletion blocked.

### Edge Function writer credential

`lf-github-reconcile-v3` version 5 still contains a static writer credential in deployed source. It must be rotated and moved to managed secrets, then bound to nonce and expiry controls.

### `net` schema ACL

The `net` schema grants were issued by `supabase_admin`. The production migration role cannot revoke those grants. Current readback still shows `USAGE` for `PUBLIC`, `anon`, `authenticated`, and `service_role`. This requires a Supabase control-plane or `supabase_admin` change.

### Baseline

The intentional V7 function, ACL, and view changes currently produce six schema drift gaps. A new reviewed baseline must be generated only after this PR is approved and merged.

## Verdict

`NOT_READY`

The public promotion vulnerability is contained, but closure remains blocked until the native GitHub ruleset, Edge secret rotation, `net` ACL correction, independent review, and post-merge baseline refresh are completed.
