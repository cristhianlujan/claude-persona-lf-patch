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

The App pin is `integration_id: 5203655`, slug `lf-migration-train`. Evidence:
comments by `lf-migration-train[bot]` on PR #2355 expose
`performed_via_github_app = {id: 5203655, slug: "lf-migration-train"}`;
the same bot (user id `338337340`) publishes `lf-merge-train/verified` on
Train merges #2355 and #2408.

## Workflow and tests

- Workflow: `.github/workflows/lf-migration-route-guard.yml`.
- Pure Python classifier and REST adapter:
  `sandbox/lf_contract_gate_test/migration_route_guard/lf_migration_route_guard.py`.
- Unit tests:
  `sandbox/lf_contract_gate_test/migration_route_guard/test_lf_migration_route_guard.py`.
- Events: `opened`, `reopened`, `synchronize`, `ready_for_review`, and
  `edited` for base `main`, plus `workflow_dispatch` with one or more
  comma/space separated PR numbers for backfill.
- No `paths` trigger filter is used.
- Opening or updating a PR with `GITHUB_TOKEN` does not trigger this guard
  automatically; dispatch the workflow manually for those PRs.

The `pull_request_target` job uses the base ref `refs/heads/main`. The
`lf-merge-train` environment admits that event/ref: the Train completed runs
and merges for PRs #2355 and #2408 using this environment.

## Strict status checks and branch freshness

`protect-main` already has
`strict_required_status_checks_policy: true`, but it currently has no effect
while `required_status_checks` is empty. Once
`lf-merge-train/verified` is required, every PR must be up to date with
`main` before merge.

The Train already satisfies this through its `sync merge train with main`
step. For a regular PR, use GitHub's **Update branch** action when it is behind.
That update produces a new PR head and re-triggers the guard through
`synchronize`.

## Activation payload

The exact Train App `integration_id` is `5203655` (slug
`lf-migration-train`), confirmed by `performed_via_github_app` on bot
comments in PR #2355 and by its status publications on Train merges #2355 and
#2408. Do not substitute the GitHub Actions App ID. The pin prevents an
identically named status from `GITHUB_TOKEN` from satisfying the check.

The activation payload is
`docs/migrations/protect-main-migration-train-route-guard-v2.json`. Preserve
the current `protect-main` rules and set `bypass_actors: []`; require only:

```json
{
  "type": "required_status_checks",
  "parameters": {
    "strict_required_status_checks_policy": true,
    "do_not_enforce_on_create": false,
    "required_status_checks": [
      {
        "context": "lf-merge-train/verified",
        "integration_id": 5203655
      }
    ]
  }
}
```

### Backfill order and scope

Backfill is needed only for open PRs against `main` that are already up to
date with `main` when the check is activated. A PR that is behind cannot merge
under strict checks; after **Update branch**, its new head automatically
re-triggers the guard and receives the status if it has no migration.

Select only the up-to-date PRs for the dispatch; review the resulting number
list before running it:

```bash
PR_NUMBERS="$(gh pr list --state open --base main --json number,mergeStateStatus --jq '[.[] | select(.mergeStateStatus != null and .mergeStateStatus != "BEHIND" and .mergeStateStatus != "UNKNOWN") | .number | tostring] | join(",")')"
gh workflow run lf-migration-route-guard.yml --ref main -f pr_number="$PR_NUMBERS"
```

Because events caused by `GITHUB_TOKEN` do not trigger the guard, manually
include any otherwise eligible PR opened or updated with that token. Wait for
the dispatch to finish and review its summaries before applying the ruleset.

## Canary checks

After activation:

1. A PR without migrations receives the App-published success automatically.
2. A PR with a migration and no Train status is blocked from manual merge; after
   `ready-to-merge`, the Train publishes status on the exact head and merges it.
3. Adding a migration in a new commit leaves the new head blocked until Train
   admission.

## Rollback

The rollback is the current ruleset configuration, with
`strict_required_status_checks_policy: true` and
`required_status_checks: []`. Remove only
`lf-merge-train/verified` from the required list; retain all other rules,
conditions, enforcement, and `bypass_actors: []`. The exact rollback object is
included in the `rollback` section of the JSON activation payload.

## Known Train risk (not changed in this patch)

The current Train step `Publish lf-merge-train/verified in DRY_RUN` publishes
success before admission. If the mode changes to `DRY_RUN`, a migration PR
could receive the required App status and be merged manually. The Train
workflow is out of scope here; correct this risk in the separate Train work
before using `DRY_RUN` with `protect-main` enforcement.
