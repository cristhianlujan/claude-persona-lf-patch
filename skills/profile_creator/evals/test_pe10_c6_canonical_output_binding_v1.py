#!/usr/bin/env python3
"""C6 canonical profile output runner: real SRCR contract, no OIDC or promotion."""
from __future__ import annotations

import copy
import hashlib
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "skills/profile_creator/validators"))
from run_bound_profile_output_validator_v1 import validate_bound_output

SLUG = "systemic_root_cause_repair_lf"
BASE = Path("profiles") / SLUG
GOOD = BASE / "examples/good_output.json"
BAD = BASE / "examples/bad_output.json"
SCHEMA = BASE / "schemas/output.schema.json"
VALIDATOR = BASE / "validators/runtime_validate.py"
BINDING = BASE / "contracts/runtime_binding.json"


def digest(path: Path) -> str:
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def packet(raw: Path, *, expected_valid: bool) -> dict:
    p = {
        "schema": "PROFILE_OUTPUT_VALIDATION_BINDING_V1",
        "operation_code": "ACTUALIZACION_PERFIL_LF",
        "profile_slug": SLUG,
        "validator_transport": "STDIN_JSON",
        "expected_valid": expected_valid,
        "runtime_binding_sha256": digest(BINDING),
    }
    for key, src in (("schema", SCHEMA), ("validator", VALIDATOR), ("raw_output", raw)):
        p[key + "_ref"] = src.as_posix()
        p[key + "_sha256"] = digest(src)
    return p


class CanonicalProfileBinding(unittest.TestCase):
    def test_bound_validator_is_declared_canonical(self):
        binding = json.loads((ROOT / BINDING).read_text(encoding="utf8"))
        self.assertEqual(binding["canonical_validator"]["path"], "validators/runtime_validate.py")
        self.assertEqual(binding["canonical_validator"]["callable"], "validate")
        self.assertEqual(binding["runtime_schema"]["default"], "schemas/output.schema.json")
        self.assertNotEqual(VALIDATOR.name[:9], "validate_")

    def test_true_output_using_full_schema_and_declared_validator(self):
        result = validate_bound_output(ROOT, packet(GOOD, expected_valid=True))
        self.assertEqual(result["status"], "CANDIDATE_OUTPUT_PARITY_OBSERVED", result)
        self.assertTrue(result["canonical_json_schema_executed"])
        self.assertTrue(result["profile_validator_executed"])
        self.assertEqual(result["validator_exit_code"], 0)
        self.assertTrue(result["source_readback_matched"])
        self.assertFalse(result["admission_authorized"])
        self.assertFalse(result["runtime_activation_authorized"])

    def test_real_invalid_output_rejected(self):
        result = validate_bound_output(ROOT, packet(BAD, expected_valid=False))
        self.assertIn(result["status"], (
            "EXPECTED_NEGATIVE_REJECTED_BY_SHAPE",
            "EXPECTED_NEGATIVE_REJECTED_BY_VALIDATOR",
        ), result)
        self.assertTrue(result["canonical_json_schema_executed"])
        self.assertFalse(result["admission_authorized"])

    def test_reject_forged_binding_digest(self):
        modified = packet(GOOD, expected_valid=True)
        modified["runtime_binding_sha256"] = "0" * 64
        result = validate_bound_output(ROOT, modified)
        self.assertEqual(result["status"], "FAIL", result)
        self.assertIn("RUNTIME_BINDING_DIGEST_MISMATCH", result["blocking_codes"])
        self.assertFalse(result["profile_validator_executed"])

    def test_reject_wrong_canonical_validator_even_with_correct_source_hash(self):
        modified = packet(GOOD, expected_valid=True)
        modified["validator_ref"] = (BASE / "validators/edge_closure.py").as_posix()
        modified["validator_sha256"] = digest(BASE / "validators/edge_closure.py")
        result = validate_bound_output(ROOT, modified)
        self.assertIn("RUNTIME_BINDING_SOURCE_NOT_CANONICAL", result["blocking_codes"])
        self.assertFalse(result["profile_validator_executed"])

    def test_reject_stale_schema_without_executing_profile(self):
        modified = packet(GOOD, expected_valid=True)
        modified["schema_sha256"] = "f" * 64
        result = validate_bound_output(ROOT, modified)
        self.assertIn("SOURCE_SHA_MISMATCH:schema", result["blocking_codes"])
        self.assertFalse(result["profile_validator_executed"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
