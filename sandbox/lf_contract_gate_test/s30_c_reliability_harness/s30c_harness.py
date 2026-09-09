#!/usr/bin/env python3
"""S30-C deterministic evidence/freeze/replay harness. Stdlib only."""
from __future__ import annotations

import argparse
import ast
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path
from typing import Any

PHASES = [
    "CONTRACT_AND_PREFLIGHT",
    "HARNESS_AND_GUARDS",
    "CANDIDATE_EXECUTION",
    "INDEPENDENT_QUALITY",
    "RECONCILIATION_AND_PROMOTION",
]
PRE_MATERIAL = "PRE-MATERIAL-WORK"
REQUIRED_FREEZE_FIELDS = {
    "phase", "version_run_id", "input_identities", "hashes",
    "expected_output_contract", "allowed_mutations",
    "invalidation_triggers", "next_phase",
}
HEX64 = set("0123456789abcdef")

REVIEWER_SCRIPT = r'''#!/usr/bin/env python3
import hashlib, json, os, socket, sys
from pathlib import Path

def deny(*args, **kwargs):
    raise RuntimeError("NETWORK_DISABLED_FOR_S30C_INDEPENDENT_REVIEW")
socket.socket = deny
socket.create_connection = deny

root = Path(sys.argv[1])
manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
results = {}
for rel, expected in manifest["files"].items():
    p = root / rel
    if not p.is_file():
        print(json.dumps({"review_completed": False, "error": "MISSING_FILE", "file": rel}))
        raise SystemExit(2)
    actual = hashlib.sha256(p.read_bytes()).hexdigest()
    results[rel] = {"expected": expected, "actual": actual, "match": actual == expected}
if not all(v["match"] for v in results.values()):
    print(json.dumps({"review_completed": False, "error": "HASH_MISMATCH", "hashes": results}, sort_keys=True))
    raise SystemExit(3)
contract = json.loads((root / "upstream_contract.json").read_text(encoding="utf-8"))
payload = json.loads((root / "artifact_payload.json").read_text(encoding="utf-8"))
receipt = {
    "receipt_version": "S30-R06-QUALITY-v1",
    "execution_mode": "CLEAN_INDEPENDENT_CONTEXT",
    "network_mode": os.environ.get("S30C_NETWORK_MODE", "OFF"),
    "review_completed": True,
    "private_repo_required": False,
    "upstream_contract_id": contract["contract_id"],
    "artifact_id": payload["artifact_id"],
    "artifact_payload_sha256": results["artifact_payload.json"]["actual"],
    "deterministic_checks": "PASS",
    "decision": "PASS_SYNTHETIC"
}
print(json.dumps(receipt, sort_keys=True))
'''

class HarnessFailure(RuntimeError):
    pass

def canonical_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")

def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())

def valid_sha256(value: str) -> bool:
    return isinstance(value, str) and len(value) == 64 and set(value) <= HEX64

def freeze_record_sha(record: dict[str, Any]) -> str:
    return sha256_bytes(canonical_bytes(record))

def validate_freeze_record(record: dict[str, Any]) -> None:
    missing = REQUIRED_FREEZE_FIELDS - set(record)
    if missing:
        raise HarnessFailure(f"FREEZE_FIELDS_MISSING:{','.join(sorted(missing))}")
    if record["phase"] not in PHASES:
        raise HarnessFailure("UNKNOWN_FREEZE_PHASE")
    idx = PHASES.index(record["phase"])
    expected_next = PHASES[idx + 1] if idx + 1 < len(PHASES) else None
    if record["next_phase"] != expected_next:
        raise HarnessFailure("INVALID_NEXT_PHASE")
    if not isinstance(record["version_run_id"], str) or not record["version_run_id"]:
        raise HarnessFailure("INVALID_RUN_ID")
    if not isinstance(record["input_identities"], dict):
        raise HarnessFailure("INVALID_INPUT_IDENTITIES")
    if not isinstance(record["hashes"], dict) or not record["hashes"]:
        raise HarnessFailure("INVALID_HASH_MAP")
    if any(not isinstance(k, str) or not valid_sha256(v) for k, v in record["hashes"].items()):
        raise HarnessFailure("INVALID_HASH_ENTRY")
    if not isinstance(record["expected_output_contract"], dict):
        raise HarnessFailure("INVALID_EXPECTED_OUTPUT_CONTRACT")
    if not isinstance(record["allowed_mutations"], list):
        raise HarnessFailure("INVALID_ALLOWED_MUTATIONS")
    if not isinstance(record["invalidation_triggers"], list):
        raise HarnessFailure("INVALID_INVALIDATION_TRIGGERS")

