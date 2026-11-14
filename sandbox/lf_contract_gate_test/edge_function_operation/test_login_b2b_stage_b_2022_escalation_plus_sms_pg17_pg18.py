#!/usr/bin/env python3
"""Actualiza ocho filas y crea política CANDIDATO solo en Docker PG17.6/18.7, con ROLLBACK."""
from __future__ import annotations
import json, os, shutil, subprocess, time, unittest, uuid
from pathlib import Path

HERE=Path(__file__).resolve().parent
SNAP=HERE/"fixtures/login_b2b_stage_b_2022_real_snapshots_20261113.json"
PATCH=HERE/"fixtures/login_b2b_stage_b_2022_escalated_full_patch_20261113.json"

def qs(value):
    return "'"+str(value).replace("'","''")+"'"

def qj(value):
    return qs(json.dumps(value,ensure_ascii=False,separators=(",",":")))+"::jsonb"

class StageBRealRollback(unittest.TestCase):
    def run_pg(self,image,expected_num):
        self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
        data=json.loads(SNAP.read_text(encoding="utf8"))
        changes=json.loads(PATCH.read_text(encoding="utf8"))
        self.assertEqual(len(data["rules"]),6)
        self.assertEqual(len(data["policies"]),2)
        self.assertEqual(len(changes["patches"]),9)
        self.assertFalse(changes["identity_verified"])
        self.assertEqual(changes["new_permission_table_proposal"]["state"],"OBJECT_NEW_DESIGN_ONLY")
        cid="lf-b2b-tx-"+uuid.uuid4().hex[:10]
        started=subprocess.run(["docker","run","-d","--rm","--name",cid,
            "-e","POSTGRES_PASSWORD=postgres","-e","POSTGRES_DB=postgres",image],
            text=True,capture_output=True,timeout=250)
        self.assertEqual(started.returncode,0,started.stderr[-3000:])
        try:
            def sql(s,timeout=300):
                r=subprocess.run(["docker","exec","-i",cid,"psql","-X","-q","-t","-A",
                     "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
                     input=s,text=True,capture_output=True,timeout=timeout)
                self.assertEqual(r.returncode,0,"SQL_FAILED:"+r.stderr[-3500:])
                return [s.strip() for s in r.stdout.splitlines() if s.strip()]
            for _ in range(90):
                if subprocess.run(["docker","exec",cid,"pg_isready","-U","postgres"],
                                  capture_output=True,timeout=10).returncode==0: break
                time.sleep(1)
            else: self.fail("POSTGRES_NOT_READY")
            self.assertEqual(sql("SHOW server_version_num;"),[expected_num])
            cols={}
            for c in data["columns"]:
                self.assertRegex(c["tab"],r"^(reglas|politicas_seguridad|politicas_rate_limit)$")
                self.assertRegex(c["col"],r"^[a-z0-9_]+$")
                self.assertRegex(c["typ"],r"^(text|integer|bigint|boolean|jsonb|timestamp with time zone)$")
                cols.setdefault(c["tab"],[]).append('"'+c["col"]+'" '+c["typ"])
            ddl=["CREATE SCHEMA lf_ops;","CREATE SCHEMA extensions;",
                 "CREATE EXTENSION pgcrypto WITH SCHEMA extensions;"]
            for table in ("reglas","politicas_seguridad","politicas_rate_limit"):
                extra=", policy_config jsonb NOT NULL DEFAULT '{}'::jsonb" if table=="politicas_rate_limit" else ""
                ddl.append("CREATE TABLE lf_ops."+table+"("+",".join(cols[table])+extra+");")
            # policy_config does NOT exist in the live rate-limit table: laboratory candidate schema only.
            self.assertFalse(any(c["tab"]=="politicas_rate_limit" and c["col"]=="policy_config" for c in data["columns"]))
            sql("\n".join(ddl))
            inserts=[]
            for r in data["rules"]:
                inserts.append("INSERT INTO lf_ops.reglas SELECT (jsonb_populate_record("+
                    "NULL::lf_ops.reglas,"+qj(r["snapshot"])+")).*;")
            for r in data["policies"]:
                inserts.append("INSERT INTO lf_ops.politicas_seguridad SELECT (jsonb_populate_record("+
                    "NULL::lf_ops.politicas_seguridad,"+qj(r["snapshot"])+")).*;")
            sql("\n".join(inserts))
            def get_hash(table,where):
                return sql("SELECT encode(extensions.digest(convert_to(to_jsonb(t)::text,"+
                       "'UTF8'),'sha256'),'hex') FROM "+table+" t WHERE "+where+";")
            before={}
            for r in data["rules"]:
                key=r["snapshot"]["codigo"]
                self.assertEqual(get_hash("lf_ops.reglas","codigo="+qs(key)),[r["sha256"]],
                                 "SOURCE_SHA_MISMATCH:"+key)
                before[key]=r["sha256"]
            for r in data["policies"]:
                key=r["snapshot"]["policy_code"]
                self.assertEqual(get_hash("lf_ops.politicas_seguridad","policy_code="+qs(key)),
                                 [r["sha256"]],"SOURCE_SHA_MISMATCH:"+key)
                before[key]=r["sha256"]
            newkey="AUTH_LOGIN_FAILED_PASSWORD"
            self.assertEqual(sql("SELECT COUNT(*) FROM lf_ops.politicas_rate_limit WHERE policy_code="+qs(newkey)+";"),["0"])
            before[newkey]="ABSENT"
            rate=next(p["row"] for p in changes["patches"] if p["kind"]=="new_rate_policy")
            config=rate["policy_config"]
            self.assertEqual([s["additional_consecutive_failures"] for s in config["stages"]],[5,3,3])
            self.assertEqual([s["lock_seconds"] for s in config["stages"]],[900,3600,86400])
            self.assertEqual([s["cumulative_failures"] for s in config["stages"]],[5,8,11])
            self.assertEqual(config["reset"]["idle_seconds_without_attempt"],86400)
            self.assertEqual(config["notifications"]["email_for_lock_stages"],[2,3])
            self.assertTrue(config["unknown_user"]["count_attempts"])
            self.assertTrue(config["unknown_user"]["message_equivalent"])
            self.assertTrue(config["unknown_user"]["response_time_equivalent"])
            self.assertFalse(config["otp_failures_counted"])
            self.assertEqual(config["support_24h_unlock"]["permission_key"],"can_unlock_password_24h")
            self.assertEqual(rate["window_seconds"],86400)
            self.assertEqual(rate["max_requests"],5)
            self.assertEqual(rate["scope_key"],"USER")
            self.assertGreaterEqual(len(rate["parameter_provenance"]),21)
            tx=["BEGIN;"]
            for p in changes["patches"]:
                if p["kind"]=="rule":
                    key=p["code"]
                    table="lf_ops.reglas"; where="codigo="+qs(key)
                    tx.append("UPDATE "+table+" SET titulo="+qs(p["title"])+
                      ",descripcion="+qs(p["description"])+
                      ",pendiente_detalle="+qs(p["pending_detail"])+
                      ",valor_config=valor_config || "+qj(p["config_set"])+" WHERE "+where+";")
                elif p["kind"]=="policy":
                    key=next(r["snapshot"]["policy_code"] for r in data["policies"]
                       if r["snapshot"]["security_policy_id"]==p["id"])
                    table="lf_ops.politicas_seguridad";where="policy_code="+qs(key)
                    tx.append("UPDATE "+table+" SET description="+qs(p["description"])+
                        ",policy_config=policy_config || "+qj(p["config_set"])+
                        " WHERE security_policy_id="+str(p["id"])+";")
                elif p["kind"]=="new_rate_policy":
                    key=p["code"];table="lf_ops.politicas_rate_limit";where="policy_code="+qs(key)
                    tx.append("INSERT INTO "+table+" SELECT (jsonb_populate_record(NULL::"+
                        table+","+qj(p["row"])+")).*;")
                else:
                    self.fail("UNEXPECTED_PATCH_KIND:"+str(p["kind"]))
                tx.append("SELECT "+qs("DURING|"+key+"|")+
                  " || encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),"+
                  "'sha256'),'hex') FROM "+table+" t WHERE "+where+";")
            tx.append("ROLLBACK;")
            for key in before:
                table=("lf_ops.politicas_rate_limit" if key==newkey else
                    "lf_ops.politicas_seguridad" if key.startswith("SEC-") else "lf_ops.reglas")
                where=("policy_code=" if key==newkey or key.startswith("SEC-") else "codigo=")+qs(key)
                tx.append("SELECT "+qs("AFTER|"+key+"|")+
                    " || COALESCE((SELECT encode(extensions.digest(convert_to(to_jsonb(t)::"+
                    "text,'UTF8'),'sha256'),'hex') FROM "+table+
                    " t WHERE "+where+"),'ABSENT');")
            lines=sql("\n".join(tx),timeout=540)
            inside={}; after={}
            for line in lines:
                if line.startswith("DURING|"):
                    _,key,sha=line.split("|",2);inside[key]=sha
                if line.startswith("AFTER|"):
                    _,key,sha=line.split("|",2);after[key]=sha
            self.assertEqual(set(inside),set(before),"MISSING_INNER_SHAS")
            self.assertEqual(set(after),set(before),"MISSING_ROLLBACK_SHAS")
            for key,orig in before.items():
                self.assertRegex(inside[key],r"^[0-9a-f]{64}$")
                self.assertNotEqual(inside[key],orig,"ROW_NOT_CHANGED:"+key)
                self.assertEqual(after[key],orig,"ROLLBACK_NOT_EXACT:"+key)
                print("ETAPAB_LAB_RESULT|"+image+"|"+key+"|"+orig+"|"+inside[key]+
                      "|"+after[key]+"|PASS",flush=True)
            print("PASS_ETAPAB_REAL_UPDATE_INSERT_ROLLBACK_"+image.replace(":","_"),flush=True)
            if os.environ.get("GITHUB_STEP_SUMMARY"):
                with open(os.environ["GITHUB_STEP_SUMMARY"],"a",encoding="utf8") as out:
                    out.write("\n### Login B2B Etapa B - "+image+" - disposable Docker\n\n")
                    out.write("| Fila | Antes | Dentro TX | Tras ROLLBACK | Resultado |\n")
                    out.write("|---|---|---|---|---|\n")
                    for key in before:
                        out.write("| "+key+" | "+before[key]+" | "+inside[key]+" | "+
                                  after[key]+" | PASS |\n")
        finally:
            subprocess.run(["docker","rm","-f",cid],text=True,capture_output=True,timeout=45)

    def test_pg_17_6(self): self.run_pg("postgres:17.6","170006")
    def test_pg_18_7(self): self.run_pg("postgres:18.7","180007")

if __name__=="__main__": unittest.main()
