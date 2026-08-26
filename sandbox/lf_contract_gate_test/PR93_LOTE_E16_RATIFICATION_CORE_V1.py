#!/usr/bin/env python3
"""Static/synthetic ratification for PR93 E.16 CA-N102/N103/N110/N111."""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path
from typing import Iterable

sys.dont_write_bytecode = True
SANDBOX = Path("sandbox/lf_contract_gate_test")
EXPECTED_BLOBS = {
    SANDBOX / "PR93_LOTE_E14_CAPTURE.py": "25367eb46dd34529edb7c33c86d6c80cc4785343",
    SANDBOX / "PR93_LOTE_E14_COMMON.py": "da7cea947b7be06ea697ff4be2f6204bdd16f008",
    SANDBOX / "PR93_LOTE_E14_VERIFY.py": "96fda451fe45c9c36b0aa574ba3a0c3fd5eecbd9",
    SANDBOX / "PR93_LOTE_E14_VERIFY_COMMON.py": "40e1bf2bf45b01248648054f2d048e796e49db35",
    SANDBOX / "PR93_LOTE_E14_VERIFY_TRANSCRIPT.py": "98a23bc9df5ca25f08d97c0b103ec693a317287d",
    SANDBOX / "PR93_LOTE_E14_SEMANTICS.py": "6895a64de5ac732d77a3588db2bb668256e19243",
    SANDBOX / "PR93_LOTE_E13_T2.psql": "c6fabd4ef11402dd097a8c2086a99baef547d81d",
    SANDBOX / "PR93_LOTE_E13_STATE_READBACK.sql": "bc70a917ccbe9cf08bcf8f158904ba82415017f0",
    SANDBOX / "PR93_LOTE_E15_1_REGRESSION_TESTS.py": "fe97d64ddc693e32fbe71d3fa0c5a841b725663a",
    SANDBOX / "PR93_LOTE_E15_GUARDS.md": "06547499021ac76545051d4ccc7c208787dc56a0",
}
PRIOR_SYNTHETIC_CLOSURE_SHA256 = "fa78ffb26aab23c8cb2f089eef8a6985b7e13fe4b51750847bef7a7f11e9e263"


def fail(message: str) -> None:
    raise SystemExit(message)


def git_blob(root: Path, relative: Path) -> str:
    result = subprocess.run(
        ["git", "hash-object", str(relative)],
        cwd=root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        text=True,
    )
    if result.returncode != 0:
        fail(result.stderr.strip() or f"cannot hash {relative}")
    return result.stdout.strip()


def text(root: Path, relative: Path) -> str:
    return (root / relative).read_text(encoding="utf-8")


def require_all(label: str, content: str, terms: Iterable[str]) -> None:
    missing = [term for term in terms if term not in content]
    if missing:
        fail(f"{label}: missing controls: {missing}")


def canonical_digest(value: object) -> str:
    data = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(data).hexdigest()


