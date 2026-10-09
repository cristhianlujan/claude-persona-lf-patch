#!/usr/bin/env python3
"""M9.0 PARITY_GIT_RUNTIME: Git migration source == remote schema_migrations, and the runtime-verification authorities are current.

Judges a live Supabase snapshot (schema_migrations rows matching '(input_gov|readiness|ig_cv)', latest 30; lf_capability_current codes)
against the migration files in the repository. Read-only: no database or repository writes.

Classification per remote row (matched by migration name; the DB may store the statement text trimmed, so a file matches by sha256 of its raw bytes or of its stripped bytes):
  EXACT            same name, same content sha, same version
  VERSION_SKEW     same name, same content sha, different version timestamp   (must be adjudicated)
  COMMENT_WHITESPACE_ONLY  different sha but identical after removing SQL line comments and all whitespace (counted, accepted)
  FORMAT_DIVERGED  same name, different normalized content                    (must be adjudicated by exact shas)
  REMOTE_WITHOUT_GIT  no file with that name                                  (never adjudicable)
Adjudications are evidence-bound: each lists the exact remote sha and git sha; any change of either invalidates it.
Edge: the deployed index.ts of the 3 input-governance functions must be byte-equal to main.
MIGRATION_SOURCE_PARITY is NOT_APPLICABLE_DISABLED_BY_GOVERNANCE for the current flow; this test therefore also requires
RUNTIME_DEPLOY_VERIFICATION and FINAL_EVIDENCE to be current.
"""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
import re
import sys
from pathlib import Path

TEST_CODE = "ENG_M9_0_PARITY_GIT_RUNTIME"
EDGE_SLUGS = ("input-governance-agent-v1", "input-governance-curator-v1", "input-governance-validator-v1")
REQUIRED_CAPS = ("RUNTIME_DEPLOY_VERIFICATION", "FINAL_EVIDENCE")


def sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def index_repo(repo: Path) -> dict:
    out: dict = {}
    for f in sorted((repo / "supabase" / "migrations").glob("*.sql")):
        v, _, n = f.stem.partition("_")
        raw = f.read_bytes()
        norm = re.sub(r"\s+", "", re.sub(r"--[^\n]*", "", raw.decode("utf-8")))
        out.setdefault(n, []).append((v, sha(raw), sha(raw.strip()), sha(norm.encode("utf-8"))))
    return out


def classify(authority: dict, files: dict) -> dict:
    res = {"EXACT": [], "VERSION_SKEW": [], "COMMENT_WHITESPACE_ONLY": [], "FORMAT_DIVERGED": [], "REMOTE_WITHOUT_GIT": []}
    for version, name, dbsha, dbnorm in authority["migrations"]:
        cands = files.get(name, [])
        if not cands:
            res["REMOTE_WITHOUT_GIT"].append([version, name])
            continue
        same = [c for c in cands if dbsha in (c[1], c[2])]
        if same:
            res["EXACT" if same[0][0] == version else "VERSION_SKEW"].append([version, name, same[0][0]])
        elif dbnorm and any(c[3] == dbnorm for c in cands):
            res["COMMENT_WHITESPACE_ONLY"].append([version, name])
        else:
            res["FORMAT_DIVERGED"].append([version, name, dbsha, cands[0][1]])
    return res


def judge(authority: dict, files: dict, repo: Path) -> tuple[bool, dict]:
    if authority.get("source") != "SUPABASE_LIVE_schema_migrations" or not authority.get("migrations"):
        return False, {"reason": "AUTHORITY_INVALID"}
    res = classify(authority, files)
    adj = authority.get("adjudicated", {})
    skew_ok = {tuple(x) for x in adj.get("version_skew", [])}
    fmt_ok = {tuple(x) for x in adj.get("format_diverged", [])}
    problems = []
    if res["REMOTE_WITHOUT_GIT"]:
        problems.append(("REMOTE_WITHOUT_GIT", res["REMOTE_WITHOUT_GIT"]))
    unadj_skew = [x for x in res["VERSION_SKEW"] if tuple(x) not in skew_ok]
    if unadj_skew:
        problems.append(("UNADJUDICATED_VERSION_SKEW", unadj_skew))
    unadj_fmt = [x for x in res["FORMAT_DIVERGED"] if tuple(x) not in fmt_ok]
    if unadj_fmt:
        problems.append(("UNADJUDICATED_FORMAT_DIVERGENCE", unadj_fmt))
    edge = authority.get("edge_functions", [])
    if {e.get("slug") for e in edge} != set(EDGE_SLUGS):
        problems.append(("EDGE_INVENTORY_INCOMPLETE", sorted(EDGE_SLUGS)))
    for e in edge:
        gp = repo / "supabase" / "functions" / str(e.get("slug")) / "index.ts"
        git_sha = sha(gp.read_bytes()) if gp.is_file() else None
        if git_sha is None or e.get("deployed_index_sha256") != git_sha:
            problems.append(("EDGE_DEPLOYED_NOT_EQUAL_GIT", [e.get("slug"), e.get("deployed_index_sha256"), git_sha]))
    caps = set(authority.get("capabilities", []))
    missing = [c for c in REQUIRED_CAPS if c not in caps]
    if missing:
        problems.append(("RUNTIME_AUTHORITY_NOT_CURRENT", missing))
    return (not problems), {"classes": {k: len(v) for k, v in res.items()}, "problems": problems}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--authority-json", required=True)
    ap.add_argument("--repo", default=".")
    a = ap.parse_args()
    authority = json.loads(Path(a.authority_json).read_text())
    files = index_repo(Path(a.repo))
    ok, detail = judge(authority, files, Path(a.repo))
    print(json.dumps({"test": TEST_CODE, "positive_ok": ok, "detail": detail}, sort_keys=True))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
