#!/usr/bin/env python3
from __future__ import annotations
import copy, hashlib, json, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
VALIDATOR = HERE.parent.parent / "validators" / "validate_semantic_judge_result.py"
RESULT = HERE / "mr02_r2_semantic_judge_result.json"
SCOPE = HERE / "mr02_r2_scope_authority_packet.json"
MANIFEST = HERE / "mr02_r2_replay_manifest.json"

def canonical_sha(payload: dict) -> str:
    raw = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()

def run(payload: dict, name: str, bind_scope: bool = True) -> tuple[str, dict]:
    tmp = HERE / (".tmp_" + name + ".json")
    try:
        tmp.write_text(json.dumps(payload, ensure_ascii=False, sort_keys=True), encoding="utf-8")
        cmd = [sys.executable, str(VALIDATOR), str(tmp)]
        if bind_scope:
            cmd += ["--scope-packet", str(SCOPE), "--candidate-sha256", payload.get("candidate_sha256", ""), "--scope-packet-sha256", payload.get("scope_packet_sha256", "")]
        proc = subprocess.run(cmd, text=True, capture_output=True)
        data = json.loads(proc.stdout)
        return ("PASS" if proc.returncode == 0 else "FAIL", data)
    finally:
        tmp.unlink(missing_ok=True)

base = json.loads(RESULT.read_text(encoding="utf-8"))
scope = json.loads(SCOPE.read_text(encoding="utf-8"))
manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
out = {}

scope_sha = canonical_sha(scope)
scope_ok = (
    scope_sha == base["scope_packet_sha256"]
    and scope_sha == manifest["scope_packet_sha256"]
)
out["scope_packet_sha_binding"] = {
    "observed": "PASS" if scope_ok else "FAIL",
    "expected": "PASS",
    "scope_sha256": scope_sha,
}

candidate_ok = base["candidate_sha256"] == manifest["candidate_sha256"]
out["candidate_sha_binding"] = {
    "observed": "PASS" if candidate_ok else "FAIL",
    "expected": "PASS",
    "candidate_sha256": base["candidate_sha256"],
}

state, data = run(base, "expected_return")
out["mr02_r2_expected_return_shape"] = {"observed": state, "detail": data, "expected": "PASS"}

bad = copy.deepcopy(base)
bad["verdict"] = "PASS_INDEPENDENT_SEMANTIC"
bad["blocking_codes"] = []
bad["open_design_decisions_found"] = []
state, data = run(bad, "malicious_pass")
out["malicious_pass_fail_closed"] = {"observed": state, "detail": data, "expected": "FAIL"}


missing_scope_item = copy.deepcopy(base)
missing_scope_item["requirement_reconciliation"] = [
    x for x in missing_scope_item["requirement_reconciliation"]
    if x.get("scope_item_id") != scope["constraints"][0]["id"]
]
state, data = run(missing_scope_item, "missing_scope_item")
out["missing_scope_item_fail_closed"] = {"observed": state, "detail": data, "expected": "FAIL"}

missing = copy.deepcopy(base)
missing["scope_conformance_reconciliation"] = [
    x for x in missing["scope_conformance_reconciliation"] if x["change_id"] != "JCHG-002"
]
state, data = run(missing, "missing_coverage")
out["missing_change_scope_coverage"] = {"observed": state, "detail": data, "expected": "FAIL"}

ok = all(v["observed"] == v["expected"] for v in out.values())
print(json.dumps({"status": "PASS" if ok else "FAIL", "cases": out}, ensure_ascii=False, sort_keys=True))
raise SystemExit(0 if ok else 1)