def validate_freeze_transition(previous: dict[str, Any], current: dict[str, Any]) -> None:
    validate_freeze_record(previous)
    validate_freeze_record(current)
    if PHASES.index(current["phase"]) != PHASES.index(previous["phase"]) + 1:
        raise HarnessFailure("FREEZE_PHASE_SKIP_OR_REUSE")
    if current.get("prior_freeze_sha256") != freeze_record_sha(previous):
        raise HarnessFailure("PRIOR_FREEZE_HASH_MISMATCH")
    for key, value in previous["input_identities"].items():
        if key in current["input_identities"] and current["input_identities"][key] != value:
            raise HarnessFailure(f"GATE_CROSS_MUTATION_INPUT:{key}")
    for key, value in previous["hashes"].items():
        if key in current["hashes"] and current["hashes"][key] != value:
            raise HarnessFailure(f"GATE_CROSS_MUTATION_HASH:{key}")

def _violation(case: dict[str, Any]) -> bool:
    s, k = case["stimulus"], case["fault_kind"]
    rules = {
        "db_missing_column": lambda: s["requested_column"] not in s["introspected_columns"],
        "wrong_relation": lambda: s["requested_relation"] not in s["available_relations"],
        "identity_generated_always": lambda: s["identity_mode"] == "GENERATED ALWAYS" and s["write_includes_identity"] and not s["overriding_system_value"],
        "wrong_function_schema": lambda: s["requested_function"] not in s["available_functions"],
        "ekb_not_consumed": lambda: not set(s["required_ekb"]).issubset(s["consumed_ekb"]),
        "field_unbound": lambda: not set(s["required_bindings"]).issubset(s["resolved_bindings"]),
        "import_closure_missing": lambda: not set(s["imports"]).issubset(s["resolved_imports"]),
        "required_file_absent": lambda: not set(s["required_files"]).issubset(s["present_files"]),
        "dependency_unresolved": lambda: not set(s["required_dependencies"]).issubset(s["resolved_dependencies"]),
        "regression_not_wired": lambda: s["required_regression_command"] not in s["workflow_commands"],
        "non_applicable_gate_blocks_lane": lambda: (not s["gate_applies"]) and s["gate_decision"] == "BLOCK",
        "unknown_path_false_na": lambda: s["path_classification"] == "UNKNOWN" and s["decision"] == "N/A",
        "bundle_incomplete": lambda: not set(s["manifest_files"]).issubset(s["bundle_files"]),
        "artifact_not_materialized": lambda: not set(s["declared_artifacts"]).issubset(s["materialized_files"]),
        "hash_mismatch": lambda: s["expected_hash"] != s["actual_hash"],
        "upstream_contract_absent": lambda: s["contract_required"] and "upstream_contract.json" not in s["bundle_files"],
        "clean_reviewer_insufficient_evidence": lambda: not set(s["required_evidence"]).issubset(s["available_evidence"]),
        "freeze_cross_mutation": lambda: s["same_run"] and s["prior_hash"] != s["current_hash"],
        "stale_head_evidence": lambda: s["evidence_head"] != s["current_head"],
        "invented_argument": lambda: not set(s["attempted_args"]).issubset(s["allowed_args"]),
        "tool_schema_unresolved": lambda: s["call_attempted"] and not s["schema_resolved"],
    }
    if k not in rules:
        raise HarnessFailure(f"UNKNOWN_FAULT_KIND:{k}")
    return bool(rules[k]())

def replay_case(case: dict[str, Any]) -> dict[str, Any]:
    if case.get("machine_detectable") and case.get("expected_stage_of_failure") != PRE_MATERIAL:
        raise HarnessFailure(f"BAD_EXPECTED_STAGE:{case.get('case_id')}")
    if _violation(case):
        return {"case_id": case["case_id"], "decision": "BLOCK", "observed_stage": PRE_MATERIAL,
                "first_bad_hop": case["expected_first_bad_hop"], "readback": "DETECTED_BEFORE_MATERIAL_WORK"}
    return {"case_id": case["case_id"], "decision": "PASS", "observed_stage": "MATERIAL-WORK",
            "first_bad_hop": None, "readback": "VIOLATION_NOT_DETECTED"}

