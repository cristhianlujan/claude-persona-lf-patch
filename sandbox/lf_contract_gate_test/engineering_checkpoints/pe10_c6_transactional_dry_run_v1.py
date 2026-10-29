#!/usr/bin/env python3
"""PE10_C6 declared test: real source tests + immutable GPT chat source proof.

This script does NOT manufacture DB authorization or provider attestation.
The material PostgreSQL positive/negative and rolled-back probe runs through
LF Migration Merge Train (migration companion) under canonical authority.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
# La captura 2026-10-16 (GPT) quedo obsoleta: el perfil cambio (SOURCE_HEAD_DRIFT). Se conserva intacta como historia.
CAPTURE = ROOT / "skills/profile_creator/evals/results/pe10_c6_same_chat_claude_material_authoring_20261027.json"
NATIVE_MODES = ("GPT_NATIVE", "CLAUDE_NATIVE")
SAME_CHAT = ROOT / "skills/profile_creator/validators/profile_updater_same_chat_v02.py"
DISPATCH = ROOT / "skills/profile_creator/validators/execute_profile_evolution_v02.py"
OIDC = ROOT / "skills/profile_creator/validators/profile_evolution_oidc_recorder_v02.py"

SUITES = [
    ("same_chat", "skills/profile_creator/evals/test_profile_updater_same_chat_v02.py", 17),
    ("planner", "skills/profile_creator/evals/test_profile_evolution_reconciliation_v1.py", 13),
    ("dispatch", "skills/profile_creator/evals/test_execute_profile_evolution_v02.py", 10),
    ("oidc_transport", "skills/profile_creator/evals/test_profile_evolution_oidc_recorder_v02.py", 7),
    ("dynamic_selection", "skills/profile_creator/evals/test_pe10_c6_dynamic_selection_repro_v2.py", 10),
]


def _json_sha(value: object) -> str:
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
        separators=(",", ":")).encode("utf-8")).hexdigest()


def check_material_capture() -> dict:
    capture_package = json.loads(CAPTURE.read_text(encoding="utf-8"))
    handoff, capture = capture_package["handoff"], capture_package["capture"]
    if handoff["handoff_sha256"] != _json_sha({
        k: v for k, v in handoff.items() if k != "handoff_sha256"
    }):
        raise ValueError("HANDOFF_SHA_MISMATCH")
    if capture["capture_sha256"] != _json_sha({
        k: v for k, v in capture.items() if k != "capture_sha256"
    }):
        raise ValueError("CAPTURE_SHA_MISMATCH")
    if capture["raw_output_sha256"] != _json_sha(capture["raw_output"]):
        raise ValueError("RAW_SHA_MISMATCH")
    if capture["handoff_sha256"] != handoff["handoff_sha256"]:
        raise ValueError("RAW_HANDOFF_MISMATCH")
    if capture["raw_output"]["methods_applied"] != handoff["selected_method_ids"]:
        raise ValueError("RAW_METHODS_MISMATCH")
    if handoff["executor_mode"] not in NATIVE_MODES:
        raise ValueError("EXECUTOR_NOT_NATIVE_CHAT")
    if (handoff["session_creation"] is not False
            or handoff["api_invocation"] is not False
            or capture["runtime_provider_attested"] is not False
            or capture["cutover_eligible"] is not False
            or capture["production_activated"] is not False):
        raise ValueError("SOURCE_CAPTURE_FORGED_AUTHORITY")
    for source in handoff["source_manifest"]:
        p = (ROOT / source["ref"]).resolve()
        if not p.is_relative_to(ROOT.resolve()) or not p.is_file():
            raise ValueError("SOURCE_PATH_UNAVAILABLE")
        if hashlib.sha256(p.read_bytes()).hexdigest() != source["sha256"]:
            raise ValueError("SOURCE_HEAD_DRIFT")
    return {"run_id": handoff["run_id"], "methods": handoff["selected_method_ids"],
            "capture_sha256": capture["capture_sha256"],
            "executor_mode": handoff["executor_mode"],
            "source_bound": True, "runtime_provider_attested": False}


def run_suite(name: str, path: str, expected: int) -> dict:
    file = ROOT / path
    if not file.is_file():
        raise RuntimeError("DECLARED_TEST_MISSING:" + path)
    proc = subprocess.run([sys.executable, str(file), "-q"], cwd=ROOT,
        text=True, capture_output=True, timeout=80, check=False)
    output = proc.stdout + "\n" + proc.stderr
    if proc.returncode:
        raise RuntimeError("TEST_FAILED:" + name + ":" + output[-2000:])
    if name == "dynamic_selection":
        got = len(re.findall(r"^PASS C\d{2}\b", output, re.MULTILINE))
        if "PASS FULL_EIGHT_METHODS_IN_TWO_SUBTASKS" not in output or (
            "PASS NEGATIVE_GATES" not in output):
            raise RuntimeError("MATRIX_FULL_OR_NEGATIVE_MISSING")
    else:
        match = re.search(r"Ran (\d+) tests?", output)
        got = int(match.group(1)) if match else -1
    if got != expected:
        raise RuntimeError(f"TEST_COUNT_MISMATCH:{name}:{got}!={expected}")
    return {"name": name, "passed": got, "source": path,
            "source_sha256": hashlib.sha256(file.read_bytes()).hexdigest()}


def build_receipt() -> dict:
    suites = [run_suite(*s) for s in SUITES]
    capture = check_material_capture()
    if not all(p.is_file() for p in (SAME_CHAT, DISPATCH, OIDC)):
        raise RuntimeError("CANONICAL_V02_COMPONENT_MISSING")
    proof = {"schema": "PE10_C6_SOURCE_AND_NATIVE_CHAT_TEST_V1",
             "status": "SOURCE_PROBES_PASS_DB_TRANSACTION_NOT_CLAIMED",
             "total_cases": sum(s["passed"] for s in suites),
             "suites": suites, "material_gpt_capture": capture,
             "selection_is_execution_certification": False,
             "claude_material_execution_claimed": capture["executor_mode"] == "CLAUDE_NATIVE",
             "production_activated": False, "checkpoint_closed": False,
             "requires_governed_postgres_probes": True}
    proof["receipt_sha256"] = _json_sha(proof)
    return proof


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    proof = build_receipt()
    rendered = json.dumps(proof, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.write_text(rendered, encoding="utf-8")
    print(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