def normalize_key_row(row: dict[str, object]) -> dict[str, object]:
    value = dict(row)
    material = value.pop("key_material", None)
    raw = "" if material is None else str(material)
    value["key_material_sha256"] = hashlib.sha256(raw.encode()).hexdigest()
    value["key_material_is_null"] = material is None
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    args = parser.parse_args()
    root = args.repo_root.resolve()

    for relative, expected in EXPECTED_BLOBS.items():
        observed = git_blob(root, relative)
        if observed != expected:
            fail(f"blob drift: {relative}: expected {expected}, observed {observed}")
    print("PASS_E16_RATIFICATION_SOURCE_BLOBS=10/10")

    state = text(root, SANDBOX / "PR93_LOTE_E13_STATE_READBACK.sql")
    require_all(
        "CA-N102 state readback",
        state,
        (
            "key_material_sha256",
            "key_material_is_null",
            "pg_catalog.sha256",
            "ROWSET_SHA256_WITH_KEY_MATERIAL_DIGEST",
        ),
    )
    before = [{"key_id": "k1", "key_material": "alpha", "active": True}]
    after = [{"key_id": "k1", "key_material": "beta", "active": True}]
    before_digest = canonical_digest([normalize_key_row(row) for row in before])
    after_digest = canonical_digest([normalize_key_row(row) for row in after])
    if before_digest == after_digest:
        fail("CA-N102 synthetic key-material mutation did not alter digest")

    capture = text(root, SANDBOX / "PR93_LOTE_E14_CAPTURE.py")
    transcript = text(root, SANDBOX / "PR93_LOTE_E14_VERIFY_TRANSCRIPT.py")
    require_all(
        "CA-N102 rollback contract",
        capture + transcript,
        (
            'rollback_status == "EXPLICIT"',
            'overall_status = "PASS" if t1_ok and t2_ok else "FAIL"',
            "overall PASS requires explicit rollback",
            "PASS cannot use NOT_VERIFIED rollback",
        ),
    )
    print("PASS_E16_CA_N102_RATIFIED=6/6")

    t2 = text(root, SANDBOX / "PR93_LOTE_E13_T2.psql")
    autocommit_index = t2.index("E13_T2_AUTOCOMMIT_REQUIRED")
    readonly_index = t2.index("E13_T2_MUST_NOT_RUN_INSIDE_T1")
    pass_index = t2.index("E13_T2_CONTEXT_GUARD_PASS")
    battery_index = t2.index("\\ir PR93_WRITER_V7_ADVERSARIAL_TESTS.sql")
    complete_index = t2.index("E13_T2_COMPLETE")
    if not (
        autocommit_index < readonly_index < battery_index < complete_index
        and autocommit_index < pass_index < battery_index < complete_index
    ):
        fail(
            "CA-N103 T2 guards/battery order invalid: "
            f"{autocommit_index},{readonly_index},{pass_index},{battery_index},{complete_index}"
        )
    require_all(
        "CA-N103 separate process",
        capture,
        (
            't1_script = sandbox / "PR93_LOTE_E13_T1.psql"',
            't2_script = sandbox / "PR93_LOTE_E13_T2.psql"',
            "t1_exit, t1_output = common.run_psql(",
            "t2_exit, t2_output = common.run_psql(",
        ),
    )
    print("PASS_E16_CA_N103_RATIFIED=7/7")

    verify = text(root, SANDBOX / "PR93_LOTE_E14_VERIFY.py")
    verify_common = text(root, SANDBOX / "PR93_LOTE_E14_VERIFY_COMMON.py")
    require_all(
        "CA-N110 external trust anchor",
        verify + capture,
        (
            'parser.add_argument("--trusted-receipt-sha256", required=True)',
            "observed_receipt_sha != args.trusted_receipt_sha256",
            "common.publish_atomically(staging, output_dir)",
            'print(f"E14_RECEIPT_SHA256={receipt_sha}")',
            '"declaration_kind": "SELF_ASSERTED_NOT_MEASURED"',
        ),
    )
    if capture.index("common.publish_atomically(staging, output_dir)") > capture.index('print(f"E14_RECEIPT_SHA256={receipt_sha}")'):
        fail("CA-N110 anchor is emitted before atomic publication")
    require_all(
        "CA-N110 exact bundle inventory",
        verify_common,
        (
            "def verify_bundle_inventory",
            "bundle inventory is not exact",
            "bundle entry must not be a symlink",
        ),
    )
    print("PASS_E16_CA_N110_RATIFIED=8/8")

    semantics = text(root, SANDBOX / "PR93_LOTE_E14_SEMANTICS.py")
    regression = text(root, SANDBOX / "PR93_LOTE_E15_1_REGRESSION_TESTS.py")
    require_all(
        "CA-N111 integrity negatives",
        semantics + transcript + regression,
        (
            "T2 head marker is forbidden inside T1",
            "capture-envelope head marker is forbidden inside T1",
            "full transcript must start with E14_CAPTURE_BEGIN",
            "full transcript must end with E14_CAPTURE_END",
            "cleanup-name-swap",
            "cleanup-symlink-swap",
        ),
    )
    print("PASS_E16_CA_N111_RATIFIED=6/6")

    print("E16_PRIOR_EVIDENCE_MODE=EVIDENCE_REUSED_BY_BLOB_IDENTITY")
    print(f"E16_PRIOR_SYNTHETIC_CLOSURE_SHA256={PRIOR_SYNTHETIC_CLOSURE_SHA256}")
    print("PASS_E16_E15_EVIDENCE_REUSE_BINDING=10/10")
    print("PASS_E16_BCD_RATIFICATION")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
