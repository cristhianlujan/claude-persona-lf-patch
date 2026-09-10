#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path

from s26_hp001.happy_path_preexecution import run_preexecution

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
FIXTURE = HERE / "s26_hp001"
MANIFEST = FIXTURE / "replay_manifest.json"
OUTPUT_TEST = HERE / "test_s26_hp001_output.py"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"MODULE_LOAD_FAILED:{path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> int:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if manifest.get("schema") != "S26_HP001_REPLAY_MANIFEST_V1":
        raise RuntimeError("REPLAY_SCHEMA_INVALID")
    if manifest.get("candidate_sha_authority") != "GITHUB_EVENT_HEAD_SHA":
        raise RuntimeError("REPLAY_SHA_AUTHORITY_INVALID")
    if manifest.get("main_is_not_replay_authority") is not True:
        raise RuntimeError("MAIN_WRONGLY_USED_AS_REPLAY_AUTHORITY")
    if manifest.get("merge_ref_is_not_replay_authority") is not True:
        raise RuntimeError("MERGE_REF_WRONGLY_USED_AS_REPLAY_AUTHORITY")
    if manifest.get("independent_review_satisfied_by_replay") is not False:
        raise RuntimeError("REPLAY_WRONGLY_CLAIMS_INDEPENDENT_REVIEW")

    input_path = REPO / manifest["input_path"]
    output_path = REPO / manifest["output_path"]
    if sha256(input_path) != manifest.get("input_sha256"):
        raise RuntimeError("REPLAY_INPUT_SHA_MISMATCH")
    if sha256(output_path) != manifest.get("output_sha256"):
        raise RuntimeError("REPLAY_OUTPUT_SHA_MISMATCH")

    pre = run_preexecution()
    if pre.get("result") != "PASS":
        raise RuntimeError("REPLAY_PREEXECUTION_FAILED")

    output_module = load_module(OUTPUT_TEST, "s26_hp001_output_replay")
    if output_module.main() != 0:
        raise RuntimeError("REPLAY_OUTPUT_VALIDATION_FAILED")

    print(json.dumps({
        "gate": "S26_HP001_DETERMINISTIC_REPLAY_V1",
        "result": "PASS",
        "input_sha256": manifest["input_sha256"],
        "output_sha256": manifest["output_sha256"],
        "preexecution_replayed": True,
        "canonical_output_validation_replayed": True,
        "independent_semantic_review_performed": False,
        "claim_ceiling": manifest["claim_ceiling"],
    }, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
