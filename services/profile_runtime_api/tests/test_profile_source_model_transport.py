from __future__ import annotations

import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
RUNTIME_DIR = REPO_ROOT / "sandbox/lf_contract_gate_test/profile_execution_runtime"
if str(RUNTIME_DIR) not in sys.path:
    sys.path.insert(0, str(RUNTIME_DIR))

from profile_runtime_runner import RuntimeExecutionBlocked, build_runtime_request


class ProfileSourceModelTransportTest(unittest.TestCase):
    def test_projected_source_reaches_request_while_canonical_hash_is_preserved(self) -> None:
        canonical = "# Profile\n## Role\nDo semantic work.\n## Maintenance\nCONTROL_PLANE_ONLY\n"
        projected = "## Role\nDo semantic work."
        request = build_runtime_request(
            execution_id="EXEC-MODEL-CONTEXT-001",
            profile_code="PERFIL-DEMO",
            profile_slug="demo",
            profile_sources=[{
                "ref": "profiles/demo/SKILL.md",
                "content": canonical,
                "model_content": projected,
            }],
            input_literal="Run the governed task.",
        )
        self.assertEqual(request["profile_sources"], [{"ref": "profiles/demo/SKILL.md", "content": projected}])
        self.assertNotIn("CONTROL_PLANE_ONLY", request["profile_sources"][0]["content"])
        self.assertEqual(request["profile_model_source_chars"], len(projected))
        self.assertNotEqual(request["profile_source_sha256"], request["profile_model_source_sha256"])

    def test_projected_transport_blocks_full_source_reuse(self) -> None:
        canonical = "# Profile\n## Role\nDo semantic work.\n"
        with self.assertRaises(RuntimeExecutionBlocked) as cm:
            build_runtime_request(
                execution_id="EXEC-MODEL-CONTEXT-002",
                profile_code="PERFIL-DEMO",
                profile_slug="demo",
                profile_sources=[{
                    "ref": "profiles/demo/SKILL.md",
                    "content": canonical,
                    "model_content": canonical,
                }],
                input_literal="Run the governed task.",
            )
        self.assertEqual(cm.exception.code, "PROFILE_FULL_SOURCE_TO_MODEL_FORBIDDEN")


if __name__ == "__main__":
    unittest.main()
