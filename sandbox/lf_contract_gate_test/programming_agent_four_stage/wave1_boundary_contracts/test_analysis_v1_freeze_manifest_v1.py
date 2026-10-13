#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import validate_analysis_v1_freeze_manifest_v1 as fz  # noqa: E402


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp)
        (base / "a.json").write_bytes(b'{"a":1}\n')
        (base / "b.json").write_bytes(b'{"b":2}\n')
        good = {"schema_version": fz.SCHEMA, "plan_code": fz.PLAN, "unit": "A15",
                "merge_performed": False,
                "story_retirement_boundary": {"story_retirement_authorized": False},
                "source_bundle": [
                    {"unit": "A1", "path": "a.json", "blob": fz.git_blob_id(b'{"a":1}\n')},
                    {"unit": "A2", "path": "b.json", "blob": fz.git_blob_id(b'{"b":2}\n')}]}
        assert fz.validate(good, base) == ("PASS_FREEZE_CURRENT", [])
        drifted = copy.deepcopy(good)
        (base / "b.json").write_bytes(b'{"b":3}\n')
        assert fz.validate(drifted, base) == ("BLOCK_FREEZE_SOURCE_DRIFT", ["A2:b.json"])
        (base / "b.json").unlink()
        assert fz.validate(good, base) == ("BLOCK_FREEZE_SOURCE_MISSING", ["A2:b.json"])
        cases = {
            "BLOCK_FREEZE_MERGE_CLAIMED": dict(good, merge_performed=True),
            "BLOCK_FREEZE_RETIREMENT_AUTHORIZED": dict(
                good, story_retirement_boundary={"story_retirement_authorized": True}),
            "BLOCK_FREEZE_MANIFEST_INVALID": dict(good, unit="A14"),
        }
        for code, manifest in cases.items():
            assert fz.validate(manifest, base)[0] == code, code
        assert fz.validate(dict(good, source_bundle=[]), base)[0] == "BLOCK_FREEZE_MANIFEST_INVALID"
        assert fz.validate(dict(good, schema_version="X"), base)[0] == "BLOCK_FREEZE_MANIFEST_INVALID"
        assert fz.validate(None, base)[0] == "BLOCK_FREEZE_MANIFEST_INVALID"
    # git blob id must agree with git itself (exact bytes rule)
    import subprocess
    probe = HERE / "analysis_v1_freeze_manifest_v1.json"
    assert fz.git_blob_id(probe.read_bytes()) == subprocess.check_output(
        ["git", "hash-object", str(probe)], text=True).strip()
    print("PASS_ANALYSIS_V1_FREEZE_VALIDATOR positives=1 negatives=8 governed_receipts=0")


if __name__ == "__main__":
    main()
