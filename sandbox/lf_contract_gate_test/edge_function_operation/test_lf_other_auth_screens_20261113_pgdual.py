#!/usr/bin/env python3
"""LF other auth screens: source SHA, 11 UPDATE + 9 INSERT (12 links) and ROLLBACK.
PostgreSQL 17.6 / 18.7 disposable Docker only. NEVER connects to Supabase live.
"""
from __future__ import annotations
import json,re,shutil,subprocess,time,unittest,uuid,hashlib
from pathlib import Path
HERE=Path(__file__).resolve().parent
DATA=HERE/"fixtures/lf_other_auth_screens_20261113_source_patch.json"
def quote(v): return "'"+str(v).replace("'","''")+"'"
def qjson(v): return quote(json.dumps(v,ensure_ascii=False,separators=(",",":")))+"::jsonb"
def sha_row(code):
    return ("SELECT encode(pg_catalog.sha256(convert_to(to_jsonb(r)::text,'UTF8')),'hex') "
            "FROM lf_ops.reglas r WHERE r.codigo="+quote(code)+";")
def hash_inserted(code):
    return ("SELECT encode(pg_catalog.sha256(convert_to(jsonb_build_object("
            "'rule',(SELECT to_jsonb(r) FROM lf_ops.reglas r WHERE r.codigo="+quote(code)+"),"
            "'links',(SELECT coalesce(jsonb_agg(to_jsonb(rp) ORDER BY rp.id),'[]'::jsonb) "
            "FROM lf_ops.reglas_pantallas rp JOIN lf_ops.reglas r ON r.id=rp.regla_id "
            "WHERE r.codigo="+quote(code)+"))::text,'UTF8')),'hex');")
COLS=("id integer,codigo text,categoria text,titulo text,descripcion text,razon text,"
      "valor_config jsonb,es_transversal boolean,estado text,origen text,"
      "created_at timestamp with time zone,updated_at timestamp with time zone,"
      "pendiente_decision boolean,pendiente_detalle text,created_by text")
