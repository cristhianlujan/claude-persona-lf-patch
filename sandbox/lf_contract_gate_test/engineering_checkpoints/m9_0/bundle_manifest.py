#!/usr/bin/env python3
"""M9.0 BUNDLE_MANIFEST_SHA: independent recomputation of the Input Governance release bundle manifest and its deterministic SHA.

Input: the manifest returned by programacion.fn_input_governance_release_bundle_manifest_v1(git_head, edge_index_sha256) (live Supabase),
plus the repository (Edge index.ts files). The judge recomputes every component digest and the bundle digest in Python with the same
canonical JSON rule as programacion.fn_v09_canonical_jsonb_text (sorted keys, compact separators, UTF-8, no ASCII escaping),
checks the Edge shas against the files on main, and runs mutation cases: every single-component change must change the bundle SHA / be blocked.
No dependency on post-pase FINAL_EVIDENCE. Read-only.
"""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
import re
import sys
from pathlib import Path

TEST_CODE = "ENG_M9_0_BUNDLE_MANIFEST_SHA"
COMPONENTS = ("contracts", "registry", "core", "semantics", "curator", "validator", "edge")
EDGE = {
    "EDGE_FN_INPUT_GOVERNANCE_AGENT_V1": "input-governance-agent-v1",
    "EDGE_FN_INPUT_GOVERNANCE_CURATOR_V1": "input-governance-curator-v1",
    "EDGE_FN_INPUT_GOVERNANCE_VALIDATOR_V1": "input-governance-validator-v1",
}
# canonical-text vectors measured on the live database (fn_v09_sha256_jsonb)
VECTORS = [({"a": 1}, "015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862")]


def canon(v) -> str:
    return json.dumps(v, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha(v) -> str:
    return hashlib.sha256(canon(v).encode("utf-8")).hexdigest()


def recompute(m: dict) -> dict:
    comps = m["components"]
    ident = {"schema_version": "IG_RELEASE_BUNDLE_MANIFEST_V1", "git_head": m["identities"]["git_head"]}
    for c in COMPONENTS:
        ident[f"{c}_sha256"] = sha(comps[c])
    return {"identities": ident, "bundle_sha256": sha(ident)}


def judge(m: dict, repo: Path) -> tuple[bool, list]:
    problems = []
    if m.get("schema_version") != "IG_RELEASE_BUNDLE_MANIFEST_V1":
        return False, ["SCHEMA"]
    if m.get("post_pase_dependency") is not False or m.get("promotion_authorized") is not False or m.get("production_authorized") is not False:
        problems.append("AUTHORIZATION_OR_POST_PASE_FLAG")
    comps = m.get("components")
    if not isinstance(comps, dict) or any(not isinstance(comps.get(c), list) or not comps.get(c) for c in COMPONENTS):
        return False, problems + ["COMPONENT_MISSING_OR_EMPTY"]
    head = m.get("identities", {}).get("git_head", "")
    if not re.fullmatch(r"[0-9a-f]{40}", str(head)):
        problems.append("GIT_HEAD_INVALID")
    try:
        r = recompute(m)
    except Exception:
        return False, problems + ["RECOMPUTE_ERROR"]
    if r["identities"] != m["identities"]:
        problems.append("IDENTITY_DIGEST_MISMATCH")
    if r["bundle_sha256"] != m.get("bundle_sha256"):
        problems.append("BUNDLE_SHA_MISMATCH")
    seen = set()
    for e in comps["edge"]:
        slug = EDGE.get(e.get("codigo_activo"))
        f = repo / "supabase" / "functions" / str(slug) / "index.ts"
        if slug is None or not f.is_file() or hashlib.sha256(f.read_bytes()).hexdigest() != e.get("index_ts_sha256"):
            problems.append(f"EDGE_NOT_EQUAL_MAIN:{e.get('codigo_activo')}")
        seen.add(e.get("codigo_activo"))
    if seen != set(EDGE):
        problems.append("EDGE_SET_INCOMPLETE")
    return not problems, problems


def negatives(m: dict, repo: Path) -> list:
    out = []

    def case(name, mutated, expect):
        ok, probs = judge(mutated, repo)
        out.append({"case": name, "blocked": (not ok) and expect in probs, "expected": expect, "got": probs})

    for c in COMPONENTS:
        x = copy.deepcopy(m)
        row = x["components"][c][0]
        k = sorted(row)[-1]
        row[k] = "MUTATED" if row[k] != "MUTATED" else "MUTATED2"
        case(f"MUTATE_{c.upper()}_VALUE", x, "IDENTITY_DIGEST_MISMATCH")
        x = copy.deepcopy(m)
        x["components"][c] = []
        case(f"EMPTY_{c.upper()}", x, "COMPONENT_MISSING_OR_EMPTY")
    x = copy.deepcopy(m)
    x["bundle_sha256"] = "0" * 64
    case("TAMPER_BUNDLE_SHA", x, "BUNDLE_SHA_MISMATCH")
    x = copy.deepcopy(m)
    x["identities"]["git_head"] = "g" * 40
    case("GIT_HEAD_FORMAT", x, "GIT_HEAD_INVALID")
    x = copy.deepcopy(m)
    x["identities"]["git_head"] = "0" * 40
    case("GIT_HEAD_CHANGED", x, "BUNDLE_SHA_MISMATCH")
    x = copy.deepcopy(m)
    x["components"]["edge"][1]["index_ts_sha256"] = "1" * 64
    case("EDGE_NE_MAIN", x, "EDGE_NOT_EQUAL_MAIN:" + x["components"]["edge"][1]["codigo_activo"])
    x = copy.deepcopy(m)
    x["post_pase_dependency"] = True
    case("POST_PASE_DEPENDENCY_FLAG", x, "AUTHORIZATION_OR_POST_PASE_FLAG")
    x = copy.deepcopy(m)
    x["production_authorized"] = True
    case("PRODUCTION_AUTHORIZED_FLAG", x, "AUTHORIZATION_OR_POST_PASE_FLAG")
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest-json", required=True)
    ap.add_argument("--repo", default=".")
    ap.add_argument("--expect-head")
    a = ap.parse_args()
    m = json.loads(Path(a.manifest_json).read_text())
    repo = Path(a.repo)
    vec_ok = all(sha(v) == h for v, h in VECTORS)
    ok, probs = judge(m, repo)
    head_ok = a.expect_head is None or m["identities"]["git_head"] == a.expect_head
    neg = negatives(m, repo)
    # determinism: recomputing twice gives the same value
    det = recompute(m) == recompute(copy.deepcopy(m))
    passed = vec_ok and ok and head_ok and det and all(c["blocked"] for c in neg)
    print(json.dumps({"test": TEST_CODE, "canonical_vectors_ok": vec_ok, "positive_ok": ok, "problems": probs, "head_ok": head_ok,
                      "deterministic": det, "negative_cases": len(neg), "negative_blocked": sum(c["blocked"] for c in neg),
                      "bundle_sha256": m.get("bundle_sha256"), "passed": passed}, sort_keys=True))
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
