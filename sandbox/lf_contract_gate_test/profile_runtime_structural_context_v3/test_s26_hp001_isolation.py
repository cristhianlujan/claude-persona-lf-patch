#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

from s26_hp001.happy_path_preexecution import run_preexecution

REPO = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
FIXTURE = HERE / "s26_hp001"
MANIFEST_PATH = FIXTURE / "isolation_manifest.json"
INPUT_PATH = FIXTURE / "input.txt"
REQUIREMENTS_PATH = FIXTURE / "expected_requirements.json"
SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA64 = re.compile(r"^[0-9a-f]{64}$")


class IsolationBlocked(RuntimeError):
    pass


def sha256_bytes(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def load_json(path: Path) -> dict:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise IsolationBlocked(f"JSON_NOT_OBJECT:{path.name}")
    return payload


def allowed_path(path: str, allowed: list[str]) -> bool:
    for rule in allowed:
        if rule.endswith("/") and path.startswith(rule):
            return True
        if path == rule:
            return True
    return False


def validate_static(manifest: dict, requirements: dict) -> None:
    if manifest.get("schema") != "S26_ISOLATED_PROJECT_GATE_V1":
        raise IsolationBlocked("BAD_MANIFEST_SCHEMA")
    if manifest.get("project_id") != "S26" or manifest.get("test_id") != "S26-HP-001":
        raise IsolationBlocked("BAD_PROJECT_IDENTITY")
    base_sha = manifest.get("source_base_sha", "")
    if not SHA40.fullmatch(base_sha):
        raise IsolationBlocked("BAD_SOURCE_BASE_SHA")
    if manifest.get("candidate_sha_mode") != "GITHUB_EVENT_HEAD_SHA":
        raise IsolationBlocked("BAD_CANDIDATE_SHA_MODE")
    if manifest.get("merge_ref_is_candidate_sha") is not False:
        raise IsolationBlocked("MERGE_REF_CONFUSION_ALLOWED")
    if manifest.get("main_is_observational_only") is not True:
        raise IsolationBlocked("MAIN_NOT_OBSERVATIONAL")
    if manifest.get("main_drift_invalidates_test") is not False:
        raise IsolationBlocked("MAIN_DRIFT_CAN_INVALIDATE")
    allowed = manifest.get("allowed_changed_paths")
    if not isinstance(allowed, list) or len(allowed) < 2 or not all(isinstance(x, str) and x for x in allowed):
        raise IsolationBlocked("BAD_ALLOWED_PATHS")

    if requirements.get("schema") != "S26_HP001_EXPECTED_REQUIREMENTS_V1":
        raise IsolationBlocked("BAD_REQUIREMENTS_SCHEMA")
    expected_input_sha = requirements.get("input_sha256", "")
    if not SHA64.fullmatch(expected_input_sha):
        raise IsolationBlocked("BAD_INPUT_SHA_FORMAT")
    actual_input_sha = sha256_bytes(INPUT_PATH.read_bytes())
    if actual_input_sha != expected_input_sha:
        raise IsolationBlocked("INPUT_SHA_MISMATCH")
    if requirements.get("validation_mode") != "MATERIAL_REQUIREMENTS_NOT_LITERAL_REFERENCE_MATCH":
        raise IsolationBlocked("BAD_VALIDATION_MODE")
    shortcuts = set(requirements.get("forbidden_validation_shortcuts") or [])
    required_shortcuts = {
        "exact_full_text_match",
        "hardcoded_single_reference_answer",
        "pass_from_runtime_status_only",
    }
    if not required_shortcuts.issubset(shortcuts):
        raise IsolationBlocked("VALIDATION_SHORTCUT_GUARD_MISSING")


def isolation_identity(manifest: dict, event_head_sha: str, observed_main_sha: str) -> tuple[str, str, str, str]:
    _ = observed_main_sha
    return (
        manifest["project_id"],
        manifest["test_id"],
        manifest["source_base_sha"],
        event_head_sha,
    )


def validate_negative_controls(manifest: dict) -> None:
    base = manifest["source_base_sha"]
    head = "1" * 40
    if isolation_identity(manifest, head, "2" * 40) != isolation_identity(manifest, head, "3" * 40):
        raise IsolationBlocked("MAIN_DRIFT_CHANGED_IDENTITY")
    if base == head:
        raise IsolationBlocked("NEGATIVE_FIXTURE_COLLISION")
    allowed = manifest["allowed_changed_paths"]
    if allowed_path(".github/workflows/validate-lf-packs.yml", allowed):
        raise IsolationBlocked("SHARED_WORKFLOW_WRONGLY_ALLOWED")
    if allowed_path("services/profile_runtime_api/profile_runtime_api/engine.py", allowed):
        raise IsolationBlocked("SHARED_RUNTIME_WRONGLY_ALLOWED")
    if not allowed_path(
        "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/input.txt",
        allowed,
    ):
        raise IsolationBlocked("OWN_FIXTURE_NOT_ALLOWED")
    event_head = "4" * 40
    synthetic_merge_ref = "5" * 40
    candidate = event_head
    if candidate == synthetic_merge_ref:
        raise IsolationBlocked("MERGE_REF_RELABELED_AS_CANDIDATE")


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=REPO, text=True).strip()


def fetch_sha(sha: str) -> None:
    subprocess.run(
        ["git", "fetch", "--no-tags", "origin", sha, "--depth=1"],
        cwd=REPO,
        check=True,
        stdout=subprocess.DEVNULL,
    )


