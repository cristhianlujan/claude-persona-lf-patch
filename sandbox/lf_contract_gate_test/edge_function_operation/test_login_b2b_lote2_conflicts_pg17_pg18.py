#!/usr/bin/env python3
"""LF L40 Login B2B: 6 CANDIDATO conflicts only, real Docker PG17.6/18.7 UPDATE+ROLLBACK.
Based on the isolated schema and SHA method of PR #3844; NEVER connects to Supabase.
"""
from __future__ import annotations
import json,os,re,shutil,subprocess,time,unittest,uuid
from pathlib import Path
HERE=Path(__file__).resolve().parent
SNAP=HERE/"fixtures/login_b2b_lote2_source_snapshot_20261113.json"
PATCH=HERE/"fixtures/login_b2b_lote2_conflict_only_patch_20261113.json"
CHANGED=("B2B-RULE-AUTH-013","B2B-RULE-AUTH-030","B2B-RULE-AUTH-033","B2B-RULE-AUTH-034","B2B-RULE-AUTH-040","B2B-RULE-AUTH-043")
PROTECTED=tuple("B2B-RULE-AUTH-"+n for n in ("018","019","020","021","026","047"))
def q(x): return "'"+str(x).replace("'","''")+"'"
def qj(x): return q(json.dumps(x,ensure_ascii=False,separators=(",",":")))+"::jsonb"

