import json
import os
from pathlib import Path
import runpy
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[3] / "scripts" / "lf_profile_router_admit.py"
CTX = {
    "schema_version": "LF_ROUTER_EXECUTION_PIPELINE_V1",
    "status": "GATE2_DERIVED_PENDING_GOVERNED_ADMISSION",
    "transport_mode": "CONTEXT_TRANSPORT",
}


class RouterAdmitRequestTest(unittest.TestCase):
    def run_request(self, context, mode):
        env = {"ROUTER_CONTEXT_JSON": context if isinstance(context, str) else json.dumps(context),
               "EXECUTOR_MODE": mode}
        with patch.dict(os.environ, env, clear=True):
            return runpy.run_path(str(SCRIPT), run_name="admit_test")["governed_request"]()

    def test_both_native_modes_accepted(self):
        for mode in ("GPT_NATIVE", "CLAUDE_NATIVE"):
            self.assertEqual(self.run_request(CTX, mode), (CTX, mode))

    def test_remote_and_unknown_modes_rejected(self):
        for mode in ("REMOTE_API", "", "claude_native", "OTHER"):
            with self.assertRaises(ValueError):
                self.run_request(CTX, mode)

    def test_bad_envelopes_rejected(self):
        for key, value in (("schema_version", "X"), ("status", "READY"), ("transport_mode", "READ_ONLY_CONTEXT")):
            with self.assertRaises(ValueError):
                self.run_request({**CTX, key: value}, "CLAUDE_NATIVE")

    def test_non_object_empty_and_oversize_rejected(self):
        for raw in ("[]", "", json.dumps({**CTX, "pad": "x" * 61000})):
            with self.assertRaises(ValueError):
                self.run_request(raw, "CLAUDE_NATIVE")


if __name__ == "__main__":
    unittest.main()
