#!/usr/bin/env python3
"""AUTH-020 + policy20 approval 1/2 actual UPDATE, rollback PG17.6/18.7; never writes live DB."""
from __future__ import annotations
import json, os, shutil, subprocess, time, unittest, uuid
from pathlib import Path

HERE=Path(__file__).resolve().parent
SNAP=HERE/"fixtures/login_b2b_stage_b_2029_auth020_source_20261113.json"
PATCH=HERE/"fixtures/login_b2b_stage_b_2029_auth020_approvers_patch_20261113.json"

def q(x): return "'"+str(x).replace("'","''")+"'"
def j(x): return q(json.dumps(x,separators=(",",":"),ensure_ascii=False))+"::jsonb"
def sh(table,key):
    return ("SELECT encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),"
            "'sha256'),'hex') FROM "+table+" t WHERE "+key+";")

class TestAuth020Configurable(unittest.TestCase):
 def run_pg(self,image,number):
    self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
    snap=json.loads(SNAP.read_text(encoding="utf-8"))
    patch=json.loads(PATCH.read_text(encoding="utf-8"))
    self.assertFalse(patch["identity_verified"])
    self.assertEqual(patch["test_scenarios"],[1,2])
    self.assertEqual(patch["policy"]["config_set"]["approvers_required"],1)
    self.assertEqual(patch["policy"]["config_set"]["approvers_required_allowed_values"],[1,2])
    self.assertEqual(patch["permission_table_proposal"]["state"],"OBJECT_NEW_DESIGN_ONLY")
    cid="lf-auth020-"+uuid.uuid4().hex[:9]
    r=subprocess.run(["docker","run","--rm","-d","--name",cid,
      "-e","POSTGRES_PASSWORD=postgres","-e","POSTGRES_DB=postgres",image],
      capture_output=True,text=True,timeout=240)
    self.assertEqual(r.returncode,0,r.stderr)
    try:
      def sql(v):
        a=subprocess.run(["docker","exec","-i",cid,"psql","-X","-q","-t","-A",
            "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
            input=v,text=True,capture_output=True,timeout=300)
        self.assertEqual(a.returncode,0,"SQL_FAILED: "+a.stderr[-3500:])
        return [x.strip() for x in a.stdout.splitlines() if x.strip()]
      for _ in range(90):
        if subprocess.run(["docker","exec",cid,"pg_isready","-U","postgres"],
           capture_output=True,timeout=10).returncode==0: break
        time.sleep(1)
      else: self.fail("PG_NOT_READY")
      self.assertEqual(sql("SHOW server_version_num;"),[number])
      cols={}
      for c in snap["columns"]:
        self.assertRegex(c["tab"],r"^(reglas|politicas_seguridad)$")
        self.assertRegex(c["col"],r"^[a-z0-9_]+$")
        self.assertRegex(c["typ"],r"^(text|integer|bigint|boolean|jsonb|timestamp with time zone)$")
        cols.setdefault(c["tab"],[]).append('"'+c["col"]+'" '+c["typ"])
      sql("CREATE SCHEMA lf_ops; CREATE SCHEMA extensions; "
          "CREATE EXTENSION pgcrypto WITH SCHEMA extensions; "
          "CREATE TABLE lf_ops.reglas("+",".join(cols["reglas"])+"); "
          "CREATE TABLE lf_ops.politicas_seguridad("+",".join(cols["politicas_seguridad"])+");")
      sql("INSERT INTO lf_ops.reglas SELECT (jsonb_populate_record(NULL::lf_ops.reglas,"+
          j(snap["rule"]["snapshot"])+")).*; "
          "INSERT INTO lf_ops.politicas_seguridad SELECT (jsonb_populate_record("
          "NULL::lf_ops.politicas_seguridad,"+j(snap["policy"]["snapshot"])+")).*;")
      keys=[("B2B-RULE-AUTH-020","lf_ops.reglas","codigo='B2B-RULE-AUTH-020'"),
            ("SEC-B2B-MFA-RECOVERY","lf_ops.politicas_seguridad","security_policy_id=20")]
      original={keys[0][0]:snap["rule"]["sha256"],keys[1][0]:snap["policy"]["sha256"]}
      for code,tbl,pred in keys:
        self.assertEqual(sql(sh(tbl,pred)),[original[code]],"SOURCE_SNAPSHOT_DRIFT:"+code)
      rule=patch["rule"]; policy=patch["policy"]
      for count in (1,2):
        # All DDL and DML below occurs only on disposable Docker Postgres.
        tx=["BEGIN;"]
        tx.append("UPDATE lf_ops.reglas SET titulo="+q(rule["title"])+
            ",descripcion="+q(rule["description"])+
            ",pendiente_detalle="+q(rule["pending_detail"])+
            ",valor_config=valor_config || "+j(rule["config_set"])+
            " WHERE codigo='B2B-RULE-AUTH-020';")
        cfg=dict(policy["config_set"])
        cfg["approvers_required"]=count
        tx.append("UPDATE lf_ops.politicas_seguridad SET description="+q(policy["description"])+
            ",policy_config=policy_config || "+j(cfg)+
            ",parameter_provenance=COALESCE(parameter_provenance,'{}'::jsonb) || "+
             j(policy["parameter_provenance_patch"])+ " WHERE security_policy_id=20;")
        # Guard at database parameter boundary and permissions by connected profile.
        tx.append("CREATE TEMP TABLE recovery_approvers_parameter(value integer NOT NULL CHECK (value IN (1,2)));")
        tx.append("INSERT INTO recovery_approvers_parameter VALUES ("+str(count)+");")
        tx.append("""CREATE TEMP TABLE b2b_recovery_profile_permissions(
          profile_id bigint PRIMARY KEY,
          can_create boolean NOT NULL,
          can_approve boolean NOT NULL,
          enabled boolean NOT NULL
        );""")
        tx.append("INSERT INTO b2b_recovery_profile_permissions VALUES (1,true,true,true),(2,false,true,true);")
        # Same actor may act twice ONLY with both permissions and central value=1.
        tx.append("""SELECT 'SAME|' || CASE
           WHEN (SELECT can_create AND can_approve AND enabled
                 FROM b2b_recovery_profile_permissions WHERE profile_id=1)
             AND (SELECT (policy_config->>'approvers_required')::integer=1
                  FROM lf_ops.politicas_seguridad WHERE security_policy_id=20)
           THEN 'ALLOW' ELSE 'BLOCK' END;""")
        # Distinct creator and approver are allowed when both have respective permissions.
        tx.append("""SELECT 'DISTINCT|' || CASE WHEN
           (SELECT can_create AND enabled FROM b2b_recovery_profile_permissions WHERE profile_id=1)
           AND (SELECT can_approve AND enabled FROM b2b_recovery_profile_permissions WHERE profile_id=2)
           AND 'actor-creator' <> 'actor-approver'
           THEN 'ALLOW' ELSE 'BLOCK' END;""")
        tx.append("""SELECT 'CONTROLS|' || CASE WHEN
             (policy_config->>'audit_events')='REQUIRED_FOR_BOTH_VALUES'
             AND (policy_config->>'recovery_wait_hours')::integer=48
             AND policy_config->'notice_previous_contact' ? 'PHONE'
             AND policy_config->'notice_previous_contact' ? 'EMAIL'
             AND (policy_config->>'approvers_required')::integer IN (1,2)
             AND parameter_provenance ? 'approvers_required'
             THEN 'PASS' ELSE 'FAIL' END
           FROM lf_ops.politicas_seguridad WHERE security_policy_id=20;""")
        for code,tbl,pred in keys:
          tx.append("SELECT "+q("DURING|"+code+"|")+"||"+
                "encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),"
                "'sha256'),'hex') FROM "+tbl+" t WHERE "+pred+";")
        tx.append("ROLLBACK;")
        for code,tbl,pred in keys:
          tx.append("SELECT "+q("AFTER|"+code+"|")+"||"+
                "encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),"
                "'sha256'),'hex') FROM "+tbl+" t WHERE "+pred+";")
        out=sql("\n".join(tx))
        results={}
        for line in out:
          if "|" in line:
            typ,value=line.split("|",1);results.setdefault(typ,[]).append(value)
        self.assertEqual(results.get("SAME"),["ALLOW" if count==1 else "BLOCK"])
        self.assertEqual(results.get("DISTINCT"),["ALLOW"])
        self.assertEqual(results.get("CONTROLS"),["PASS"])
        inside={k.split("|",1)[0]:k.split("|",1)[1] for k in results.get("DURING",[])}
        after={k.split("|",1)[0]:k.split("|",1)[1] for k in results.get("AFTER",[])}
        self.assertEqual(set(inside),set(original));self.assertEqual(set(after),set(original))
        for code in original:
          self.assertRegex(inside[code],r"^[0-9a-f]{64}$")
          self.assertNotEqual(inside[code],original[code])
          self.assertEqual(after[code],original[code])
          print("AUTH020_APPROVAL_LAB|"+image+"|"+str(count)+"|"+code+"|"+
             original[code]+"|"+inside[code]+"|"+after[code]+"|PASS",flush=True)
        print("PASS_AUTH020_APPROVERS_REQUIRED_"+str(count)+"_"+image.replace(":","_"),flush=True)
        if os.environ.get("GITHUB_STEP_SUMMARY"):
          with open(os.environ["GITHUB_STEP_SUMMARY"],"a",encoding="utf-8") as f:
            f.write("\n### AUTH-020 policy20 approvers_required="+str(count)+", "+image+"\n\n")
            f.write("| Fila | SHA antes | SHA dentro TX | SHA tras ROLLBACK | Estado |\n|---|---|---|---|---|\n")
            for code in original:
              f.write("| "+code+" | "+original[code]+" | "+inside[code]+" | "+after[code]+" | PASS |\n")
    finally:
      subprocess.run(["docker","rm","-f",cid],capture_output=True,text=True,timeout=40)
 def test_pg_17_6(self): self.run_pg("postgres:17.6","170006")
 def test_pg_18_7(self): self.run_pg("postgres:18.7","180007")
if __name__=="__main__": unittest.main()
