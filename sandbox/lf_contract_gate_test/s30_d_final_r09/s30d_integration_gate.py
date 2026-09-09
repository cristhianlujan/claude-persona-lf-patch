#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
A_CONTRACT = ROOT / "gobernanza/contratos/s30_self_governance_gate_v1.json"
A_JUDGE = ROOT / "gobernanza/judges/validate_s30_self_governance_gate.py"
A_RECEIPT = ROOT / "sandbox/lf_contract_gate_test/s30_self_governance/s30_a_prewrite_receipt.json"
B_DIR = ROOT / "sandbox/lf_contract_gate_test/s30_data_access_candidate"
C_DIR = ROOT / "sandbox/lf_contract_gate_test/s30_c_reliability_harness"

ASSURANCE_INTERFACE = "PREEXECUTION_ASSURANCE_RESULT"
DATA_INTERFACE = "PREEXECUTION_DATA_ACCESS_RESULT"


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot resolve import spec for {path}")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def git_blob_sha(path: Path) -> str:
    payload = path.read_bytes()
    return hashlib.sha1(f"blob {len(payload)}\0".encode("ascii") + payload).hexdigest()


def binding_receipt(binding: dict[str, Any]) -> dict[str, Any]:
    fields = list(binding["fields"])
    schema = binding["object_identity"].split(".", 1)[0]
    return {
        "object_identity": binding["object_identity"],
        "schema": schema,
        "object_type": binding["object_type"],
        "exact_columns": [{"name": name} for name in fields],
        "data_types": {name: "text" for name in fields},
        "nullability": {name: True for name in fields},
        "defaults": {name: None for name in fields},
        "identity_generation": {name: None for name in fields},
        "constraints": [],
        "indexes": [],
        "key_fields": list(binding["key_fields"]),
        "allowed_filters": list(binding["allowed_filters"]),
        "schema_fingerprint": binding["schema_fingerprint"],
        "freshness": {"status": "CURRENT_FOR_INTERFACE_PROBE"},
    }


