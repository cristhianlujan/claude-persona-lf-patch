#!/usr/bin/env python3
"""A15Q_C2 Git <-> Supabase reconciliation (Git side + pure comparison; mechanics only).

git_side() recomputes, from the CURRENT bytes in the checkout, the fingerprints the Supabase
receipts must agree with: the canonical source sha256 of every A1Q..A14Q C1, the A15 freeze
manifest sha256 and its bundle blobs, the PG-01 programming entry contract blob and the judge
dossier shape. reconcile() compares those with the rows read from Supabase and returns the list
of violations (empty list = reconciled). The close migration embeds git_side() output and repeats
the same comparison inside the database transaction at apply time.

Limits: it proves agreement of fingerprints, not that a model ran, and it is not provider
attestation or independent review. It never writes to any system.
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
DOSSIER = REPO / "docs/programming-agent/ANALYSIS_QUALIFICATION_JUDGE_DOSSIER_V1.json"
MANIFEST = HERE / "analysis_v1_freeze_manifest_v1.json"
PG01_PATH = "programming_entry_contract_v1.json"
UNITS = [f"A{n}" for n in range(1, 15)]


def sha256_file(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def git_blob(data: bytes) -> str:
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def git_side(base: Path = REPO) -> dict:
    dossier = json.loads((base / DOSSIER.relative_to(REPO)).read_text(encoding="utf-8"))
    out = {"c1_source_sha256": {}, "dossier": {"checkpoint_count": dossier["checkpoint_count"],
                                               "qualified_count": dossier["qualified_count"]}}
    for u in UNITS:
        e = next(x for x in dossier["checkpoints"] if x["checkpoint_code"] == f"{u}Q_C1")
        cur = sha256_file(base / e["canonical_source"]["path"])
        out["c1_source_sha256"][u] = cur
        if cur != e["canonical_source"]["sha256"]:
            out.setdefault("git_internal_drift", []).append(u)
    mpath = base / MANIFEST.relative_to(REPO)
    manifest = json.loads(mpath.read_text(encoding="utf-8"))
    out["a15_manifest_sha256"] = sha256_file(mpath)
    pg01 = next(e for e in manifest["source_bundle"] if e["path"] == PG01_PATH)
    pg01_file = mpath.parent / PG01_PATH
    out["pg01_contract"] = {"blob": git_blob(pg01_file.read_bytes()), "declared_blob": pg01["blob"],
                            "sha256": sha256_file(pg01_file)}
    if out["pg01_contract"]["blob"] != pg01["blob"]:
        out.setdefault("git_internal_drift", []).append("PG01")
    return out


def reconcile(git: dict, sb: dict) -> list[str]:
    """sb = {rows:[{checkpoint_code,status,evidence_ref,stored_raw_sha256}], checkpoint_rows:int, pg01_fn_md5, pg01_fn_expected_md5}."""
    bad = []
    if git.get("git_internal_drift"):
        bad.append("GIT_INTERNAL_DRIFT:" + ",".join(git["git_internal_drift"]))
    rows = {r["checkpoint_code"]: r for r in sb.get("rows", [])}
    if sb.get("checkpoint_rows") != 45:
        bad.append("CHECKPOINT_ROWS_NOT_45")
    for u in UNITS:
        for c in (1, 2, 3):
            r = rows.get(f"{u}Q_C{c}")
            if not r or r.get("status") != "DONE":
                bad.append(f"NOT_DONE:{u}Q_C{c}")
                continue
            ev = r.get("evidence_ref") or ""
            if c == 1:
                m = __import__("re").search(r"sha256:([0-9a-f]{64});actor", ev)
                if not m or m.group(1) != git["c1_source_sha256"][u]:
                    bad.append(f"C1_SHA_MISMATCH:{u}")
            else:
                m = __import__("re").search(r"raw_sha256:([0-9a-f]{64})", ev)
                if not m or m.group(1) != r.get("stored_raw_sha256"):
                    bad.append(f"RAW_SHA_MISMATCH:{u}Q_C{c}")
    r15 = rows.get("A15Q_C1")
    m = __import__("re").search(r"sha256:([0-9a-f]{64});actor", (r15 or {}).get("evidence_ref") or "")
    if not r15 or r15.get("status") != "DONE" or not m or m.group(1) != git["a15_manifest_sha256"]:
        bad.append("A15_C1_MANIFEST_MISMATCH")
    if sb.get("pg01_fn_md5") is None or sb.get("pg01_fn_md5") != sb.get("pg01_fn_expected_md5"):
        bad.append("PG01_GUARD_FINGERPRINT")
    if git["pg01_contract"]["blob"] != git["pg01_contract"]["declared_blob"]:
        bad.append("PG01_CONTRACT_DRIFT")
    if git["dossier"] != {"checkpoint_count": 45, "qualified_count": 0}:
        bad.append("DOSSIER_SHAPE")
    return bad


if __name__ == "__main__":
    print(json.dumps(git_side(), indent=2))
