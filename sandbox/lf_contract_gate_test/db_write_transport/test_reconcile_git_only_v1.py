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
# the version/name/hash16 recorded in the reconciliation ledger.
LOTE3 = (
    ("20261008214500", "ig_m8_2_per_family_resolver", "20261008195346", "ig_m8_2_per_family_resolver_hook_v1", "1286c3df773b462c"),
    ("20261008214501", "ig_m8_2_per_family_resolver", "20261008195353", "ig_m8_2_per_family_resolver_facade_v1", "77caaec4232596fd"),
    ("20261008222000", "ig_m8_6_batch_common", "20261008201658", "ig_m8_6_batch_common_v1", "ac90953794d8c827"),
    ("20261011040000", "lf_d2_facade_request_plan_v1", "20261011050556", "20261011040000_lf_d2_facade_request_plan_v1", "e00eb01ada6513c3"),
    ("20261011041000", "lf_d2_facade_receipt_readback_v1", "20261011050603", "20261011041000_lf_d2_facade_receipt_readback_v1", "7503b8fdf364352f"),
    ("20261011042000", "lf_d2_source_binding_candidate_v1", "20261011051027", "20261011042000_lf_d2_source_binding_candidate_v1", "94ef32181b43508b"),
    ("20261011043000", "lf_d2_admission_readiness_v1", "20261011080740", "20261011043000_lf_d2_admission_readiness_v1", "935721846ef24888"),
    ("20261011050000", "b2b_scoped_load_metadata_rls_v1", "20261011082936", "20261011050000_b2b_scoped_load_metadata_rls_v1", "7a93d928eb1a7624"),
    ("20261011051000", "lf_d2_admission_column_grants_v1", "20261011083212", "20261011051000_lf_d2_admission_column_grants_v1", "6848d2b554f86ea9"),
    ("20261011054000", "lf_source_asset_authority_acl_v1", "20261011223601", "20261011054000_lf_source_asset_authority_acl_v1", "335c063ee19b4916"),
    ("20261011060000", "lf_d2_metadata_admission_split_v1", "20261012004355", "20261011060000_lf_d2_metadata_admission_split_v1", "c37a92e9444fec61"),
    ("20261012001100", "ig_m99_ekb_jsonb_null_assertion_v1", "20261012001330", "20261012001100_ig_m99_ekb_jsonb_null_assertion_v1", "4886b1cb340371ed"),
    ("20261012002200", "ig_m99_cohort_authority_reconcile_v1", "20261012000842", "20261012002200_ig_m99_cohort_authority_reconcile_v1", "41eaeefecb41fbac"),
    ("20261012004000", "ig_m99_rollback_receipt_policy_v1", "20261012002150", "20261012004000_ig_m99_rollback_receipt_policy_v1", "3ae9672fcdc517ec"),
    ("20261012005800", "ig_m99_transversal_reconciler_decouple_v1", "20261012003510", "20261012005800_ig_m99_transversal_reconciler_decouple_v1", "9e009b9f09ba8cec"),
    ("20261012010600", "ig_m99_runtime_proof_gate_contract_v1", "20261012003903", "20261012010600_ig_m99_runtime_proof_gate_contract_v1", "29a851f5209c50c9"),
    ("20261012011000", "ig_m910_versioned_cohort_contract_v1", "20261012004206", "20261012011000_ig_m910_versioned_cohort_contract_v1", "d716c2b5d160537c"),
    ("20261012011500", "ig_m99_reversible_consumer_binding_v1", "20261012004144", "20261012011500_ig_m99_reversible_consumer_binding_v1", "c75302294228f560"),
    ("20261012015000", "ig_m910_residue_delta_ekb_v1", "20261012004415", "20261012015000_ig_m910_residue_delta_ekb_v1", "e028e8aac8f562f2"),
    ("20261012021000", "ig_m912_readiness_ig_owned_contract_v1", "20261012005601", "20261012021000_ig_m912_readiness_ig_owned_contract_v1", "59f0ef6e35dc9a28"),
    ("20261012021100", "ig_m912_receipt_sourcepack_reconcile_v1", "20261012005604", "20261012021100_ig_m912_receipt_sourcepack_reconcile_v1", "2cd0e69a30547d73"),
    ("20261012021200", "ig_m912_ekb_contract_errors_v1", "20261012005606", "20261012021200_ig_m912_ekb_contract_errors_v1", "7ff9d3fef0d995b7"),
    ("20261012023000", "ig_m912_m98_technical_consumption_v1", "20261012011005", "20261012023000_ig_m912_m98_technical_consumption_v1", "c0d29af5f0bf21ad"),
    ("20261012032000", "ig_m913_ledger_independent_contract_v1", "20261012011948", "20261012032000_ig_m913_ledger_independent_contract_v1", "885a2bd5e5d8a355"),
    ("20261012032100", "ig_m913_ekb_contract_errors_v1", "20261012011950", "20261012032100_ig_m913_ekb_contract_errors_v1", "fb80e5a5c69bd5ae"),
    ("20261012040000", "ig_m100_typed_frozen_bundle_contract_v1", "20261012012743", "20261012040000_ig_m100_typed_frozen_bundle_contract_v1", "d9de7324c0650d91"),
    ("20261012040100", "ig_m100_human_approval_semantics_v1", "20261012012746", "20261012040100_ig_m100_human_approval_semantics_v1", "1c5015d2441c6c1b"),
    ("20261012040200", "ig_m100_ekb_contract_findings_v1", "20261012012748", "20261012040200_ig_m100_ekb_contract_findings_v1", "2a0738d85f0de625"),
    ("20261012072000", "lf_gpt_native_in_chat_capture_policy_candidate_v1", "20261012080128", "20261012072000_lf_gpt_native_in_chat_capture_policy_candidate_v1", "98ba73f61e26035d"),
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
        source_sql = {}
        changes = []
        ledger = {}
        for git_version,git_name,ledger_version,ledger_name,hash16 in LOTE3:
            old_name = f"{git_version}_{git_name}.sql"
            new_name = f"{ledger_version}_{ledger_name}.sql"
            old_rel = f"supabase/migrations/{old_name}"
            new_rel = f"supabase/migrations/{new_name}"
            sql = (repo/old_rel).read_text(encoding="utf-8")
            self.assertTrue(direct_source_hash(sql).startswith(hash16), old_rel)
            source_sql[ledger_version] = sql
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
