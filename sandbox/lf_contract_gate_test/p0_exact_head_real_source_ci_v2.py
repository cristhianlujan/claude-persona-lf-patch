#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

import p0_exact_head_real_source_ci_v1 as legacy

CONFIG_PATH = Path(__file__).with_name("p0_exact_head_real_source_v2.json")
POLICY_TEST_PATH = legacy.REPO_ROOT / "supabase/functions/lf-p0-exact-head-evidence-broker-v2/policy_test.mjs"
SUMMARY_PATH = legacy.REPO_ROOT / ".audit-output/creating-integral-user-stories/p0-exact-head-real-source-summary.json"
GOVERNED_REF_RE = re.compile(r"^refs/heads/lf/p0-[A-Za-z0-9._/-]+$")


def governed_ref(ref: str) -> bool:
    return ref == "refs/heads/main" or bool(GOVERNED_REF_RE.fullmatch(ref or ""))


def load_config() -> dict:
    try:
        config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        legacy.die("FAIL_P0_EXACT_HEAD_V2_CONFIG_INVALID", type(exc).__name__)
    if config.get("schema_version") != "p0-exact-head-real-source-config/v2":
        legacy.die("FAIL_P0_EXACT_HEAD_V2_CONFIG_SCHEMA")
    if config.get("repository") != legacy.REPOSITORY:
        legacy.die("FAIL_P0_EXACT_HEAD_V2_CONFIG_REPOSITORY")
    if config.get("source_sha256") != legacy.SOURCE_SHA256:
        legacy.die("FAIL_P0_EXACT_HEAD_V2_CONFIG_SOURCE_SHA")
    if config.get("source_evidence_object_id") != legacy.SOURCE_EVIDENCE_OBJECT_ID:
        legacy.die("FAIL_P0_EXACT_HEAD_V2_CONFIG_SOURCE_OBJECT")
    if config.get("production_authorized") is not False or config.get("p0_5_authorized") is not False:
        legacy.die("FAIL_P0_EXACT_HEAD_V2_CONFIG_AUTHORIZATION_BOUNDARY")
    broker_url = str(config.get("broker_url") or "").strip()
    if not broker_url.startswith("https://") or not broker_url.endswith("/lf-p0-exact-head-evidence-broker-v2"):
        legacy.die("FAIL_P0_EXACT_HEAD_V2_BROKER_URL_INVALID")
    return config


def self_test() -> int:
    config = load_config()
    checks = {
        "main_allowed": governed_ref("refs/heads/main"),
        "p0_branch_allowed": governed_ref("refs/heads/lf/p0-exact-head-real-source-v2"),
        "arbitrary_feature_blocked": not governed_ref("refs/heads/feature/arbitrary"),
        "non_p0_lf_blocked": not governed_ref("refs/heads/lf/not-p0"),
        "tag_blocked": not governed_ref("refs/tags/v1"),
        "config_ref_policy_matches": config.get("governed_refs") == ["refs/heads/main", "refs/heads/lf/p0-*"],
    }
    print(json.dumps({"gate": "PASS_P0_EXACT_HEAD_RUNNER_POLICY_V2" if all(checks.values()) else "FAIL", "checks": checks}, sort_keys=True))
    return 0 if all(checks.values()) else 2


def run_broker_policy_test() -> None:
    node = shutil.which("node")
    if not node:
        legacy.die("FAIL_P0_EXACT_HEAD_NODE_MISSING")
    completed = subprocess.run([node, str(POLICY_TEST_PATH)], cwd=legacy.REPO_ROOT, text=True, capture_output=True, check=False)
    if completed.returncode != 0:
        legacy.die("FAIL_P0_EXACT_HEAD_BROKER_POLICY_TEST", completed.stdout[-500:] + completed.stderr[-500:])
    print(completed.stdout.strip())


