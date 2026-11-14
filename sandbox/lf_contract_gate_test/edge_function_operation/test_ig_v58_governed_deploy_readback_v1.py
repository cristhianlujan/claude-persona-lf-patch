from __future__ import annotations
import hashlib
import importlib.util
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
SCRIPT=ROOT/"sandbox/lf_contract_gate_test/edge_function_operation/edge_ig_v58_governed_readback_v1.py"
spec=importlib.util.spec_from_file_location("ig_v58_readback",SCRIPT)
assert spec and spec.loader
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
WORKFLOW=(ROOT/".github/workflows/lf-edge-deploy-credential-readback.yml").read_text(encoding="utf-8")

class IgV58GovernedEdgeReadbackTests(unittest.TestCase):
    def sample(self,slug,source="const agent = 1;",version=20):
        return {"slug":slug,"status":"ACTIVE","verify_jwt":True,"version":version,
                "files":[{"name":"index.ts","content":source}],
                "ezbr_sha256":"a"*64}

    def test_validator_and_agent_hash_readback(self):
        for slug,marker in (("input-governance-validator-v1","VALIDATOR_RECURATION_RECEIPT_INVALID"),
                            ("input-governance-agent-v1","CURATOR_RECURATION_SUCCESSOR")):
            source="const marker = '"+marker+"';"
            digest=hashlib.sha256(source.encode()).hexdigest()
            got=module.inspect_metadata(self.sample(slug,source),slug,digest,19)
            self.assertEqual(got["source_sha256"],digest)
            self.assertEqual(got["version"],20)
            self.assertTrue(got["verify_jwt"])

    def test_wrong_source_or_version_or_jwt_blocked(self):
        slug="input-governance-agent-v1"
        good=self.sample(slug,source="CURATOR_RECURATION_SUCCESSOR")
        for corrupted in (
            {**good,"verify_jwt":False},
            {**good,"version":18},
            {**good,"files":[]},
            {**good,"status":"DELETING"},
            {**good,"slug":"unrelated-function"},
        ):
            with self.assertRaises(module.ReadbackBlocked):
                module.inspect_metadata(corrupted,slug,"b"*64,19)
        with self.assertRaises(module.ReadbackBlocked):
            module.inspect_metadata(good,slug,"c"*64,19)

    def test_deploy_workflow_is_owned_by_issue_label_and_exact_sandbox(self):
        block=WORKFLOW.split("  deploy-ig-v58-runtime:",1)[1]
        self.assertIn("lf-ig-v58-edge-deploy-governed",block)
        self.assertIn('SUPABASE_PROJECT_REF: mhwmirqcgxxukpctffuv',block)
        self.assertIn('environment: lf-edge-deploy',block)
        self.assertIn("checkout@v4",block)
        self.assertIn('test "$(git rev-parse HEAD)" = "$GITHUB_SHA"',block)
        self.assertIn('git merge-base --is-ancestor "$IG_V58_MERGE_SHA" HEAD',block)
        self.assertEqual(block.count("supabase functions deploy"),4) # initial 2 + rollback 2
        self.assertIn("input-governance-agent-v1",block)
        self.assertIn("input-governance-validator-v1",block)
        self.assertIn("edge_ig_v58_governed_readback_v1.py",block)
        self.assertIn("rollback",block.lower())
        self.assertIn("SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}",block)
        self.assertNotIn("--no-verify-jwt",block) # both require verify_jwt=true
        for secret in ("SUPABASE_SERVICE_ROLE_KEY","PGPASSWORD","DATABASE_URL",
                       "OPENAI_API_KEY","ANTHROPIC_API_KEY"):
            self.assertNotIn(secret,block)

if __name__=="__main__":
    unittest.main()
