"""PE10 E2 C4 evaluation-evidence validator. Read-only, no DB, no model invocation.

Checks integrity and internal consistency of the archived C4 evidence. It does NOT attest
provider isolation, evaluator correctness, or that the full evaluator RAW is archived (it is not).
"""
import hashlib
import json
import sys
from pathlib import Path

CASE = "PE10-IG-M107-M109-P0"
RAW_SHA = "6c0fc0c270cbeea246be704d4115016f13c02db1fb2e6508047beaa51bf5d5b4"
MAPPING = {"X1": "B18_ORIGINAL", "X2": "B18_EVOLVED", "X3": "B29_EVOLVED", "X4": "B29_ORIGINAL"}
OUTPUTS = ("C4_EVALUATION_MANIFEST_V1.json", "C4_EVALUATION_RECEIPT_V1.json")


def sha(b):
    return hashlib.sha256(b).hexdigest()


def validate(root):
    root = Path(root)
    man = json.loads((root / "C4_EVALUATION_MANIFEST_V1.json").read_text(encoding="utf-8"))
    assert man["schema"] == "PE10_E2_C4_EVALUATION_MANIFEST_V1" and man["case_ref"] == CASE
    files = man["files"]
    on_disk = sorted(p.name for p in root.iterdir() if p.is_file() and p.name not in OUTPUTS)
    assert on_disk == sorted(files), "inventory mismatch"
    for name, meta in files.items():
        data = (root / name).read_bytes()
        assert sha(data) == meta["sha256"] and len(data) == meta["bytes"], "hash/bytes mismatch " + name
        assert b"\r" not in data, "CR in " + name

    mapping = json.loads((root / "C4_BLIND_MAPPING_COORDINATOR_ONLY.json").read_text(encoding="utf-8"))
    assert mapping == MAPPING, "mapping changed"

    s = json.loads((root / "C4_EVALUATION_SUMMARY_V1.json").read_text(encoding="utf-8"))
    assert s["case_ref"] == CASE and s["evaluator_raw"]["sha256"] == RAW_SHA
    assert s["evaluator_raw"]["archived_in_repo"] == "PREFIX_ONLY"
    prefix = (root / s["evaluator_raw"]["archived_prefix_file"]).read_bytes()
    assert len(prefix) == s["evaluator_raw"]["archived_prefix_chars"] == 20700
    assert prefix.decode("utf-8").startswith("\n{") or prefix.decode("utf-8").startswith("{")
    db = s["de_blinded"]
    for key, cand in (("B18_original", "X1"), ("B18_evolved", "X2"), ("B29_evolved", "X3"), ("B29_original", "X4")):
        assert MAPPING[cand] == key.upper(), key
        assert db[key]["candidate"] == cand and db[key]["score"] == s["scores_0_18"][cand]
    for cand, st in s["reference_fact_states"].items():
        assert set(st) == {"R1", "R2", "R3", "R4"}
    chk = s["coordinator_check_of_evaluator_claim"]["result"]
    assert chk["n"] == 38 and chk["equal_prosrc"] + chk["changed_prosrc"] == 38
    assert s["evaluator_basis"]["provider_isolation_attested"] is False
    assert s["evaluator_basis"]["h1_h4_canonical_text_available"] is False
    assert all(s["pair_verdicts"][k] in ("NO_DEMOSTRADO", "MEJORA_DEMOSTRADA", "REGRESION_DEMOSTRADA") for k in ("B18", "B29"))
    return {"status": "PASS", "candidates": 4, "files": len(files), "raw_full_archived": False,
            "scores": s["scores_0_18"], "pair_verdicts": s["pair_verdicts"]}


if __name__ == "__main__":
    print(json.dumps(validate(sys.argv[1]), sort_keys=True, indent=1))
