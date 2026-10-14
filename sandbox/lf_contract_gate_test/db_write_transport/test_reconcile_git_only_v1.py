from __future__ import annotations
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
import json, subprocess, sys, tempfile, unittest
from unittest.mock import patch
import lf_migration_reconcile_git as m
from migration_transport_normalization import direct_source_hash

OLD="supabase/migrations/20261012040000_ig_example_v1.sql"
NEW="supabase/migrations/20261012012743_ig_example_v1.sql"

# Lot 3 replay: each source is read from the real base tree and checked against
# version, name and full canonical SHA-256 read from the reconciliation ledger.
LOTE3 = (
    ("20261008214500", "ig_m8_2_per_family_resolver", "20261008195346", "ig_m8_2_per_family_resolver_hook_v1", "1286c3df773b462c99a52316df3e458c446decaad6a39a62f295b367472d2c1c"),
    ("20261008214501", "ig_m8_2_per_family_resolver", "20261008195353", "ig_m8_2_per_family_resolver_facade_v1", "77caaec4232596fd812be2c8dd8b0a7e6db528c31fcec166baf0799aba325ac0"),
    ("20261008222000", "ig_m8_6_batch_common", "20261008201658", "ig_m8_6_batch_common_v1", "ac90953794d8c827b53e94194c1d16b46d54fdc2d563bc73b7a72bcf3c6f36b8"),
    ("20261011040000", "lf_d2_facade_request_plan_v1", "20261011050556", "20261011040000_lf_d2_facade_request_plan_v1", "e00eb01ada6513c3c949a939ff4a3fda09c2996015b463fcd1a4c3fa8498027d"),
    ("20261011041000", "lf_d2_facade_receipt_readback_v1", "20261011050603", "20261011041000_lf_d2_facade_receipt_readback_v1", "7503b8fdf364352f2771e7402ecd260c0d8cd26635cdf15438fedd460dda56e5"),
    ("20261011042000", "lf_d2_source_binding_candidate_v1", "20261011051027", "20261011042000_lf_d2_source_binding_candidate_v1", "94ef32181b43508bbead0e02342d45bf513cd8800470f22a6bfc1be6e3941bcc"),
    ("20261011043000", "lf_d2_admission_readiness_v1", "20261011080740", "20261011043000_lf_d2_admission_readiness_v1", "935721846ef248883abab4426ff8093224465fd037f1772339f613ae1fa722fc"),
    ("20261011050000", "b2b_scoped_load_metadata_rls_v1", "20261011082936", "20261011050000_b2b_scoped_load_metadata_rls_v1", "7a93d928eb1a7624f0e1071c77beb107496d8539daee729d4211f8be6e8b57b6"),
    ("20261011051000", "lf_d2_admission_column_grants_v1", "20261011083212", "20261011051000_lf_d2_admission_column_grants_v1", "6848d2b554f86ea93c3b7150853663d30e3d501fe88e2a67622bc0e2a0406fac"),
    ("20261011054000", "lf_source_asset_authority_acl_v1", "20261011223601", "20261011054000_lf_source_asset_authority_acl_v1", "335c063ee19b491663ff9c2f7be9d3d159c16becbbcbffcfdce3bcf7a1b9948d"),
    ("20261011060000", "lf_d2_metadata_admission_split_v1", "20261012004355", "20261011060000_lf_d2_metadata_admission_split_v1", "c37a92e9444fec61c9e2ecf137976be81b285ef561d242005b880297fa0663c1"),
    ("20261012001100", "ig_m99_ekb_jsonb_null_assertion_v1", "20261012001330", "20261012001100_ig_m99_ekb_jsonb_null_assertion_v1", "4886b1cb340371edd1d6335708da98dee8e35ed13baf608fccd2e1a1798b1db3"),
    ("20261012002200", "ig_m99_cohort_authority_reconcile_v1", "20261012000842", "20261012002200_ig_m99_cohort_authority_reconcile_v1", "41eaeefecb41fbac81727a203e4aff3ab327aae39be9b6f30d1464cb8d801e9c"),
    ("20261012004000", "ig_m99_rollback_receipt_policy_v1", "20261012002150", "20261012004000_ig_m99_rollback_receipt_policy_v1", "3ae9672fcdc517ecbacd5c33cbb92d7ed8dcb90c2327f0ae6e253ee9bf36516c"),
    ("20261012005800", "ig_m99_transversal_reconciler_decouple_v1", "20261012003510", "20261012005800_ig_m99_transversal_reconciler_decouple_v1", "9e009b9f09ba8cecbe5f3fc94d6af55103663872a35cb238684eb5a50b954967"),
    ("20261012010600", "ig_m99_runtime_proof_gate_contract_v1", "20261012003903", "20261012010600_ig_m99_runtime_proof_gate_contract_v1", "29a851f5209c50c99f05df4d77d541120526333c3143a42ee23f530844a2bece"),
    ("20261012011000", "ig_m910_versioned_cohort_contract_v1", "20261012004206", "20261012011000_ig_m910_versioned_cohort_contract_v1", "d716c2b5d160537c2b57d6a214830f06991a74b924860939f569973236df4193"),
    ("20261012011500", "ig_m99_reversible_consumer_binding_v1", "20261012004144", "20261012011500_ig_m99_reversible_consumer_binding_v1", "c75302294228f560380dc380e5104b2fb0ac146b5a0ab9438703cec289451b0e"),
    ("20261012015000", "ig_m910_residue_delta_ekb_v1", "20261012004415", "20261012015000_ig_m910_residue_delta_ekb_v1", "e028e8aac8f562f25c5ea8b78e00cdb780de8b7107ffd77c071b48ab1b7e347c"),
    ("20261012021000", "ig_m912_readiness_ig_owned_contract_v1", "20261012005601", "20261012021000_ig_m912_readiness_ig_owned_contract_v1", "59f0ef6e35dc9a28c069566622e8b43c37dd1ec07939caa6636e2302f33607f6"),
    ("20261012021100", "ig_m912_receipt_sourcepack_reconcile_v1", "20261012005604", "20261012021100_ig_m912_receipt_sourcepack_reconcile_v1", "2cd0e69a30547d734280232237f955a3c8acb7b27383b982851d2686e7246201"),
    ("20261012021200", "ig_m912_ekb_contract_errors_v1", "20261012005606", "20261012021200_ig_m912_ekb_contract_errors_v1", "7ff9d3fef0d995b7e38028b9b0b470f1dd870a5aaa783593e4626ed4570253f9"),
    ("20261012023000", "ig_m912_m98_technical_consumption_v1", "20261012011005", "20261012023000_ig_m912_m98_technical_consumption_v1", "c0d29af5f0bf21ad51b4b491bcc670ce22169ee6c27e34313fdaa4fbd63cbb83"),
    ("20261012032000", "ig_m913_ledger_independent_contract_v1", "20261012011948", "20261012032000_ig_m913_ledger_independent_contract_v1", "885a2bd5e5d8a35590d9c90101bbb8ebba954df9cd88548b2a69e65a324d2fa1"),
    ("20261012032100", "ig_m913_ekb_contract_errors_v1", "20261012011950", "20261012032100_ig_m913_ekb_contract_errors_v1", "fb80e5a5c69bd5ae8efd2dad9f5452bba221b39ef55d609a4ef629cb16383b2d"),
    ("20261012040000", "ig_m100_typed_frozen_bundle_contract_v1", "20261012012743", "20261012040000_ig_m100_typed_frozen_bundle_contract_v1", "d9de7324c0650d913cae161368ca2752830d58195cc7abbc333f8cc8c61c996a"),
    ("20261012040100", "ig_m100_human_approval_semantics_v1", "20261012012746", "20261012040100_ig_m100_human_approval_semantics_v1", "1c5015d2441c6c1bd0bbb18edc48da168729dd5fbf3476225a3a0597d014875e"),
    ("20261012040200", "ig_m100_ekb_contract_findings_v1", "20261012012748", "20261012040200_ig_m100_ekb_contract_findings_v1", "2a0738d85f0de6254682056aaab7fc7e5ab11ac8d5d8d98b799dbf37dbb93163"),
    ("20261012072000", "lf_gpt_native_in_chat_capture_policy_candidate_v1", "20261012080128", "20261012072000_lf_gpt_native_in_chat_capture_policy_candidate_v1", "98ba73f61e26035dfdc4a644edc4bc16843aa5750446173be1e9c924e16b8076"),
)

