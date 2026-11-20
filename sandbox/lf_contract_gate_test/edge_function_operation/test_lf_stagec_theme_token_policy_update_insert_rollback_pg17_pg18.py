#!/usr/bin/env python3
"""LF THEME-002 token policy: actual UPDATE+INSERT+ROLLBACK on disposable PG17.6/18.7."""
from __future__ import annotations
import json,os,re,shutil,subprocess,time,unittest,uuid
from pathlib import Path

HERE=Path(__file__).resolve().parent
SOURCE=HERE/"fixtures/lf_stagec_theme_token_policy_snapshots_20261113.json"
PATCH=HERE/"fixtures/lf_stagec_theme_token_policy_patch_20261113.json"

def qs(x):return "'"+str(x).replace("'","''")+"'"
def qj(x):return qs(json.dumps(x,ensure_ascii=False,separators=(",",":")))+"::jsonb"

class TestThemeTokenPolicyLab(unittest.TestCase):
 def run_pg(self,image,num):
  self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
  src=json.loads(SOURCE.read_text(encoding="utf8"))
  doc=json.loads(PATCH.read_text(encoding="utf8"))
  self.assertFalse(src["identity_verified"])
  self.assertFalse(doc["identity_verified"])
  self.assertEqual(doc["policy_table_selected"],"private.lf_reusable_policy_registry_v1")
  self.assertEqual(len(src["color_tokens"]),3)
  self.assertEqual(len(doc["role_approval"]["rows"]),3)
  self.assertFalse(doc["role_approval"]["role_registered"])
  self.assertEqual(doc["role_approval"]["state"],"OBJECT_NEW_DESIGN_ONLY")
  self.assertEqual(doc["role_approval"]["role_permission_code_proposed"],"LF_DESIGN_TOKEN_APPROVE")
  self.assertNotRegex(json.dumps(doc,ensure_ascii=False),r"#[0-9A-Fa-f]{6}")
  cid="lf-theme-"+uuid.uuid4().hex[:10]
  r=subprocess.run(["docker","run","-d","--rm","--name",cid,"-e",
         "POSTGRES_PASSWORD=postgres","-e","POSTGRES_DB=postgres",image],
         capture_output=True,text=True,timeout=240)
  self.assertEqual(r.returncode,0,r.stderr)
  try:
   def sql(s):
    t=subprocess.run(["docker","exec","-i",cid,"psql","-X","-q","-t","-A","-v",
         "ON_ERROR_STOP=1","-U","postgres","-d","postgres"],input=s,
         capture_output=True,text=True,timeout=320)
    self.assertEqual(t.returncode,0,"SQL_FAILED:"+t.stderr[-4000:])
    return [x.strip() for x in t.stdout.splitlines() if x.strip()]
   for _ in range(90):
    if subprocess.run(["docker","exec",cid,"pg_isready","-U","postgres"],capture_output=True,timeout=10).returncode==0:break
    time.sleep(1)
   else:self.fail("PG_NOT_READY")
   self.assertEqual(sql("SHOW server_version_num;"),[num])
   cols={}
   for c in src["columns"]:
    self.assertRegex(c["schema"],r"^(private|lf_ops|lf_design)$")
    self.assertRegex(c["tab"],r"^(lf_reusable_policy_registry_v1|reglas|color_tokens|theme_bindings)$")
    self.assertRegex(c["col"],r"^[a-z0-9_]+$")
    self.assertRegex(c["typ"],r"^(text|text\[\]|integer|bigint|boolean|jsonb|timestamp with time zone)$")
    cols.setdefault((c["schema"],c["tab"]),[]).append('"'+c["col"]+'" '+c["typ"])
   ddl=["CREATE SCHEMA private;","CREATE SCHEMA lf_ops;","CREATE SCHEMA lf_design;",
        "CREATE SCHEMA extensions;","CREATE EXTENSION pgcrypto WITH SCHEMA extensions;"]
   for (schema,table),fields in cols.items():
    ddl.append("CREATE TABLE "+schema+"."+table+"("+",".join(fields)+");")
   ddl.append("""CREATE TABLE lf_design.token_identity_role_approvals_candidate(
      token_name text PRIMARY KEY,
      design_system_code text NOT NULL,
      status text NOT NULL,
      role_permission_code text NOT NULL,
      approval_actor_verified boolean NOT NULL,
      aa_contrast_verified boolean NOT NULL,
      token_value_source text NOT NULL,
      owner_decision_ref text NOT NULL
     );""")
   sql("\n".join(ddl))
   preload=[]
   rows=[
    ("private","lf_reusable_policy_registry_v1",src["existing_policy"]["snapshot"]),
    ("lf_ops","reglas",src["theme_rule"]["snapshot"]),
    ("lf_design","theme_bindings",src["binding"]["snapshot"])
   ]+[("lf_design","color_tokens",x["snapshot"]) for x in src["color_tokens"]]
   for schema,table,row in rows:
    typ=schema+"."+table
    preload.append("INSERT INTO "+typ+" SELECT (jsonb_populate_record(NULL::"+typ+","+qj(row)+")).*;")
   sql("\n".join(preload))
   key_policy="LF-DESIGN-TOKEN-REFERENCE-POLICY-V1"
   key_rule="B2B-RULE-THEME-002"
   token_keys=[x["snapshot"]["token_name"] for x in src["color_tokens"]]
   def select_hash(table,where):
    return ("SELECT encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),"
            "'sha256'),'hex') FROM "+table+" t WHERE "+where+";")
   def gethash(table,where):
    return sql(select_hash(table,where))
   baseline={key_policy:src["existing_policy"]["sha256"],
             key_rule:src["theme_rule"]["sha256"],
             "LF_B2B_THEME_DARK":src["binding"]["sha256"]}
   for token in src["color_tokens"]:
    baseline[token["snapshot"]["token_name"]]=token["sha256"]
   defs={key_policy:("private.lf_reusable_policy_registry_v1","policy_code="+qs(key_policy)),
         key_rule:("lf_ops.reglas","codigo="+qs(key_rule)),
         "LF_B2B_THEME_DARK":("lf_design.theme_bindings","theme_binding_code='LF_B2B_THEME_DARK'")}
   for token in token_keys:defs[token]=("lf_design.color_tokens","token_name="+qs(token))
   for key,(table,where) in defs.items():
    self.assertEqual(gethash(table,where),[baseline[key]],"LIVE_PREIMAGE_SHA_MISMATCH:"+key)
   for token in token_keys:
    self.assertEqual(sql("SELECT status||'|'||coalesce(hex_value,'NULL')||'|'||coalesce(rgb_value,'NULL') FROM lf_design.color_tokens WHERE token_name="+qs(token)),
     ["PENDIENTE_DECISION_FINAL|NULL|NULL"])
   self.assertEqual(gethash("lf_design.token_identity_role_approvals_candidate","TRUE"),[])
   original_constraints=src["existing_policy"]["snapshot"]["execution_constraints"]
   added=doc["policy"]["new_execution_constraints"]
   self.assertFalse(set(added).intersection(original_constraints))
   combined=original_constraints+added
   tx=["BEGIN;"]
   tx.append("UPDATE private.lf_reusable_policy_registry_v1 SET status='CANDIDATO',"+
      "semantic_descriptor="+qs(doc["policy"]["semantic_descriptor"])+
      ",execution_constraints="+qj(combined)+" WHERE policy_code="+qs(key_policy)+";")
   theme=doc["theme_rule"]
   tx.append("UPDATE lf_ops.reglas SET titulo="+qs(theme["title"])+
     ",descripcion="+qs(theme["description"])+
     ",pendiente_detalle="+qs(theme["pending_detail"])+
     ",valor_config=valor_config || "+qj(theme["config_set"])+
     " WHERE codigo="+qs(key_rule)+";")
   for row in doc["role_approval"]["rows"]:
    tx.append("INSERT INTO lf_design.token_identity_role_approvals_candidate SELECT ("+
      "jsonb_populate_record(NULL::lf_design.token_identity_role_approvals_candidate,"+
      qj(row)+")).*;")
   tx.append("""SELECT 'GUARD|'
      || CASE WHEN status='CANDIDATO'
          AND execution_constraints ? 'COLOR_TOKEN_LITERAL_VALUE_SOURCE_ONLY_LF_DESIGN_COLOR_TOKENS'
          AND execution_constraints ? 'LF_VISUAL_RULES_AND_COMPONENTS_STORE_CANONICAL_TOKEN_NAMES_ONLY'
          THEN 'PASS' ELSE 'FAIL' END
     FROM private.lf_reusable_policy_registry_v1
     WHERE policy_code='LF-DESIGN-TOKEN-REFERENCE-POLICY-V1';""")
   tx.append("""SELECT 'ROLE|'||CASE WHEN
        COUNT(*)=3 AND BOOL_AND(NOT approval_actor_verified)
        AND BOOL_AND(NOT aa_contrast_verified)
        AND BOOL_AND(status='CANDIDATE_PENDING_ROLE_VERIFICATION_AND_AA')
        AND BOOL_AND(token_value_source='lf_design.color_tokens')
        THEN 'PASS' ELSE 'FAIL' END
      FROM lf_design.token_identity_role_approvals_candidate;""")
   for key,(table,where) in defs.items():
    tx.append("SELECT "+qs("DURING|"+key+"|")+"||"+
      "encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),"
      "'sha256'),'hex') FROM "+table+" t WHERE "+where+";")
   for token in token_keys:
    table="lf_design.token_identity_role_approvals_candidate"
    tx.append("SELECT "+qs("DURING|ROLE_APPROVAL:"+token+"|")+"||"+
      "encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),"+
      "'sha256'),'hex') FROM "+table+" t WHERE token_name="+qs(token)+";")
   tx.append("ROLLBACK;")
   for key,(table,where) in defs.items():
    tx.append("SELECT "+qs("AFTER|"+key+"|")+"||"+
      "encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),"+
      "'sha256'),'hex') FROM "+table+" t WHERE "+where+";")
   for token in token_keys:
    tx.append("SELECT "+qs("AFTER|ROLE_APPROVAL:"+token+"|")+"||"+
      "coalesce((SELECT encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),"+
      "'sha256'),'hex') FROM lf_design.token_identity_role_approvals_candidate"+
      " t WHERE token_name="+qs(token)+"),'ABSENT');")
   lines=sql("\n".join(tx))
   inside={};after={};flags={}
   for line in lines:
    if line.startswith("GUARD|") or line.startswith("ROLE|"):
      name,val=line.split("|",1);flags[name]=val
    if line.startswith("DURING|"):
      _,key,val=line.split("|",2);inside[key]=val
    if line.startswith("AFTER|"):
      _,key,val=line.split("|",2);after[key]=val
   self.assertEqual(flags,{"GUARD":"PASS","ROLE":"PASS"})
   self.assertEqual(set(inside),set(baseline)|{"ROLE_APPROVAL:"+x for x in token_keys})
   self.assertEqual(set(after),set(inside))
   for key in inside:
    orig=baseline.get(key,"ABSENT")
    self.assertRegex(inside[key],r"^[0-9a-f]{64}$")
    self.assertEqual(after[key],orig,"ROLLBACK_READBACK_FAILED:"+key)
    if key not in token_keys and key!="LF_B2B_THEME_DARK":
      self.assertNotEqual(inside[key],orig,"NO_CHANGE_WITHIN_TX:"+key)
    else:
      self.assertEqual(inside[key],orig,"TOKEN_OR_BINDING_CHANGED:"+key)
    print("LF_THEMEC_LAB|"+image+"|"+key+"|"+orig+"|"+inside[key]+"|"+after[key]+"|PASS",flush=True)
   print("PASS_LF_THEMEC_UPDATE_INSERT_ROLLBACK_"+image.replace(":","_"),flush=True)
   if os.environ.get("GITHUB_STEP_SUMMARY"):
    with open(os.environ["GITHUB_STEP_SUMMARY"],"a",encoding="utf8") as f:
     f.write("\n### LF THEME token policy rollback "+image+"\n\n")
     f.write("| Fila | Antes | Dentro TX | Después ROLLBACK | Resultado |\n|---|---|---|---|---|\n")
     for key in inside:
      f.write("| "+key+" | "+baseline.get(key,"ABSENT")+" | "+inside[key]+" | "+after[key]+" | PASS |\n")
  finally:
   subprocess.run(["docker","rm","-f",cid],text=True,capture_output=True,timeout=45)
 def test_pg_17_6(self):self.run_pg("postgres:17.6","170006")
 def test_pg_18_7(self):self.run_pg("postgres:18.7","180007")
if __name__=="__main__":unittest.main()
