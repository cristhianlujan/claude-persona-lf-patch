"""B07 SALY native-profile create: documentary scope, exact allowlist, no production inheritance."""
import importlib.util
import json
import pathlib
import unittest

ROOT=pathlib.Path(__file__).resolve().parents[3]
CALLER=(ROOT/"supabase/functions/lf-profile-creator-governance-caller-v1/index.ts").read_text()
RUNTIME=(ROOT/"supabase/functions/run-creacion-perfil-lf/index.ts").read_text()
WORKFLOW=(ROOT/".github/workflows/lf-customer-profile-creator-governance-caller.yml").read_text()
PARSER=ROOT/"scripts/lf_profile_update_issue_dispatch.py"
RECEIPT="107332ebbae4295dc76179bd5619856cb61807b91a856c080b12e1942018fb0f"

def load_dispatcher():
 spec=importlib.util.spec_from_file_location("lf_saly_dispatcher",PARSER)
 module=importlib.util.module_from_spec(spec)
 spec.loader.exec_module(module)
 return module

class SalyCallerAdmission(unittest.TestCase):
 def test_static_boundaries(self):
  for val in ("PERFIL-PRODUCT-DIRECTOR-SALY","saly_product_director",
              "SALY_CREATION_OIDC_SCOPE_DENIED","SALY_CREATION_SCOPE_OR_DECISION_INVALID"):
   self.assertIn(val,CALLER)
  self.assertIn('body.action === "saly_profile_creator_init_v1"',CALLER)
  self.assertIn('caller.method !== UPDATE_CALLER_METHOD',CALLER)
  self.assertIn('body.production_authorized !== false',CALLER)
  self.assertIn("identity.workflowRef !== UPDATE_WORKFLOW_REF",CALLER)
  self.assertIn("SALY_CREATION_DOCUMENTARY_AUTHORITY_INVALID",RUNTIME)
  self.assertIn("PROFILE_CREATION_CALLER_SCOPE_DENIED",RUNTIME)
  self.assertIn("customer_profile_scope: !salyTarget",RUNTIME)
  self.assertIn("production_authorized: !salyTarget",RUNTIME)
  self.assertIn("identity_verified: false",RUNTIME)
  self.assertIn('caller.method !== CUSTOMER_CALLER_METHOD',RUNTIME)
  self.assertIn("saly_profile_create_init",WORKFLOW)
  self.assertIn("SALY_NATIVE_CREATION_START_PASS",WORKFLOW)
  self.assertIn('m.get("production_authorized") is False',WORKFLOW)
  self.assertIn("lf-profile-create-saly-governed",WORKFLOW)
  # Still four and ONLY four Customer targets; do not mutate their production contracts.
  self.assertEqual(CALLER.count('"PERFIL-CUSTOMER-'),4)
  self.assertIn("production_authorized: !salyTarget",RUNTIME)
  self.assertIn('if (body.action === "profile_creator_init_v1")',CALLER)

 def test_issue_contract_negative_no_cross_project_or_prod(self):
  mod=load_dispatcher()
  body={"schema_version":"LF_SALY_PROFILE_CREATE_REQUEST_V1",
        "action":"saly_profile_create_init",
        "project_code":"SALY","target_code":"PERFIL-PRODUCT-DIRECTOR-SALY",
        "profile_slug":"saly_product_director","owner_decision_sha256":RECEIPT,
        "identity_verified":False,"production_authorized":False}
  evt={"action":"labeled","label":{"name":"lf-profile-create-saly-governed"},
       "issue":{"state":"open","repository_url":"https://api.github.com/repos/cristhianlujan/claude-persona-lf-patch","body":json.dumps(body)}}
  env={"GITHUB_EVENT_NAME":"issues","GITHUB_REPOSITORY":"cristhianlujan/claude-persona-lf-patch"}
  good=mod.governed_request(evt,env)
  self.assertEqual(good["action"],"saly_profile_create_init")
  self.assertEqual(good["project_code"],"SALY")
  self.assertNotIn("production_authorized",good) # workflow/caller fix false on server
  for field,value in (("production_authorized",True),("identity_verified",True),
       ("project_code","LF"),("target_code","PERFIL-PRODUCT-DIRECTOR-LF"),
       ("owner_decision_sha256","0"*64),("profile_slug","product_director_lf")):
   bad=dict(body,**{field:value});e=dict(evt,issue=dict(evt["issue"],body=json.dumps(bad)))
   with self.assertRaises(ValueError,msg=field):mod.governed_request(e,env)
  e=dict(evt,label={"name":"lf-profile-update-governed"})
  with self.assertRaises(ValueError):mod.governed_request(e,env)
  self.assertIn("lf-customer-profile-creator-governance-caller.yml",mod.dispatch_command(good))
  self.assertIn("action=saly_profile_create_init",mod.dispatch_command(good))
  print("PASS_B07_SALY_CREATOR_OIDC_EXACT_SCOPE_NO_PRODUCTION_INHERITANCE")

if __name__=="__main__":unittest.main()
