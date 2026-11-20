"""LF owner decision L16 Q01/Q04/Q10/Q11/Q12: exact SQL PG17.6/18.7 apply/rollback.

Only fixture rows obtained by SELECT, no live writes or direct Supabase connections.
"""
import json
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
SQL=ROOT/"supabase/migrations/20261114155700_lf_owner_l16_conflict_rule_homologation_v1.sql"
FIXTURE=ROOT/"sandbox/lf_contract_gate_test/edge_function_operation/fixtures/lf_owner_l16_homologation_source_rows_20261114.json"
TABLE=r"""
CREATE SCHEMA lf_ops;
CREATE TABLE lf_ops.reglas(
 id integer PRIMARY KEY,codigo text NOT NULL,estado text NOT NULL,
 descripcion text,razon text,valor_config jsonb,
 pendiente_decision boolean,pendiente_detalle text,
 updated_at timestamptz DEFAULT now());
"""

BEFORE=r"""
SELECT 'RULES='||count(*)||':'||
 count(*) FILTER(WHERE estado='CANDIDATO')||':'||
 count(*) FILTER(WHERE estado='VIGENTE')
 FROM lf_ops.reglas;
SELECT 'GOOGLE_SAML='||(valor_config->>'admin_identity_provider')
 FROM lf_ops.reglas WHERE id=438;
SELECT 'CARTA_SLA='||coalesce(valor_config->>'sla_generacion_h','NULL')
 FROM lf_ops.reglas WHERE id=235;
"""
AFTER=r"""
SELECT 'RULES='||count(*)||':'||
 count(*) FILTER(WHERE estado='CANDIDATO')||':'||
 count(*) FILTER(WHERE estado='VIGENTE')
 FROM lf_ops.reglas;
SELECT 'AUTH019_METHOD='||(valor_config->>'admin_factor_method')
 FROM lf_ops.reglas WHERE id=438;
SELECT 'AUTH020_HOLD='||(valor_config->>'hold_hours')
 FROM lf_ops.reglas WHERE id=439;
SELECT 'CARTA_SLA='||coalesce(valor_config->>'sla_generacion_h','NULL')
 FROM lf_ops.reglas WHERE id=235;
SELECT 'NO_GRACE='||(valor_config->>'grace_policy')
 FROM lf_ops.reglas WHERE id=532;
SELECT 'UNBOUND_RISK='||(valor_config->>'threshold_policy_binding')
 FROM lf_ops.reglas WHERE id=440;
SELECT 'UNBOUND_PASSWORD='||(valor_config->>'threshold_policy_binding')
 FROM lf_ops.reglas WHERE id=577;
SELECT 'EVIDENCE='||count(*) FROM lf_ops.reglas
 WHERE id IN (235,438,439,440,532,577)
   AND valor_config->>'owner_decision_identity_verified'='false';
"""


class L16HomologationPGDual(unittest.TestCase):
    def test_exact_sql_rollback_and_drift(self):
        self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
        sql=SQL.read_text(encoding="utf-8")
        fixture=json.loads(FIXTURE.read_text(encoding="utf-8"))["rows"]
        self.assertEqual(len(fixture),6)
        self.assertEqual(set(x["id"] for x in fixture),
                         {235,438,439,440,532,577})
        self.assertIn("LF_L16_HOMOLOGATION_PREIMAGE_DRIFT",sql)
        self.assertNotIn("INSERT INTO lf_ops.reglas",sql)
        self.assertNotIn("UPDATE public.lf_rule_promotion_v1",sql)
        self.assertEqual(sql.count("UPDATE lf_ops.reglas SET"),6)
        # To test actual SQL inside an externally controlled transaction, strip
        # the outer transaction commands; no SQL expression is rewritten.
        body=sql.split("\nBEGIN;\n",1)[1].rsplit("\nCOMMIT;\n",1)[0]
        row_data=json.dumps(fixture,ensure_ascii=False,separators=(",",":"))
        escaped=row_data.replace("'","''")
        seed=TABLE+"""
INSERT INTO lf_ops.reglas
 (id,codigo,estado,descripcion,razon,valor_config,
  pendiente_decision,pendiente_detalle)
SELECT (x->>'id')::integer,x->>'codigo',x->>'estado',
 x->>'descripcion',x->>'razon',x->'valor_config',
 (x->>'pendiente_decision')::boolean,x->>'pendiente_detalle'
FROM jsonb_array_elements('"""+escaped+"""'::jsonb) x;
"""
        for pg in ("17.6","18.7"):
            with self.subTest(pg=pg):
                name="lf-owner-l16-"+uuid.uuid4().hex[:11]
                process=subprocess.run(["docker","run","-d","--rm","--name",name,
                      "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+pg],
                      capture_output=True,text=True,timeout=180)
                self.assertEqual(process.returncode,0,process.stderr)
                try:
                    for _ in range(80):
                        ready=subprocess.run(["docker","exec",name,"pg_isready",
                            "-U","postgres"],capture_output=True,timeout=8)
                        if ready.returncode==0:
                            logs=subprocess.run(["docker","logs",name],
                                capture_output=True,text=True,timeout=8)
                            if "PostgreSQL init process complete; ready for start up." in (logs.stdout+logs.stderr):
                                break
                        time.sleep(.7)
                    self.assertEqual(ready.returncode,0)
                    def psql(text,good=True):
                        r=subprocess.run(["docker","exec","-i",name,"psql",
                           "-X","-A","-t","-U","postgres","-d","postgres",
                           "-v","ON_ERROR_STOP=1"],input=text,
                           capture_output=True,text=True,timeout=120)
                        if good: self.assertEqual(r.returncode,0,r.stderr[-4000:])
                        else: self.assertNotEqual(r.returncode,0,r.stdout)
                        return r
                    init=psql(seed+BEFORE)
                    self.assertIn("RULES=6:4:2",init.stdout)
                    self.assertIn("GOOGLE_SAML=GOOGLE_WORKSPACE",init.stdout)
                    self.assertIn("CARTA_SLA=48",init.stdout)
                    positive=psql("BEGIN;\n"+body+"\n"+AFTER+"\nROLLBACK;\n"+BEFORE)
                    for needle in ("AUTH019_METHOD=LF_EMAIL_OTP",
                         "AUTH020_HOLD=48","CARTA_SLA=NULL",
                         "NO_GRACE=NO_GRACE_OWNER_DECIDED",
                         "UNBOUND_RISK=PENDING_SPECIFIC_CONTROL_UNIT_EVENT",
                         "UNBOUND_PASSWORD=PENDING_CONTROL_UNIT",
                         "EVIDENCE=6","RULES=6:4:2",
                         "GOOGLE_SAML=GOOGLE_WORKSPACE"):
                        self.assertIn(needle,positive.stdout,needle+"\n"+positive.stdout)
                    negative=psql("BEGIN;\nUPDATE lf_ops.reglas "
                       "SET descripcion=descripcion||' STALE' WHERE id=438;\n"
                       +body+"\nROLLBACK;",good=False)
                    self.assertIn("LF_L16_HOMOLOGATION_PREIMAGE_DRIFT",negative.stderr)
                    final=psql(BEFORE)
                    self.assertIn("RULES=6:4:2",final.stdout)
                    self.assertIn("GOOGLE_SAML=GOOGLE_WORKSPACE",final.stdout)
                    self.assertIn("CARTA_SLA=48",final.stdout)
                    print("PASS_OWNER_L16_PG"+pg+
                       "_6_EXACT_RULES_ROLLBACK_DRIFT_BLOCKED")
                finally:
                    subprocess.run(["docker","rm","-f",name],
                        capture_output=True,timeout=30)
