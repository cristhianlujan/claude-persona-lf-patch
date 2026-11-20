"""Static negative contract: screen44 owner Issue invokes only existing exact OIDC workflow."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[3]
W=(ROOT/".github/workflows/lf-edge-deploy-credential-readback.yml").read_text(encoding="utf-8")
class RecurationOwnerTransport(unittest.TestCase):
 def test_owner_bound_reuses_exact_workflow(self):
  self.assertEqual(W.count("  ig-screen44-owner-dispatch:"),1)
  job=W.split("  ig-screen44-owner-dispatch:",1)[1].split("  deploy-ig-v58-runtime:",1)[0]
  for marker in ("issue.number == 3912","author_association == 'OWNER'",
    "comment.user.login == 'cristhianlujan'",
    "LF_IG_SCREEN44_RECURATE_EXECUTE_V1",
    "main","lf-edge-deploy",
    "github.token","actions: write","gh workflow run lf-input-governance-recurate-dispatch.yml",
    "-f pantalla_ids=44","-f cp2_edge_mode=false","-f context_pack_mode=false",
    '"parent_513_assertions_reusable":False',"no_promotion_without_validator_pass",
    "IG_SCREEN44_GOVERNED_WORKFLOW_DISPATCH_SUBMITTED"):
   self.assertIn(marker,job)
  self.assertNotIn("supabase functions deploy",job)
  self.assertNotIn("curl ",job)
  self.assertNotIn("SUPABASE_ACCESS_TOKEN",job)
  self.assertNotIn("SUPABASE_SERVICE_ROLE_KEY",job)
  self.assertNotIn("insert into",job.lower())
  self.assertEqual(job.count("gh workflow run"),1)
 def test_existing_v58_and_native_caller_unchanged(self):
  self.assertIn("  deploy-ig-v58-runtime:",W)
  self.assertIn("  native-profile-resume:",W)
  self.assertIn("  deploy-ig-transport-guard:",W)
if __name__=="__main__":unittest.main()
