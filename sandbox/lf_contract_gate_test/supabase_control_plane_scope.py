#!/usr/bin/env python3
"""Classify whether lf-contract-check must read Supabase Management API state.

The hosted PostgREST exposed-schema readback is a remote security control. It is
required when the candidate can change that control surface, when it can change
the classifier/gate itself, on explicit manual audits, or when changed-file
scope cannot be established safely. It is not a functional dependency of
unrelated semantic or sandbox evidence changes.
"""
from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path
from typing import Iterable, Mapping

CONTROL_PLANE_EXACT = frozenset(
    {
        "supabase/config.toml",
        ".github/workflows/lf-contract-check.yml",
        "sandbox/lf_contract_gate_test/supabase_control_plane_scope.py",
    }
)
CONTROL_PLANE_PREFIXES = ("supabase/migrations/",)


def _normalize(path: str) -> str:
    value = str(path).strip().replace("\\", "/")
    if not value or value.startswith("/"):
        raise ValueError(f"invalid repo path: {path!r}")
    parts = value.split("/")
    if any(part in {"", ".", ".."} for part in parts):
        raise ValueError(f"invalid repo path: {path!r}")
    return value


def classify_control_plane_scope(event_name: str, changed_paths: Iterable[str]) -> dict:
    event = (event_name or "").strip()
    if event == "workflow_dispatch":
        return {
            "required": True,
            "reason": "MANUAL_DISPATCH_FULL_SECURITY_READBACK",
            "matched_paths": [],
        }

    normalized: list[str] = []
    try:
        normalized = sorted({_normalize(path) for path in changed_paths})
    except ValueError:
        return {
            "required": True,
            "reason": "INVALID_CHANGED_PATH_FAIL_CLOSED",
            "matched_paths": [],
        }

    if not normalized:
        return {
            "required": True,
            "reason": "NO_CHANGED_PATHS_FAIL_CLOSED",
            "matched_paths": [],
        }

    matched = [
        path
        for path in normalized
        if path in CONTROL_PLANE_EXACT
        or any(path.startswith(prefix) for prefix in CONTROL_PLANE_PREFIXES)
    ]
    if matched:
        return {
            "required": True,
            "reason": "SUPABASE_CONTROL_SURFACE_CHANGED",
            "matched_paths": matched,
        }

    return {
        "required": False,
        "reason": "NO_SUPABASE_CONTROL_SURFACE_CHANGE",
        "matched_paths": [],
    }


def _run_git(args: list[str], cwd: str | Path | None = None) -> str:
    return subprocess.check_output(
        ["git", *args], cwd=cwd, text=True, stderr=subprocess.STDOUT
    ).strip()


def changed_paths_between(base: str, head: str, cwd: str | Path | None = None) -> list[str]:
    # --no-renames is intentional: a migration renamed out of the governed
    # prefix must still expose the deleted old path and therefore require the
    # remote control-plane gate.
    output = _run_git(["diff", "--name-only", "--no-renames", base, head, "--"], cwd=cwd)
    return [line.strip() for line in output.splitlines() if line.strip()]


def _event_payload(env: Mapping[str, str]) -> dict:
    path = env.get("GITHUB_EVENT_PATH", "").strip()
    if not path:
        return {}
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def discover_changed_paths(event_name: str, env: Mapping[str, str] | None = None) -> list[str]:
    env = env or os.environ
    event = (event_name or "").strip()

    if event == "workflow_dispatch":
        return []

    if event == "pull_request":
        base_ref = env.get("GITHUB_BASE_REF", "main").strip() or "main"
        return changed_paths_between(f"origin/{base_ref}", "HEAD")

    if event == "push":
        payload = _event_payload(env)
        before = str(payload.get("before") or "").strip()
        after = str(payload.get("after") or env.get("GITHUB_SHA") or "HEAD").strip()
        if before and not set(before) <= {"0"}:
            return changed_paths_between(before, after)
        return changed_paths_between("HEAD~1", "HEAD")

    return changed_paths_between("HEAD~1", "HEAD")


if __name__ == "__main__":
    event = os.environ.get("GITHUB_EVENT_NAME", "")
    paths = discover_changed_paths(event)
    print(json.dumps(classify_control_plane_scope(event, paths), sort_keys=True))