class TestLoginOtherCandidates(unittest.TestCase):
    def exercise(self,image,exact_number):
        self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
        snap=json.loads(SNAP.read_text(encoding="utf8"))
        patches=json.loads(PATCH.read_text(encoding="utf8"))
        self.assertEqual(len(snap["rules"]),32)
        self.assertEqual(len(patches["proposals"]),6)
        self.assertEqual(set(patches["conflict_codes"]),set(CHANGED))
        self.assertFalse(set(PROTECTED) & set(patches["conflict_codes"]))
        self.assertFalse(patches["identity_verified"])
        self.assertTrue(all(p["source_status"]=="CANDIDATO" for p in patches["proposals"]))
        self.assertTrue(all(not re.search(r"#[a-fA-F0-9]{3,8}\\b",p["proposed_description"]) for p in patches["proposals"]))
        bycode={r["snapshot"]["codigo"]:r for r in snap["rules"]}
        self.assertEqual(set(bycode),set(patches["scope_codes"]))
        self.assertEqual(bycode["B2B-RULE-STATE-001"]["snapshot"]["estado"],"VIGENTE")
        self.assertTrue(all(p["source_sha256"]==bycode[p["code"]]["sha256"] for p in patches["proposals"]))
        self.assertEqual(len({p["code"] for p in patches["proposals"]}),6)
        cid="lf-login-l40-"+uuid.uuid4().hex[:10]
        run=subprocess.run(["docker","run","--rm","-d","--name",cid,
             "-e","POSTGRES_PASSWORD=postgres","-e","POSTGRES_DB=postgres",image],
            capture_output=True,text=True,timeout=240)
        self.assertEqual(run.returncode,0,run.stderr[-3000:])
        try:
            def sql(source,timeout=300):
                p=subprocess.run(["docker","exec","-i",cid,"psql","-X","-t","-A","-q",
                    "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
                    input=source,text=True,capture_output=True,timeout=timeout)
                self.assertEqual(p.returncode,0,"SQL_FAILED:"+p.stderr[-4000:])
                return [s.strip() for s in p.stdout.splitlines() if s.strip()]
            for _ in range(90):
                try:
                    is_ready=subprocess.run(["docker","exec",cid,"pg_isready","-U","postgres"],
                       capture_output=True,timeout=10).returncode==0
                except subprocess.SubprocessError: is_ready=False
                if is_ready: break
                time.sleep(1)
            else: self.fail("PG_NOT_READY")
            self.assertEqual(sql("SHOW server_version_num;"),[exact_number])
            cols=[]
            for c in snap["columns"]:
                self.assertRegex(c["col"],r"^[a-z0-9_]+$")
                self.assertIn(c["typ"],("integer","bigint","text","boolean","jsonb","timestamp with time zone"))
                cols.append('"'+c["col"]+'" '+c["typ"])
            sql("CREATE SCHEMA lf_ops;CREATE SCHEMA extensions;"
                "CREATE EXTENSION pgcrypto WITH SCHEMA extensions;"
                "CREATE TABLE lf_ops.reglas("+",".join(cols)+");")
            inserts=["INSERT INTO lf_ops.reglas SELECT (jsonb_populate_record(NULL::lf_ops.reglas,"+
                qj(r["snapshot"])+")).*;" for r in snap["rules"]]
            sql("\n".join(inserts))
            hash_sql="SELECT codigo||'|'||encode(extensions.digest(convert_to(to_jsonb(r)::text,'UTF8'),'sha256'),'hex') FROM lf_ops.reglas r ORDER BY codigo;"
            def decode(lines):
                return dict(x.split("|",1) for x in lines)
            before=decode(sql(hash_sql))
            self.assertEqual(set(before),set(bycode))
            for code,row in bycode.items():
                self.assertEqual(before[code],row["sha256"],"SOURCE_SNAPSHOT_SHA_MISMATCH:"+code)
            tx=["BEGIN;"]
            for p in patches["proposals"]:
                code=p["code"]
                # Do not touch other rules, profiles, policy or state machine.
                tx.append("UPDATE lf_ops.reglas SET descripcion="+q(p["proposed_description"])+
                   ",valor_config=COALESCE(valor_config,'{}'::jsonb)||"+qj(p["config_patch"])+
                   " WHERE codigo="+q(code)+" AND estado='CANDIDATO';")
            tx.append("SELECT 'DURING|'||codigo||'|'||encode(extensions.digest(convert_to(to_jsonb(r)::text,'UTF8'),'sha256'),'hex') FROM lf_ops.reglas r ORDER BY codigo;")
            tx.append("SELECT 'GATES|'||CASE WHEN "+
                "(SELECT count(*) FROM lf_ops.reglas WHERE estado='CANDIDATO')=31 "+
                "AND (SELECT estado FROM lf_ops.reglas WHERE codigo='B2B-RULE-STATE-001')='VIGENTE' "+
                "AND (SELECT count(*) FROM lf_ops.reglas)=32 "+
                "AND (SELECT valor_config->>'admin_identity_provider' FROM lf_ops.reglas WHERE codigo='B2B-RULE-AUTH-013')='PENDING_ADR_003_M1_SPIKE' "+
                "AND (SELECT valor_config->>'mfa_trigger_device_recognition' FROM lf_ops.reglas WHERE codigo='B2B-RULE-AUTH-033')='DENY' "+
                "AND (SELECT valor_config->>'rate_limit_contract_status' FROM lf_ops.reglas WHERE codigo='B2B-RULE-AUTH-043')='PENDING_CANONICAL_GENERAL_MFA_OTP_RATE_LIMIT' "+
                "THEN 'PASS' ELSE 'FAIL' END;")
            tx.append("ROLLBACK;")
            tx.append("SELECT 'AFTER|'||codigo||'|'||encode(extensions.digest(convert_to(to_jsonb(r)::text,'UTF8'),'sha256'),'hex') FROM lf_ops.reglas r ORDER BY codigo;")
            lines=sql("\n".join(tx))
            during=decode(x[len("DURING|"):] for x in lines if x.startswith("DURING|"))
            after=decode(x[len("AFTER|"):] for x in lines if x.startswith("AFTER|"))
            self.assertIn("GATES|PASS",lines)
            self.assertEqual(set(before),set(during))
            self.assertEqual(set(before),set(after))
            for code in sorted(before):
                self.assertRegex(during[code],r"^[0-9a-f]{64}$")
                if code in CHANGED:
                    self.assertNotEqual(during[code],before[code],"CONFLICT_UNCHANGED:"+code)
                    print("LOGIN_L40_SHA|"+image+"|"+code+"|"+before[code]+"|"+during[code]+"|"+after[code]+"|PASS",flush=True)
                else:
                    self.assertEqual(during[code],before[code],"UNAUTHORIZED_CHANGE:"+code)
                self.assertEqual(after[code],before[code],"ROLLBACK_MISMATCH:"+code)
            print("PASS_LOGIN_L40_6_UPDATES_26_UNCHANGED_"+image.replace(":","_"),flush=True)
            if os.environ.get("GITHUB_STEP_SUMMARY"):
                with open(os.environ["GITHUB_STEP_SUMMARY"],"a",encoding="utf8") as f:
                    f.write("\n### LF L40 - "+image+" - SIX CANDIDATO ONLY, rollback\n\n")
                    f.write("| Código | SHA antes | SHA dentro | SHA tras rollback | Resultado |\n|---|---|---|---|---|\n")
                    for code in CHANGED:
                        f.write("| "+code+" | "+before[code]+" | "+during[code]+" | "+after[code]+" | PASS |\n")
        finally:
            subprocess.run(["docker","rm","-f",cid],capture_output=True,text=True,timeout=60)
    def test_pg17_6(self): self.exercise("postgres:17.6","170006")
    def test_pg18_7(self): self.exercise("postgres:18.7","180007")
if __name__=="__main__":unittest.main()
