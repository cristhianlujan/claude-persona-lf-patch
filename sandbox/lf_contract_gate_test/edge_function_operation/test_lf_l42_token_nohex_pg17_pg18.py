#!/usr/bin/env python3
"""L42: literal color → named design tokens; 6 staged rows, dual PG rollback.
No connection or writer to live Supabase. VIGENTE rows staged as proposals only.
"""
from __future__ import annotations
import json,re,shutil,subprocess,time,unittest,uuid,os
from pathlib import Path
HERE=Path(__file__).resolve().parent
SOURCE=HERE/"fixtures/lf_l42_color_token_mapping_and_staged_patches.json"
def quote(x): return "'"+str(x).replace("'","''")+"'"
def qjson(x): return quote(json.dumps(x,ensure_ascii=False,separators=(",",":")))+"::jsonb"
RE_COL=r"#[[:xdigit:]]{8}([^[:xdigit:]]|$)|#[[:xdigit:]]{6}([^[:xdigit:]]|$)|#[[:xdigit:]]{3}([^[:xdigit:]]|$)|(rgba?|hsla?)[[:space:]]*\("
class L42LiteralNoHex(unittest.TestCase):
 def trial(self,image,version):
    self.assertTrue(shutil.which("docker"),"Docker required, no live fallback")
    src=json.loads(SOURCE.read_text(encoding="utf8"))
    changes=src["changes"]
    self.assertEqual(len(changes),6)
    self.assertEqual({x["code"] for x in changes},{
      "UX-GAMIF-TERMOMETRO-01","UX-RUTA-ACCESIBILIDAD-01",
      "UX-RUTA-ESTADOS-01","UX-TOKEN-CONSOLIDACION-01",
      "link_inline_default","text_button_primary"})
    self.assertFalse(src["identity_verified"])
    self.assertEqual([x["status"] for x in changes].count("STAGED_BLOCKED_MISSING_2_COLOR_TOKENS"),1)
    self.assertEqual([x["source_state"] for x in changes].count("VIGENTE"),4)
    known={x["token_name"]:x["hex_value"] for x in src["color_tokens"] if x["status"]=="VIGENTE"}
    for actual,token in src["confirmed_mapping"].items():
       self.assertEqual(known.get(token),actual,"CANONICAL_EXISTING_TOKEN_MISMATCH")
    for old,name in src["missing_mapping"].items():
       self.assertNotIn(name,known,"MISSING_TOKEN_INCORRECTLY_PRESENT")
    for item in changes:
       text=json.dumps(item["proposed"],ensure_ascii=False)
       self.assertNotRegex(text,r"#[0-9a-fA-F]{3,8}\b|(rgba?|hsla?)\s*\(")
       self.assertTrue(item["source_sha256"])
    cname="lf-l42-color-"+uuid.uuid4().hex[:10]
    run=subprocess.run(["docker","run","--rm","-d","--name",cname,
      "-e","POSTGRES_PASSWORD=postgres","-e","POSTGRES_DB=postgres",image],
      capture_output=True,text=True,timeout=240)
    self.assertEqual(run.returncode,0,run.stderr[-3000:])
    try:
      def sql(code):
        p=subprocess.run(["docker","exec","-i",cname,"psql","-X","-q","-A","-t","-v","ON_ERROR_STOP=1",
         "-U","postgres","-d","postgres"],input=code,capture_output=True,text=True,timeout=300)
        self.assertEqual(p.returncode,0,p.stderr[-3700:])
        return [l.strip() for l in p.stdout.splitlines() if l.strip()]
      for i in range(90):
        if subprocess.run(["docker","exec",cname,"pg_isready","-U","postgres"],
         capture_output=True,timeout=10).returncode==0:break
        time.sleep(1)
      else:self.fail("PG_NOT_READY")
      self.assertEqual(sql("SHOW server_version_num;"),[version])
      tables={x["type"]:{"RULE":("lf_ops","reglas","codigo"),"COMPONENT":("lf_design","component_tokens","component_token_code"),
          "TYPOGRAPHY":("lf_design","typography_tokens","token_name")}[x["type"]] for x in changes}
      setup=["CREATE SCHEMA lf_ops; CREATE SCHEMA lf_design; CREATE SCHEMA extensions;",
        "CREATE EXTENSION pgcrypto WITH SCHEMA extensions;"]
      for schema,table,key in sorted(set(tables.values())):
        cols=[x for x in src["columns"] if x["table_schema"]==schema and x["table_name"]==table]
        self.assertTrue(cols)
        self.assertTrue(all(re.fullmatch(r"[a-z0-9_]+",x["col"]) for x in cols))
        self.assertTrue(all(x["typ"] in ("text","jsonb","integer","bigint","boolean","timestamp with time zone") for x in cols))
        ddl=",".join('"'+x["col"]+'" '+x["typ"] for x in cols)
        setup.append("CREATE TABLE "+schema+"."+table+"("+ddl+");")
      for x in changes:
        schema,table,key=tables[x["type"]]
        setup.append("INSERT INTO "+schema+"."+table+" SELECT (jsonb_populate_record(NULL::"+
         schema+"."+table+","+qjson(x["source_row"])+")).*;")
      sql("\n".join(setup))
      def gather():
        parts=[]
        for typ,(schema,tab,key) in sorted(tables.items()):
          parts.append("SELECT '"+typ+"|'||"+key+"||'|'||encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),'sha256'),'hex') "
           "FROM "+schema+"."+tab+" t ORDER BY "+key+";")
        result=sql("\n".join(parts))
        return dict(x.split("|",1) for x in result)
      # gather() result keys already TYPE|code
      before=gather()
      self.assertEqual(len(before),6)
      for x in changes:
        key=x["type"]+"|"+x["code"]
        self.assertEqual(before[key],x["source_sha256"],"SOURCE_PREIMAGE_DRIFT:"+key)
      trans=["BEGIN;"]
      for x in changes:
         schema,table,key=tables[x["type"]]
         if x["type"]=="RULE":
           update="descripcion="+quote(x["proposed"]["descripcion"])+",razon="+quote(x["proposed"]["razon"])+",valor_config="+qjson(x["proposed"]["valor_config"])
           statuskey="estado"
         else:
           update="notes="+quote(x["proposed"]["notes"])
           statuskey="status"
         trans.append("UPDATE "+schema+"."+table+" SET "+update+" WHERE "+key+"="+quote(x["code"])+
           " AND "+statuskey+"="+quote(x["source_state"])+";")
      for typ,(schema,tab,key) in sorted(tables.items()):
          trans.append("SELECT 'DURING|"+typ+"|'||"+key+"||'|'||encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),'sha256'),'hex') FROM "+schema+"."+tab+" t ORDER BY "+key+";")
      for typ,(schema,tab,key) in sorted(tables.items()):
          trans.append("SELECT 'LITERAL_CHECK|"+typ+"|'||COUNT(*) FROM "+schema+"."+tab+" t WHERE to_jsonb(t)::text ~* "+quote(RE_COL)+";")
      trans.append("SELECT 'STATE_GUARD|'||CASE WHEN "
          "(SELECT count(*) FROM lf_ops.reglas WHERE estado='VIGENTE')=2 "
          "AND (SELECT count(*) FROM lf_ops.reglas WHERE estado='CANDIDATO')=2 "
          "AND (SELECT count(*) FROM lf_design.component_tokens WHERE status='VIGENTE')=1 "
          "AND (SELECT count(*) FROM lf_design.typography_tokens WHERE status='VIGENTE')=1 "
          "THEN 'PASS' ELSE 'FAIL' END;")
      trans.append("ROLLBACK;")
      for typ,(schema,tab,key) in sorted(tables.items()):
          trans.append("SELECT 'AFTER|"+typ+"|'||"+key+"||'|'||encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),'sha256'),'hex') FROM "+schema+"."+tab+" t ORDER BY "+key+";")
      out=sql("\n".join(trans))
      self.assertIn("STATE_GUARD|PASS",out)
      for typ in tables:
          self.assertIn("LITERAL_CHECK|"+typ+"|0",out,"NON_TOKEN_LITERAL_IN_PROPOSAL:"+typ)
      def parse(prefix):
         return dict(y[len(prefix):].split("|",1) for y in out if y.startswith(prefix))
      during=parse("DURING|");after=parse("AFTER|")
      self.assertEqual(set(before),set(during));self.assertEqual(set(before),set(after))
      for key in sorted(before):
         self.assertNotEqual(during[key],before[key],"NO_UPDATE:"+key)
         self.assertEqual(after[key],before[key],"ROLLBACK_NOT_EXACT:"+key)
         print("LF_L42_SHA|"+image+"|"+key+"|"+before[key]+"|"+during[key]+"|"+after[key]+"|PASS",flush=True)
      print("PASS_LF_L42_6_STAGED_UPDATES_SQL_NO_HEX_OR_RGB_HSL_ROLLBACK_"+image.replace(":","_"),flush=True)
      if os.environ.get("GITHUB_STEP_SUMMARY"):
          with open(os.environ["GITHUB_STEP_SUMMARY"],"a",encoding="utf-8") as f:
              f.write("\n### LF L42 "+image+" — 6 staged updates with 0 HEX/RGB/HSL\n\n")
              f.write("| Row | Source SHA | During UPDATE | After ROLLBACK | Result |\n|---|---|---|---|---|\n")
              for key in sorted(before):
                  f.write("| "+key+" | "+before[key]+" | "+during[key]+" | "+after[key]+" | PASS |\n")
    finally:
      subprocess.run(["docker","rm","-f",cname],capture_output=True,text=True,timeout=75)
 def test_pg17_6(self):self.trial("postgres:17.6","170006")
 def test_pg18_7(self):self.trial("postgres:18.7","180007")
if __name__=="__main__":unittest.main()