class OtherAuthScreenAudit(unittest.TestCase):
    def exercise(self,image,expected_version):
        self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
        doc=json.loads(DATA.read_text(encoding="utf8"))
        self.assertEqual(doc["schema"],"LF_OTHER_LOGIN_SCREENS_AUDIT_V1")
        self.assertEqual(sum(x["vinculos"] for x in doc["scope"]),344)
        self.assertEqual(len(doc["updates"]),11)
        self.assertEqual(len(doc["inserts"]),9)
        self.assertEqual(sum(len(x["screens"]) for x in doc["inserts"]),12)
        owner=doc["owner_decision"]
        self.assertFalse(owner["identity_verified"])
        self.assertFalse(owner["signed"])
        self.assertTrue(owner["supersedes_client_wait_48h_for_entry"])
        self.assertEqual(owner["actual_config_source"],"SEC-CLIENT-RECOVERY-LIMITED-ACCESS")
        bycode={x["codigo"]:x for x in doc["updates"]}
        self.assertEqual(len(bycode),11)
        candidate_rec=[x for x in doc["updates"] if x["codigo"].startswith("REG_CLIENT_RECOVERY")]
        self.assertEqual(len(candidate_rec),5)
        self.assertTrue(all(x["estado"]=="VIGENTE" and x["estado_nuevo"]=="CANDIDATO" for x in candidate_rec))
        self.assertFalse(any("48 horas" in x["texto_nuevo"] for x in candidate_rec))
        self.assertIn("INMEDIATA",bycode["REG_CLIENT_RECOVERY_ACCESS_AFTER_REBIND_001"]["texto_nuevo"])
        self.assertEqual(bycode["REG_CLIENT_RECOVERY_ACCESS_AFTER_REBIND_001"]["config_nueva"]["success_outcome"],"LIMITED_ACTIVE")
        self.assertEqual(bycode["REG_CLIENT_RECOVERY_REBIND_ATOMIC_001"]["config_nueva"]["require_window_elapsed_for_limited_access"],False)
        self.assertEqual({x["codigo"] for x in doc["inserts"] if "B2B-AUTH-004" in x["screens"]},{"B2B-RULE-RECOVERY-MFA-SEPARATION-001"})
        self.assertEqual({x["codigo"] for x in doc["inserts"] if x["codigo"].startswith("REG_CLIENT_RECOVERY") and "REC_001" in x["screens"]},
                         {"REG_CLIENT_RECOVERY_SUPPORT_Q11_001","REG_CLIENT_RECOVERY_ALTERNATE_CONTACT_001","REG_CLIENT_RECOVERY_LIMITED_SESSION_001","REG_CLIENT_RECOVERY_WINDOW_GUARD_001","REG_CLIENT_RECOVERY_OWNER_OBJECTION_001"})
        self.assertTrue(all(x["valor_config"].get("identity_verified") is False for x in doc["inserts"]))
        policy=doc["policy_proposal"]["record"]
        self.assertEqual(policy["status"],"CANDIDATO")
        self.assertEqual(policy["policy_config"]["approvers_allowed"],[1,2])
        self.assertEqual(policy["policy_config"]["session_mode"],"LIMITED_ACTIVE")
        self.assertEqual(policy["policy_config"]["notification_channel_for_change"]["PHONE"],"PREVIOUS_VERIFIED_EMAIL")
        self.assertEqual(policy["policy_config"]["notification_channel_for_change"]["EMAIL"],"PREVIOUS_VERIFIED_PHONE")
        self.assertTrue(policy["policy_config"]["alternate_contact_optional_for_onboarding"])
        self.assertGreater(policy["policy_config"]["security_window_hours"],0)
        self.assertIn("NO_DEBT_LETTER_DELIVERY",policy["policy_config"]["limited_blocked_actions"])
        protected=set(doc["protected_codes"])
        self.assertFalse(protected & {x["codigo"] for x in doc["updates"]})
        self.assertFalse(protected & {x["codigo"] for x in doc["inserts"]})
        for x in doc["updates"]+doc["inserts"]:
            value=x.get("texto_nuevo",x.get("descripcion",""))
            self.assertFalse(re.search(r"#[0-9a-fA-F]{3,8}\b",value),"HEX_LITERAL:"+x["codigo"])
        replaced=next(x for x in doc["scope"] if x["pantalla"]=="B2B-AUTH-005")
        self.assertEqual((replaced["estado"],replaced["activa"],replaced["vigente"],replaced["vinculos"]),
                         ("REEMPLAZADO",False,21,24))
        cid="lf-other-auth-"+uuid.uuid4().hex[:10]
        start=subprocess.run(["docker","run","-d","--rm","--name",cid,
            "-e","POSTGRES_PASSWORD=postgres","-e","POSTGRES_DB=postgres",image],
            capture_output=True,text=True,timeout=240)
        self.assertEqual(start.returncode,0,start.stderr[-1600:])
        try:
            def sql(query,timeout=240):
                r=subprocess.run(["docker","exec","-i",cid,"psql","-X","-q","-A","-t",
                    "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
                    input=query,text=True,capture_output=True,timeout=timeout)
                self.assertEqual(r.returncode,0,r.stderr[-2000:]+"\n"+query[:500])
                return [v.strip() for v in r.stdout.splitlines() if v.strip()]
            for _ in range(60):
                r=subprocess.run(["docker","exec",cid,"pg_isready","-U","postgres"],
                    capture_output=True,timeout=12)
                if r.returncode==0: break
                time.sleep(1)
            else: self.fail("POSTGRES_NOT_READY")
            self.assertEqual(sql("SHOW server_version_num;"),[expected_version])
            sql("CREATE SCHEMA lf_ops;"
                "CREATE TABLE lf_ops.reglas("+COLS+");"
                "CREATE TABLE lf_ops.pantallas(id integer,codigo text,estado text,activa boolean);"
                "CREATE TABLE lf_ops.reglas_pantallas("
                "id integer,regla_id integer,pantalla_id integer,nota text,created_at timestamp with time zone);")
            for x in doc["scope"]:
                sql("INSERT INTO lf_ops.pantallas(id,codigo,estado,activa) VALUES ("+
                    str(x["id"])+","+quote(x["pantalla"])+","+quote(x["estado"])+","+
                    ("true" if x["activa"] else "false")+");")
            for x in doc["updates"]:
                src=x["source_row"]
                self.assertEqual(src["codigo"],x["codigo"])
                self.assertEqual(src["id"],x["id"])
                sql("INSERT INTO lf_ops.reglas SELECT (jsonb_populate_record(NULL::lf_ops.reglas,"+
                    qjson(src)+")).*;")
            # Critical: every source-row SHA must equal the read-only Supabase SHA, not local guess.
            for x in doc["updates"]:
                before=sql(sha_row(x["codigo"]))[0]
                self.assertEqual(before,x["before_sha256"],"SOURCE_FULLROW_SHA_DRIFT:"+x["codigo"])
                change=("UPDATE lf_ops.reglas AS r SET titulo="+quote(x["titulo_nuevo"])+
                        ",descripcion="+quote(x["texto_nuevo"])+
                        ",estado="+quote(x.get("estado_nuevo",x["estado"]))+
                        ",valor_config="+qjson(x["config_nueva"])+
                        " WHERE r.codigo="+quote(x["codigo"])+
                        " AND r.id="+str(x["id"])+
                        " AND r.estado="+quote(x["estado"])+
                        " AND encode(pg_catalog.sha256(convert_to(to_jsonb(r)::text,'UTF8')),'hex')="+
                        quote(before)+";")
                lines=sql("BEGIN;\n"+change+"\nSELECT 'DURING|'||"+
                    "encode(pg_catalog.sha256(convert_to(to_jsonb(r)::text,'UTF8')),'hex') "
                    "FROM lf_ops.reglas r WHERE codigo="+quote(x["codigo"])+";\n"+
                    "SELECT 'DURING_STATE|'||estado FROM lf_ops.reglas WHERE codigo="+quote(x["codigo"])+";\nROLLBACK;\n"+
                    "SELECT 'AFTER|'||encode(pg_catalog.sha256(convert_to(to_jsonb(r)::text,'UTF8')),'hex') "
                    "FROM lf_ops.reglas r WHERE codigo="+quote(x["codigo"])+";")
                if x.get("estado_nuevo") == "CANDIDATO":
                    cand=sql("SELECT estado FROM lf_ops.reglas WHERE codigo="+quote(x["codigo"])+";")
                    self.assertEqual(cand,["VIGENTE"],"ROLLBACK_CANDIDATE_STATE_MISMATCH:"+x["codigo"])
                during_state=[v.split("|",1)[1] for v in lines if v.startswith("DURING_STATE|")]
                self.assertEqual(during_state,[x.get("estado_nuevo",x["estado"])],"INSIDE_CANDIDATE_STATUS_MISMATCH:"+x["codigo"])
                during=[v.split("|",1)[1] for v in lines if v.startswith("DURING|")]
                after=[v.split("|",1)[1] for v in lines if v.startswith("AFTER|")]
                self.assertEqual(len(during),1)
                self.assertEqual(len(after),1)
                self.assertRegex(during[0],r"^[0-9a-f]{64}$")
                self.assertNotEqual(during[0],before,"UPDATE_DID_NOT_CHANGE:"+x["codigo"])
                self.assertEqual(after[0],before,"ROLLBACK_MISMATCH:"+x["codigo"])
                print("SHA_UPDATE|"+image+"|"+x["codigo"]+"|"+before+"|"+
                      during[0]+"|"+after[0]+"|PASS",flush=True)
            for i,x in enumerate(doc["inserts"]):
                code=x["codigo"];fake_id=100001+i
                before=sql(hash_inserted(code))[0]
                statement=("INSERT INTO lf_ops.reglas(id,codigo,categoria,titulo,descripcion,valor_config,"
                    "estado,origen,pendiente_decision) VALUES ("+str(fake_id)+","+
                    quote(code)+","+quote(x["categoria"])+","+quote(x["titulo"])+","+
                    quote(x["descripcion"])+","+qjson(x["valor_config"])+
                    ",'CANDIDATO','PROPOSAL_SANDBOX',true);")
                joins=[]
                for j,screen in enumerate(x["screens"]):
                    target=next(y for y in doc["scope"] if y["pantalla"]==screen)
                    joins.append("INSERT INTO lf_ops.reglas_pantallas(id,regla_id,pantalla_id,nota)"
                        " VALUES("+str(200001+i*10+j)+","+str(fake_id)+","+
                        str(target["id"])+",'CANDIDATE_ONLY');")
                lines=sql("BEGIN;\n"+statement+"\n"+"\n".join(joins)+
                    "\nSELECT 'DURING|'||("+hash_inserted(code).replace("SELECT ","SELECT ",1).rstrip(";")+
                    ");\nSELECT 'LINKS|'||count(*) FROM lf_ops.reglas_pantallas WHERE regla_id="+str(fake_id)+";"+
                    "\nROLLBACK;\nSELECT 'AFTER|'||("+hash_inserted(code).rstrip(";")+");")
                during=[v.split("|",1)[1] for v in lines if v.startswith("DURING|")]
                after=[v.split("|",1)[1] for v in lines if v.startswith("AFTER|")]
                links=[int(v.split("|",1)[1]) for v in lines if v.startswith("LINKS|")]
                self.assertEqual(len(during),1)
                self.assertEqual(after,[before])
                self.assertNotEqual(during[0],before)
                self.assertEqual(links,[len(x["screens"])])
                self.assertEqual(sql("SELECT count(*) FROM lf_ops.reglas WHERE codigo="+quote(code)+";"),["0"])
                print("SHA_INSERT|"+image+"|"+code+"|"+before+"|"+during[0]+"|"+after[0]+"|PASS",flush=True)
            print("PASS_OTHER_AUTH_11_UPDATES_9_INSERTS_12_LINKS_ROLLBACK_"+image.replace(":","_"),flush=True)
        finally:
            subprocess.run(["docker","rm","-f",cid],capture_output=True,text=True,timeout=60)
    def test_pg176(self):self.exercise("postgres:17.6","170006")
    def test_pg187(self):self.exercise("postgres:18.7","180007")
if __name__=="__main__": unittest.main()
