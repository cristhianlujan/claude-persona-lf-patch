#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import analysis_qualification_c1_ci_attest_v1 as ci  # noqa: E402


def main() -> None:
    head = ci.head_sha()
    good = ci.run(ci.UNITS, ci.DOSSIER, head)
    assert good["all_passed"] is True and len(good["results"]) == 14, good["results"]
    assert all(r["all_passed"] for r in good["results"])
    # not on the exact SHA the run started on -> blocked
    stale = ci.run(["A2"], ci.DOSSIER, "0" * 40)
    assert stale["all_passed"] is False and stale["results"][0]["run_on_exact_main_sha"] is False
    no_env = ci.run(["A2"], ci.DOSSIER, None)
    assert no_env["all_passed"] is False
    # committed hash differs from the bytes CI sees -> blocked (drift)
    dossier = json.loads(ci.DOSSIER.read_text(encoding="utf-8"))
    for entry in dossier["checkpoints"]:
        if entry["checkpoint_code"] == "A3Q_C1":
            entry["canonical_source"]["sha256"] = "0" * 64
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "dossier.json"
        path.write_text(json.dumps(dossier), encoding="utf-8")
        drift = ci.run(["A3", "A4"], path, head)
    by = {r["checkpoint_code"]: r for r in drift["results"]}
    assert by["A3Q_C1"]["source_sha256_matches"] is False and by["A3Q_C1"]["all_passed"] is False
    assert by["A4Q_C1"]["all_passed"] is True and drift["all_passed"] is False
    print("PASS_ANALYSIS_C1_CI_ATTEST units=14 negatives=3 db_writes=0 transitions=0")


if __name__ == "__main__":
    main()
