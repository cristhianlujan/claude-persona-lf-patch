#!/usr/bin/env python3
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
wf=(ROOT/".github/workflows/lf-migration-merge-train.yml").read_text(encoding="utf-8")
checks=0
for marker in (
    "pull_request_target:",
    "types: [labeled]",
    "group: lf-migrations",
    "queue: max",
    "cancel-in-progress: false",
    "ready-to-merge",
    "refs/heads/main",
    "lf_migration_assign_version.py",
    "lf_migration_version_order_check.py",
    "lf_migration_git_persist.py",
    "lf_migration_exact_apply.py",
    "lf_migration_orchestrated_saga.py",
    "LF_MIGRATION_TRAIN_APP_ID",
    "LF_MIGRATION_TRAIN_APP_PRIVATE_KEY",
):
    assert marker in wf, marker
    checks+=1

assert "apply_migration" not in wf
checks+=1
assert "ref: ${{ github.event.pull_request.head.sha }}" not in wf
checks+=1
assert "gh pr checkout" not in wf
checks+=1
assert "LF_MIGRATION_TRAIN_MODE: DRY_RUN" in wf
checks+=1
assert "BLOCK_REAL_MODE_NOT_ARMED_UNTIL_FASE5" in wf
checks+=1
assert "PASE-GLOBAL-04" in wf
checks+=1
print(f"PASS_MIGRATION_MERGE_TRAIN_WORKFLOW_CONTRACT={checks}/20")
