#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
wf = (ROOT / ".github/workflows/lf-migration-merge-train.yml").read_text(encoding="utf-8")
checks = 0

for marker in (
    "pull_request_target:",
    "types: [labeled]",
    "group: lf-migrations",
    "queue: max",
    "cancel-in-progress: false",
    "ready-to-merge",
    "refs/heads/main",
    "contents: read",
    "supabase/setup-cli@v1",
    "postgresql-client",
    "lf_migration_assign_version.py",
    "lf_migration_version_order_check.py",
    "lf_migration_git_persist.py",
    "lf_migration_exact_apply.py",
    "lf_migration_orchestrated_saga.py",
    "run_migration_source_parity_focal_v1.py",
    'status=="READY_TO_APPLY"',
    "POST-APPLY STOP",
    "LF_MIGRATION_TRAIN_APP_ID",
    "LF_MIGRATION_TRAIN_APP_PRIVATE_KEY",
    "PASE-GLOBAL-04",
    "LF_MIGRATION_TRAIN_MODE: DRY_RUN",
    "--paginate --slurp",
    "sleep 10",
):
    assert marker in wf, marker
    checks += 1

# pull_request_target is privileged: PR code must never be checked out/executed.
assert "ref: ${{ github.event.pull_request.head.sha }}" not in wf
checks += 1
assert "gh pr checkout" not in wf
checks += 1
assert "actions/checkout@v4" in wf and "ref: refs/heads/main" in wf
checks += 1

# Exact DB writes are only through the merged transport wrapper.
assert "apply_migration" not in wf
checks += 1
assert "--allow-fallback" in wf
checks += 1

# Source mutation/merge in REAL uses a GitHub App so generated events can run CI.
assert "actions/create-github-app-token@v2" in wf
checks += 1
assert "steps.app_token.outputs.token" in wf
checks += 1

# No fabricated final Saga closure.
assert "Final CONSISTENT is not fabricated" in wf
checks += 1

assert "WARN_TRAIN_COMMENT_UNAVAILABLE" in wf
checks += 1
assert 'migration objetivo=$TARGET_PATH' in wf
checks += 1
assert 'migration objetivo `$TARGET_PATH`' not in wf
checks += 1

print(f"PASS_MIGRATION_MERGE_TRAIN_WORKFLOW_CONTRACT={checks}/35")
