import importlib.util
from pathlib import Path
import unittest

p=Path(__file__).with_name("edge_pg01_oidc_train_authority_v1.py")
s=importlib.util.spec_from_file_location("pg01_train_auth",p)
m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
MAIN="a"*40
HEAD="b"*40
def fixture():
    pr={"state":"closed","merged_at":"2026-11-02T00:03:00Z","merge_commit_sha":MAIN,"base":{"ref":"main"},"head":{"sha":HEAD}}
    status={"sha":HEAD,"statuses":[{"context":"lf-merge-train/verified","state":"success","creator":{"type":"Bot","login":"lf-migration-train[bot]","id":338337340},"created_at":"2026-11-02T00:01:00Z"}]}
    run={"status":"completed","conclusion":"success","workflow_id":375839198,"id":41514055490,"run_started_at":"2026-11-02T00:00:00Z","path":".github/workflows/lf-migration-merge-train.yml","event":"pull_request_target","head_sha":HEAD,"repository":{"full_name":"cristhianlujan/claude-persona-lf-patch"}}
    return [MAIN,pr,status,run]
class Tests(unittest.TestCase):
    def test_deploy_binding_positive(self):
        self.assertIsNone(m.qualify_deploy_binding(MAIN,"lf-pg01-oidc-authority-v1",MAIN,["supabase/functions/lf-pg01-oidc-authority-v1/index.ts","supabase/functions/lf-pg01-oidc-authority-v1/auth.ts"]))
    def test_deploy_binding_wrong_target(self):
        self.assertEqual(m.qualify_deploy_binding(MAIN,"other",MAIN,list(m.TARGET_PATHS)),"DEPLOY_TARGET_MISMATCH")
    def test_deploy_binding_wrong_commit(self):
        self.assertEqual(m.qualify_deploy_binding(MAIN,m.TARGET_SLUG,HEAD,list(m.TARGET_PATHS)),"DEPLOY_CHECKOUT_SHA_MISMATCH")
    def test_deploy_binding_wrong_source(self):
        self.assertEqual(m.qualify_deploy_binding(MAIN,m.TARGET_SLUG,MAIN,["other.ts"]),"DEPLOY_SOURCE_PATHS_MISMATCH")
    def test_deploy_binding_repeated_path(self):
        self.assertEqual(m.qualify_deploy_binding(MAIN,m.TARGET_SLUG,MAIN,["other.ts","other.ts"]),"DEPLOY_SOURCE_PATHS_MISMATCH")
    def test_pass(self):self.assertIsNone(m.qualify(*fixture()))
    def test_unmerged(self):
        x=fixture();x[1]["merged_at"]=None;self.assertEqual(m.qualify(*x),"PR_NOT_MERGED")
    def test_main_mismatch(self):
        x=fixture();x[1]["merge_commit_sha"]="c"*40;self.assertEqual(m.qualify(*x),"MERGE_SHA_NOT_CURRENT_MAIN")
    def test_status_wrong_head(self):
        x=fixture();x[2]["sha"]="c"*40;self.assertEqual(m.qualify(*x),"STATUS_HEAD_MISMATCH")
    def test_status_self_issued(self):
        x=fixture();x[2]["statuses"][0]["creator"]={"type":"User","login":"paulozterra"};self.assertEqual(m.qualify(*x),"STATUS_NOT_TRUSTED_TRAIN_APP")
    def test_impostor_bot(self):
        x=fixture();x[2]["statuses"][0]["creator"]={"type":"Bot","login":"other[bot]","id":338337340,"created_at":"2026-11-02T00:01:00Z"}
        self.assertEqual(m.qualify(*x),"STATUS_NOT_TRUSTED_TRAIN_APP")
    def test_wrong_app_id(self):
        x=fixture();x[2]["statuses"][0]["creator"]["id"]=123
        self.assertEqual(m.qualify(*x),"STATUS_NOT_TRUSTED_TRAIN_APP")
    def test_untrusted_status_competes(self):
        x=fixture();x[2]["statuses"].append({"context":"lf-merge-train/verified","state":"failure"})
        self.assertEqual(m.qualify(*x),"TRAIN_STATUS_AMBIGUOUS_OR_MISSING")
    def test_malformed_statuses(self):
        x=fixture();x[2]["statuses"]="success";self.assertEqual(m.qualify(*x),"TRAIN_STATUSES_INVALID")
    def test_malformed_pr_head(self):
        x=fixture();x[1]["head"]=None;self.assertEqual(m.qualify(*x),"PR_SOURCE_SHA_INVALID")
    def test_malformed_run_repo(self):
        x=fixture();x[3]["repository"]=None;self.assertEqual(m.qualify(*x),"TRAIN_REPO_MISMATCH")
    def test_no_status(self):
        x=fixture();x[2]["statuses"]=[];self.assertEqual(m.qualify(*x),"TRAIN_STATUS_AMBIGUOUS_OR_MISSING")
    def test_duplicated_status(self):
        x=fixture();x[2]["statuses"]*=2;self.assertEqual(m.qualify(*x),"TRAIN_STATUS_AMBIGUOUS_OR_MISSING")
    def test_wrong_run(self):
        x=fixture();x[3]["path"]=".github/workflows/other.yml";self.assertEqual(m.qualify(*x),"TRAIN_WORKFLOW_MISMATCH")
    def test_wrong_event(self):
        x=fixture();x[3]["event"]="workflow_dispatch";self.assertEqual(m.qualify(*x),"TRAIN_EVENT_MISMATCH")
    def test_run_fail(self):
        x=fixture();x[3]["conclusion"]="failure";self.assertEqual(m.qualify(*x),"TRAIN_RUN_NOT_SUCCESS")
    def test_wrong_workflow_id(self):
        x=fixture();x[3]["workflow_id"]=77;self.assertEqual(m.qualify(*x),"TRAIN_WORKFLOW_ID_MISMATCH")
    def test_status_after_merge(self):
        x=fixture();x[2]["statuses"][0]["created_at"]="2026-11-02T01:00:00Z";self.assertEqual(m.qualify(*x),"TRAIN_PROVENANCE_TIME_ORDER_MISMATCH")
    def test_missing_timestamp(self):
        x=fixture();x[3].pop("run_started_at");self.assertEqual(m.qualify(*x),"TRAIN_PROVENANCE_TIME_MISSING")
    def test_stale_main(self):
        x=fixture();x[3]["head_sha"]="c"*40;self.assertEqual(m.qualify(*x),"TRAIN_SOURCE_HEAD_MISMATCH")
if __name__=="__main__":unittest.main()
