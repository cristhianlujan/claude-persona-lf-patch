#!/usr/bin/env python3
"""Stage D: role receipts with candidate values, no live writes; isolated PG17.6/18.7."""
from __future__ import annotations
import json,math,os,re,shutil,subprocess,time,unittest,uuid
from pathlib import Path

HERE=Path(__file__).resolve().parent
SOURCE=HERE/"fixtures/lf_stagec_theme_token_policy_snapshots_20261113.json"
PATCH=HERE/"fixtures/lf_staged_theme_approved_visual_candidates_role_receipts_20261113.json"
VIGENT=HERE/"fixtures/lf_staged_source_vigente_tokens_20261113.json"

def qs(x):return "'"+str(x).replace("'","''")+"'"
def qj(x):return qs(json.dumps(x,separators=(",",":"),ensure_ascii=False))+"::jsonb"
def lum(hexstr):
    a=[int(hexstr[i:i+2],16)/255 for i in (1,3,5)]
    a=[x/12.92 if x<=0.04045 else ((x+0.055)/1.055)**2.4 for x in a]
    return .2126*a[0]+.7152*a[1]+.0722*a[2]
def ratio(c1,c2):
    x,y=sorted((lum(c1),lum(c2)));return (y+0.05)/(x+0.05)

class TestStageDDarkFinal(unittest.TestCase):
 def run_pg(self,image,num):
    src=json.loads(SOURCE.read_text(encoding="utf8"))
    patch=json.loads(PATCH.read_text(encoding="utf8"))
    raw=json.loads(VIGENT.read_text(encoding="utf8"))
    self.assertFalse(patch["provenance"]["identity_verified"])
    self.assertIsNone(patch["provenance"]["profile_execution_id"])
    self.assertFalse(patch["provenance"]["profile_runtime_enabled"])
    self.assertTrue(patch["constraints"]["no_hex_in_rules"])
    self.assertEqual(len(patch["role_approval_receipts"]),3)
    for receipt in patch["role_approval_receipts"]:
        self.assertRegex(receipt["proposal_hex"],r"^#[0-9A-Fa-f]{6}$")
        self.assertFalse(receipt["role_verified"])
        self.assertFalse(receipt["qa_visual_verified"])
        self.assertEqual(receipt["source_value_status"],"PENDIENTE_DECISION_FINAL")
    v={r["token_name"]:r["hex_value"] for r in raw["tokens"]}
    self.assertEqual(set(v),{"green_action_hover","border_soft","green_action_border","card_surface","slate_text","slate_text_strong"})
    self.assertTrue(all(r["status"]=="VIGENTE" for r in raw["tokens"]))
    proposed={r["token_name"]:r["proposal_hex"] for r in patch["role_approval_receipts"]}
    colors={**v,**proposed}
    b=patch["binding_proposal_tokens_only"]
    ratios={
      "primary_text_over_card":ratio(colors[b["primary_text"]],colors[b["background_card"]]),
      "secondary_text_over_card":ratio(colors[b["secondary_text"]],colors[b["background_card"]]),
      "button_over_card":ratio(colors[b["button_background"]],colors[b["background_card"]]),
      "button_text_over_button":ratio(colors[b["button_label"]],colors[b["button_background"]]),
      "border_over_card":ratio(colors[b["input_border"]],colors[b["background_card"]]),
      "focus_over_card":ratio(colors[b["focus_ring"]],colors[b["background_card"]]),
    }
    self.assertEqual(b["secondary_text"],"dark_mode_text")
    self.assertEqual(b["button_background"],"green_action_hover")
    self.assertEqual(b["button_label"],"card_surface")
    for k,vv in ratios.items():
        floor=4.5 if "text_over" in k or k=="button_text_over_button" else 3.3 if k=="button_over_card" else 3.0
        self.assertGreaterEqual(vv,floor,"WCAG_FAILED:"+k)
        print("LF_DARK_FINAL_RATIO|"+image+"|"+k+"|"+format(vv,".4f")+"|minimum="+str(floor)+"|PASS",flush=True)
    for bad in ("slate_text","slate_text_strong"):
        r=ratio(colors[bad],colors["dark_mode_card"])
        self.assertLess(r,4.5,"UNEXPECTED_SECONDARY_PASS:"+bad)
        print("LF_DARK_FINAL_REJECTED|"+image+"|"+bad+"|"+format(r,".4f")+"|AA_NO",flush=True)
    self.assertLess(ratio(colors["green_action_hover"],"#141627"),3.3)
    self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
    cid="lf-stage-d-"+uuid.uuid4().hex[:9]
    p=subprocess.run(["docker","run","-d","--rm","--name",cid,
       "-e","POSTGRES_PASSWORD=postgres","-e","POSTGRES_DB=postgres",image],
       capture_output=True,text=True,timeout=230)
    self.assertEqual(p.returncode,0,p.stderr)
    try:
     def sql(s):
      r=subprocess.run(["docker","exec","-i",cid,"psql","-X","-q","-t","-A",
                        "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
                        input=s,capture_output=True,text=True,timeout=280)
      self.assertEqual(r.returncode,0,"SQL_FAILED:"+r.stderr[-4000:])
      return [x.strip() for x in r.stdout.splitlines() if x.strip()]
     for _ in range(90):
      if subprocess.run(["docker","exec",cid,"pg_isready","-U","postgres"],capture_output=True,timeout=10).returncode==0:break
      time.sleep(1)
     else:self.fail("PG_NOT_READY")
     self.assertEqual(sql("SHOW server_version_num;"),[num])
     cols={}
     needed={"reglas":"lf_ops","color_tokens":"lf_design","theme_bindings":"lf_design"}
     for c in src["columns"]:
       if c["tab"] not in needed:continue
       self.assertRegex(c["col"],r"^[a-z0-9_]+$")
       self.assertRegex(c["typ"],r"^(text|text\[\]|integer|bigint|boolean|jsonb|timestamp with time zone)$")
       cols.setdefault((c["schema"],c["tab"]),[]).append('"'+c["col"]+'" '+c["typ"])
     ddl=["CREATE SCHEMA lf_ops;","CREATE SCHEMA lf_design;","CREATE SCHEMA extensions;",
          "CREATE EXTENSION pgcrypto WITH SCHEMA extensions;"]
     for (schema,table),cl in cols.items():
       ddl.append("CREATE TABLE "+schema+"."+table+"("+",".join(cl)+");")
     ddl.append("""CREATE TABLE lf_design.theme_token_role_candidate_receipts_lab(
       receipt_ref text PRIMARY KEY,token_name text NOT NULL,design_system_code text NOT NULL,
       proposal_hex text NOT NULL CHECK(proposal_hex ~ '^#[0-9A-Fa-f]{6}$'),
       status text NOT NULL,source_value_status text NOT NULL,
       role_verified boolean NOT NULL,qa_visual_verified boolean NOT NULL,
       decision_ref text NOT NULL,identity_verified boolean NOT NULL
       );""")
     sql("\n".join(ddl))
     rows=[("lf_ops","reglas",src["theme_rule"]["snapshot"]),
           ("lf_design","theme_bindings",src["binding"]["snapshot"])]
     rows += [("lf_design","color_tokens",r["snapshot"]) for r in src["color_tokens"]]
     sql("\n".join("INSERT INTO "+sc+"."+tab+
         " SELECT (jsonb_populate_record(NULL::"+sc+"."+tab+","+qj(row)+")).*;"
         for sc,tab,row in rows))
     before={"B2B-RULE-THEME-002":src["theme_rule"]["sha256"],
             "LF_B2B_THEME_DARK":src["binding"]["sha256"]}
     before.update({r["snapshot"]["token_name"]:r["sha256"] for r in src["color_tokens"]})
     refs={"B2B-RULE-THEME-002":("lf_ops.reglas","codigo='B2B-RULE-THEME-002'"),
           "LF_B2B_THEME_DARK":("lf_design.theme_bindings","theme_binding_code='LF_B2B_THEME_DARK'")}
     for t in src["color_tokens"]:
        k=t["snapshot"]["token_name"];refs[k]=("lf_design.color_tokens","token_name="+qs(k))
     def hash_select(tbl,where):
        return ("SELECT encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),"+
          "'sha256'),'hex') FROM "+tbl+" t WHERE "+where+";")
     for key,(table,where) in refs.items():
       self.assertEqual(sql(hash_select(table,where)),[before[key]],"PREIMAGE_MISMATCH:"+key)
     tx=["BEGIN;"]
     # No literal values in THEME-002 rule. Color proposals exclusively in candidate receipts.
     rule_delta={"candidate_receipts_ref":"lf_design.theme_token_role_candidate_receipts_lab",
       "candidate_receipts_status":"PROPOSED_ONLY_NOT_ROLE_VERIFIED",
       "required_tokens":[r["token_name"] for r in patch["role_approval_receipts"]],
       "primary_action_token":"green_action_hover","primary_action_text_token":"card_surface",
       "secondary_text_token":"dark_mode_text","border_token":"border_soft",
       "focus_token":"green_action_border","aa_pending_qa":True}
     new_desc=("Modo noche CANDIDATO: referencias por nombre a dark_mode_surface, "+
       "dark_mode_card y dark_mode_text; valores candidatos únicamente en recibos "+
       "de diseño, sin valores literales en la regla. Botón green_action_hover con "+
       "card_surface para texto; texto secundario dark_mode_text; borde border_soft "+
       "y foco green_action_border. Promoción condicionada a autoridad por rol, "+
       "contraste AA y QA real; no promover por esta propuesta.")
     self.assertNotRegex(new_desc+json.dumps(rule_delta),r"#[0-9A-Fa-f]{6}")
     tx.append("UPDATE lf_ops.reglas SET descripcion="+qs(new_desc)+
       ",valor_config=valor_config || "+qj(rule_delta)+
       " WHERE codigo='B2B-RULE-THEME-002';")
     for receipt in patch["role_approval_receipts"]:
       tx.append("INSERT INTO lf_design.theme_token_role_candidate_receipts_lab SELECT "+
        "(jsonb_populate_record(NULL::lf_design.theme_token_role_candidate_receipts_lab,"+
        qj(receipt)+")).*;")
     tx.append("""SELECT 'RECEIPT_GUARD|'|| CASE WHEN count(*)=3 AND
         bool_and(NOT role_verified) AND bool_and(NOT qa_visual_verified)
         AND bool_and(status='CANDIDATE_PROPOSED_PENDING_ROLE_AND_AA_QA')
         THEN 'PASS' ELSE 'FAIL' END
         FROM lf_design.theme_token_role_candidate_receipts_lab;""")
     for key,(table,where) in refs.items():
       tx.append("SELECT "+qs("DURING|"+key+"|")+
         "||encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),"+
         "'sha256'),'hex') FROM "+table+" t WHERE "+where+";")
     for receipt in patch["role_approval_receipts"]:
       token=receipt["token_name"];name="ROLE_RECEIPT:"+token
       tx.append("SELECT "+qs("DURING|"+name+"|")+
         "||encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),"+
         "'sha256'),'hex') FROM lf_design.theme_token_role_candidate_receipts_lab "+
         "t WHERE token_name="+qs(token)+";")
     tx.append("ROLLBACK;")
     for key,(table,where) in refs.items():
       tx.append("SELECT "+qs("AFTER|"+key+"|")+
         "||encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),"+
         "'sha256'),'hex') FROM "+table+" t WHERE "+where+";")
     for receipt in patch["role_approval_receipts"]:
       token=receipt["token_name"];name="ROLE_RECEIPT:"+token
       tx.append("SELECT "+qs("AFTER|"+name+"|")+
          "||coalesce((SELECT encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),"+
          "'sha256'),'hex') FROM lf_design.theme_token_role_candidate_receipts_lab t"+
          " WHERE token_name="+qs(token)+"),'ABSENT');")
     output=sql("\n".join(tx));during={};after={};guard=None
     for item in output:
       if item.startswith("DURING|"):
         _,key,h=item.split("|",2);during[key]=h
       elif item.startswith("AFTER|"):
         _,key,h=item.split("|",2);after[key]=h
       elif item.startswith("RECEIPT_GUARD|"):guard=item.split("|")[1]
     self.assertEqual(guard,"PASS")
     allkeys=set(before)|{"ROLE_RECEIPT:"+r["token_name"] for r in patch["role_approval_receipts"]}
     self.assertEqual(set(during),allkeys);self.assertEqual(set(after),allkeys)
     for key in sorted(allkeys):
       orig=before.get(key,"ABSENT")
       self.assertRegex(during[key],r"^[0-9a-f]{64}$")
       self.assertEqual(after[key],orig,"ROLLBACK_NOT_EXACT:"+key)
       if key.startswith("ROLE_RECEIPT:") or key=="B2B-RULE-THEME-002":self.assertNotEqual(during[key],orig)
       else:self.assertEqual(during[key],orig,"CANONICAL_TOKEN_MUTATED:"+key)
       print("LF_STAGE_D_TX|"+image+"|"+key+"|"+orig+"|"+during[key]+"|"+after[key]+"|PASS",flush=True)
     print("PASS_LF_STAGE_D_PROPOSAL_UPDATE_INSERT_ROLLBACK_"+image.replace(":","_"),flush=True)
     if os.environ.get("GITHUB_STEP_SUMMARY"):
      with open(os.environ["GITHUB_STEP_SUMMARY"],"a",encoding="utf8") as f:
       f.write("\n### Stage D dark candidate "+image+"\n\n")
       f.write("| Fila | Antes | Dentro TX | Tras ROLLBACK | Resultado |\n|---|---|---|---|---|\n")
       for k in sorted(allkeys):
        f.write("| "+k+" | "+before.get(k,"ABSENT")+" | "+during[k]+" | "+after[k]+" | PASS |\n")
       f.write("\nRATIO (source VIGENTE + candidate proposal only):\n")
       for k,vv in ratios.items():f.write("- "+k+": "+format(vv,".4f")+"\n")
    finally:
      subprocess.run(["docker","rm","-f",cid],capture_output=True,text=True,timeout=45)
 def test_pg17_6(self):self.run_pg("postgres:17.6","170006")
 def test_pg18_7(self):self.run_pg("postgres:18.7","180007")
if __name__=="__main__": unittest.main()