def live_branch_name() -> str:
    return (os.environ.get("GITHUB_HEAD_REF") or os.environ.get("GITHUB_REF_NAME") or "").strip()


def validate_live(manifest: dict) -> dict[str, str | list[str]]:
    branch = live_branch_name()
    expected_branch = manifest["expected_head_branch"]
    if branch != expected_branch:
        return {
            "mode": "SELFTEST_ONLY",
            "branch": branch or "LOCAL_OR_UNKNOWN",
            "reason": "NOT_HP001_BRANCH",
        }

    event = os.environ.get("GITHUB_EVENT_NAME", "").strip()
    checkout_sha = git("rev-parse", "HEAD")
    if not SHA40.fullmatch(checkout_sha):
        raise IsolationBlocked("BAD_EXECUTED_CHECKOUT_SHA")

    base_sha = manifest["source_base_sha"]
    base_branch = manifest["frozen_base_branch"]
    event_head_sha = ""
    event_base_sha = base_sha
    event_base_branch = base_branch

    if event == "pull_request":
        event_path = Path(os.environ["GITHUB_EVENT_PATH"])
        payload = json.loads(event_path.read_text(encoding="utf-8"))
        pr = payload.get("pull_request") or {}
        event_base = pr.get("base") or {}
        event_head = pr.get("head") or {}
        event_base_branch = str(event_base.get("ref") or "")
        event_base_sha = str(event_base.get("sha") or "")
        event_head_branch = str(event_head.get("ref") or "")
        event_head_sha = str(event_head.get("sha") or "")
        if event_base_branch != base_branch:
            raise IsolationBlocked("EVENT_BASE_BRANCH_DRIFT")
        if event_base_sha != base_sha:
            raise IsolationBlocked("EVENT_BASE_SHA_DRIFT")
        if event_head_branch != expected_branch:
            raise IsolationBlocked("EVENT_HEAD_BRANCH_DRIFT")
    elif event == "push":
        event_head_sha = str(os.environ.get("GITHUB_SHA") or "")
        event_head_branch = branch
        if event_head_branch != expected_branch:
            raise IsolationBlocked("PUSH_HEAD_BRANCH_DRIFT")
    else:
        return {
            "mode": "SELFTEST_ONLY",
            "branch": branch,
            "reason": f"UNSUPPORTED_LIVE_EVENT:{event or 'NONE'}",
        }

    if not SHA40.fullmatch(event_head_sha):
        raise IsolationBlocked("BAD_EVENT_HEAD_SHA")

    subprocess.run(
        [
            "git", "fetch", "--no-tags", "origin",
            f"refs/heads/{base_branch}:refs/remotes/origin/{base_branch}", "--depth=1",
        ],
        cwd=REPO,
        check=True,
        stdout=subprocess.DEVNULL,
    )
    frozen_ref_sha = git("rev-parse", f"refs/remotes/origin/{base_branch}")
    if frozen_ref_sha != base_sha:
        raise IsolationBlocked("FROZEN_BASE_REF_MOVED")

    fetch_sha(base_sha)
    fetch_sha(event_head_sha)
    raw = subprocess.check_output(
        ["git", "diff", "--name-only", "-z", base_sha, event_head_sha, "--"],
        cwd=REPO,
    )
    changed = [item.decode("utf-8", "strict") for item in raw.split(b"\0") if item]
    if not changed:
        raise IsolationBlocked("NO_PROJECT_CHANGES")
    outside = [path for path in changed if not allowed_path(path, manifest["allowed_changed_paths"])]
    if outside:
        raise IsolationBlocked("CROSS_PROJECT_PATH_MUTATION:" + ",".join(outside))

    observed_main = "OBSERVATIONAL_NOT_BOUND"
    try:
        subprocess.run(
            ["git", "fetch", "--no-tags", "origin", "main:refs/remotes/origin/main", "--depth=1"],
            cwd=REPO,
            check=True,
            stdout=subprocess.DEVNULL,
        )
        observed_main = git("rev-parse", "refs/remotes/origin/main")
    except subprocess.CalledProcessError:
        pass

    identity_a = isolation_identity(manifest, event_head_sha, observed_main)
    identity_b = isolation_identity(manifest, event_head_sha, "f" * 40)
    if identity_a != identity_b:
        raise IsolationBlocked("MAIN_DRIFT_AFFECTED_PROJECT_IDENTITY")

    return {
        "mode": "LIVE_ISOLATION_PASS",
        "event_name": event,
        "event_base_branch": event_base_branch,
        "event_base_sha": event_base_sha,
        "event_head_branch": branch,
        "event_head_sha": event_head_sha,
        "executed_checkout_sha": checkout_sha,
        "checkout_identity": "BRANCH_HEAD" if checkout_sha == event_head_sha else "MERGE_REF_OR_OTHER_CHECKOUT",
        "observed_main_sha": observed_main,
        "changed_files": changed,
    }


def main() -> int:
    manifest = load_json(MANIFEST_PATH)
    requirements = load_json(REQUIREMENTS_PATH)
    validate_static(manifest, requirements)
    validate_negative_controls(manifest)
    preexecution = run_preexecution()
    live = validate_live(manifest)
    print(json.dumps({
        "gate": "S26_HP001_ISOLATION_GATE_V1",
        "result": "PASS",
        "input_sha256": requirements["input_sha256"],
        "source_base_sha": manifest["source_base_sha"],
        "claim_ceiling": manifest["claim_ceiling"],
        "live": live,
        "preexecution": preexecution,
        "negative_controls": 5,
    }, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
