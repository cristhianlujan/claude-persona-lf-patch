"""V11 B25/B28: two behavior mutants killed only by exact expected assertions.

Mutates only the temporary GitHub Actions worktree and restores byte-for-byte.
Never import into production or run on an official checked-out workspace.
"""
from __future__ import annotations

import hashlib
import os
import subprocess
import sys
from pathlib import Path

assert os.environ.get("GITHUB_ACTIONS") == "true"
assert os.environ.get("SALY_MUTATION_SANDBOX") == "1"

source_path = Path(__file__).with_name("native_handoff_reservation_bridge_v1.py")
original = source_path.read_bytes()
source = original.decode("utf-8")
original_sha = hashlib.sha256(original).hexdigest()
root = Path(__file__).resolve().parents[3]

mutations = (
    (
        "INDEPENDENT_DB_ROW_READBACK_GUARD",
        "and all(row.get(k) == v for k, v in expected.items()),",
        "and True,",
        "test_reservation_readback_wrong_archive_hash",
    ),
    (
        "FALSE_NATIVE_DELIVERY_FLAG_GUARD",
        "and all(result.get(k) is False for k in NOT_SENT)",
        "and True",
        "test_reservation_report_false_delivery",
    ),
)
try:
    for name, old, replacement, method in mutations:
        if source.count(old) != 1:
            raise AssertionError("MUTATION_TARGET_NOT_UNIQUE:" + name)
        source_path.write_text(source.replace(old, replacement))
        r = subprocess.run(
            [sys.executable, "-m", "unittest", "-v",
             "sandbox.creative_factory.queue_v11.test_native_handoff_reservation_bridge_v1."
             "V11Tests." + method],
            cwd=root, capture_output=True, text=True, timeout=30, check=False)
        out = r.stdout + r.stderr
        if r.returncode == 0 or "HandoffReservationRejected not raised" not in out:
            raise AssertionError("MUTANT_NOT_KILLED_BY_EXPECTED_ASSERTION:" + name + ":" + out[-1700:])
        if "SyntaxError" in out or "ImportError" in out or "ModuleNotFoundError" in out:
            raise AssertionError("MUTANT_KILLED_BY_WRONG_ERROR:" + name)
        print("MUTANT_KILLED_BY_EXPECTED_ASSERTION:" + name)
finally:
    source_path.write_bytes(original)
    if hashlib.sha256(source_path.read_bytes()).hexdigest() != original_sha:
        raise AssertionError("MUTANT_SOURCE_RESTORE_DRIFT")
print("PASS_V11_2_OF_2_BEHAVIOR_MUTANTS_SOURCE_RESTORED")
