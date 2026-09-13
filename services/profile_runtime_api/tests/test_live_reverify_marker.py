from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "mark_live_reverified.py"
DEPS_AVAILABLE = importlib.util.find_spec("psycopg") is not None

if DEPS_AVAILABLE:
    spec = importlib.util.spec_from_file_location("mark_live_reverified", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)


@unittest.skipUnless(DEPS_AVAILABLE, "psycopg is not installed")
class LiveReverifyRecordTest(unittest.TestCase):
    SOURCE = "b" * 40

    @staticmethod
    def record() -> dict:
        return {
            "request_id": "471946b9-6e53-4cf5-b9b0-ee6c4ce18f8b",
            "status": "SUCCEEDED",
            "error_code": None,
            "error_detail": None,
            "runtime_target": "HETZNER",
            "runtime_provider": "hetzner_profile_runtime_api",
            "runtime_attestation": {"source_sha": "b" * 40, "attested_at": "2026-09-13T03:31:48Z"},
            "result_package": {
                "result": {
                    "result": {
                        "runtime_completion": {"status": "PASS"},
                        "profile_contract_valid": {"status": "PASS"},
                        "semantic_utility": {"status": "PASS"},
                        "downstream_authorized": False,
                    }
                }
            },
            "runtime_request_envelope": {
                "input_governance": {
                    "status": "ADVISORY_READ_ONLY",
                    "subject_mode": "NON_CANONICAL_ARTIFACT",
                    "constraints": {
                        "read_only": True,
                        "no_write": True,
                        "no_promotion": True,
                        "canonical_registration_required": False,
                    },
                }
            },
        }

    def test_valid_record_is_accepted(self) -> None:
        evidence = module.verify_record(self.record(), self.SOURCE)
        self.assertEqual(evidence["semantic_utility"], "PASS")
        self.assertFalse(evidence["downstream_authorized"])

    def test_source_drift_and_unsafe_flags_fail_closed(self) -> None:
        row = self.record(); row["runtime_attestation"]["source_sha"] = "c" * 40
        with self.assertRaisesRegex(RuntimeError, "LIVE_REVERIFY_SOURCE_SHA_MISMATCH"):
            module.verify_record(row, self.SOURCE)
        row = self.record(); row["runtime_request_envelope"]["input_governance"]["constraints"]["no_promotion"] = False
        with self.assertRaisesRegex(RuntimeError, "LIVE_REVERIFY_CONSTRAINT_INVALID:no_promotion"):
            module.verify_record(row, self.SOURCE)


if __name__ == "__main__":
    unittest.main()
