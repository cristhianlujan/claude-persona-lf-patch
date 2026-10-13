#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import generate_analysis_qualification_dossier_v1 as gen  # noqa: E402


def main() -> None:
    dossier = json.loads(gen.OUT.read_text(encoding="utf-8"))
    assert gen.OUT.read_text(encoding="utf-8") == gen.render(), "dossier stale: regenerate with --write"
    entries = dossier["checkpoints"]
    assert dossier["checkpoint_count"] == len(entries) == 45
    assert dossier["qualified_count"] == 0
    assert len({e["checkpoint_code"] for e in entries}) == 45
    assert all(e["transition_performed"] is False for e in entries)
    assert all(e["repository_side_status"] == "MECHANICS_READY_AWAITING_GOVERNED_RUNTIME" for e in entries)
    with_adapter = [e for e in entries if e["adapter"]["path"]]
    assert len(with_adapter) == 44 and all(e["adapter"]["sha256"] for e in with_adapter)
    assert [e["checkpoint_code"] for e in entries if not e["adapter"]["path"]] == ["A15Q_C1"]
    assert all(e["canonical_source"]["sha256"] for e in entries if e["order"] == 1)
    c3 = [e for e in entries if e["order"] == 3]
    assert len(c3) == 15 and all(e["review_envelope"]["skeleton_verdict"] == gen.v3.BLOCK for e in c3)
    # a runtime-only field must never be claimed as repository-provable
    for e in entries:
        assert set(e["supplied_only_by_governed_runtime"]) <= set(e["acceptance_evidence_fields"])
    # drift in an adapter must change the dossier (freshness is real, not decorative)
    first = next(e for e in with_adapter)
    assert first["adapter"]["sha256"] == gen.sha256_file(gen.REPO / first["adapter"]["path"])
    print("PASS_ANALYSIS_QUALIFICATION_DOSSIER checkpoints=45 qualified=0 adapters=44 transitions=0")


if __name__ == "__main__":
    main()
