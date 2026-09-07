#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import subprocess
import tempfile
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("supabase_control_plane_scope.py")
spec = importlib.util.spec_from_file_location("supabase_control_plane_scope", MODULE_PATH)
if spec is None or spec.loader is None:
    raise SystemExit("FAIL_SUPABASE_CONTROL_PLANE_SCOPE_MODULE_LOAD")
scope = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scope)

CASES = [
    ("story_only", "pull_request", ["skills/creating-integral-user-stories/scripts/validate_test_coverage.py"], False),
    ("unrelated_contract_sandbox", "pull_request", ["sandbox/lf_contract_gate_test/input_governance_s28/example.sql"], False),
    ("scope_selftest_only", "pull_request", ["sandbox/lf_contract_gate_test/supabase_control_plane_scope_selftest.py"], False),
    ("workflow_self_change", "pull_request", [".github/workflows/lf-contract-check.yml"], True),
    ("classifier_self_change", "pull_request", ["sandbox/lf_contract_gate_test/supabase_control_plane_scope.py"], True),
    ("supabase_config", "pull_request", ["supabase/config.toml"], True),
    ("versioned_migration", "pull_request", ["supabase/migrations/20260907010101_security_v9.sql"], True),
    ("nested_migration_family", "pull_request", ["supabase/migrations/archive/20260907010101_security_v9.sql"], True),
    ("mixed_story_migration", "pull_request", ["skills/creating-integral-user-stories/SKILL.md", "supabase/migrations/20260907010102_x.sql"], True),
    ("mixed_story_classifier", "pull_request", ["skills/creating-integral-user-stories/SKILL.md", "sandbox/lf_contract_gate_test/supabase_control_plane_scope.py"], True),
    ("lookalike_not_family", "pull_request", ["supabase/migrationz/20260907010103_x.sql"], False),
    ("edge_function_not_postgrest_schema_config", "pull_request", ["supabase/functions/example/index.ts"], False),
    ("manual_audit", "workflow_dispatch", [], True),
    ("missing_scope_fail_closed", "pull_request", [], True),
    ("invalid_traversal_fail_closed", "pull_request", ["../supabase/config.toml"], True),
]

passed = 0
for name, event, paths, expected in CASES:
    result = scope.classify_control_plane_scope(event, paths)
    actual = bool(result["required"])
    if actual != expected:
        raise SystemExit(
            f"FAIL_SUPABASE_CONTROL_PLANE_SCOPE_CASE name={name} expected={expected} actual={actual} result={result}"
        )
    passed += 1

# Real git-topology negative: a migration renamed outside the protected prefix
# must still show the old migration path because discovery uses --no-renames.
with tempfile.TemporaryDirectory(prefix="lf-cp-scope-") as tmp:
    root = Path(tmp)
    subprocess.run(["git", "init", "-q"], cwd=root, check=True)
    subprocess.run(["git", "config", "user.email", "ci@example.invalid"], cwd=root, check=True)
    subprocess.run(["git", "config", "user.name", "LF CI"], cwd=root, check=True)
    migration = root / "supabase/migrations/20260907010104_move_me.sql"
    migration.parent.mkdir(parents=True)
    migration.write_text("select 1;\n", encoding="utf-8")
    subprocess.run(["git", "add", "."], cwd=root, check=True)
    subprocess.run(["git", "commit", "-qm", "base"], cwd=root, check=True)
    base = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    target = root / "docs/moved.sql"
    target.parent.mkdir(parents=True)
    subprocess.run(["git", "mv", str(migration.relative_to(root)), str(target.relative_to(root))], cwd=root, check=True)
    subprocess.run(["git", "commit", "-qm", "rename"], cwd=root, check=True)
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    changed = scope.changed_paths_between(base, head, cwd=root)
    if "supabase/migrations/20260907010104_move_me.sql" not in changed:
        raise SystemExit(f"FAIL_SUPABASE_CONTROL_PLANE_SCOPE_RENAME_OLD_PATH_MISSING changed={changed}")
    result = scope.classify_control_plane_scope("pull_request", changed)
    if not result["required"]:
        raise SystemExit(f"FAIL_SUPABASE_CONTROL_PLANE_SCOPE_RENAME_BYPASS result={result}")
    passed += 1

print(f"PASS_SUPABASE_CONTROL_PLANE_SCOPE_SELFTEST={passed}/{len(CASES)+1}")
