#!/usr/bin/env python3
"""Fail-closed scope tests for the salvaged PR56 shared operational protocol."""

from __future__ import annotations

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = ROOT / "scripts" / "lf_contract_check.py"

spec = importlib.util.spec_from_file_location("lf_contract_check", VALIDATOR)
if spec is None or spec.loader is None:
    raise SystemExit("BLOCKED: cannot load lf_contract_check")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

approved = [
    "CLAUDE.md",
    ".claude/operational-execution.md",
    ".claude/scripts/validate_artifact_output.py",
]
rejected = [
    "CLAUDE.md.bak",
    ".claude/operational-execution.md.bak",
    ".claude/operational-execution/child.md",
    ".claude/scripts/validate_artifact_output.py.bak",
    ".claude/scripts/extra.py",
    ".claude/other.md",
]

checks: list[tuple[str, bool]] = []
for path in approved:
    checks.append((f"approved_exact:{path}", module.is_allowed_path(path)))
for path in rejected:
    checks.append((f"rejected_lookalike:{path}", not module.is_allowed_path(path)))

checks.append(("dot_claude_not_prefix_allowed", ".claude/" not in module.ALLOWED_PREFIXES))
checks.append(("root_claude_md_exact_only", "CLAUDE.md" in module.ALLOWED_EXACT))

failed = [name for name, passed in checks if not passed]
if failed:
    raise SystemExit("FAIL_PR56_OPERATIONAL_SCOPE=" + ",".join(failed))

print(f"PASS_PR56_OPERATIONAL_SCOPE={len(checks)}/{len(checks)}")