def replay_corpus(corpus: dict[str, Any]) -> dict[str, Any]:
    results = [replay_case(c) for c in corpus["cases"]]
    by_id = {c["case_id"]: c for c in corpus["cases"]}
    escapes = [r for r in results if r["observed_stage"] != PRE_MATERIAL]
    metrics = {
        "PREVENTABLE_FIRST_HOP_ESCAPE_COUNT": len(escapes),
        "avoidable_retry_count": len(escapes),
        "schema_introspection_after_error_count": sum(by_id[r["case_id"]]["category"] == "DB/schema" for r in escapes),
        "unbound_field_or_argument_attempts": sum(by_id[r["case_id"]]["fault_kind"] in {"field_unbound", "invented_argument", "tool_schema_unresolved"} for r in escapes),
        "gate_cross_mutation_count": sum(by_id[r["case_id"]]["fault_kind"] == "freeze_cross_mutation" for r in escapes),
        "false_N/A": sum(r["decision"] == "N/A" for r in results),
        "false_PASS": sum(r["decision"] == "PASS" for r in results),
        "missing_readback": sum(not r.get("readback") for r in results),
    }
    return {"corpus_id": corpus["corpus_id"], "case_count": len(results), "metrics": metrics, "results": results,
            "build_replay_status": "PASS" if all(v == 0 for v in metrics.values()) else "FAIL",
            "final_r09_acceptance": "NOT_RUN_WAITING_FOR_FROZEN_S30_A_AND_S30_B"}

