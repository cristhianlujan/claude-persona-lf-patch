#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

EDGE_CALL_RE = re.compile(r'callRuntime\(\s*["\']([^"\']+)["\']')
SUPABASE_EDGE_URL_RE = re.compile(r'/functions/v1/([A-Za-z0-9._-]+)')
LOCAL_REUSABLE_RE = re.compile(r'^\s*uses:\s*(?:\./)?\.github/workflows/([^@\s]+)(?:@[^\s]+)?\s*$', re.M)
REMOTE_REUSABLE_RE = re.compile(r'^\s*uses:\s*([^\s]+/\.github/workflows/[^@\s]+)@([^\s]+)\s*$', re.M)
WORKFLOW_CALL_RE = re.compile(r'(?m)^\s{0,2}workflow_call:\s*$')


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    root = Path(args.repo_root).resolve()
    caller_path = root / "supabase/functions/lf-profiles-governance-caller-v1/index.ts"
    workflows_dir = root / ".github/workflows"
    reusable_name = "lf-input-governance-recurate.yml"

    caller = read(caller_path)
    edge_destinations = sorted(set(EDGE_CALL_RE.findall(caller)))

    workflows = []
    callers_of_reusable = []
    for path in sorted(list(workflows_dir.glob("*.yml")) + list(workflows_dir.glob("*.yaml"))):
        text = read(path)
        edge_calls = sorted(set(SUPABASE_EDGE_URL_RE.findall(text)))
        local_calls = sorted(set(LOCAL_REUSABLE_RE.findall(text)))
        remote_calls = sorted(set(f"{p}@{ref}" for p, ref in REMOTE_REUSABLE_RE.findall(text)))
        declares_workflow_call = bool(WORKFLOW_CALL_RE.search(text))
        rel = path.relative_to(root).as_posix()
        workflows.append({
            "path": rel,
            "declares_workflow_call": declares_workflow_call,
            "edge_calls": edge_calls,
            "local_reusable_calls": local_calls,
            "remote_reusable_calls": remote_calls,
        })
        if reusable_name in local_calls or any(
            f"/.github/workflows/{reusable_name}@" in item for item in remote_calls
        ):
            callers_of_reusable.append(rel)

    result = {
        "schema_version": "lf-inv-caller-workflow-call-extraction/v1",
        "source": {
            "caller": caller_path.relative_to(root).as_posix(),
            "workflows_dir": workflows_dir.relative_to(root).as_posix(),
        },
        "caller_edge_destinations": edge_destinations,
        "workflows": workflows,
        "reusable_workflow": {
            "path": f".github/workflows/{reusable_name}",
            "callers_in_main_tree": sorted(callers_of_reusable),
        },
    }

    if args.json:
        print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    else:
        print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