def live_broker_negative_probes(broker_url: str) -> None:
    token = legacy.require_env("GITHUB_TOKEN")
    base = {
        "repository": legacy.require_env("GITHUB_REPOSITORY"),
        "ref": legacy.require_env("GITHUB_REF"),
        "github_sha": legacy.require_env("GITHUB_SHA"),
        "run_id": int(legacy.require_env("GITHUB_RUN_ID")),
        "run_attempt": int(legacy.require_env("GITHUB_RUN_ATTEMPT")),
        "event_name": legacy.require_env("GITHUB_EVENT_NAME"),
        "action": "get_source",
    }
    probes = [
        ("bad_ref", {**base, "ref": "refs/heads/feature/arbitrary"}, "GITHUB_REQUEST_REF_NOT_GOVERNED"),
        ("bad_sha", {**base, "github_sha": "0" * 40}, "GITHUB_WORKFLOW_SHA_MISMATCH"),
        ("bad_event", {**base, "event_name": "pull_request"}, "GITHUB_EVENT_INVALID"),
    ]
    for name, payload, expected in probes:
        request = urllib.request.Request(
            broker_url,
            data=json.dumps(payload, separators=(",", ":")).encode("utf-8"),
            method="POST",
            headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json", "Accept": "application/json"},
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                observed = json.loads(response.read().decode("utf-8"))
            legacy.die("FAIL_P0_EXACT_HEAD_NEGATIVE_PROBE_ALLOWED", f"{name}:{observed}")
        except urllib.error.HTTPError as exc:
            try:
                observed = json.loads(exc.read().decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                legacy.die("FAIL_P0_EXACT_HEAD_NEGATIVE_PROBE_RESPONSE", name)
            if observed.get("outcome") != "BLOCKED" or observed.get("code") != expected:
                legacy.die("FAIL_P0_EXACT_HEAD_NEGATIVE_PROBE_MISMATCH", f"{name}:expected={expected}:observed={observed}")
            print(f"PASS_P0_EXACT_HEAD_NEGATIVE_PROBE:{name}:{expected}")


def verify_persisted_summary(technical_exit_code: int) -> dict:
    if not SUMMARY_PATH.is_file():
        legacy.die("FAIL_P0_EXACT_HEAD_SUMMARY_MISSING", f"technical_exit={technical_exit_code}")
    try:
        summary = json.loads(SUMMARY_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        legacy.die("FAIL_P0_EXACT_HEAD_SUMMARY_JSON", str(exc))
    expected_sha = legacy.require_env("GITHUB_SHA")
    checks = {
        "github_sha": summary.get("github_sha") == expected_sha,
        "observed_git_head": summary.get("observed_git_head") == expected_sha,
        "source_sha256": summary.get("source_sha256") == legacy.SOURCE_SHA256,
        "receipt_persisted": bool(summary.get("receipt_evidence_object_id")),
        "production_boundary": summary.get("production_authorized") is False,
        "p0_5_boundary": summary.get("p0_5_authorized") is False,
    }
    if not all(checks.values()):
        legacy.die("FAIL_P0_EXACT_HEAD_EVIDENCE_CAPTURE_BINDING", json.dumps(checks, sort_keys=True))
    result = {
        "gate": "P0_EXACT_HEAD_EVIDENCE_CAPTURED_V2",
        "technical_exit_code": technical_exit_code,
        "github_sha": expected_sha,
        "source_sha256": legacy.SOURCE_SHA256,
        "receipt_evidence_object_id": summary.get("receipt_evidence_object_id"),
        "receipt_sha256": summary.get("receipt_sha256"),
        "technical_result": summary.get("technical_result"),
        "terminal_result": summary.get("terminal_result"),
        "production_authorized": False,
        "p0_5_authorized": False,
    }
    print(json.dumps(result, sort_keys=True))
    return result


def run_capture_mode(config: dict) -> int:
    if self_test() != 0:
        return 2
    run_broker_policy_test()
    live_broker_negative_probes(config["broker_url"])
    technical_exit_code = 0
    try:
        returned = legacy.main()
        technical_exit_code = int(returned or 0)
    except SystemExit as exc:
        technical_exit_code = int(exc.code) if isinstance(exc.code, int) else 2
    verify_persisted_summary(technical_exit_code)
    return 0


def main() -> int:
    if "--self-test" in sys.argv[1:]:
        return self_test()

    config = load_config()
    github_ref = os.environ.get("GITHUB_REF", "").strip()
    if not governed_ref(github_ref):
        legacy.die("FAIL_P0_EXACT_HEAD_REF_NOT_GOVERNED", github_ref or "<missing>")

    legacy.EXPECTED_REF = github_ref
    legacy.BROKER_URL = config["broker_url"]
    if "--evidence-capture" in sys.argv[1:]:
        return run_capture_mode(config)
    return legacy.main()


if __name__ == "__main__":
    raise SystemExit(main())
