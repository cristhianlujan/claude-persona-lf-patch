# LF Profile Runtime Transport Policy v1

Status: CANDIDATE / SOURCE-ENFORCED / NOT YET LIVE-DEPLOYED

## Canonical roles

- `HETZNER` is the authoritative/default profile runtime transport.
- `GITHUB_ACTIONS` is backup/fallback only.
- No request may be silently downgraded from `HETZNER` to `GITHUB_ACTIONS`.
- A missing governed `runtime_request_envelope` is a producer defect and must fail closed; it is not a reason to choose the backup transport automatically.

## Test rule

Production-equivalent, performance, quality, depth, and end-to-end canaries must run through the primary path:

`Router -> Input Governance -> governed runtime_request_envelope -> Supabase -> HETZNER worker -> Profile Runtime API -> llama-server -> validators -> durable readback`.

A GitHub-hosted model execution is valid evidence only when the test is explicitly about backup/recovery behavior. It must never be used as evidence for primary-path E2E latency or readiness.

## Primary-path acceptance evidence

A primary E2E result must show all of the following:

- `runtime_target = HETZNER`
- `runtime_provider = hetzner_profile_runtime_api`
- `runtime_request_envelope is not null`
- `github_run_id is null`
- governed artifact binding and Input Governance receipt remain current
- validator/quality/depth gates remain equivalent or better
- durable Supabase readback exists

## Backup evidence

A GitHub Actions execution is explicitly backup-only. Its measurements must be labeled as backup transport and cannot be mixed into primary performance baselines.

## Fail-closed invariant

The database route function must never contain an automatic assignment equivalent to:

`new.runtime_target := 'GITHUB_ACTIONS'`

when the request was intended for `HETZNER`. CI validates this invariant for current and future migrations.
