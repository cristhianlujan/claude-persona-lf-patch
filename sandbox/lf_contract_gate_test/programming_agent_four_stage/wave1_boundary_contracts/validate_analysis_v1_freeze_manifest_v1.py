#!/usr/bin/env python3
"""A15 freeze validator: compares analysis_v1_freeze_manifest_v1.json with CURRENT file bytes.

For every source_bundle entry it recomputes the git blob id of the current file and blocks on
drift or missing files. It also blocks if the manifest claims a merge was performed, authorizes
story retirement, or has the wrong schema/plan/unit. A drifted bundle means the freeze must be
re-issued under governance. A refreeze stays blocked until it carries an independent_confirmation_ref; this validator never rewrites the manifest and never emits a receipt.
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MANIFEST = HERE / "analysis_v1_freeze_manifest_v1.json"
SCHEMA = "ANALYSIS_V1_FREEZE_MANIFEST_V1"
PLAN = "PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1"


def git_blob_id(data: bytes) -> str:
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def validate(manifest, base: Path = HERE) -> tuple[str, list[str]]:
    """Return (PASS_FREEZE_CURRENT | BLOCK_FREEZE_<REASON>, details). Fail closed."""
    if not isinstance(manifest, dict):
        return "BLOCK_FREEZE_MANIFEST_INVALID", ["not_object"]
    if manifest.get("schema_version") != SCHEMA:
        return "BLOCK_FREEZE_MANIFEST_INVALID", ["schema_version"]
    if manifest.get("plan_code") != PLAN or manifest.get("unit") != "A15":
        return "BLOCK_FREEZE_MANIFEST_INVALID", ["plan_or_unit"]
    if manifest.get("merge_performed") is not False:
        return "BLOCK_FREEZE_MERGE_CLAIMED", ["merge_performed"]
    if (manifest.get("story_retirement_boundary") or {}).get("story_retirement_authorized") is not False:
        return "BLOCK_FREEZE_RETIREMENT_AUTHORIZED", ["story_retirement_authorized"]
    bundle = manifest.get("source_bundle")
    if not isinstance(bundle, list) or not bundle:
        return "BLOCK_FREEZE_MANIFEST_INVALID", ["source_bundle"]
    drift, missing = [], []
    for entry in bundle:
        path = base / str(entry.get("path", ""))
        if not entry.get("path") or not entry.get("blob"):
            return "BLOCK_FREEZE_MANIFEST_INVALID", ["entry_incomplete:" + str(entry.get("unit"))]
        if not path.is_file():
            missing.append(f"{entry['unit']}:{entry['path']}")
        elif git_blob_id(path.read_bytes()) != entry["blob"]:
            drift.append(f"{entry['unit']}:{entry['path']}")
    if missing:
        return "BLOCK_FREEZE_SOURCE_MISSING", missing
    if drift:
        return "BLOCK_FREEZE_SOURCE_DRIFT", drift
    refreeze = manifest.get("refreeze")
    if refreeze is not None:
        ref = refreeze.get("independent_confirmation_ref") if isinstance(refreeze, dict) else None
        if not isinstance(ref, str) or not ref.strip():
            return "BLOCK_FREEZE_INDEPENDENT_CONFIRMATION_PENDING", ["refreeze.independent_confirmation_ref"]
    return "PASS_FREEZE_CURRENT", []


def main() -> int:
    verdict, details = validate(json.loads(MANIFEST.read_text(encoding="utf-8")))
    print(verdict + (" " + ",".join(details) if details else ""))
    return 0 if verdict == "PASS_FREEZE_CURRENT" else 1


if __name__ == "__main__":
    sys.exit(main())
