"""B07: a second guarded deployment target only, no direct Supabase calls in tests."""
import importlib.util,json,pathlib,unittest
ROOT=pathlib.Path(__file__).resolve().parents[3]
SCRIPT=ROOT/"scripts/lf_profile_update_issue_dispatch.py"
READ=ROOT/"sandbox/lf_contract_gate_test/edge_function_operation/edge_profile_creator_caller_readback_v1.py"
WORKFLOW=ROOT/".github/workflows/lf-edge-deploy-credential-readback.yml"

def module(path,name):
 spec=importlib.util.spec_from_file_location(name,path)
 m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m

class SalyCreatorDeployGoverned(unittest.TestCase):
 def test_only_fixed_issuer_dispatch(self):
  p=module(SCRIPT,"saly_deploy_dispatch")
  body={"schema_version":"LF_PROFILE_UPDATE_REQUEST_V1","action":"profile_creator_caller_deploy"}
  event={"action":"labeled","label":{"name":"lf-profile-update-governed"},
         "issue":{"state":"open","repository_url":"https://api.github.com/repos/cristhianlujan/claude-persona-lf-patch","body":json.dumps(body)}}
  env={"GITHUB_EVENT_NAME":"issues","GITHUB_REPOSITORY":"cristhianlujan/claude-persona-lf-patch"}
  out=p.governed_request(event,env)
  cmd=p.dispatch_command(out)
  self.assertIn("lf-edge-deploy-credential-readback.yml",cmd)
  self.assertIn("action=deploy-profile-creator-caller",cmd)
  self.assertIn("main",cmd)
  bad=dict(body,target_code="PERFIL-ANY")
  evt=dict(event,issue=dict(event["issue"],body=json.dumps(bad)))
  with self.assertRaises(ValueError):p.governed_request(evt,env)
 def test_immutable_jwt_false_management_readback(self):
  m=module(READ,"saly_creator_readback")
  data={"slug":"lf-profile-creator-governance-caller-v1","status":"ACTIVE","verify_jwt":False,"version":17}
  x=m.verify_function_metadata(data,"lf-profile-creator-governance-caller-v1")
  self.assertEqual(x["result"],"EDGE_MANAGEMENT_READ_PASS")
  self.assertTrue(x["jwt_mode_preserved"])
  with self.assertRaises(m.ReadbackBlocked):m.verify_function_metadata(dict(data,verify_jwt=True),"lf-profile-creator-governance-caller-v1")
  with self.assertRaises(m.ReadbackBlocked):m.function_url("any-other-function")
 def test_official_guard_and_rollback_is_bounded(self):
  w=WORKFLOW.read_text(encoding="utf-8")
  self.assertIn("deploy-profile-creator-caller:",w)
  self.assertIn("github.event_name == 'workflow_dispatch' && inputs.action == 'deploy-profile-creator-caller'",w)
  self.assertIn("environment: lf-edge-deploy",w)
  self.assertIn("ROLLBACK_COMMIT: e39abc6eb8fc44d21252f6bcdd34ca2431e816b8",w)
  self.assertIn('test "$(git rev-parse HEAD)" = "$GITHUB_SHA"',w)
  self.assertIn("grep -Fq 'saly_profile_creator_init_v1'",w)
  self.assertIn('--no-verify-jwt --use-api',w)
  self.assertIn("after['version']>before['version']",w)
  self.assertIn('git checkout "$ROLLBACK_COMMIT" -- supabase/functions/lf-profile-creator-governance-caller-v1',w)
  self.assertNotIn('supabase db push',w)
  print("PASS_B07_SALY_CREATOR_DEPLOY_FIXED_GOVERNED_SCOPE")

if __name__=="__main__":unittest.main()
