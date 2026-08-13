#!/usr/bin/env python3
from __future__ import annotations

import base64
import hashlib
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
P0_ROOT = REPO_ROOT / "sandbox" / "story_creator_p0_visual" / "v1.1"
RUNNER = P0_ROOT / "evals" / "p0_visual_real_rerun_v4.py"
CONFIG = P0_ROOT / "evals" / "p0-closed-loop-runtime-config-v4.json"
SOURCE_EVIDENCE_OBJECT_ID = "be7fcf20-5f83-46d4-be0e-c80dc3ceed7c"
SOURCE_SHA256 = "e308b66778d1108241e2832997f6628f47841d7da1fc53820007834fdbb720d7"
SOURCE_BYTES = 1_384_686
REPOSITORY = "cristhianlujan/claude-persona-lf-patch"
EXPECTED_REF = "refs/heads/lf/p0-persistence-ocr-completion-20260812"
BROKER_URL = "https://mhwmirqcgxxukpctffuv.supabase.co/functions/v1/lf-p0-exact-head-evidence-broker-v1"


def die(code: str, detail: str = "") -> "NoReturn":
    message = code if not detail else f"{code}: {detail}"
    print(message, file=sys.stderr)
    raise SystemExit(2)


def require_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        die(f"FAIL_{name}_MISSING")
    return value


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def broker(token: str, payload: dict) -> dict:
    request = urllib.request.Request(
        BROKER_URL,
        data=json.dumps(payload, separators=(",", ":")).encode("utf-8"),
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "lf-p0-exact-head-real-source-ci-v1",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            body = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:1000]
        die("FAIL_P0_EVIDENCE_BROKER_HTTP", f"status={exc.code} body={detail}")
    except (urllib.error.URLError, TimeoutError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        die("FAIL_P0_EVIDENCE_BROKER_TRANSPORT", type(exc).__name__)
    if not isinstance(body, dict):
        die("FAIL_P0_EVIDENCE_BROKER_RESPONSE_TYPE")
    return body


def main() -> int:
    event_name = require_env("GITHUB_EVENT_NAME")
    github_ref = require_env("GITHUB_REF")
    github_sha = require_env("GITHUB_SHA")
    github_token = require_env("GITHUB_TOKEN")
    run_id = int(require_env("GITHUB_RUN_ID"))
    run_attempt = int(require_env("GITHUB_RUN_ATTEMPT"))
    repository = require_env("GITHUB_REPOSITORY")

    if event_name not in {"push", "workflow_dispatch"}:
        die("FAIL_P0_EXACT_HEAD_EVENT_TYPE", event_name)
    if github_ref != EXPECTED_REF:
        die("FAIL_P0_EXACT_HEAD_BRANCH", github_ref)
    if repository != REPOSITORY:
        die("FAIL_P0_EXACT_HEAD_REPOSITORY", repository)
    observed_head = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=REPO_ROOT, text=True
    ).strip()
    if observed_head != github_sha:
        die("FAIL_P0_EXACT_HEAD_CHECKOUT", f"expected={github_sha} observed={observed_head}")
    if len(github_sha) != 40 or any(ch not in "0123456789abcdef" for ch in github_sha):
        die("FAIL_P0_EXACT_HEAD_SHA_FORMAT")

    identity = {
        "repository": repository,
        "ref": github_ref,
        "github_sha": github_sha,
        "run_id": run_id,
        "run_attempt": run_attempt,
        "event_name": event_name,
    }
    delivered = broker(github_token, {**identity, "action": "get_source"})
    if delivered.get("outcome") != "SOURCE_DELIVERED_TO_EXACT_GITHUB_RUN":
        die("FAIL_P0_SOURCE_DELIVERY_OUTCOME", str(delivered.get("outcome")))
    source_info = delivered.get("source")
    if not isinstance(source_info, dict):
        die("FAIL_P0_SOURCE_DELIVERY_SHAPE")
    if source_info.get("evidence_object_id") != SOURCE_EVIDENCE_OBJECT_ID:
        die("FAIL_P0_SOURCE_EVIDENCE_ID")
    if source_info.get("content_sha256") != SOURCE_SHA256 or int(source_info.get("content_bytes", -1)) != SOURCE_BYTES:
        die("FAIL_P0_SOURCE_DELIVERY_METADATA_INTEGRITY")
    try:
        source = base64.b64decode(source_info["content_base64"], validate=False)
    except Exception as exc:
        die("FAIL_P0_SOURCE_BASE64", type(exc).__name__)
    if len(source) != SOURCE_BYTES or sha256_bytes(source) != SOURCE_SHA256:
        die("FAIL_P0_SOURCE_DELIVERY_CRYPTOGRAPHIC_INTEGRITY")

    run_root = Path(os.environ.get("RUNNER_TEMP", "/tmp")) / "lf-p0-real-source"
    run_root.mkdir(parents=True, exist_ok=True)
    source_path = run_root / "source.png"
    source_path.write_bytes(source)
    config_sha = sha256_bytes(CONFIG.read_bytes())
    receipt_path = run_root / "p0-real-rerun-v4.json"

    runner = subprocess.run(
        [
            sys.executable,
            str(RUNNER),
            "--source", str(source_path),
            "--source-sha", SOURCE_SHA256,
            "--code-head", github_sha,
            "--config-sha", config_sha,
            "--output", str(receipt_path),
        ],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
        env=os.environ.copy(),
    )
    (run_root / "runner.stdout").write_text(runner.stdout, encoding="utf-8")
    (run_root / "runner.stderr").write_text(runner.stderr, encoding="utf-8")
    if not receipt_path.exists():
        source_path.unlink(missing_ok=True)
        die("FAIL_P0_EXACT_HEAD_RECEIPT_MISSING", f"runner_exit={runner.returncode}")

    receipt_bytes = receipt_path.read_bytes()
    receipt_sha = sha256_bytes(receipt_bytes)
    try:
        receipt = json.loads(receipt_bytes)
    except json.JSONDecodeError as exc:
        source_path.unlink(missing_ok=True)
        die("FAIL_P0_EXACT_HEAD_RECEIPT_JSON", str(exc))
    if receipt.get("source_sha256") != SOURCE_SHA256:
        die("FAIL_P0_EXACT_HEAD_RECEIPT_SOURCE_BINDING")
    if receipt.get("code_head_sha") != github_sha:
        die("FAIL_P0_EXACT_HEAD_RECEIPT_HEAD_BINDING")
    if receipt.get("configuration_sha256") != config_sha:
        die("FAIL_P0_EXACT_HEAD_RECEIPT_CONFIG_BINDING")

    persisted = broker(
        github_token,
        {
            **identity,
            "action": "store_receipt",
            "receipt_base64": base64.b64encode(receipt_bytes).decode("ascii"),
            "receipt_bytes": len(receipt_bytes),
            "receipt_sha256": receipt_sha,
            "configuration_sha256": config_sha,
            "runner_exit_code": runner.returncode,
        },
    )
    if persisted.get("outcome") != "RECEIPT_PERSISTED_WITH_CRYPTOGRAPHIC_AND_SEMANTIC_BINDING":
        die("FAIL_P0_RECEIPT_PERSISTENCE_OUTCOME", str(persisted.get("outcome")))
    if persisted.get("receipt_sha256") != receipt_sha or int(persisted.get("receipt_bytes", -1)) != len(receipt_bytes):
        die("FAIL_P0_RECEIPT_PERSISTENCE_READBACK")

    mutation = receipt.get("mutation_campaign") if isinstance(receipt.get("mutation_campaign"), dict) else {}
    residual = receipt.get("visual_residual_gate") if isinstance(receipt.get("visual_residual_gate"), dict) else {}
    technical = receipt.get("result") if isinstance(receipt.get("result"), dict) else {}
    terminal = receipt.get("terminal_result")
    summary = {
        "schema_version": "p0-exact-head-ci-summary/v2",
        "github_event_name": event_name,
        "github_ref": github_ref,
        "github_sha": github_sha,
        "observed_git_head": observed_head,
        "source_sha256": SOURCE_SHA256,
        "source_bytes": SOURCE_BYTES,
        "source_evidence_object_id": SOURCE_EVIDENCE_OBJECT_ID,
        "configuration_sha256": config_sha,
        "receipt_evidence_object_id": persisted.get("evidence_object_id"),
        "receipt_sha256": receipt_sha,
        "receipt_bytes": len(receipt_bytes),
        "runner_exit_code": runner.returncode,
        "technical_result": technical.get("result"),
        "terminal_result": terminal,
        "human_review_ready": terminal == "READY_FOR_HUMAN_REVIEW_RECHECK",
        "mutation_status": mutation.get("status"),
        "mutation_count": mutation.get("mutation_count"),
        "mutation_detected_count": mutation.get("detected_count"),
        "residual_status": residual.get("status"),
        "residual_errors": residual.get("errors") if isinstance(residual.get("errors"), list) else [],
        "production_authorized": False,
        "p0_5_authorized": False,
    }
    audit_dir = REPO_ROOT / ".audit-output" / "creating-integral-user-stories"
    audit_dir.mkdir(parents=True, exist_ok=True)
    (audit_dir / "p0-exact-head-real-source-summary.json").write_text(
        json.dumps(summary, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(summary, sort_keys=True))

    source_path.unlink(missing_ok=True)
    receipt_path.unlink(missing_ok=True)
    if runner.returncode != 0:
        die("BLOCKED_P0_EXACT_HEAD_REAL_SOURCE_RERUN", f"runner_exit={runner.returncode} terminal={terminal}")
    if terminal != "READY_FOR_HUMAN_REVIEW_RECHECK":
        die("BLOCKED_P0_EXACT_HEAD_TERMINAL_RESULT", str(terminal))
    print("READY_FOR_HUMAN_REVIEW_RECHECK_EXACT_HEAD")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