def _fixed_zip_write(zf: zipfile.ZipFile, rel: str, data: bytes) -> None:
    info = zipfile.ZipInfo(rel, date_time=(2026, 9, 9, 12, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o600 << 16
    zf.writestr(info, data)

def create_frozen_bundle(work: Path) -> tuple[Path, dict[str, Any]]:
    producer, persisted = work / "producer", work / "persisted"
    producer.mkdir(parents=True); persisted.mkdir(parents=True)
    payload = {"artifact_id": "S30-R06-SYNTHETIC-001", "producer": "S30-C-synthetic-producer",
               "value": {"status": "candidate", "number": 30}}
    contract = {"contract_id": "S30-R06-UPSTREAM-CONTRACT-v1",
                "required_artifact_fields": ["artifact_id", "producer", "value"], "quality_mode": "DETERMINISTIC_ONLY"}
    (producer / "artifact_payload.json").write_bytes(canonical_bytes(payload))
    shutil.copy2(producer / "artifact_payload.json", persisted / "artifact_payload.json")
    (persisted / "upstream_contract.json").write_bytes(canonical_bytes(contract))
    (persisted / "independent_reviewer.py").write_text(REVIEWER_SCRIPT, encoding="utf-8", newline="\n")
    names = ["artifact_payload.json", "upstream_contract.json", "independent_reviewer.py"]
    manifest = {"bundle_id": "S30-R06-FROZEN-BUNDLE-v1", "files": {n: sha256_file(persisted / n) for n in names},
                "artifact_payload_sha256": sha256_file(persisted / "artifact_payload.json")}
    (persisted / "manifest.json").write_bytes(canonical_bytes(manifest)); names.append("manifest.json")
    bundle = work / "frozen_bundle.zip"
    with zipfile.ZipFile(bundle, "w") as zf:
        for name in names: _fixed_zip_write(zf, name, (persisted / name).read_bytes())
    return bundle, manifest

def independent_review(bundle: Path) -> tuple[dict[str, Any], Path]:
    clean = Path(tempfile.mkdtemp(prefix="s30c_clean_review_"))
    with zipfile.ZipFile(bundle, "r") as zf: zf.extractall(clean)
    env = {"PATH": os.environ.get("PATH", ""), "S30C_NETWORK_MODE": "OFF", "PYTHONNOUSERSITE": "1"}
    proc = subprocess.run([sys.executable, "-I", str(clean / "independent_reviewer.py"), str(clean)], cwd=clean,
                          env=env, text=True, capture_output=True, timeout=20)
    if proc.returncode != 0:
        raise HarnessFailure(f"INDEPENDENT_REVIEW_FAILED:{proc.returncode}:{proc.stdout.strip()}:{proc.stderr.strip()}")
    return json.loads(proc.stdout.strip().splitlines()[-1]), clean

def run_artifact_e2e() -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="s30c_r06_") as td:
        bundle, manifest = create_frozen_bundle(Path(td)); receipt, clean = independent_review(bundle)
        try:
            hash_ok = receipt["artifact_payload_sha256"] == manifest["artifact_payload_sha256"]
            probes = {
                "PRIVATE_REPO_UNAVAILABLE_BUT_FROZEN_BUNDLE_SELF_CONTAINED": not (clean / ".git").exists() and receipt["private_repo_required"] is False,
                "ARTIFACT_PAYLOAD_HASH_RECOMPUTES_EXACTLY": hash_ok,
                "UPSTREAM_CONTRACT_AVAILABLE_WITHOUT_CHAT_MEMORY": (clean / "upstream_contract.json").is_file() and bool(receipt["upstream_contract_id"]),
                "INDEPENDENT_REVIEWER_CAN_COMPLETE_WITH_NETWORK_OFF": receipt["network_mode"] == "OFF" and receipt["review_completed"],
            }
            reconciled = receipt["decision"] == "PASS_SYNTHETIC" and receipt["deterministic_checks"] == "PASS" and hash_ok
            return {"bundle_sha256": sha256_file(bundle), "manifest": manifest, "quality_receipt": receipt,
                    "reconciliation": "PASS" if reconciled else "FAIL", "probes": probes}
        finally: shutil.rmtree(clean, ignore_errors=True)

def import_closure(paths: list[Path]) -> dict[str, Any]:
    stdlib = set(getattr(sys, "stdlib_module_names", ())); imported = set()
    for path in paths:
        tree = ast.parse(path.read_text(encoding="utf-8"))
        for node in ast.walk(tree):
            if isinstance(node, ast.Import): imported.update(a.name.split(".")[0] for a in node.names)
            elif isinstance(node, ast.ImportFrom) and node.module: imported.add(node.module.split(".")[0])
    internal = {"__future__"} | {p.stem for p in paths}; unresolved = sorted(x for x in imported if x not in stdlib and x not in internal)
    return {"imports": sorted(imported), "unresolved": unresolved, "complete": not unresolved}

def workflow_wiring(workflow: Path) -> dict[str, Any]:
    text = workflow.read_text(encoding="utf-8")
    required = ["python sandbox/lf_contract_gate_test/s30_c_reliability_harness/test_s30c_harness.py",
                "python sandbox/lf_contract_gate_test/s30_c_reliability_harness/s30c_harness.py ci-receipt",
                "S30C_CI_ACTUAL: \"1\"", "startsWith(github.ref, 'refs/heads/lf/s30-c-')"]
    missing = [x for x in required if x not in text]
    return {"required_markers": required, "missing": missing, "wired": not missing}

def build_self_check(root: Path) -> dict[str, Any]:
    harness_dir = root / "sandbox/lf_contract_gate_test/s30_c_reliability_harness"
    workflow = root / ".github/workflows/validate-lf-packs.yml"
    corpus = json.loads((harness_dir / "replay_corpus.json").read_text(encoding="utf-8")); e2e = run_artifact_e2e()
    closure = import_closure([harness_dir / "s30c_harness.py", harness_dir / "test_s30c_harness.py"]); wiring = workflow_wiring(workflow)
    e2e["probes"]["CI_RUNNER_ACTUALLY_EXECUTES_NEW_REGRESSION"] = bool(os.environ.get("S30C_CI_ACTUAL") == "1" and wiring["wired"])
    e2e["probes"]["DEPENDENCY_IMPORT_CLOSURE_COMPLETE"] = closure["complete"]
    return {"r06": e2e, "r07": {"freeze_contract_loaded": (harness_dir / "freeze_contract.json").is_file()},
            "r09_build_replay": replay_corpus(corpus), "dependency_import_closure": closure, "ci_wiring": wiring}

def ci_receipt(root: Path) -> dict[str, Any]:
    check = build_self_check(root); probes = check["r06"]["probes"]; metrics = check["r09_build_replay"]["metrics"]
    ok = all(probes.values()) and check["r06"]["reconciliation"] == "PASS" and all(v == 0 for v in metrics.values()) and check["ci_wiring"]["wired"]
    return {"receipt_version": "S30-C-CI-READBACK-v1", "semantic_status": "BUILD_HARNESS_VERIFIED" if ok else "BUILD_HARNESS_FAILED",
            "CI_RUNNER_ACTUALLY_EXECUTES_NEW_REGRESSION": "PASS" if probes["CI_RUNNER_ACTUALLY_EXECUTES_NEW_REGRESSION"] else "FAIL",
            "r06_probes": probes, "r06_reconciliation": check["r06"]["reconciliation"], "r09_build_metrics": metrics,
            "r09_final": "NOT_RUN_WAITING_FOR_FROZEN_S30_A_AND_S30_B", "exit_state": "READY_FOR_FINAL_R09_INTEGRATION" if ok else "NOT_READY",
            "claim_ceiling": "EVIDENCE_FREEZE_AND_REPLAY_HARNESS_READY" if ok else "NONE"}

def main() -> int:
    p = argparse.ArgumentParser(); p.add_argument("command", choices=["self-check", "ci-receipt", "replay"])
    p.add_argument("--root", default=str(Path(__file__).resolve().parents[3])); args = p.parse_args(); root = Path(args.root).resolve()
    if args.command == "self-check": out = build_self_check(root)
    elif args.command == "replay":
        c = root / "sandbox/lf_contract_gate_test/s30_c_reliability_harness/replay_corpus.json"; out = replay_corpus(json.loads(c.read_text(encoding="utf-8")))
    else:
        out = ci_receipt(root); print(json.dumps(out, sort_keys=True)); return 0 if out["exit_state"] == "READY_FOR_FINAL_R09_INTEGRATION" else 1
    print(json.dumps(out, indent=2, sort_keys=True)); return 0

if __name__ == "__main__":
    raise SystemExit(main())
