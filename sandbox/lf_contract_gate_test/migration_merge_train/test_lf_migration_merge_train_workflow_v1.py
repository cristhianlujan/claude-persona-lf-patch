#!/usr/bin/env python3
from pathlib import Path
import re

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
    "contents: write",
    "pull-requests: write",
    "issues: write",
    "actions: read",
    "checks: read",
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
    "LF_MIGRATION_TRAIN_MODE: REAL",
    "--paginate --slurp",
    "sleep 10",
    "GITHUB_STEP_SUMMARY",
    "git merge-tree --write-tree",
    "git commit-tree",
    "--force-with-lease",
    "PASS_TRAIN_SYNC_BRANCH_READBACK",
    "PASS_TRAIN_SYNC_PR_HEAD_READBACK",
    "FAIL_TRAIN_SYNC_PR_HEAD_UNEXPECTED",
    "FAIL_TRAIN_SYNC_PR_HEAD_READBACK_TIMEOUT",
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
assert "pulls/$PR/update-branch" not in wf
checks += 1

# Exact DB writes are only through the merged transport wrapper.
assert "apply_migration" not in wf
checks += 1
assert "--allow-fallback" in wf
checks += 1

# REAL uses App token to preserve active push->main workflows.
assert "actions/create-github-app-token@v2" in wf
checks += 1
assert "steps.app_token.outputs.token" in wf
checks += 1

# No fabricated final Saga closure.
assert "Final CONSISTENT is not fabricated" in wf
checks += 1

# Security lint: no github.event interpolation inside any run block.
lines = wf.splitlines()
run_blocks = []
i = 0
while i < len(lines):
    m = re.match(r"^(\s*)run:\s*\|\s*$", lines[i])
    if not m:
        i += 1
        continue
    indent = len(m.group(1))
    block = []
    i += 1
    while i < len(lines):
        line = lines[i]
        if line.strip() and (len(line) - len(line.lstrip())) <= indent:
            break
        block.append(line)
        i += 1
    run_blocks.append("\n".join(block))

assert run_blocks
for index, block in enumerate(run_blocks, start=1):
    assert "${{ github.event" not in block, f"github.event interpolation in run block {index}"
checks += 1

# PR metadata enters via env and is consumed as quoted shell variables.
for marker in (
    "HEAD_REPOSITORY: ${{ github.event.pull_request.head.repo.full_name }}",
    "BASE_REF: ${{ github.event.pull_request.base.ref }}",
    "PR_NUMBER: ${{ github.event.pull_request.number }}",
    "PR_HEAD_SHA: ${{ github.event.pull_request.head.sha }}",
    "PR_HEAD_REF: ${{ github.event.pull_request.head.ref }}",
):
    assert marker in wf, marker
checks += 1

# DRY_RUN report must be read-only and summary/log-only.
dry = wf.split("- name: Report DRY-RUN plan", 1)[1].split("- name: Retimestamp migration atomically", 1)[0]
assert "gh api" not in dry
assert "--method POST" not in dry
assert "--method DELETE" not in dry
assert "GITHUB_STEP_SUMMARY" in dry
assert "No GitHub write, no DB write" in dry
assert "`$TARGET_PATH`" not in dry
checks += 1

# Sync push readback tolerates only the known stale PR head, never an unexpected third SHA.
sync = wf.split("- name: Sync PR branch with current main in REAL mode", 1)[1].split(
    "- name: Resolve exact PR files and migration blob", 1
)[0]
assert "PR: ${{ steps.admission.outputs.pr_number }}" in sync
assert 'git ls-remote origin "refs/heads/$HEAD_REF"' in sync
assert "for attempt in $(seq 1 10)" in sync
assert "sleep 2" in sync
assert "FAIL_TRAIN_SYNC_PR_HEAD_UNEXPECTED" in sync
assert "FAIL_TRAIN_SYNC_PR_HEAD_READBACK_TIMEOUT" in sync
assert sync.index("git push --force-with-lease") < sync.index("PASS_TRAIN_SYNC_BRANCH_READBACK")
assert sync.index("PASS_TRAIN_SYNC_BRANCH_READBACK") < sync.index("PASS_TRAIN_SYNC_PR_HEAD_READBACK")
checks += 1

# DRY_RUN failure path is read-only; GitHub mutation exists only under REAL.
assert "if: failure() && env.LF_MIGRATION_TRAIN_MODE == 'REAL'" in wf
assert "if: failure() && env.LF_MIGRATION_TRAIN_MODE == 'DRY_RUN'" in wf
checks += 1

# F09-X16: versioned main check list, exact-head, conclusion=success.
guard_path = ROOT / "sandbox/lf_contract_gate_test/migration_merge_train/lf_train_required_check_guard.py"
guard = guard_path.read_text(encoding="utf-8")
assert "lf_train_required_check_guard.py" in wf
for marker in (
    'DEFAULT_CHECKS_FILE = Path(__file__).with_name("lf_train_required_pre_apply_checks_v1.json")',
    'def load_required_checks(',
    'required_checks: tuple[str, ...]',
    'observed_head != expected_head',
    'conclusion != "success"',
    '"{code}_TRAIN_REQUIRED_CHECK_MISSING check={name}"',
    "FAIL_TRAIN_REQUIRED_CHECK_NOT_SUCCESS",
):
    assert marker in guard, marker
    checks += 1
assert 'for attempt in $(seq 1 90); do' in wf
assert 'if [ "$attempt" -eq 90 ]; then guard_args+=(--final); fi' in wf
assert "guard_args+=(--final)" in wf
assert 'python3 sandbox/lf_contract_gate_test/migration_merge_train/lf_train_required_check_guard.py' in wf
assert '--checks-file sandbox/lf_contract_gate_test/migration_merge_train/lf_train_required_pre_apply_checks_v1.json' in wf
assert 'checks="$(gh api --paginate --slurp "repos/$REPO/commits/$EXPECTED_HEAD/check-runs?per_page=100")"' in wf
assert 'conclusion!="skipped"' not in wf
checks_config = (ROOT / "sandbox/lf_contract_gate_test/migration_merge_train/lf_train_required_pre_apply_checks_v1.json").read_text(encoding="utf-8")
assert '"lf-independent-change-admission"' in checks_config
assert '"ig-runtime-candidate-judge"' in checks_config
assert 'lf_train_required_pre_apply_checks_v1.json' in guard
checks += 1

print(f"PASS_MIGRATION_MERGE_TRAIN_WORKFLOW_CONTRACT={checks}/{checks}")

