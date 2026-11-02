"""The unapproved Router intermediate and direct profile starter are retired."""
import contextlib
from io import StringIO
from pathlib import Path
import runpy
import unittest

SCRIPT = Path(__file__).resolve().parents[3] / "scripts" / "lf_profile_router_admit.py"


class RetiredRouterProfileLauncherTest(unittest.TestCase):
    def test_never_invokes_a_profile_or_a_backend(self):
        namespace = runpy.run_path(str(SCRIPT), run_name="unit_test")
        self.assertNotIn("call_json", namespace)
        self.assertNotIn("oidc", namespace)
        capture = StringIO()
        with contextlib.redirect_stdout(capture):
            self.assertEqual(namespace["main"](), 1)
        self.assertIn("ROUTER_PROFILE_DIRECT_CALL_RETIRED", capture.getvalue())

    def test_retired_script_has_no_indirect_execution_action(self):
        source = SCRIPT.read_text(encoding="utf-8")
        for forbidden in ("profile_execution_begin_from_router_context_v1",
                          "router_profile_admit_context_v2",
                          "lf_profile_execution_begin_from_handoff_v1",
                          "call_json("):
            self.assertNotIn(forbidden, source)


if __name__ == "__main__":
    unittest.main()
