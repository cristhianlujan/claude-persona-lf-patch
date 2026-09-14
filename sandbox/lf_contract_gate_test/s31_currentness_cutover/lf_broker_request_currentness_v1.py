#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
MATERIAL = HERE.parent / "material_currentness"
sys.path.insert(0, str(MATERIAL))

from lf_broker_currentness_bridge_v1 import bridge_decision  # noqa: E402

HEX40 = re.compile(r"^[0-9a-f]{40}$")


def _git(repo: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", "-C", str(repo), *args], text=True, capture_output=True)


def _blocked(decision: str, **extra: Any) -> dict[str, Any]:
    return {"ready": False, "decision": decision, **extra}


def build_broker_request(
    *,
    repo: Path,
    binding: dict[str, Any],
    requested_base_revision: str,
    current_revision: str,
    source_revision: str,
    source_ref: str,
    target_branch: str,
    receipt_path: Path,
) -> dict[str, Any]:
    for label, value in {
        "requested_base_revision": requested_base_revision,
        "current_revision": current_revision,
        "source_revision": source_revision,
    }.items():
        if not HEX40.fullmatch(value or ""):
            return _blocked("BLOCK_BROKER_REVISION_FORMAT_INVALID", field=label)
    if not source_ref.startswith("lf/staging-s30-"):
        return _blocked("BLOCK_BROKER_SOURCE_NAMESPACE")
    if not target_branch.startswith("lf/s30-"):
        return _blocked("BLOCK_BROKER_TARGET_NAMESPACE")

    currentness = bridge_decision(
        repo=repo,
        binding=binding,
        base_revision=requested_base_revision,
        current_revision=current_revision,
    )
    if not currentness.get("ready"):
        return _blocked(
            currentness.get("decision", "BLOCK_BROKER_CURRENTNESS_UNPROVEN"),
            currentness=currentness,
        )

    effective_base = currentness.get("effective_base_revision")
    if not isinstance(effective_base, str) or not HEX40.fullmatch(effective_base):
        return _blocked("BLOCK_BROKER_EFFECTIVE_BASE_INVALID", currentness=currentness)

    ancestry = _git(repo, "merge-base", "--is-ancestor", effective_base, source_revision)
    if ancestry.returncode != 0:
        return _blocked(
            "BLOCK_BROKER_SOURCE_NOT_DESCENDANT_OF_EFFECTIVE_BASE",
            effective_base_revision=effective_base,
            source_revision=source_revision,
            currentness=currentness,
        )

    if not receipt_path.is_file():
        return _blocked("BLOCK_BROKER_RECEIPT_PATH")
    try:
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    except Exception as exc:
        return _blocked("BLOCK_BROKER_RECEIPT_INVALID_JSON", detail=str(exc))

    broker_binding = receipt.get("git_write_binding") or {}
    required = {
        "status": "OPERATIONAL",
        "source_branch": source_ref,
        "target_branch": target_branch,
        "base_main_sha": effective_base,
        "secret_present": True,
        "promotion_authority": "BROKER_ONLY",
    }
    mismatches = sorted(key for key, expected in required.items() if broker_binding.get(key) != expected)
    if mismatches:
        return _blocked(
            "BLOCK_BROKER_RECEIPT_REHYDRATION_REQUIRED",
            mismatched_fields=mismatches,
            effective_base_revision=effective_base,
            currentness=currentness,
        )

    request = {
        "request_schema": "s30-git-broker/v1",
        "source_ref": source_ref,
        "target_branch": target_branch,
        "base_main_sha": effective_base,
        "receipt_path": str(receipt_path.as_posix()),
    }
    return {
        "ready": True,
        "decision": "BROKER_REQUEST_CURRENTNESS_BOUND",
        "requested_base_revision": requested_base_revision,
        "effective_base_revision": effective_base,
        "source_revision": source_revision,
        "currentness_decision": currentness.get("decision"),
        "request": request,
        "currentness": currentness,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="Prepare an existing S30 broker request through CURRENTNESS_AUTHORITY without weakening the broker's exact-main atomicity guard.")
    ap.add_argument("--repo", type=Path, default=Path("."))
    ap.add_argument("--binding", type=Path, required=True)
    ap.add_argument("--requested-base-revision", required=True)
    ap.add_argument("--current-revision", required=True)
    ap.add_argument("--source-revision", required=True)
    ap.add_argument("--source-ref", required=True)
    ap.add_argument("--target-branch", required=True)
    ap.add_argument("--receipt-path", type=Path, required=True)
    ap.add_argument("--output", type=Path)
    ns = ap.parse_args()
    binding = json.loads(ns.binding.read_text(encoding="utf-8"))
    result = build_broker_request(
        repo=ns.repo,
        binding=binding,
        requested_base_revision=ns.requested_base_revision,
        current_revision=ns.current_revision,
        source_revision=ns.source_revision,
        source_ref=ns.source_ref,
        target_branch=ns.target_branch,
        receipt_path=ns.receipt_path,
    )
    text = json.dumps(result, sort_keys=True, indent=2)
    if ns.output:
        ns.output.write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0 if result.get("ready") else 2


if __name__ == "__main__":
    raise SystemExit(main())
