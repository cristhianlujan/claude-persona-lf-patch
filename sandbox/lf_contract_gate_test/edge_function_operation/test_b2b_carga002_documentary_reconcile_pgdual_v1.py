"""PG17/PG18 transactional regression for the bounded B2B documentary patch.

The seeded Train rows are isolated TEST FIXTURES. They never authorize a live
write and these tests do not claim file-processing or financial-behavior QA.
"""
import json
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FIXTURE = Path(__file__).with_name("fixtures") / "b2b_carga002_documentary_reconcile_v1.json"
MIGRATION_NAME = "lf_b2b_carga002_documentary_reconcile_v1"

def q(value):
    return "'" + value.replace("'", "''") + "'"

def psql(name, sql, success=True):
    proc = subprocess.run(
        ["docker", "exec", "-i", name, "psql", "-X", "-A", "-t",
         "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1"],
        input=sql, capture_output=True, text=True, timeout=60,
    )
    if success and proc.returncode:
        raise AssertionError(proc.stderr[-5000:])
    if not success and not proc.returncode:
        raise AssertionError("NEGATIVE_PROBE_UNEXPECTEDLY_SUCCEEDED")
    return proc.stdout.strip(), proc.stderr

def seed(data):
    sql = """
CREATE SCHEMA lf_ops;
CREATE SCHEMA extensions;
CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
CREATE TABLE lf_ops.reglas (
 id integer PRIMARY KEY, codigo text UNIQUE, categoria text, titulo text,
 descripcion text, razon text, valor_config jsonb, es_transversal boolean,
 estado text, origen text, created_at timestamptz, updated_at timestamptz,
 pendiente_decision boolean, pendiente_detalle text, created_by text
);
CREATE TABLE lf_ops.reglas_pantallas (
 id integer PRIMARY KEY, regla_id integer, pantalla_id integer, nota text,
 created_at timestamptz
);
CREATE TABLE public.lf_operation_execution (
 execution_id text PRIMARY KEY, operation_code text, target_type text,
 target_code text, target_path text, target_repo text, status text, manifest jsonb
);
CREATE TABLE public.lf_operation_execution_steps (
 execution_id text, step_id text, status text, evidence_payload jsonb
);
"""
    for row in data["source_rules"]:
        sql += "INSERT INTO lf_ops.reglas SELECT * FROM jsonb_populate_record(NULL::lf_ops.reglas," + q(json.dumps(row,ensure_ascii=False)) + "::jsonb);\n"
    other = dict(data["source_rules"][0])
    other.update(id=99999, codigo="TEST-UNRELATED-RULE")
    sql += "INSERT INTO lf_ops.reglas SELECT * FROM jsonb_populate_record(NULL::lf_ops.reglas," + q(json.dumps(other,ensure_ascii=False)) + "::jsonb);\n"
    sql += "INSERT INTO lf_ops.reglas_pantallas SELECT * FROM jsonb_populate_record(NULL::lf_ops.reglas_pantallas," + q(json.dumps(data["source_relation"],ensure_ascii=False)) + "::jsonb);\n"
    target = "20261116012000_" + MIGRATION_NAME
    path = "supabase/migrations/" + target + ".sql"
    manifest = {
        "producer":"lf-migration-merge-train",
        "router_authority_receipt":{
            "schema_version":"LF_ROUTER_DOWNSTREAM_AUTHORITY_RECEIPT_V1",
            "operation_code":"ACTUALIZACION_DB_LF","target_code":target
        }
    }
    evidence = {
        "producer":"lf-migration-merge-train",
        "exact_target":{"target_path":path},
        "trust_validation":{"valid":True}
    }
    sql += "INSERT INTO public.lf_operation_execution VALUES ('TEST-TRAIN','ACTUALIZACION_DB_LF','MIGRATION'," + q(target) + "," + q(path) + ",'cristhianlujan/claude-persona-lf-patch','IN_PROGRESS'," + q(json.dumps(manifest)) + "::jsonb);"
    sql += "INSERT INTO public.lf_operation_execution_steps VALUES ('TEST-TRAIN','preflight','PASS_CLEAN'," + q(json.dumps(evidence)) + "::jsonb);"
    return sql

SNAPSHOT = """SELECT jsonb_build_object(
 'rules',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.reglas r),
 'links',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.reglas_pantallas r)
)::text;"""