def git(root,*args):
    p=subprocess.run(["git",*args],cwd=root,capture_output=True,text=True)
    if p.returncode: raise RuntimeError(p.stderr)
    return p.stdout.strip()

class ReconcileGitOnlyTest(unittest.TestCase):
    def prepare(self, status="renamed", mutate=False, extra=False, source_sql="select 1;\n"):
        tmp=tempfile.TemporaryDirectory()
        root=Path(tmp.name)
        git(root,"init","-q");git(root,"config","user.email","tests@example.test");git(root,"config","user.name","Tests")
        p=root/OLD;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(source_sql)
        git(root,"add",".");git(root,"commit","-qm","original")
        base=git(root,"rev-parse","HEAD")
        p.rename(root/NEW)
        if mutate:(root/NEW).write_text("select 2;\n")
        git(root,"add","-A");git(root,"commit","-qm","rename")
        head=git(root,"rev-parse","HEAD")
        rows=[{"status":status,"filename":NEW,"previous_filename":OLD}]
        if extra:rows.append({"status":"modified","filename":"README.md"})
        file=root/"changed.json";file.write_text(json.dumps([rows]))
        return tmp,root,file,base,head

    def run_case(self,*,status="renamed",mutate=False,extra=False,source_sql="select 1;\n",ledger=None):
        tmp,root,changes,base,head=self.prepare(status=status,mutate=mutate,extra=extra,source_sql=source_sql)
        try:
            args=["test","--repo-root",str(root),"--pr-files",str(changes),"--base-sha",base,"--head-sha",head,
                  "--router-execution-id","EXEC-RECONCILE-1","--repository","o/r","--db-url","test-db"]
            with patch.object(sys,"argv",args),patch.object(m,"validate_router") as auth,patch.object(m,"ledger_row",return_value=ledger or ("ig_example_v1","select 1;\n",1)):
                with redirect_stdout(StringIO()) as out:
                    m.main()
                return json.loads(out.getvalue()),auth.call_count
        finally:
            tmp.cleanup()

    def test_mode_contract_extends_existing_judge_without_promoting(self):
        root=Path(__file__).resolve().parents[3]
        path=root/"docs/migrations/LF_TRAIN_RECONCILE_JUDGE_EXTENSION_CANDIDATE_V1.json"
        candidate=json.loads(path.read_text(encoding="utf-8"))
        self.assertEqual(candidate["status"],"CANDIDATE_NOT_REGISTERED_NOT_ACTIVE")
        self.assertEqual(candidate["operation_code"],"ACTUALIZACION_DB_LF")
        self.assertEqual(candidate["mode"],"RECONCILE_GIT_ONLY")
        self.assertEqual(candidate["authority_boundary"]["entry"],"ACT-0001")
        self.assertFalse(candidate["authority_boundary"]["db_writes_allowed"])
        self.assertFalse(candidate["authority_boundary"]["ledger_dml_allowed"])
        self.assertEqual(candidate["existing_bindings_not_to_override"]["judge_code"],"JUDGE_DB_MUTATION_SANDBOX_MINIMAL_V1")
        self.assertEqual(sorted(candidate["proposed_mode_judge"]),["patch","preflight","verify"])
        self.assertEqual(candidate["implementation_state"]["git_only_closeout"],"NOT_IMPLEMENTED")
    def test_train_routes_reconcile_without_db_apply(self):
        wf=(Path(__file__).resolve().parents[3]/".github/workflows/lf-migration-merge-train.yml").read_text()
        self.assertLess(wf.index("- name: Resolve RECONCILE governed mode"),
                        wf.index("- name: Sync PR branch with current main in REAL mode"))
        self.assertIn("RECONCILE_GIT_ONLY_PASS",wf)
        gate = wf.index("- name: Block RECONCILE promotion until governed Git-only closeout exists")
        publish = wf.index("- name: Publish lf-merge-train/verified before REAL merge")
        merge = wf.index("- name: Merge exact head only")
        self.assertLess(gate,publish)
        self.assertLess(publish,merge)
        self.assertIn("BLOCK_RECONCILE_GIT_ONLY_CLOSURE_JUDGE_NOT_ADMITTED",wf[gate:publish])
        self.assertIn("exit 2",wf[gate:publish])
        self.assertIn("migration_count=0",wf)
        self.assertIn("--router-execution-id",wf)
        self.assertIn("steps.reconcile_mode.outputs.mode != 'RECONCILE'",wf)
        self.assertIn("RECONCILE_MIXED_SCOPE_FORBIDDEN",(Path(__file__).resolve().parent/"lf_migration_reconcile_git.py").read_text())

    def test_multi_statement_ledger_blocks_without_any_write(self):
        tmp,root,changes,base,head=self.prepare()
        try:
            args=["test","--repo-root",str(root),"--pr-files",str(changes),
                  "--base-sha",base,"--head-sha",head,
                  "--router-execution-id","EXEC-RECONCILE-1","--repository","o/r","--db-url","read-only"]
            with patch.object(sys,"argv",args),patch.object(m,"validate_router"),\
                 patch.object(m,"ledger_row",return_value=("ig_example_v1","select 1;\n",2)):
                with self.assertRaisesRegex(RuntimeError,"RECONCILE_CANONICAL_PARITY_FAILED"):
                    m.main()
        finally:
            tmp.cleanup()

    def test_ledger_sql_mismatch_is_rejected_by_canonical_core(self):
        tmp,root,changes,base,head=self.prepare()
        try:
            args=["test","--repo-root",str(root),"--pr-files",str(changes),
                  "--base-sha",base,"--head-sha",head,
                  "--router-execution-id","EXEC-RECONCILE-1","--repository","o/r","--db-url","read-only"]
            with patch.object(sys,"argv",args),patch.object(m,"validate_router"),\
                 patch.object(m,"ledger_row",return_value=("ig_example_v1","select 99;\n",1)):
                with self.assertRaisesRegex(RuntimeError,"RECONCILE_CANONICAL_PARITY_FAILED"):
                    m.main()
        finally:
            tmp.cleanup()
    def test_cli_multi_statement_ledger_representation_passes(self):
        sql="select 1;\nselect 2;\n"
        got,auth=self.run_case(source_sql=sql,ledger=("ig_example_v1","select 1\nselect 2",2))
        self.assertEqual(got["code"],"RECONCILE_GIT_ONLY_PASS")
        self.assertEqual(auth,1)

    def test_lote3_replays_all_29_real_source_pairs_against_ledger_hashes(self):
        self.assertEqual(len(LOTE3), 29)
        repo = Path(__file__).resolve().parents[3]
        tmp = tempfile.TemporaryDirectory()
        root = Path(tmp.name)
        git(root,"init","-q");git(root,"config","user.email","tests@example.test");git(root,"config","user.name","Tests")
        changes = []
        ledger = {}
        for git_version,git_name,ledger_version,ledger_name,ledger_hash in LOTE3:
            old_name = f"{git_version}_{git_name}.sql"
            new_name = f"{ledger_version}_{ledger_name}.sql"
            old_rel = f"supabase/migrations/{old_name}"
            new_rel = f"supabase/migrations/{new_name}"
            sql = (repo/old_rel).read_text(encoding="utf-8")
            self.assertEqual(direct_source_hash(sql), ledger_hash, old_rel)
            ledger[ledger_version] = (ledger_name,sql,1)
            target = root/old_rel
            target.parent.mkdir(parents=True,exist_ok=True)
            target.write_text(sql,encoding="utf-8")
            changes.append({"status":"renamed","filename":new_rel,"previous_filename":old_rel})
        git(root,"add",".");git(root,"commit","-qm","lot 3 source base")
        base=git(root,"rev-parse","HEAD")
        for row in changes:
            (root/row["previous_filename"]).rename(root/row["filename"])
        git(root,"add","-A");git(root,"commit","-qm","lot 3 ledger rename replay")
        head=git(root,"rev-parse","HEAD")
        change_file=root/"changed.json";change_file.write_text(json.dumps([changes]),encoding="utf-8")
        args=["test","--repo-root",str(root),"--pr-files",str(change_file),"--base-sha",base,"--head-sha",head,
              "--router-execution-id","EXEC-RECONCILE-LOTE3","--repository","o/r","--db-url","test-db"]
        try:
            with patch.object(sys,"argv",args),patch.object(m,"validate_router") as auth,\
                 patch.object(m,"ledger_row",side_effect=lambda _url,version: ledger.get(version)):
                with redirect_stdout(StringIO()) as out:
                    m.main()
            result=json.loads(out.getvalue())
            self.assertEqual(result["code"],"RECONCILE_GIT_ONLY_PASS")
            self.assertEqual(result["count"],29)
            self.assertEqual(auth.call_count,1)
            self.assertEqual({(item["version"],item["name"]) for item in result["renames"]},
                             {(v,n) for _,_,v,n,_ in LOTE3})
        finally:
            tmp.cleanup()

    def test_target_ledger_version_missing_blocks(self):
        tmp,root,changes,base,head=self.prepare()
        try:
            args=["test","--repo-root",str(root),"--pr-files",str(changes),"--base-sha",base,"--head-sha",head,
                  "--router-execution-id","EXEC-RECONCILE-1","--repository","o/r","--db-url","read-only"]
            with patch.object(sys,"argv",args),patch.object(m,"validate_router"),patch.object(m,"ledger_row",return_value=None):
                with self.assertRaisesRegex(RuntimeError,"RECONCILE_TARGET_LEDGER_VERSION_MISSING"):
                    m.main()
        finally:
            tmp.cleanup()

    def test_removed_file_without_rename_pair_blocks(self):
        tmp,root,changes,base,head=self.prepare()
        try:
            rows=json.loads(changes.read_text(encoding="utf-8"))[0]
            rows[0]={"status":"removed","filename":OLD,"previous_filename":None}
            changes.write_text(json.dumps([rows]),encoding="utf-8")
            args=["test","--repo-root",str(root),"--pr-files",str(changes),"--base-sha",base,"--head-sha",head,
                  "--router-execution-id","EXEC-RECONCILE-1","--repository","o/r","--db-url","read-only"]
            with patch.object(sys,"argv",args),patch.object(m,"validate_router"),\
                 patch.object(m,"ledger_row",return_value=("ig_example_v1","select 1;\n",1)):
                with self.assertRaisesRegex(RuntimeError,"RECONCILE_NOT_RENAME_ONLY"):
                    m.main()
        finally:
            tmp.cleanup()

    def test_new_migration_mixed_with_renames_blocks(self):
        tmp,root,changes,base,head=self.prepare()
        try:
            rows=json.loads(changes.read_text(encoding="utf-8"))[0]
            rows.append({"status":"added","filename":"supabase/migrations/20261014000000_new_migration.sql"})
            changes.write_text(json.dumps([rows]),encoding="utf-8")
            args=["test","--repo-root",str(root),"--pr-files",str(changes),"--base-sha",base,"--head-sha",head,
                  "--router-execution-id","EXEC-RECONCILE-1","--repository","o/r","--db-url","read-only"]
            with patch.object(sys,"argv",args),patch.object(m,"validate_router"),\
                 patch.object(m,"ledger_row",return_value=("ig_example_v1","select 1;\n",1)):
                with self.assertRaisesRegex(RuntimeError,"RECONCILE_NOT_RENAME_ONLY"):
                    m.main()
        finally:
            tmp.cleanup()

    def test_inconsistent_ledger_statement_payload_is_rejected(self):
        record={"name":"ig_example_v1","statement_count":2,"statements":["select 1;"]}
        with patch.object(m,"read_only_query",return_value=[json.dumps(record)]):
            with self.assertRaisesRegex(RuntimeError,"RECONCILE_LEDGER_STATEMENT_PAYLOAD_INVALID"):
                m.ledger_row("fake-read-only","20261012012743")
    def test_git_only_exact_content_passes(self):
        got,auth=self.run_case()
        self.assertEqual(got["code"],"RECONCILE_GIT_ONLY_PASS")
        self.assertEqual(got["count"],1)
        self.assertEqual(auth,1)

    def test_sql_changed_blocks(self):
        with self.assertRaisesRegex(RuntimeError,"RECONCILE_CONTENT_CHANGED"):
            self.run_case(mutate=True)

    def test_nonrename_blocks(self):
        with self.assertRaisesRegex(RuntimeError,"RECONCILE_NOT_RENAME_ONLY"):
            self.run_case(status="modified")

    def test_mixed_scope_blocks(self):
        with self.assertRaisesRegex(RuntimeError,"RECONCILE_MIXED_SCOPE_FORBIDDEN"):
            self.run_case(extra=True)

    def test_invalid_router_receipt_blocks(self):
        receipt={"status":"IN_PROGRESS","operation_code":"ACTUALIZACION_DB_LF","target_type":"MIGRATION",
                 "target_code":"RECONCILE_GIT_ONLY","target_repo":"o/r","target_path":"supabase/migrations",
                 "source_base":"a"*40,"source_head":"b"*40,
                 "authority":{"applicable":True,"valid":False,"code":"ROUTER_DOWNSTREAM_AUTHORITY_NOT_BOUND"}}
        with patch.object(m,"read_only_query",return_value=[json.dumps(receipt)]):
            with self.assertRaisesRegex(RuntimeError,"ROUTER_AUTHORITY_NOT_VALID"):
                m.validate_router("test","EXEC-RECONCILE-1","o/r","a"*40,"b"*40)

if __name__=="__main__":unittest.main()
