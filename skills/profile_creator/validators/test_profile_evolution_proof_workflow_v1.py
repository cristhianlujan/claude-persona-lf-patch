import re, unittest
from pathlib import Path
import yaml

WF = Path(__file__).resolve().parents[3] / ".github/workflows/lf-profile-evolution-proof.yml"


class ProofWorkflow(unittest.TestCase):
    def setUp(self):
        self.text = WF.read_text()
        self.doc = yaml.safe_load(self.text)
        self.on = self.doc.get("on", self.doc.get(True))

    def test_dispatch_only_read_only_main_only(self):
        self.assertEqual(list(self.on.keys()), ["workflow_dispatch"])
        self.assertEqual(self.doc["permissions"], {"contents": "read"})
        self.assertEqual(self.doc["jobs"]["proof"]["if"], "github.ref == 'refs/heads/main'")

    def test_run_name_binds_every_input(self):
        rn = self.doc["run-name"]
        for k in ("mode", "profile_slug", "base_sha", "candidate_sha"):
            self.assertIn("inputs." + k, rn)

    def test_no_secrets_no_environment_no_network_tools(self):
        self.assertNotIn("secrets.", self.text)
        self.assertNotIn("environment:", self.text)
        for bad in ("curl ", "wget ", "psql", "supabase "):
            self.assertNotIn(bad, self.text)

    def test_no_expression_inside_shell(self):
        for step in self.doc["jobs"]["proof"]["steps"]:
            run = step.get("run", "")
            self.assertNotIn("${{", run, step.get("name"))

    def test_trusted_main_checkout_and_no_credentials(self):
        co = self.doc["jobs"]["proof"]["steps"][0]
        self.assertEqual(co["with"]["ref"], "${{ github.sha }}")
        self.assertIs(co["with"]["persist-credentials"], False)

    def test_inputs_are_validated_before_use(self):
        names = [s["name"] for s in self.doc["jobs"]["proof"]["steps"]]
        self.assertLess(names.index("Validate inputs"), names.index("Materialize profile trees from Git objects"))
        v = [s for s in self.doc["jobs"]["proof"]["steps"] if s["name"] == "Validate inputs"][0]["run"]
        for code in ("BLOCK_PROOF_SLUG_INVALID", "BLOCK_PROOF_BASE_SHA_INVALID", "BLOCK_PROOF_CANDIDATE_SHA_INVALID", "BLOCK_PROOF_MODE_INVALID", "BLOCK_PROOF_SAME_COMMIT"):
            self.assertIn(code, v)

    def test_green_run_means_demonstrated(self):
        run = self.doc["jobs"]["proof"]["steps"][-1]["run"]
        self.assertIn('proof.get("verdict") == "EVOLUTION_DEMONSTRATED"', run)
        self.assertIn("::notice title=LF_PROFILE_EVOLUTION_PROOF::", run)


if __name__ == "__main__":
    unittest.main()