class DocumentaryReconciliationPGDual(unittest.TestCase):
    def test_atomic_exact_patch_and_negative_guards(self):
        self.assertTrue(shutil.which("docker"), "DOCKER_REQUIRED")
        candidates=list((ROOT/"supabase/migrations").glob("*_"+MIGRATION_NAME+".sql"))
        self.assertEqual(len(candidates),1,"EXACT_MIGRATION_NAME_REQUIRED")
        sql=candidates[0].read_text(encoding="utf-8")
        data=json.loads(FIXTURE.read_text(encoding="utf-8"))
        for version in ("17.6","18.7"):
            with self.subTest(postgres=version):
                name="lf-b2b-doc-"+uuid.uuid4().hex[:10]
                proc=subprocess.run(
                    ["docker","run","-d","--rm","--name",name,
                     "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+version],
                    capture_output=True,text=True,timeout=180)
                self.assertEqual(proc.returncode,0,proc.stderr[-1000:])
                try:
                    ready=False
                    for _ in range(100):
                        probe=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],capture_output=True,timeout=10)
                        logs=subprocess.run(["docker","logs",name],capture_output=True,text=True,timeout=10)
                        if probe.returncode==0 and "PostgreSQL init process complete; ready for start up." in logs.stdout+logs.stderr:
                            ready=True;break
                        time.sleep(0.4)
                    self.assertTrue(ready,"POSTGRES_NOT_READY")
                    psql(name,seed(data))
                    original=psql(name,SNAPSHOT)[0]
                    hashes=psql(name,"SELECT id,encode(extensions.digest(convert_to(to_jsonb(r)::text,'UTF8'),'sha256'),'hex') FROM lf_ops.reglas r WHERE id<>99999 ORDER BY id;")[0]
                    expected="\n".join(str(r["id"])+"|"+r["before_sha256"] for r in data["patch"]["rules"])
                    self.assertEqual(hashes,expected,"CANONICAL_FIXTURE_PREIMAGE_MISMATCH")
                    # Actual SQL runs twice in one transaction; exact replay is a no-op.
                    check = """DO $check$ DECLARE p jsonb; r lf_ops.reglas%ROWTYPE; BEGIN
 FOR p IN SELECT value FROM jsonb_array_elements(""" + q(json.dumps(data["patch"]["rules"],ensure_ascii=False)) + """::jsonb) LOOP
  SELECT * INTO STRICT r FROM lf_ops.reglas WHERE id=(p->>'id')::int;
  IF r.estado IS DISTINCT FROM p->>'state'
   OR r.descripcion IS DISTINCT FROM p->>'after_description'
   OR r.pendiente_detalle IS DISTINCT FROM p->>'after_pending'
   OR encode(extensions.digest(convert_to((to_jsonb(r)-'descripcion'-'pendiente_detalle'-'updated_at')::text,'UTF8'),'sha256'),'hex')
      IS DISTINCT FROM p->>'protected_sha256'
  THEN RAISE EXCEPTION 'POSITIVE_READBACK_FAILED'; END IF;
 END LOOP;
END $check$;"""
                    positive="BEGIN;"+sql+check+"""
CREATE TEMP TABLE replay_before AS SELECT to_jsonb(r) AS row FROM lf_ops.reglas r;
"""+sql+"""
DO $replay$ BEGIN
 IF EXISTS ((SELECT row FROM replay_before EXCEPT SELECT to_jsonb(r) FROM lf_ops.reglas r)
 UNION ALL (SELECT to_jsonb(r) FROM lf_ops.reglas r EXCEPT SELECT row FROM replay_before))
 THEN RAISE EXCEPTION 'REPLAY_WROTE_AGAIN'; END IF;
END $replay$;
ROLLBACK;"""
                    psql(name,positive)
                    self.assertEqual(psql(name,SNAPSHOT)[0],original,"EXPLICIT_ROLLBACK_LOST_BASELINE")
                    probes=[
                        ("missing_authority","DELETE FROM public.lf_operation_execution_steps;","TRAIN_AUTHORITY_NOT_BOUND"),
                        ("wrong_train_target","UPDATE public.lf_operation_execution SET target_repo='unrelated/repo';","TRAIN_AUTHORITY_NOT_BOUND"),
                        ("source_text_drift","UPDATE lf_ops.reglas SET descripcion='concurrent text' WHERE id=617;","PREIMAGE_DRIFT"),
                        ("source_state_drift","UPDATE lf_ops.reglas SET estado='VIGENTE' WHERE id=620;","IDENTITY_OR_STATE_DRIFT"),
                        ("protected_config_drift","UPDATE lf_ops.reglas SET valor_config=valor_config||'{\"forged\":true}'::jsonb WHERE id=620;","PROTECTED_SOURCE_DRIFT"),
                        ("missing_rule","DELETE FROM lf_ops.reglas WHERE id=620;","IDENTITY_OR_STATE_DRIFT"),
                        ("link_conflict","UPDATE lf_ops.reglas_pantallas SET nota='concurrent note';","RELATION_PREIMAGE_DRIFT"),
                        ("link_wrong_identity","UPDATE lf_ops.reglas_pantallas SET pantalla_id=51;","RELATION_IDENTITY_DRIFT"),
                        ("late_partial_failure","CREATE FUNCTION public.test_late_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'TEST_LATE_FAILURE'; END $$; CREATE TRIGGER test_late_failure BEFORE UPDATE ON lf_ops.reglas_pantallas FOR EACH ROW EXECUTE FUNCTION public.test_late_failure();","TEST_LATE_FAILURE"),
                    ]
                    for label,mutation,error in probes:
                        with self.subTest(postgres=version,negative=label):
                            _,stderr=psql(name,"BEGIN;"+mutation+sql,False)
                            self.assertIn(error,stderr)
                            self.assertEqual(psql(name,SNAPSHOT)[0],original,"FAILED_DO_LEFT_PARTIAL_EFFECTS")
                    # Unrelated source row must not be touched by the successful path.
                    untouched=psql(name,"BEGIN;"+sql+"SELECT count(*) FROM lf_ops.reglas WHERE codigo='TEST-UNRELATED-RULE' AND id=99999;ROLLBACK;")[0]
                    self.assertIn("\n1\n", "\n"+untouched+"\n")
                finally:
                    subprocess.run(["docker","rm","-f",name],capture_output=True,timeout=30)

if __name__=="__main__":
    unittest.main()
