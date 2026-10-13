from __future__ import annotations
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
import json, subprocess, sys, tempfile, unittest
from unittest.mock import patch
import lf_migration_reconcile_git as m

OLD="supabase/migrations/20261012040000_ig_example_v1.sql"
NEW="supabase/migrations/20261012012743_ig_example_v1.sql"

def git(root,*args):
    p=subprocess.run(["git",*args],cwd=root,capture_output=True,text=True)
    if p.returncode: raise RuntimeError(p.stderr)
    return p.stdout.strip()

class ReconcileGitOnlyTest(unittest.TestCase):
    def prepare(self, status="renamed", mutate=False, extra=False):
        tmp=tempfile.TemporaryDirectory()
        root=Path(tmp.name)
        git(root,"init","-q");git(root,"config","user.email","tests@example.test");git(root,"config","user.name","Tests")
        p=root/OLD;p.parent.mkdir(parents=True,exist_ok=True);p.write_text("select 1;\n")
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

    def run_case(self,*,status="renamed",mutate=False,extra=False):
        tmp,root,changes,base,head=self.prepare(status=status,mutate=mutate,extra=extra)
        try:
            args=["test","--repo-root",str(root),"--pr-files",str(changes),"--base-sha",base,"--head-sha",head,
                  "--router-execution-id","EXEC-RECONCILE-1","--repository","o/r","--db-url","test-db"]
            with patch.object(sys,"argv",args),patch.object(m,"validate_router") as auth,patch.object(m,"ledger_row",return_value=("ig_example_v1","select 1;\n",1)):
                with redirect_stdout(StringIO()) as out:
                    m.main()
                return json.loads(out.getvalue()),auth.call_count
        finally:
            tmp.cleanup()

    def test_train_routes_reconcile_without_db_apply(self):
        wf=(Path(__file__).resolve().parents[3]/".github/workflows/lf-migration-merge-train.yml").read_text()
        self.assertLess(wf.index("- name: Resolve RECONCILE governed mode"),
                        wf.index("- name: Sync PR branch with current main in REAL mode"))
        self.assertIn("RECONCILE_GIT_ONLY_PASS",wf)
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
                with self.assertRaisesRegex(RuntimeError,"RECONCILE_LEDGER_CARDINALITY_INVALID"):
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
