# Migration route guard — mandatory Train status (F2)

## Purpose and boundary

`lf-merge-train/verified` is the only required `protect-main` status. The LF
Migration Train App publishes it for migration PRs after admission and on the
exact head it is about to merge. This workflow publishes the same status only
for an open PR against `main` whose complete changed-file list contains no
path in `supabase/migrations/`.

The guard has no database credentials or database effects. It does not check
out PR content. Its classifier is fetched through the GitHub contents API at
the workflow's trusted base SHA. Read-only PR metadata and file-list calls use
the workflow token; the App installation token has only `statuses: write` and
publishes the status from the `lf-merge-train` environment.

For an added, modified, removed, or renamed migration path, or an incomplete or
capped file list, the workflow publishes nothing in
`lf-merge-train/verified`. It does not post `pending` or `failure` in that
context. Before publishing the non-migration success it re-reads the PR and
requires the same head SHA.

## Workflow and tests

- Workflow: `.github/workflows/lf-migration-route-guard.yml`.
- Pure Python classifier and REST adapter:
  `sandbox/lf_contract_gate_test/migration_route_guard/lf_migration_route_guard.py`.
- Unit tests:
  `sandbox/lf_contract_gate_test/migration_route_guard/test_lf_migration_route_guard.py`.
- Events: `opened`, `reopened`, `synchronize`, `ready_for_review`, and `edited`
  for base `main`, plus `workflow_dispatch` with one or more comma/space
  separated PR numbers for the backfill.
- No `paths` trigger filter is used.

The job's `pull_request_target` ref is the base branch ref. For a PR targeting
`main`, it is `refs/heads/main`, the same ref family used by the Train workflow's
`lf-merge-train` environment. Confirm the environment's branch policy still
allows `main` before enabling the required check.

## `protect-main` activation payload

Before applying, resolve the numeric integration ID for the LF Migration Train
GitHub App from the configured `LF_MIGRATION_TRAIN_APP_ID`. Do not substitute
the GitHub Actions App ID. Apply only after backfill and owner review. The
ruleset API update must retain its current deletion, non-fast-forward, pull
request, conditions, and enforcement settings, and set:

```json
{
  "bypass_actors": [],
  "rules": [
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "do_not_enforce_on_create": false,
        "required_status_checks": [
          {
            "context": "lf-merge-train/verified",
            "integration_id": 0
          }
        ]
      }
    }
  ]
}
```

In the API payload, replace `0` with the numeric integration ID for the Train
App. Preserve the other existing rules unchanged. The committed ruleset template
is `docs/migrations/protect-main-migration-train-route-guard-v2.json`.

## Backfill, canaries, and rollback

1. After this workflow is on `main`, dispatch it once with every open PR whose
   base is `main`, before requiring the status. This supplies the success status
   to currently open migration-free PRs; migration PRs remain without this
   guard status unless the Train publishes it.
2. Activate the required check only after backfill completes and its results
   are reviewed.
3. Verify three canaries: a PR with no migration receives the App-published
   success automatically; a migration PR without Train status is blocked and
   the same PR merges only through `ready-to-merge` and the Train; adding a
   migration in a new commit leaves the new head blocked without a Train status.
4. Rollback is one ruleset update: remove the
   `lf-merge-train/verified` required status check. Keep all other rules and
   `bypass_actors: []` unchanged.

## Known Train risk (not changed in this patch)

The current Train step `Publish lf-merge-train/verified in DRY_RUN` publishes
success before admission. If the mode changes to `DRY_RUN`, a migration PR could
receive the required App status and be merged manually. The Train workflow is
out of scope here; this risk must be corrected in the separate Train work before
using DRY_RUN with `protect-main` enforcement.
