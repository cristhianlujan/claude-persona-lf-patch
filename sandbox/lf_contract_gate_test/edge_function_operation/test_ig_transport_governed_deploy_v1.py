"""Offline, no credentials: governed 3-function Edge deploy and rollback negatives."""
import importlib.util
import json
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent

def import_script(name):
    spec=importlib.util.spec_from_file_location(name,HERE/(name+".py"))
    mod=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

AUTH=import_script("validate_ig_transport_deploy_issue_v1")
BODY=import_script("edge_ig_transport_governed_readback_v1")
WORKFLOW=(ROOT/".github/workflows/lf-edge-deploy-credential-readback.yml").read_text(encoding="utf-8")

def event():
    return {"action":"created",
      "issue":{"number":3907,"state":"open","body":json.dumps(AUTH.EXPECTED)},
      "comment":{"body":"LF_IG_TRANSPORT_DEPLOY_EXECUTE_V1",
         "author_association":"OWNER","user":{"login":"cristhianlujan"}}}
ENV={"GITHUB_EVENT_NAME":"issue_comment","GITHUB_REF":"refs/heads/main",
     "GITHUB_REPOSITORY":"cristhianlujan/claude-persona-lf-patch","GITHUB_SHA":"f"*40}

class GovernedThreeEdgeDeploy(unittest.TestCase):
    def test_owner_trigger_exact(self):
        self.assertEqual(AUTH.validate(event(),ENV)["status"],"AUTHORITY_PASS")
        for field,value in [
           ("action","edited"),("comment.body","SEND_NOW"),("comment.author_association","COLLABORATOR"),
           ("comment.user.login","unauthorized"),("issue.number",3908),("issue.state","closed"),
           ("issue.body",'{}'),
        ]:
            with self.subTest(field=field):
                bad=event()
                target=bad
                parts=field.split(".")
                for p in parts[:-1]:target=target[p]
                target[parts[-1]]=value
                with self.assertRaises(AUTH.Blocked):AUTH.validate(bad,ENV)
        for key in ENV:
            with self.subTest(context=key):
                wrong={**ENV,key:"wrong"}
                with self.assertRaises(AUTH.Blocked):AUTH.validate(event(),wrong)
        for field in AUTH.EXPECTED:
            bad=event()
            b={**AUTH.EXPECTED,field:None}
            bad["issue"]["body"]=json.dumps(b)
            with self.subTest(issue_field=field):
                with self.assertRaises(AUTH.Blocked):AUTH.validate(bad,ENV)

    def test_postread_parity_all_three_slugs(self):
        guard=b"export const validateLfIgTransport = () => null;"
        index=b"import {validateLfIgTransport} from '../_shared/lf_ig_transport_guard_v1.ts';"
        for slug,version in BODY.ROLLOUT.items():
            with self.subTest(slug=slug):
                meta={"slug":slug,"version":version+1,"verify_jwt":True,"status":"ACTIVE"}
                got=BODY.validate(meta,slug,"after",index,guard,index,guard)
                self.assertEqual(got["status"],"READBACK_PASS")
                self.assertTrue(got["guard_sha256"])
                self.assertEqual(got["verify_jwt"],True)
                for mutated in [{**meta,"verify_jwt":False},{**meta,"version":version},
                                {**meta,"slug":"rogue"},{**meta,"status":"DELETING"}]:
                    with self.assertRaises(BODY.ReadbackBlocked):
                        BODY.validate(mutated,slug,"after",index,guard,index,guard)
                for idx,shr in [(b"wrong",guard),(index,b"wrong"),(index,None)]:
                    with self.assertRaises(BODY.ReadbackBlocked):
                        BODY.validate(meta,slug,"after",idx,shr,index,guard)
                with self.assertRaises(BODY.ReadbackBlocked):
                    BODY.validate(meta,slug,"after",b"const x=1",guard,b"const x=1",guard)

    def test_preimage_and_rollback_guard(self):
        index=b"const old = 'frozen';"
        for slug,version in BODY.ROLLOUT.items():
            meta={"slug":slug,"version":version,"verify_jwt":True,"status":"ACTIVE"}
            self.assertEqual(BODY.validate(meta,slug,"before",index,None,index,None)["version"],version)
            after={**meta,"version":version+2}
            self.assertEqual(BODY.validate(after,slug,"rollback",index,None,index,None)["mode"],"rollback")
            with self.assertRaises(BODY.ReadbackBlocked):
                BODY.validate(meta,slug,"rollback",index,None,index,None)

    def test_workflow_uses_exact_issue_existing_credential_and_rollback(self):
        chunk=WORKFLOW.split("  deploy-ig-transport-guard:",1)[1].split("  deploy-ig-v58-runtime:",1)[0]
        for marker in ("issue.number == 3907","issue_comment",
          "environment: lf-edge-deploy",
          "SUPABASE_PROJECT_REF: mhwmirqcgxxukpctffuv",
          "secrets.SUPABASE_ACCESS_TOKEN","validate_ig_transport_deploy_issue_v1.py",
          "edge_ig_transport_governed_readback_v1.py",
          "git merge-base --is-ancestor","git checkout","rollback",
          "input-governance-agent-v1","input-governance-validator-v1",
          "input-governance-curator-v1","--use-api"):
            self.assertIn(marker,chunk)
        self.assertEqual(chunk.count("supabase functions deploy"),2) # in 2 loops
        self.assertNotIn("--no-verify-jwt",chunk)
        for forbidden in ("SUPABASE_SERVICE_ROLE_KEY","OPENAI_API_KEY","DATABASE_URL"):
            self.assertNotIn(forbidden,chunk)

if __name__=="__main__":unittest.main()
