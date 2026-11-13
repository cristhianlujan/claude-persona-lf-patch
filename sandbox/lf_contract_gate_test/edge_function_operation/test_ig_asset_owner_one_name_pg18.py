#!/usr/bin/env python3
"""PostgreSQL 18 and 17.6 real SQL tests on deployed PR3803 documentary ABI.\nNo live Supabase writes, no human identity signature verification.\n"""
import csv
import json
import os
import subprocess
import time
import unittest
import uuid
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "sandbox/lf_contract_gate_test/input_governance_lifecycle/pg18_live_object_slice_baseline.sql"
UPSTREAM = ROOT / "supabase/migrations/20261113030000_lf_ig_rule_lifecycle_writer_v2.sql"
MIGRATION = ROOT / "supabase/migrations/20261113233000_lf_asset_owner_one_name_guard_v1.sql"
PREIMAGE = ROOT / "docs/input-governance/owner-one-name/preimage_238_20261112.csv"
OWNER = "00000000-0000-4000-8000-000000000111"
PARENT = "EXEC-DB-TRAIN-PG18-OWNER-V1"

def quote(value):
    return "NULL" if value is None else "'" + str(value).replace("'", "''") + "'"

def data():
    with PREIMAGE.open(encoding="utf-8", newline="") as f:
        return list(csv.DictReader(line for line in f if not line.startswith("#")))

