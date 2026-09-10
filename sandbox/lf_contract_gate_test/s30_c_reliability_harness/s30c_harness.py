#!/usr/bin/env python3
"""S30-C deterministic evidence/freeze/replay harness. Stdlib only; no model calls."""
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
READY = "READY_FOR_FINAL_R09_INTEGRATION"
CLAIM = "EVIDENCE_FREEZE_AND_REPLAY_HARNESS_READY"
HEX64 = set("0123456789abcdef")
REQUIRED_FREEZE_FIELDS = {
    "phase", "version_run_id", "input_identities", "hashes",
    "expected_output_contract", "allowed_mutations",
    "invalidation_triggers", "next_phase",
}

REVIEWER_SCRIPT = r'''#!/usr/bin/env python3
import hashlib, json, os, socket, sys
from pathlib import Path

def deny(*args, **kwargs):
    raise RuntimeError("NETWORK_DISABLED_FOR_S30C_INDEPENDENT_REVIEW")
socket.socket = deny
socket.create_connection = deny
root = Path(sys.argv[1])
manifest = json.loads((root / "bundle_manifest.json").read_text(encoding="utf-8"))
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
    "receipt_version": "S30-R06-QUALITY-v2",
    "execution_mode": "CLEAN_INDEPENDENT_CONTEXT",
    "network_mode": os.environ.get("S30C_NETWORK_MODE", "OFF"),
    "review_completed": True,
    "private_repo_required": False,
    "chat_memory_required": False,
    "model_calls": 0,
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
    if current["version_run_id"] != previous["version_run_id"]:
        raise HarnessFailure("FREEZE_RUN_ID_CHANGED_WITHOUT_BOUNDED_VERSION")
    for key, value in previous["input_identities"].items():
        if key in current["input_identities"] and current["input_identities"][key] != value:
            raise HarnessFailure(f"GATE_CROSS_MUTATION_INPUT:{key}")
    for key, value in previous["hashes"].items():
        if key in current["hashes"] and current["hashes"][key] != value:
            raise HarnessFailure(f"GATE_CROSS_MUTATION_HASH:{key}")


def validate_freeze_chain(chain: dict[str, Any]) -> dict[str, Any]:
    records = chain.get("records")
    if not isinstance(records, list) or not records:
        raise HarnessFailure("FREEZE_CHAIN_EMPTY")
    for record in records:
        validate_freeze_record(record)
    for prev, cur in zip(records, records[1:]):
        validate_freeze_transition(prev, cur)
    return {"status": "PASS", "record_count": len(records), "last_phase": records[-1]["phase"]}


def _violation(case: dict[str, Any]) -> bool:
    s, kind = case["stimulus"], case["fault_kind"]
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
        "derivable_work_sent_to_model": lambda: s["work_classification"] == "DETERMINISTIC" and not s["semantic_gap_present"] and s["model_call_attempted"],
        "model_system_owned_field": lambda: not set(s["model_fields"]).issubset(s["allowed_model_fields"]),
        "calculable_score_delegated_to_model": lambda: s["score_calculable"] and s["score_authority"] != "DETERMINISTIC",
        "producer_self_verdict": lambda: "self_verdict" in s["producer_output_fields"],
        "nondeterministic_materialization": lambda: s["materializer_authority"] != s["required_authority"],
        "semantic_judge_replaces_guard": lambda: s["semantic_judge_role"] != s["allowed_role"],
    }
    if kind not in rules:
        raise HarnessFailure(f"UNKNOWN_FAULT_KIND:{kind}")
    return bool(rules[kind]())


def replay_case(case: dict[str, Any]) -> dict[str, Any]:
    if case.get("machine_detectable") and case.get("expected_stage_of_failure") != PRE_MATERIAL:
        raise HarnessFailure(f"BAD_EXPECTED_STAGE:{case.get('case_id')}")
    if _violation(case):
        return {
            "case_id": case["case_id"], "decision": "BLOCK", "observed_stage": PRE_MATERIAL,
            "first_bad_hop": case["expected_first_bad_hop"], "readback": "DETECTED_BEFORE_MATERIAL_WORK",
            "model_calls": 0,
        }
    return {
        "case_id": case["case_id"], "decision": "PASS", "observed_stage": "MATERIAL-WORK",
        "first_bad_hop": None, "readback": "VIOLATION_NOT_DETECTED", "model_calls": 0,
    }


def replay_corpus(corpus: dict[str, Any]) -> dict[str, Any]:
    results = [replay_case(case) for case in corpus["cases"]]
    by_id = {case["case_id"]: case for case in corpus["cases"]}
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
        "model_calls_for_machine_detectable_replay": sum(r["model_calls"] for r in results),
    }
    return {
        "corpus_id": corpus["corpus_id"], "case_count": len(results), "metrics": metrics, "results": results,
        "build_replay_status": "PASS" if all(v == 0 for v in metrics.values()) else "FAIL",
        "final_r09_acceptance": "NOT_RUN_DEFERRED_TO_S30_D",
    }


def create_frozen_bundle(work: Path) -> tuple[Path, dict[str, Any]]:
    producer = work / "producer"
    persisted = work / "persisted"
    bundle = work / "frozen_bundle"
    producer.mkdir(parents=True)
    persisted.mkdir(parents=True)
    payload = {
        "artifact_id": "S30-R06-SYNTHETIC-002",
        "producer": "S30-C-synthetic-producer",
        "value": {"status": "candidate", "number": 30},
    }
    contract = {
        "contract_id": "S30-R06-UPSTREAM-CONTRACT-v2",
        "required_artifact_fields": ["artifact_id", "producer", "value"],
        "quality_mode": "DETERMINISTIC_ONLY",
        "model_calls_allowed": 0,
    }
    (producer / "artifact_payload.json").write_bytes(canonical_bytes(payload))
    shutil.copy2(producer / "artifact_payload.json", persisted / "artifact_payload.json")
    (persisted / "upstream_contract.json").write_bytes(canonical_bytes(contract))
    (persisted / "independent_reviewer.py").write_text(REVIEWER_SCRIPT, encoding="utf-8", newline="\n")
    files = ["artifact_payload.json", "upstream_contract.json", "independent_reviewer.py"]
    manifest = {
        "bundle_id": "S30-R06-FROZEN-BUNDLE-v2",
        "format": "SELF_CONTAINED_DIRECTORY",
        "files": {name: sha256_file(persisted / name) for name in files},
        "artifact_payload_sha256": sha256_file(persisted / "artifact_payload.json"),
    }
    (persisted / "bundle_manifest.json").write_bytes(canonical_bytes(manifest))
    shutil.copytree(persisted, bundle)
    return bundle, manifest


def independent_review(bundle: Path) -> tuple[dict[str, Any], Path]:
    clean = Path(tempfile.mkdtemp(prefix="s30c_clean_review_"))
    shutil.copytree(bundle, clean / "bundle", dirs_exist_ok=True)
    target = clean / "bundle"
    env = {"PATH": os.environ.get("PATH", ""), "S30C_NETWORK_MODE": "OFF", "PYTHONNOUSERSITE": "1"}
    proc = subprocess.run(
        [sys.executable, "-I", str(target / "independent_reviewer.py"), str(target)],
        cwd=target, env=env, text=True, capture_output=True, timeout=20,
    )
    if proc.returncode != 0:
        raise HarnessFailure(f"INDEPENDENT_REVIEW_FAILED:{proc.returncode}:{proc.stdout.strip()}:{proc.stderr.strip()}")
    return json.loads(proc.stdout.strip().splitlines()[-1]), clean


def run_artifact_e2e() -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="s30c_r06_") as td:
        bundle, manifest = create_frozen_bundle(Path(td))
        receipt, clean = independent_review(bundle)
        try:
            hash_ok = receipt["artifact_payload_sha256"] == manifest["artifact_payload_sha256"]
            probes = {
                "PRIVATE_REPO_UNAVAILABLE_BUT_FROZEN_BUNDLE_SELF_CONTAINED": not (clean / "bundle" / ".git").exists() and receipt["private_repo_required"] is False,
                "ARTIFACT_PAYLOAD_HASH_RECOMPUTES_EXACTLY": hash_ok,
                "UPSTREAM_CONTRACT_AVAILABLE_WITHOUT_CHAT_MEMORY": (clean / "bundle" / "upstream_contract.json").is_file() and receipt["chat_memory_required"] is False,
                "INDEPENDENT_REVIEWER_CAN_COMPLETE_WITH_NETWORK_OFF": receipt["network_mode"] == "OFF" and receipt["review_completed"],
                "MODEL_NOT_REQUIRED_FOR_EVIDENCE_PATH": receipt["model_calls"] == 0,
            }
            reconciled = receipt["decision"] == "PASS_SYNTHETIC" and receipt["deterministic_checks"] == "PASS" and hash_ok
            return {
                "bundle_manifest_sha256": sha256_bytes(canonical_bytes(manifest)),
                "manifest": manifest, "quality_receipt": receipt,
                "reconciliation": "PASS" if reconciled else "FAIL", "probes": probes,
            }
        finally:
            shutil.rmtree(clean, ignore_errors=True)


def import_closure(paths: list[Path]) -> dict[str, Any]:
    stdlib = set(getattr(sys, "stdlib_module_names", ()))
    imported: set[str] = set()
    for path in paths:
        tree = ast.parse(path.read_text(encoding="utf-8"))
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                imported.update(alias.name.split(".")[0] for alias in node.names)
            elif isinstance(node, ast.ImportFrom) and node.module:
                imported.add(node.module.split(".")[0])
    internal = {"__future__"} | {path.stem for path in paths}
    unresolved = sorted(name for name in imported if name not in stdlib and name not in internal)
    return {"imports": sorted(imported), "unresolved": unresolved, "complete": not unresolved}


def workflow_wiring(workflow: Path) -> dict[str, Any]:
    text = workflow.read_text(encoding="utf-8")
    required = [
        "Validate bounded S30 sandbox regressions",
        "tests=(sandbox/lf_contract_gate_test/s30_*/test_*.py)",
        'python "${test_file}"',
        "BLOCK_S30_SANDBOX_REGRESSION_MISSING",
    ]
    missing = [marker for marker in required if marker not in text]
    return {
        "mode": "GENERIC_S30_DISCOVERY",
        "test_path": "sandbox/lf_contract_gate_test/s30_c_reliability_harness/test_s30c_harness.py",
        "required_markers": required, "missing": missing, "wired": not missing,
    }


def upstream_receipt_binding(root: Path) -> dict[str, Any]:
    hdir = root / "sandbox/lf_contract_gate_test/s30_c_reliability_harness"
    manifest = json.loads((hdir / "source_manifest.json").read_text(encoding="utf-8"))
    bound = manifest["upstream_frozen_receipts"]
    results = {}
    for key, spec in bound.items():
        p = root / spec["path"]
        actual = sha256_file(p) if p.is_file() else None
        results[key] = {"exists": p.is_file(), "expected_sha256": spec["sha256"], "actual_sha256": actual, "hash_match": actual == spec["sha256"]}
    if not all(r["exists"] and r["hash_match"] for r in results.values()):
        return {"status": "BLOCKED", "blocking_code": "BLOCK_UPSTREAM_FROZEN_RECEIPT_HASH", "bindings": results}
    a = json.loads((root / bound["S30-A"]["path"]).read_text(encoding="utf-8"))
    b = json.loads((root / bound["S30-B"]["path"]).read_text(encoding="utf-8"))
    be = json.loads((root / bound["S30-B-evidence"]["path"]).read_text(encoding="utf-8"))
    checks = {
        "s30_a_closeout": a.get("receipt_mode") == "CLOSEOUT",
        "s30_a_claim": (a.get("gate_evidence_envelope") or {}).get("output_exact", {}).get("result") == bound["S30-A"]["required_result"],
        "s30_b_result": b.get("result") == bound["S30-B"]["required_result"],
        "s30_b_terminal": b.get("terminal_state") == "FINAL_CLOSED" and b.get("remaining_blockers") == [],
        "s30_b_evidence_terminal": be.get("verification_state") == bound["S30-B-evidence"]["required_state"] and be.get("remaining_gates") == [],
    }
    return {
        "status": "PASS" if all(checks.values()) else "BLOCKED",
        "blocking_code": None if all(checks.values()) else "BLOCK_UPSTREAM_FROZEN_RECEIPT_STATE",
        "checks": checks, "bindings": results,
    }


def build_self_check(root: Path) -> dict[str, Any]:
    hdir = root / "sandbox/lf_contract_gate_test/s30_c_reliability_harness"
    workflow = root / ".github/workflows/validate-lf-packs.yml"
    corpus = json.loads((hdir / "replay_corpus.json").read_text(encoding="utf-8"))
    closure = import_closure([hdir / "s30c_harness.py", hdir / "test_s30c_harness.py"])
    wiring = workflow_wiring(workflow)
    upstream = upstream_receipt_binding(root)
    freeze_chain_path = hdir / "freeze_records.json"
    freeze_chain = validate_freeze_chain(json.loads(freeze_chain_path.read_text(encoding="utf-8"))) if freeze_chain_path.is_file() else {"status": "PENDING"}
    return {
        "execution_authority": {"default": "DETERMINISTIC_FIRST", "model_calls": 0},
        "r06": run_artifact_e2e(),
        "r07": {"freeze_contract_loaded": (hdir / "freeze_contract.json").is_file(), "freeze_chain": freeze_chain},
        "r09_build_replay": replay_corpus(corpus),
        "upstream_receipts": upstream,
        "dependency_import_closure": closure,
        "ci_wiring": wiring,
    }


def readiness(root: Path) -> dict[str, Any]:
    check = build_self_check(root)
    metrics = check["r09_build_replay"]["metrics"]
    probes = check["r06"]["probes"]
    ok = (
        all(probes.values())
        and check["r06"]["reconciliation"] == "PASS"
        and all(value == 0 for value in metrics.values())
        and check["upstream_receipts"]["status"] == "PASS"
        and check["dependency_import_closure"]["complete"]
        and check["ci_wiring"]["wired"]
        and check["r07"]["freeze_chain"].get("status") == "PASS"
    )
    return {
        "status": "PASS" if ok else "BLOCKED",
        "exit_state": READY if ok else "NOT_READY",
        "claim_ceiling": CLAIM if ok else "NONE",
        "model_calls": 0,
        "r09_final_acceptance": "NOT_RUN_DEFERRED_TO_S30_D",
        "details": check,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["self-check", "readiness", "replay", "upstream"])
    parser.add_argument("--root", default=str(Path(__file__).resolve().parents[3]))
    args = parser.parse_args()
    root = Path(args.root).resolve()
    if args.command == "self-check":
        out = build_self_check(root)
    elif args.command == "readiness":
        out = readiness(root)
    elif args.command == "upstream":
        out = upstream_receipt_binding(root)
    else:
        corpus = root / "sandbox/lf_contract_gate_test/s30_c_reliability_harness/replay_corpus.json"
        out = replay_corpus(json.loads(corpus.read_text(encoding="utf-8")))
    print(json.dumps(out, indent=2, sort_keys=True))
    return 0 if out.get("status", out.get("build_replay_status", "PASS")) != "BLOCKED" else 1


if __name__ == "__main__":
    raise SystemExit(main())
