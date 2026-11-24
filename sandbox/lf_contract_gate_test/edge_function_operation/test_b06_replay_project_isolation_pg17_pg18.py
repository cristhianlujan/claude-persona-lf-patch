#!/usr/bin/env python3
"""B06 G03: isolated PG17.6/18.7 replay and LF/SALY negative proof, Docker-only."""
import sys
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "sandbox/lf_contract_gate_test/edge_function_operation"))
import test_ig_asset_owner_one_name_pg18 as old
Q = old.quote
PARENT = old.PARENT

class B06Lab:
    PG_IMAGE = None
    @classmethod
    def setUpClass(cls):
        image = "postgres:18" if cls.PG_IMAGE == "postgres:18.7" else cls.PG_IMAGE
        cls.lab = type("Local_" + cls.__name__, (old.AssetOwnerPG18,),
                       {"PG_IMAGE":image,"EXPECTED_VERSION":18 if "18" in image else 17})
        cls.lab.setUpClass()
        version = int(cls.lab.run_sql("SHOW server_version_num;"))
        expected = {"postgres:17.6":170006,"postgres:18.7":180007}[cls.PG_IMAGE]
        if version != expected: raise AssertionError("B06_WRONG_EXACT_PG_VERSION " + str(version))
    @classmethod
    def tearDownClass(cls):
        if hasattr(cls,"lab"): cls.lab.tearDownClass()
    def sql(self,q,error=None):
        return self.lab.run_sql(q,error=error)
    def sha(self,code):
        return self.lab.sha(code)
    def approval(self,code,sha=None,archived=False):
        sha = sha or self.sha(code)
        fun = "lf_ig_asset_owner_approve_archived_v3" if archived else "lf_ig_asset_owner_approve_v2"
        dec = ("jsonb_build_object('codigo_activo'," + Q(code) + ",'preimagen_sha256'," + Q(sha) +
               ",'veredicto','APROBAR','decisor','Cristhian Luján','fecha',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD')||'T'||to_char(clock_timestamp() at time zone 'UTC','HH24:MI:SS')||'Z','frase_literal','B06 PG-only decision')")
        return ("SELECT public." + fun + "(" + Q(PARENT) + "," + Q(code) + "," + Q(sha) +
                ",'LF_GOVERNANCE'," + dec + ")::text;")
    def test_duplicate_receipt_active(self):
        code="ACT-0001"; before=self.sha(code); apply=self.approval(code)
        self.sql("BEGIN; SET LOCAL ROLE service_role;" + apply + apply + "COMMIT;",
                 error="lf_ig_asset_owner_receipt_v2_train_execution_id_asset_code_key")
        self.assertEqual(self.sql("SELECT count(*) FROM public.lf_ig_asset_owner_receipt_v2 WHERE asset_code="+Q(code)),"0")
        self.assertEqual(self.sha(code),before)
        print("PASS_B06_ACTIVE_DUPLICATE_RECEIPT_FAIL_CLOSED_ROLLBACK",flush=True)
    def test_duplicate_receipt_archived(self):
        code="PERFIL-SEGURIDAD-GOBERNANZA-LF-20260529"; before=self.sha(code)
        apply=self.approval(code,archived=True)
        self.sql("BEGIN; SET LOCAL ROLE service_role;" + apply + apply + "COMMIT;",
                 error="lf_ig_asset_owner_receipt_v2_train_execution_id_asset_code_key")
        self.assertEqual(self.sql("SELECT count(*) FROM public.lf_ig_asset_owner_receipt_v2 WHERE asset_code="+Q(code)),"0")
        self.assertEqual(self.sha(code),before)
        print("PASS_B06_ARCHIVED_DUPLICATE_RECEIPT_FAIL_CLOSED_ROLLBACK",flush=True)
    def test_saly_owner_must_not_authorize_lf(self):
        code="ACT-0002";before=self.sha(code)
        sql=("BEGIN; UPDATE public.lf_ig_project_owner_v2 SET project_code='SALY' WHERE project_code='LF' AND owner_name='Cristhian Luján';"
             "SET LOCAL ROLE service_role;" + self.approval(code) + "COMMIT;")
        self.sql(sql,error="LF_IG_ASSET_OWNER_DECLARATION_MISSING")
        self.assertEqual(self.sql("SELECT count(*) FROM public.lf_ig_project_owner_v2 WHERE project_code='LF'"),"1")
        self.assertEqual(self.sql("SELECT count(*) FROM public.lf_ig_project_owner_v2 WHERE project_code='SALY'"),"0")
        self.assertEqual(self.sql("SELECT count(*) FROM public.lf_ig_asset_owner_receipt_v2"),"0")
        self.assertEqual(self.sha(code),before)
        print("PASS_B06_SALY_DECLARATION_CANNOT_SIGN_LF",flush=True)
    def test_saly_only_asset_rejected(self):
        code="SALY-ONLY-OWNER-PROBE"
        sql=("BEGIN; CREATE SCHEMA IF NOT EXISTS saly; CREATE TABLE saly.owner_probe (code text PRIMARY KEY, owner text NOT NULL);"
             "INSERT INTO saly.owner_probe VALUES ('SALY-ONLY-OWNER-PROBE','SALY_PROJECT_OWNER');"
             "SET LOCAL ROLE service_role;" + self.approval(code,sha="0"*64) + "COMMIT;")
        self.sql(sql,error="LF_IG_ASSET_SCOPE_INVALID")
        self.assertEqual(self.sql("SELECT to_regclass('saly.owner_probe') IS NULL;"),"t")
        self.assertEqual(self.sql("SELECT count(*) FROM public.lf_ig_asset_owner_receipt_v2"),"0")
        print("PASS_B06_SALY_ONLY_ASSET_OUT_OF_SCOPE",flush=True)
    def test_lf_apply_preserves_saly_shadow_and_rollback(self):
        code="ACT-0003";before=self.sha(code)
        sql=("BEGIN; CREATE SCHEMA IF NOT EXISTS saly; CREATE TABLE saly.owner_probe (code text PRIMARY KEY, owner text NOT NULL);"
             "INSERT INTO saly.owner_probe VALUES ('ACT-0003','SALY_PROJECT_OWNER');"
             "SET LOCAL ROLE service_role;" + self.approval(code) + "RESET ROLE;"
             "DO $b06$ DECLARE rid uuid; v jsonb; BEGIN SELECT receipt_id INTO rid FROM public.lf_ig_asset_owner_receipt_v2 WHERE asset_code='ACT-0003' AND state='APPROVED';"
             "v:=public.lf_ig_asset_owner_apply_v2(rid);"
             "IF v->>'status'<>'APPLIED_VERIFIED' THEN RAISE EXCEPTION 'LF_APPLY_NOT_VERIFIED'; END IF;"
             "IF (SELECT owner FROM saly.owner_probe WHERE code='ACT-0003')<>'SALY_PROJECT_OWNER' THEN RAISE EXCEPTION 'SALY_MUTATED'; END IF;"
             "IF (SELECT owner_name FROM public.lf_activos WHERE codigo_activo='ACT-0003')<>'LF_GOVERNANCE' THEN RAISE EXCEPTION 'LF_NOT_APPLIED'; END IF;"
             "END $b06$; ROLLBACK;")
        self.sql(sql)
        self.assertEqual(self.sha(code),before)
        self.assertEqual(self.sql("SELECT count(*) FROM public.lf_ig_asset_owner_receipt_v2"),"0")
        self.assertEqual(self.sql("SELECT to_regclass('saly.owner_probe') IS NULL;"),"t")
        print("PASS_B06_LF_APPLY_CANNOT_MUTATE_SALY_AND_ROLLBACK",flush=True)

class B06PG176(B06Lab,unittest.TestCase): PG_IMAGE="postgres:17.6"
class B06PG187(B06Lab,unittest.TestCase): PG_IMAGE="postgres:18.7"
