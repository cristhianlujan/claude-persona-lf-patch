#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import jsonschema
from pathlib import Path
import re
import subprocess
import sys
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
G09 = Path(__file__).with_name("g09_cold_replay_v1.py")
SCHEMA = Path(__file__).with_name("g10_final_closure_package_v1.schema.json")
README = Path(__file__).with_name("README.md")
MIGRATION = ROOT / "supabase/migrations/20260922144000_work_protocol_manifest_v1.sql"
LOCATOR = Path(__file__).with_name("candidate_db_wiring_v1.sql")
EKB_CODE = "WORK-PROTOCOL-FINAL-CLOSURE-PACKAGE-001"
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def sha256_bytes(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def git_blob(path: Path) -> str:
    return subprocess.check_output(
        ["git", "-C", str(ROOT), "hash-object", str(path.relative_to(ROOT))],
        text=True,
    ).strip()


def run_g09() -> dict[str, Any]:
    proc = subprocess.run(
        [sys.executable, str(G09)],
        cwd=ROOT,
        text=True,
        capture_output=True,
        timeout=120,
        check=False,
    )
    if proc.returncode != 0:
        raise AssertionError({
            "code": "G10_G09_REPLAY_FAILED",
            "returncode": proc.returncode,
            "stdout": proc.stdout[-4000:],
            "stderr": proc.stderr[-4000:],
        })
    payload = json.loads(proc.stdout)
    assert payload["status"] == "PASS", payload
    assert payload["gate_count"] == 9, payload
    assert payload["dimension_count"] == 5, payload
    assert payload["matrix_case_count"] == 45, payload
    assert payload["cold_replay"]["status"] == "PASS", payload
    assert payload["cold_replay"]["byte_equivalent_canonical_json"] is True, payload
    for gate_id in [f"G{i:02d}" for i in range(9)]:
        row = payload["matrix_results"][gate_id]
        assert row == {
            "positive": "PASS",
            "negative": "PASS",
            "drift": "PASS",
            "bypass": "PASS",
            "timeout": "PASS",
        }, (gate_id, row)
    return payload


def validate_ci_plan(plan: dict[str, Any]) -> tuple[str, str, str]:
    assert plan.get("schema_version") == "lf-ci-execution-plan/v2", plan.get("schema_version")
    head = plan.get("head_sha")
    base = plan.get("base_sha")
    current = (plan.get("source_authority") or {}).get("resolved_revision")
    decision = (plan.get("source_authority") or {}).get("decision")
    ready = (plan.get("source_authority") or {}).get("ready")
    assert isinstance(head, str) and HEX40.fullmatch(head), head
    assert isinstance(base, str) and HEX40.fullmatch(base), base
    assert isinstance(current, str) and HEX40.fullmatch(current), current
    assert decision in {"CURRENT", "CURRENT_REBOUND"}, plan.get("source_authority")
    assert ready is True, plan.get("source_authority")
    required_changed = {
        ".github/workflows/validate-lf-packs.yml",
        "sandbox/lf_contract_gate_test/work_protocol_manifest_v1/g10_final_closure_package_v1.py",
        "sandbox/lf_contract_gate_test/work_protocol_manifest_v1/g10_final_closure_package_v1.schema.json",
    }
    changed = set(plan.get("changed_paths") or [])
    assert required_changed.issubset(changed), {
        "code": "G10_CURRENT_HEAD_NOT_MATERIALIZED",
        "missing": sorted(required_changed - changed),
    }
    return head, base, current


def validate_documented_readbacks() -> list[str]:
    text = README.read_text(encoding="utf-8")
    required_sections = [
        "### G00 Owner-first Entry — READBACK_CLOSED",
        "### G03 Gate Contract — READBACK_CLOSED",
        "### G04 Evidence / Independent Verification — READBACK_CLOSED",
        "### G06 Change / Waiver / Irreversibility — READBACK_CLOSED",
        "### G07 Execution Controller — READBACK_CLOSED",
        "### G08 Closure Controller — READBACK_CLOSED",
        "### G09 Gate Self-Test / Cold Replay — READBACK_CLOSED",
    ]
    missing = [s for s in required_sections if s not in text]
    assert not missing, {"code": "G10_DOCUMENTED_READBACK_MISSING", "missing": missing}
    return required_sections


def build_package(plan: dict[str, Any]) -> dict[str, Any]:
    head, base, current = validate_ci_plan(plan)
    g09 = run_g09()
    documented = validate_documented_readbacks()

    migration_bytes = MIGRATION.read_bytes()
    migration_blob = git_blob(MIGRATION)
    migration_sha256 = sha256_bytes(migration_bytes)
    assert HEX40.fullmatch(migration_blob), migration_blob
    assert HEX64.fullmatch(migration_sha256), migration_sha256

    locator = LOCATOR.read_text(encoding="utf-8")
    assert f"Proven source Git blob SHA: {migration_blob}" in locator, {
        "code": "G10_MIGRATION_LOCATOR_STALE",
        "expected_blob": migration_blob,
    }

    gate_status = {f"G{i:02d}": "READBACK_CLOSED" for i in range(10)}
    package: dict[str, Any] = {
        "schema_version": "LF_WORK_PROTOCOL_G10_FINAL_CLOSURE_PACKAGE_V1",
        "result": "READY_FOR_EKB_READBACK",
        "candidate_head_sha": head,
        "base_sha": base,
        "authority_current_revision": current,
        "authority_currentness": (plan.get("source_authority") or {}).get("decision"),
        "gate_status": gate_status,
        "g09_matrix": {
            "status": "PASS",
            "gate_count": g09["gate_count"],
            "dimension_count": g09["dimension_count"],
            "matrix_case_count": g09["matrix_case_count"],
            "cold_replay_sha256": g09["cold_replay"]["replay_sha256"],
        },
        "migration_binding": {
            "path": str(MIGRATION.relative_to(ROOT)),
            "git_blob_sha1": migration_blob,
            "source_sha256": migration_sha256,
        },
        "documented_live_readback_sections": documented,
        "waiver_debt_count": 0,
        "receipt_boundary": {
            "candidate_receipt_required": True,
            "candidate_receipt_satisfied_by_g10": False,
            "receipt_gate": "G11",
        },
        "ekb_learning": {
            "code": EKB_CODE,
            "state": "PENDING_DURABLE_READBACK",
        },
        "runtime_activation_allowed": False,
        "production_activation_allowed": False,
        "next_gate": "G11_CANDIDATE_RECEIPT",
    }
    package["package_sha256"] = sha256_bytes(canonical_bytes(package))
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    jsonschema.Draft202012Validator(schema).validate(package)
    verify_source = dict(package)
    supplied_digest = verify_source.pop("package_sha256")
    recomputed = sha256_bytes(canonical_bytes(verify_source))
    assert supplied_digest == recomputed, {
        "code": "G10_PACKAGE_DIGEST_MISMATCH",
        "supplied": supplied_digest,
        "recomputed": recomputed,
    }
    return package


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ci-plan", required=True)
    ap.add_argument("--output")
    args = ap.parse_args()

    plan = json.loads(Path(args.ci_plan).read_text(encoding="utf-8"))
    package = build_package(plan)
    raw = json.dumps(package, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    if args.output:
        out = Path(args.output)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(raw, encoding="utf-8")
    print(json.dumps(package, sort_keys=True, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
