import importlib.util
import pathlib
import unittest
ROOT=pathlib.Path(__file__).resolve().parents[3]
PATH=ROOT/"skills/profile_creator/validators/srcr_updater_handoff_v1.py"
spec=importlib.util.spec_from_file_location("srcr_handoff",PATH)
gate=importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)

def sample():
    return {"schema_version":"LF_SRCR_UPDATER_HANDOFF_V1",
            "business":"LF","mode":"REQUEST_ONLY",
            "source_operation":"EJECUCION_PERFIL_LF",
            "source_profile_code":"PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF",
            "source_execution_id":"EXEC-PROFILE-GATE2-AAAAAAAAAAAAAAAAAAAAAAAA",
            "target_operation":"ACTUALIZACION_PERFIL_LF",
            "target_code":"PERFIL-UI-ARCHITECT",
            "target_path":"profiles/ui_architect/SKILL.md",
            "request_sha256":"a"*64,
            "router_authorization_receipt_sha256":"b"*64,
            "policy_snapshot_sha256":"c"*64,
            "diagnosis_ref":"supabase://public/lf_operation_execution_steps/parent",
            "diagnosis_sha256":"d"*64,
            "target_main_revision_sha":"e"*40,
            "target_blob_sha":"f"*40,
            "authorized_scope":["PERFIL-UI-ARCHITECT"]}

class SRCRHandoffTest(unittest.TestCase):
    def test_structure_not_authority(self):
        r=gate.inspect(sample())
        self.assertEqual(r["status"],"READY_FOR_SERVER_VERIFICATION")
        self.assertFalse(r["dispatch_authorized"])
        self.assertFalse(r["server_verified"])

    def test_forbidden_sources(self):
        for field,value in [("business","SALY"),("mode","GOVERNED_REPAIR_WRITE"),
                            ("source_profile_code","PERFIL-OTHER"),
                            ("source_operation","ACTUALIZACION_PERFIL_LF"),
                            ("authorized_scope",["PERFIL-OTHER"]),
                            ("target_path","profiles/../secret/SKILL.md"),
                            ("request_sha256","wrong"),
                            ("target_main_revision_sha","wrong"),
                            ("target_blob_sha","wrong")]:
            h=sample();h[field]=value
            with self.subTest(field=field):
                self.assertEqual(gate.inspect(h)["status"],"BLOCKED")

    def test_rejects_escalation_and_missing(self):
        for field in ("service_role","repair_execution_authority","direct_dispatch_authorized"):
            h=sample();h[field]=True
            with self.subTest(field=field):
                self.assertEqual(gate.inspect(h)["status"],"BLOCKED")
        h=sample();del h["source_execution_id"]
        self.assertEqual(gate.inspect(h)["status"],"BLOCKED")
        for obsolete in ("context_transport","consumer","resume_via"):
            h=sample();h[obsolete]="CONTEXT_PACK"
            with self.subTest(obsolete=obsolete):
                self.assertEqual(gate.inspect(h)["status"],"BLOCKED")

    def test_return_requires_independent_readback(self):
        h=sample()
        r={"schema_version":"LF_SRCR_UPDATER_RETURN_V1",
           "source_execution_id":h["source_execution_id"],
           "child_execution_id":"EXEC-ACTUALIZACION-PERFIL-LF-OIDC-aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
           "target_code":h["target_code"],"status":"COMPLETED",
           "terminal_receipt_ref":"supabase://public/lf_operation_execution_steps/child",
           "terminal_receipt_sha256":"f"*64,
           "exact_head_sha":"a"*40,"next_action":"RETURN_TO_SRCR"}
        result=gate.inspect_return(h,r)
        self.assertEqual(result["status"],"READY_FOR_INDEPENDENT_READBACK")
        self.assertFalse(result["terminal_verified"])
        r["target_code"]="PERFIL-OTHER"
        self.assertEqual(gate.inspect_return(h,r)["status"],"BLOCKED")
        r["target_code"]=h["target_code"];r["terminal_receipt_sha256"]="not-a-sha"
        self.assertEqual(gate.inspect_return(h,r)["status"],"BLOCKED")


    def test_existing_runner_outcome_is_not_trusted_as_receipt(self):
        h=sample()
        runner={"status":"COMPLETED",
                "execution_id":"EXEC-ACTUALIZACION-PERFIL-LF-OIDC-12345678-1234-4123-8123-123456789abc",
                "state":{"closed":True,"commit":"a"*40,"merge_sha":"b"*40,"pr":3520}}
        out=gate.inspect_existing_runner_result(h,runner)
        self.assertEqual(out["status"],"AWAITING_SERVER_READBACK")
        self.assertFalse(out["server_verified"])
        self.assertFalse(out["terminal_verified"])
        self.assertEqual(out["source_execution_id"],h["source_execution_id"])
        self.assertEqual(out["child_execution_id"],runner["execution_id"])

        runner["state"]["closed"]=False
        self.assertEqual(gate.inspect_existing_runner_result(h,runner)["status"],"BLOCKED")
        runner["state"]["closed"]=True
        runner["execution_id"]=h["source_execution_id"]
        self.assertEqual(gate.inspect_existing_runner_result(h,runner)["status"],"BLOCKED")

    def test_existing_runner_dry_or_stopped_does_not_close_parent(self):
        h=sample()
        dry=gate.inspect_existing_runner_result(h,{"status":"DRY_RUN_OK"})
        self.assertEqual(dry["status"],"NOT_EXECUTED")
        blocked=gate.inspect_existing_runner_result(h,{"status":"STOPPED","code":"MAIN_ADVANCED_SINCE_EXECUTION_ANCHOR"})
        self.assertEqual(blocked["status"],"BLOCKED")
        self.assertEqual(blocked["next_action"],"RETURN_BLOCKER_TO_PARENT")
        self.assertFalse(blocked["terminal_verified"])
        self.assertEqual(gate.inspect_existing_runner_result(h,{"status":"COMPLETED","state":{}})["status"],"BLOCKED")

if __name__=="__main__": unittest.main()
