#!/usr/bin/env python3
"""LF B07 scoped preflight: real Postgres 17.6/18 + V2 migration on disposable copies.

Important: NOT a B07 completion. L28 document 12 does not specify the
four LF or five SALY field names and their UP/DOWN scripts. This suite
replays existing V2 on a live-object schema SLICE (not a full live dump),
adds SALY shape from read-only information_schema, proves a reversible
known-column rehearsal and blocks a fabricated B07 pass.

Never connect to Supabase; never mutate existing RUNs.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[3]
FIXTURE = ROOT / "sandbox/lf_contract_gate_test/input_governance_lifecycle/pg18_live_object_slice_baseline.sql"
V2 = ROOT / "supabase/migrations/20261113030000_lf_ig_rule_lifecycle_writer_v2.sql"

# Structurally copied from live saly.reglas SELECT information_schema,
# 2026-11-13; intentionally uses a synthetic row (no customer data).
SALY_COPY_SQL = """
CREATE SCHEMA IF NOT EXISTS saly;
CREATE TABLE saly.reglas(
 id bigint NOT NULL PRIMARY KEY,
 codigo text NOT NULL UNIQUE,
 categoria text NOT NULL,
 titulo text NOT NULL,
 regla text NOT NULL,
 razon text,
 alcance text NOT NULL DEFAULT 'PRODUCTO',
 producto_codigo text,
 valor_config jsonb NOT NULL DEFAULT '{}'::jsonb,
 parametrizable boolean NOT NULL DEFAULT true,
 es_transversal boolean NOT NULL DEFAULT false,
 estado text NOT NULL DEFAULT 'BORRADOR',
 vigente boolean NOT NULL DEFAULT true,
 decision_id bigint,
 fuente text,
 metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE saly.reglas ENABLE ROW LEVEL SECURITY;
INSERT INTO saly.reglas(id,codigo,categoria,titulo,regla,estado)
 VALUES (10001,'SALY-B07-CI-ONLY','TEST','Copia aislada','No publicar','VALIDADO');
"""

def q(value):
    return "'" + str(value).replace("'", "''") + "'"

def j(value):
    return q(json.dumps(value, ensure_ascii=False, separators=(",", ":"))) + "::jsonb"

SNAPSHOT_SQL = """
SELECT encode(extensions.digest(convert_to(jsonb_build_object(
  'schema',(SELECT coalesce(jsonb_agg(
    jsonb_build_array(n.nspname,c.relname,a.attnum,a.attname,
      format_type(a.atttypid,a.atttypmod),a.attnotnull,
      pg_get_expr(d.adbin,d.adrelid))
    ORDER BY n.nspname,c.relname,a.attnum),'[]'::jsonb)
    FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid
    JOIN pg_namespace n ON n.oid=c.relnamespace
    LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
    WHERE (n.nspname,c.relname) IN (('lf_ops','reglas'),('saly','reglas'))
      AND a.attnum>0 AND NOT a.attisdropped),
  'lf_data',(SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.id),'[]'::jsonb)
             FROM lf_ops.reglas r),
  'saly_data',(SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.id),'[]'::jsonb)
               FROM saly.reglas r),
  'rls',(SELECT coalesce(jsonb_agg(
        jsonb_build_array(n.nspname,c.relname,c.relrowsecurity)
        ORDER BY n.nspname,c.relname),'[]'::jsonb)
        FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE (n.nspname,c.relname) IN (('lf_ops','reglas'),('saly','reglas')))
)::text,'UTF8'),'sha256'),'hex');
"""

class B07LiveSliceRehearsal(unittest.TestCase):
    def run_pg(self, image, prefix):
        self.assertIsNotNone(shutil.which("docker"), "NOT_TESTED_DOCKER_UNAVAILABLE")
        self.assertTrue(FIXTURE.is_file() and V2.is_file(), "NOT_TESTED_SOURCE_MISSING")
        name = "lf-b07-schema-" + uuid.uuid4().hex[:12]
        r = subprocess.run(["docker", "run", "--rm", "-d", "--name", name,
            "-e", "POSTGRES_PASSWORD=postgres", "-e", "POSTGRES_DB=postgres", image],
            capture_output=True, text=True, timeout=240)
        self.assertEqual(r.returncode, 0, "DOCKER_FAILED:" + r.stderr[-3000:])
        try:
            def sql(command, timeout=450):
                p = subprocess.run(["docker", "exec", "-i", name, "psql",
                    "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1",
                    "-U", "postgres", "-d", "postgres"],
                    input=command, capture_output=True, text=True, timeout=timeout)
                self.assertEqual(p.returncode, 0,
                                 "SQL_FAILURE:" + p.stderr[-3500:] + "\n" + command[:700])
                return p.stdout.strip()

            for _ in range(60):
                ready = subprocess.run(["docker","exec",name,"pg_isready",
                    "-U","postgres","-d","postgres"],capture_output=True,text=True)
                if ready.returncode == 0:
                    break
                time.sleep(1)
            else:
                self.fail("POSTGRES_NOT_READY")
            version = sql("SHOW server_version_num;").splitlines()[-1]
            self.assertTrue(version.startswith(prefix), f"WRONG_PG_VERSION:{version}")
            if image == "postgres:17.6":
                self.assertEqual(version, "170006", "REQUIRES_EXACT_PG_17_6")

            sql(FIXTURE.read_text(encoding="utf-8"))
            manifest = {
                "producer":"lf-migration-merge-train", "pr":3803,
                "train_run_id":"43379990001", "head_sha":"e"*40,
                "router_authority_receipt": {
                    "schema_version":"LF_ROUTER_DOWNSTREAM_AUTHORITY_RECEIPT_V1",
                    "operation_code":"ACTUALIZACION_DB_LF",
                    "target_repo":"cristhianlujan/claude-persona-lf-patch",
                    "target_code":"20261113030000_lf_ig_rule_lifecycle_writer_v2",
                    "target_path":"supabase/migrations/20261113030000_lf_ig_rule_lifecycle_writer_v2.sql",
                    "route_eligibility_only":True,"scope_attested":False}}
            train_id="EXEC-DB-TRAIN-PR3803-20261113030000-R43379990001"
            train_code="20261113030000_lf_ig_rule_lifecycle_writer_v2"
            sql(f"""INSERT INTO public.lf_operation_execution(
                execution_id,operation_code,target_type,target_code,target_repo,
                target_path,status,request_sha256,manifest,idempotency_key,
                created_by_execution_id)
              VALUES({q(train_id)},'ACTUALIZACION_DB_LF','MIGRATION',
                {q(train_code)},'cristhianlujan/claude-persona-lf-patch',
                {q('supabase/migrations/'+train_code+'.sql')},'IN_PROGRESS',
                {q('f'*64)},{j(manifest)},
                {q('train:20261113030000:'+'e'*40)},
                'LF-MIGRATION-TRAIN-RUN-43379990001');""")

            # This is the exact forward V2 blob checked out at CI HEAD.
            sql(V2.read_text(encoding="utf-8"))
            self.assertEqual(sql("SELECT to_regprocedure('public.lf_ig_rule_finalize_v2(text)') IS NOT NULL;"), "t")
            self.assertEqual(sql("SELECT to_regprocedure('public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)') IS NOT NULL;"), "t")
            sql(SALY_COPY_SQL)
            before = sql(SNAPSHOT_SQL)
            self.assertEqual(len(before), 64)
            self.assertEqual(sql("SELECT estado FROM saly.reglas WHERE id=10001;"), "VALIDADO")
            # The B07 exact approved LF4/SALY5 DDL is absent from L28 doc12.
            # We must fail-closed rather than invent nine production columns.
            live_shape = sql("""SELECT
                (SELECT count(*) FROM pg_attribute a
                 WHERE a.attrelid='saly.reglas'::regclass
                   AND a.attname='lifecycle_state' AND NOT a.attisdropped);""")
            self.assertEqual(live_shape, "0", "UNEXPECTED_LIFECYCLE_STATE_PRESENT")

            # Isolated rehearsal of ONE KNOWN field only; NOT LF4/SALY5.
            # Reversible after a synthetic data update; VALIDADO remains intact.
            rehearsal = sql("""BEGIN;
                ALTER TABLE saly.reglas ADD COLUMN lifecycle_state text;
                UPDATE saly.reglas SET lifecycle_state='CI_ONLY_NOT_CANONICAL' WHERE id=10001;
                SELECT estado||'|'||lifecycle_state FROM saly.reglas WHERE id=10001;
                ROLLBACK;""")
            self.assertIn("VALIDADO|CI_ONLY_NOT_CANONICAL", rehearsal)
            after = sql(SNAPSHOT_SQL)
            self.assertEqual(before, after, "POST_DATA_ROLLBACK_SCHEMA_OR_ROWS_CHANGED")
            self.assertEqual(sql("SELECT estado FROM saly.reglas WHERE id=10001;"), "VALIDADO")
            self.assertEqual(sql("SELECT count(*) FROM pg_attribute WHERE attrelid='saly.reglas'::regclass AND attname='lifecycle_state' AND NOT attisdropped;"), "0")
            self.assertEqual(sql("SELECT to_regprocedure('public.lf_ig_rule_finalize_v2(text)') IS NOT NULL;"), "t")

            print("PASS_B07_PARTIAL_SCHEMA_PREIMAGE_SHA256_" + image.replace(":","_") +
                  " pg_version=" + version + " sha256=" + before, flush=True)
            print("PASS_B07_PARTIAL_SALY_KNOWN_FIELD_POST_DATA_ROLLBACK_" +
                  image.replace(":","_"), flush=True)
            print("B07_NO_GO_MISSING_APPROVED_LF4_SALY5_UP_DOWN_AND_FULL_CONSUMER_PROOF",flush=True)
            print("COPY_SCOPE=LIVE_OBJECT_SLICE_PLUS_RECONSTRUCTED_SALY_SCHEMA_SYNTHETIC_DATA",flush=True)
        finally:
            subprocess.run(["docker","rm","-f",name],
                           capture_output=True,text=True,timeout=90)

    def test_pg17_6(self):
        self.run_pg("postgres:17.6", "170006")

    def test_pg18(self):
        self.run_pg("postgres:18", "18")

if __name__ == "__main__":
    unittest.main()