def evaluate(*, force_b_block: bool = False, force_c_invalid: bool = False) -> dict[str, Any]:
    required = [
        A_CONTRACT,
        A_JUDGE,
        A_RECEIPT,
        B_DIR / "data_access_registry_v1.json",
        B_DIR / "lf_data_access.py",
        B_DIR / "s30_b_currentness_receipt.json",
        C_DIR / "freeze_contract.json",
        C_DIR / "replay_corpus.json",
        C_DIR / "s30c_harness.py",
        C_DIR / "source_manifest.json",
        C_DIR / "test_s30c_harness.py",
        C_DIR / "s30_c_frozen_receipt_r02.json",
    ]
    missing = [str(path.relative_to(ROOT)) for path in required if not path.is_file()]
    if missing:
        return {
            "interface": ASSURANCE_INTERFACE,
            "status": "BLOCKED",
            "material_work_allowed": False,
            "first_bad_hop": "REQUIRED_FILES_EXIST",
            "missing_files": missing,
        }

    a_mod = load_module("s30a_judge_for_s30d", A_JUDGE)
    a_result = a_mod.evaluate(load_json(A_CONTRACT), load_json(A_RECEIPT))
    a_pass = a_result.get("result") == "PASS_TO_MATERIAL_WORK" and a_result.get("material_work_allowed") is True

    b_mod = load_module("s30b_data_access_for_s30d", B_DIR / "lf_data_access.py")
    registry = b_mod.load_registry(B_DIR / "data_access_registry_v1.json")
    binding = registry["sources"]["EKB"]
    schema_receipt = binding_receipt(binding)
    access = b_mod.LFDataAccess.from_registry(registry)
    if force_b_block:
        b_result = access.read_ekb(schema_receipt=schema_receipt, free_sql="select * from public.lf_error_knowledge")
    else:
        b_result = access.read_ekb(schema_receipt=schema_receipt, fields=["codigo", "estado"], filters={"codigo": "DB-001"})
    b_pass = b_result.get("interface") == DATA_INTERFACE and b_result.get("status") == "PASS"

    c_receipt = load_json(C_DIR / "s30_c_frozen_receipt_r02.json")
    expected_c_blobs = dict(c_receipt.get("artifacts") or {})
    c_hash_mismatches = []
    for filename, expected_sha in expected_c_blobs.items():
        path = C_DIR / filename
        observed = git_blob_sha(path) if path.is_file() else "MISSING"
        if observed != expected_sha:
            c_hash_mismatches.append({"file": filename, "expected": expected_sha, "observed": observed})
    c_pass = (
        c_receipt.get("expected_output") == "READY_FOR_FINAL_R09_INTEGRATION"
        and c_receipt.get("claim_ceiling") == "EVIDENCE_FREEZE_AND_REPLAY_HARNESS_READY"
        and not c_hash_mismatches
    )
    if force_c_invalid:
        c_pass = False
        c_hash_mismatches.append({"file": "controlled-negative", "expected": "FROZEN", "observed": "MUTATED"})

    combined_pass = a_pass and b_pass and c_pass
    if not a_pass:
        first_bad = "S30-A"
    elif not b_pass:
        first_bad = "S30-B"
    elif not c_pass:
        first_bad = "S30-C"
    else:
        first_bad = None

    return {
        "interface": ASSURANCE_INTERFACE,
        "status": "PASS" if combined_pass else "BLOCKED",
        "material_work_allowed": combined_pass,
        "first_bad_hop": first_bad,
        "PREEXECUTION_ASSURANCE_RESULT": "PASS" if combined_pass else "BLOCKED",
        "PREEXECUTION_DATA_ACCESS_RESULT": b_result.get("status"),
        "a_upstream_result": a_result.get("result"),
        "b_code": b_result.get("code"),
        "c_expected_output": c_receipt.get("expected_output"),
        "c_hash_mismatches": c_hash_mismatches,
        "wiring_order": [
            "S30-A_SELF_GOVERNANCE_GATE",
            "S30-B_PREEXECUTION_DATA_ACCESS_RESULT",
            "S30-C_FROZEN_EVIDENCE_CONSUMPTION",
            "ONLY_THEN_MATERIAL_WORK",
        ],
        "evidence": {
            "a": "sandbox/lf_contract_gate_test/s30_self_governance/s30_a_prewrite_receipt.json",
            "b": "sandbox/lf_contract_gate_test/s30_data_access_candidate/s30_b_currentness_receipt.json",
            "c": "sandbox/lf_contract_gate_test/s30_c_reliability_harness/s30_c_frozen_receipt_r02.json",
        },
    }


def self_test() -> dict[str, Any]:
    positive = evaluate()
    assert positive["status"] == "PASS"
    assert positive["material_work_allowed"] is True
    assert positive["PREEXECUTION_ASSURANCE_RESULT"] == "PASS"
    assert positive["PREEXECUTION_DATA_ACCESS_RESULT"] == "PASS"

    b_negative = evaluate(force_b_block=True)
    assert b_negative["status"] == "BLOCKED"
    assert b_negative["material_work_allowed"] is False
    assert b_negative["first_bad_hop"] == "S30-B"
    assert b_negative["PREEXECUTION_DATA_ACCESS_RESULT"] == "BLOCKED"

    c_negative = evaluate(force_c_invalid=True)
    assert c_negative["status"] == "BLOCKED"
    assert c_negative["material_work_allowed"] is False
    assert c_negative["first_bad_hop"] == "S30-C"

    return {
        "status": "PASS",
        "interface": ASSURANCE_INTERFACE,
        "cases": {
            "combined_positive": "PASS_TO_MATERIAL_WORK",
            "blocked_b_prebackend": "BLOCKED_BEFORE_MATERIAL_WORK",
            "blocked_c_frozen_evidence_mismatch": "BLOCKED_BEFORE_MATERIAL_WORK",
        },
        "positive": positive,
    }


if __name__ == "__main__":
    print(json.dumps(self_test(), indent=2, sort_keys=True))