class AssetOwnerPG18(unittest.TestCase):
    @classmethod
    def run_sql(cls, sql, error=None):
        result = subprocess.run(
            ["docker", "exec", "-i", cls.container, "psql", "-X", "-q", "-A", "-t",
             "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "postgres"],
            input=sql, text=True, capture_output=True, timeout=240
        )
        if error:
            if result.returncode == 0 or error not in result.stderr:
                raise AssertionError("UNEXPECTED_SQL_ACCEPTANCE " + error + "\n" + result.stdout + "\n" + result.stderr[-900:])
            return result.stderr
        if result.returncode:
            raise AssertionError("PG18_SQL_FAILURE " + result.stderr[-2500:] + "\nQUERY=" + sql[:600])
        return result.stdout.strip()

    @classmethod
    def setUpClass(cls):
        cls.assets = data()
        assert len(cls.assets) == 238, "FROZEN_MANIFEST_COUNT"
        assert len([r for r in cls.assets if r["change_required"] == "true"]) == 155
        assert len([r for r in cls.assets if r["cohort"] == "ARCHIVED_SEPARATE"]) == 13
        assert len([r for r in cls.assets if r["cohort"] == "ARCHIVED_SEPARATE" and r["change_required"] == "true"]) == 11
        assert len([r for r in cls.assets if r["cohort"] == "ARCHIVED_SEPARATE" and r["owner_original"] == "GOVERNANZA_LF"]) == 6
        assert all(len(r["preimage_sha256"]) == 64 for r in cls.assets)
        cls.container = "lf-owner-" + uuid.uuid4().hex[:10]
        image = getattr(cls, "PG_IMAGE", "postgres:18")
        expected = getattr(cls, "EXPECTED_VERSION", 18)
        if image not in ("postgres:18", "postgres:17.6"):
            raise AssertionError("PG18_OR_PG17_6_REQUIRED")
        p = subprocess.run(
            ["docker", "run", "-d", "--rm", "--name", cls.container,
             "-e", "POSTGRES_PASSWORD=postgres", "-e", "POSTGRES_DB=postgres", image],
            text=True, capture_output=True, timeout=240
        )
        if p.returncode: raise AssertionError("DOCKER_PG18_UNAVAILABLE " + p.stderr[-900:])
        for _ in range(45):
            v = subprocess.run(["docker", "exec", cls.container, "pg_isready", "-U", "postgres"],
                               capture_output=True, text=True, timeout=10)
            if v.returncode == 0: break
            time.sleep(2)
        else: raise AssertionError("PG18_NOT_READY")
        version = int(cls.run_sql("SHOW server_version_num;"))
        if not (version // 10000 == expected): raise AssertionError("WRONG_POSTGRESQL_VERSION")
        print("OWNER_GUARD_PG_VERSION=" + str(version), flush=True)
        cls.run_sql(BASE.read_text(encoding="utf-8"))
        # Fixture rows are copies of identifiers, original owners and archive
        # indicators ONLY. The frozen real full-row hashes cannot be recomputed
        # from this limited fixture; SQL computes *new fixture* hashes at runtime.
        values = []
        for i, r in enumerate(cls.assets, 1):
            old_owner = None if r["owner_original_null"] == "true" else r["owner_original"]
            archived = r["archived_at"] or None
            values.append("(" + ",".join([
                r["id"], quote(r["codigo_activo"]), quote(r["codigo_activo"]),
                quote(r["tipo_activo"]), "'CANDIDATO'", "'READ_ONLY'",
                quote(old_owner), quote("PG18_ONLY"), quote("PG18_ONLY"),
                quote("OWNER_PREIMAGE"), str(i), quote("00000000-0000-4000-8000-000000000001") + "::uuid",
                quote(archived) + "::timestamptz"
            ]) + ")")
        cls.run_sql(
            "INSERT INTO public.lf_activos(id,codigo_activo,nombre_canonico,tipo_activo,"
            "estado_documental,estado_operativo,owner_name,source_spreadsheet_id,"
            "source_spreadsheet_title,source_sheet_name,source_row_number,"
            "migration_batch_id,archived_at) VALUES\n" + ",\n".join(values) + ";"
        )
        cls.run_sql(UPSTREAM.read_text(encoding="utf-8"))
        cls.run_sql(MIGRATION.read_text(encoding="utf-8"))
        # Upstream PR3803 migration seeds TEMP_DOCUMENTARY_ACTIVE Cristhian.
        # Synthetic only: exact ACT-0001/Train fields required by PR3803 scope.
        # This is not a real Router scope receipt or an authorization to write
        # outside PostgreSQL Docker. Train itself owns these in Supabase.
        train_code = "20261113233000_lf_asset_owner_one_name_guard_v1"
        train_path = "supabase/migrations/" + train_code + ".sql"
        train_manifest = {
            "producer": "lf-migration-merge-train",
            "head_sha": "a"*40,
            "train_run_id": "123456789",
            "pr": "3804",
            "proposer_actor": "LF_GOVERNANCE",
            "router_authority_receipt": {
                "schema_version": "LF_ROUTER_DOWNSTREAM_AUTHORITY_RECEIPT_V1",
                "router": "ACT-0001",
                "operation_code": "ACTUALIZACION_DB_LF",
                "action_code": "UPDATE",
                "target_repo": "cristhianlujan/claude-persona-lf-patch",
                "target_path": train_path,
                "target_code": train_code,
                "scope_attested": False,
                "route_eligibility_only": True
            }
        }
        cls.run_sql(
            "INSERT INTO public.lf_operation_execution "
            "(execution_id,operation_code,target_type,target_code,target_repo,target_path,"
            "idempotency_key,created_by_execution_id,request_sha256,manifest) VALUES("
            + quote(PARENT) + ",'ACTUALIZACION_DB_LF','MIGRATION',"
            + quote(train_code) + ",'cristhianlujan/claude-persona-lf-patch',"
            + quote(train_path) + ",'pg-fixture-owner-guard',"
            "'PG_FIXTURE_ONLY'," + quote("a"*64) + ","
            + quote(json.dumps(train_manifest, ensure_ascii=False)) + "::jsonb);"
            + "INSERT INTO public.lf_operation_execution_steps "
              "(execution_id,step_order,step_id,status,created_by_execution_id) "
              "VALUES(" + quote(PARENT) + ",10,'preflight','PASS_CLEAN','PG_FIXTURE_ONLY');"
        )
        assert cls.run_sql("SELECT count(*) FROM public.lf_activos;") == "238"
        print("PASS_PG18_OWNER_238_SOURCE_ROWS", flush=True)

    @classmethod
    def tearDownClass(cls):
        if getattr(cls,"container",None):
            subprocess.run(["docker","rm","-f",cls.container],capture_output=True,text=True,timeout=35)

    @classmethod
    def sha(cls, code):
        return cls.run_sql("SELECT encode(extensions.digest(convert_to("
                   "(to_jsonb(a)-'updated_at')::text,'UTF8'),'sha256'),'hex') "
                   "FROM public.lf_activos a WHERE codigo_activo=" + quote(code) + ";")

    @classmethod
    def documentary_approve(cls, function, code, sha, new_owner="LF_GOVERNANCE",
                            error=None, decisor="Cristhian Luján"):
        decision = {
            "codigo_activo": code, "preimagen_sha256": sha,
            "veredicto": "APROBAR", "decisor": decisor,
            "fecha": datetime.now(timezone.utc).isoformat(),
            "frase_literal": "Apruebo el owner LF_GOVERNANCE para todos los activos"
        }
        query = ("BEGIN; SET LOCAL ROLE service_role;"
                 " SELECT public."+function+"("+quote(PARENT)+","+quote(code)+","
                 +quote(sha)+","+quote(new_owner)+","
                 +quote(json.dumps(decision,ensure_ascii=False))+"::jsonb)::text; COMMIT;")
        result=cls.run_sql(query,error)
        if error: return result
        for line in result.splitlines():
            if line.startswith("{"): return json.loads(line)
        raise AssertionError("DOCUMENTARY_RECEIPT_NOT_RETURNED " + result)

    def test_00_full_155_atomic_rollback(self):
        """Run all 155 documentary approvals with no JWT, then 155 writer
        calls in one database transaction; verify 238/238 and ROLLBACK.
        NOT a real signed identity or production authority."""
        # Source reads happen only as PG18 postgres fixture, not as authenticated
        # role (which correctly has zero SELECT on public.lf_activos).
        source = self.run_sql(
            "SELECT json_agg(json_build_object("
            "'code',a.codigo_activo,'archive',a.archived_at IS NOT NULL,"
            "'sha',encode(extensions.digest(convert_to("
            "(to_jsonb(a)-'updated_at')::text,'UTF8'),'sha256'),'hex')) "
            "ORDER BY a.id)::text FROM public.lf_activos a "
            "WHERE a.owner_name IS DISTINCT FROM 'LF_GOVERNANCE';"
        )
        rows = json.loads(source)
        self.assertEqual(len(rows), 155)
        self.assertEqual(sum(1 for x in rows if x["archive"]), 11)
        approvals = "\n".join(
            "SELECT public." +
            ("lf_ig_asset_owner_approve_archived_v3" if item["archive"]
             else "lf_ig_asset_owner_approve_v2") +
            "(" + quote(PARENT) + "," + quote(item["code"]) + "," +
            quote(item["sha"]) + ",'LF_GOVERNANCE'," +
            "jsonb_build_object('codigo_activo'," + quote(item["code"]) +
            ",'preimagen_sha256'," + quote(item["sha"]) +
            ",'veredicto','APROBAR','decisor','Cristhian Luján'," +
            "'fecha',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD') || 'T' || " +
            "to_char(clock_timestamp() at time zone 'UTC','HH24:MI:SS') || 'Z'," +
            "'frase_literal','Apruebo el owner LF_GOVERNANCE para todos los activos'));"
            for item in rows
        )
        sql = ("BEGIN; SET LOCAL ROLE service_role;" +
               approvals + " RESET ROLE;" + """
        DO $apply_batch$
        DECLARE rec record; n int:=0;
        BEGIN
          FOR rec IN SELECT receipt_id FROM public.lf_ig_asset_owner_receipt_v2
            WHERE train_execution_id='""" + PARENT + """' AND state='APPROVED'
            ORDER BY asset_code
          LOOP
            PERFORM public.lf_ig_asset_owner_apply_v2(rec.receipt_id);
            n:=n+1;
          END LOOP;
          IF n<>155 THEN RAISE EXCEPTION 'FULL_APPLY_COUNT_BAD %',n; END IF;
          IF (SELECT count(*) FROM public.lf_activos)<>238
             OR (SELECT count(*) FROM public.lf_activos WHERE owner_name='LF_GOVERNANCE')<>238
             OR (SELECT count(*) FROM public.lf_activos WHERE archived_at IS NOT NULL)<>13
             OR (SELECT count(*) FROM public.lf_ig_asset_owner_receipt_v2
                  WHERE state='APPLIED' AND after_sha256 IS NOT NULL
                    AND before_row->>'owner_name' IS DISTINCT FROM 'LF_GOVERNANCE'
                    AND decisor='Cristhian Luján')<>155
          THEN RAISE EXCEPTION 'FULL_BATCH_READBACK_INVALID'; END IF;
        END
        $apply_batch$;
        ROLLBACK;""")
        self.run_sql(sql)
        self.assertEqual(self.run_sql(
            "SELECT count(*) FROM public.lf_activos WHERE owner_name IS DISTINCT FROM 'LF_GOVERNANCE';"),
            "155", "ROLLBACK_DID_NOT_RESTORE_ALL_155")
        self.assertEqual(self.run_sql("SELECT count(*) FROM public.lf_ig_asset_owner_receipt_v2;"),
                         "0", "ROLLBACK_LEFT_RECEIPTS")
        self.assertEqual(self.run_sql(
            "SELECT count(*) FROM public.lf_activos WHERE archived_at IS NOT NULL;"),
            "13", "ARCHIVE_COHORT_CHANGED")
        print("PASS_PG18_FULL_155_ATOMIC_APPLY_AND_ROLLBACK", flush=True)

    def test_04_scope_policy_rebound_and_router_receipt(self):
        policy = json.loads(self.run_sql(
            "SELECT json_build_object('pinned',p.writer_source_md5,"
            "'live',md5(pg_get_functiondef("
            "'public.lf_ig_asset_owner_apply_v2(uuid)'::regprocedure)),"
            "'scope',p.scope_code)::text FROM public.lf_router_scope_policy_v1 p "
            "WHERE p.scope_code='LF_ACTIVOS_OWNER_NAME_WRITE_V1';"
        ))
        self.assertEqual(policy["pinned"],policy["live"])
        self.assertNotEqual(policy["pinned"],"cc5c36bf2ae0686bd46192b97956cbb2")
        receipt=json.loads(self.run_sql(
            "SELECT public.lf_router_scope_bind_v1(" + quote(PARENT) + ")::text;"
        ))
        self.assertEqual(receipt["status"],"SCOPE_ATTESTED_ROUTE_ONLY")
        self.assertEqual(receipt["scope_code"],"LF_ACTIVOS_OWNER_NAME_WRITE_V1")
        self.assertFalse(receipt["effect_authority"])
        self.assertFalse(receipt["downstream_execution_allowed"])
        self.assertEqual(receipt["positive_scope"][0]["table"],"public.lf_activos")
        self.assertEqual(self.run_sql(
            "SELECT count(*) FROM public.lf_router_scope_receipt_v1 "
            "WHERE execution_id="+quote(PARENT)+";"),"1")
        print("PASS_POSTGRES_ROUTER_SCOPE_POLICY_WRITER_REPIN",flush=True)

    def test_01_guard_and_counts(self):
        self.assertEqual(self.run_sql("SELECT count(*) FROM public.lf_activos WHERE owner_name IS DISTINCT FROM 'LF_GOVERNANCE';"), "155")
        self.assertEqual(self.run_sql("SELECT count(*) FROM public.lf_activos WHERE archived_at IS NOT NULL AND owner_name IS DISTINCT FROM 'LF_GOVERNANCE';"), "11")
        self.run_sql("BEGIN; INSERT INTO public.lf_activos(id,codigo_activo,nombre_canonico,tipo_activo,estado_documental,estado_operativo,owner_name,source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,migration_batch_id) VALUES (888888,'PG18-GUARD-NONCANONICAL','PG18','DOC','CANDIDATO','READ_ONLY','SUPER_ADMIN','PG18','PG18','PG18',888888,'00000000-0000-4000-8000-000000000001'); DO $$BEGIN IF (SELECT owner_name FROM public.lf_activos WHERE id=888888)<>'LF_GOVERNANCE' THEN RAISE EXCEPTION 'INSERT_NOT_NORMALIZED'; END IF; END$$; ROLLBACK;")
        self.run_sql("BEGIN; INSERT INTO public.lf_activos(id,codigo_activo,nombre_canonico,tipo_activo,estado_documental,estado_operativo,source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,migration_batch_id) VALUES (888889,'PG18-GUARD-DEFAULT','PG18','DOC','CANDIDATO','READ_ONLY','PG18','PG18','PG18',888889,'00000000-0000-4000-8000-000000000001'); DO $$BEGIN IF (SELECT owner_name FROM public.lf_activos WHERE id=888889)<>'LF_GOVERNANCE' THEN RAISE EXCEPTION 'DEFAULT_NOT_NORMALIZED'; END IF; END$$; ROLLBACK;")
        self.run_sql("UPDATE public.lf_activos SET owner_name='SUPER_ADMIN' WHERE codigo_activo='ACT-0001';", "LF_OWNER_ONLY_LF_GOVERNANCE_ALLOWED")
        print("PASS_PG18_INSERT_NORMALIZES_NULL_VARIANTS",flush=True)

    def test_02_authorization_active_and_archived(self):
        active="ACT-0001"
        archive="PERFIL-SEGURIDAD-GOBERNANZA-LF-20260529"
        self.documentary_approve("lf_ig_asset_owner_approve_archived_v3",active,self.sha(active),
                            error="LF_IG_ARCHIVED_SCOPE_INVALID")
        self.documentary_approve("lf_ig_asset_owner_approve_v2",archive,self.sha(archive),
                            error="LF_IG_ASSET_SCOPE_INVALID")
        self.documentary_approve("lf_ig_asset_owner_approve_v2",active,"0"*64,
                            error="LF_IG_ASSET_PREIMAGE_STALE")
        self.documentary_approve("lf_ig_asset_owner_approve_v2",active,self.sha(active),
                            new_owner="LF_SUPER_ADMIN",error="LF_IG_ASSET_SCOPE_INVALID")
        old_a=self.sha(active);old_b=self.sha(archive)
        a=self.documentary_approve("lf_ig_asset_owner_approve_v2",active,old_a)
        b=self.documentary_approve("lf_ig_asset_owner_approve_archived_v3",archive,old_b)
        self.assertEqual(a["status"],"APPROVED")
        self.assertEqual(b["status"],"APPROVED")
        for item in (a,b):
            v=json.loads(self.run_sql("SELECT public.lf_ig_asset_owner_apply_v2("+quote(item["receipt_id"])+"::uuid)::text;"))
            self.assertEqual(v["status"],"APPLIED_VERIFIED")
        self.assertEqual(self.run_sql("SELECT count(*) FROM public.lf_activos WHERE owner_name IS DISTINCT FROM 'LF_GOVERNANCE';"),"153")
        self.assertEqual(self.run_sql("SELECT count(*) FROM public.lf_activos WHERE archived_at IS NOT NULL AND owner_name IS DISTINCT FROM 'LF_GOVERNANCE';"),"10")
        self.assertEqual(self.run_sql("SELECT count(*) FROM public.lf_activos WHERE codigo_activo="+quote(archive)+" AND archived_at IS NOT NULL AND owner_name='LF_GOVERNANCE';"),"1")
        self.assertEqual(self.run_sql("SELECT count(*) FROM public.lf_ig_asset_owner_receipt_v2 WHERE state='APPLIED' AND before_row->>'owner_name' IS DISTINCT FROM 'LF_GOVERNANCE' AND after_sha256 IS NOT NULL;"),"2")
        self.run_sql("SELECT public.lf_ig_asset_owner_apply_v2("+quote(a["receipt_id"])+"::uuid);","LF_IG_ASSET_OWNER_RECEIPT_NOT_APPROVED")
        print("PASS_PG18_ACTIVE_AND_ARCHIVED_OFFICIAL_WRITER_READBACK",flush=True)

    def test_03_never_approve_as_super_admin(self):
        self.documentary_approve("lf_ig_asset_owner_approve_v2","ACT-0002",
                                 self.sha("ACT-0002"),decisor="SUPER_ADMIN",
                                 error="LF_IG_ASSET_DECISION_INPUT_INVALID")
        # Document decisions never claim human authentication.
        receipt=self.documentary_approve("lf_ig_asset_owner_approve_v2","ACT-0003",
                                         self.sha("ACT-0003"))
        self.assertFalse(receipt["identity_verified"])
        self.assertEqual(receipt["decisor"],"Cristhian Luján")
        self.assertEqual(self.run_sql(
          "SELECT count(*) FROM public.lf_ig_asset_owner_receipt_v2 "
          "WHERE asset_code='ACT-0003' AND decisor='Cristhian Luján';"),"1")
        print("PASS_PG18_DOCUMENTARY_CRISTHIAN_NO_AUTH_SIGNATURE",flush=True)

class AssetOwnerPG176(AssetOwnerPG18):
    """Run the exact guard/documentary writer tests on PostgreSQL 17.6."""
    PG_IMAGE = "postgres:17.6"
    EXPECTED_VERSION = 17

if __name__ == "__main__":
    unittest.main()
