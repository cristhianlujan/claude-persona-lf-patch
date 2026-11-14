#!/usr/bin/env python3
"""L41: 260 source-anchored rows, 3 updates, real policy provenance guard, full rollback.
PG17.6 / PG18.7 only in disposable Docker. Never writes to live Supabase.
"""
from __future__ import annotations
import json,os,re,shutil,subprocess,time,unittest,uuid
from pathlib import Path
HERE=Path(__file__).resolve().parent
FIX=HERE/"fixtures"
SRC_NAMES=[f"lf_l41_rules_slice_{i:02d}_source.json" for i in range(4)]
POLICY=FIX/"lf_l41_policies_rate_guard_source.json"
PATCH=FIX/"lf_l41_remaining_conflicts_patch.json"
INV=HERE.parents[2]/"audits/login-b2b-lote41/01_inventario_260_reglas_politicas_estado_choque.json"
def q(v): return "'"+str(v).replace("'","''")+"'"
def jb(v): return q(json.dumps(v,separators=(",",":"),ensure_ascii=False))+"::jsonb"
def sha(table,key):
    return ("SELECT encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),'sha256'),'hex') FROM "+table+" t WHERE "+key+";")
class TestL41B2BRemaining(unittest.TestCase):
 def lab(self,image,version):
    self.assertTrue(shutil.which("docker"),"Docker required; no live fallback")
    rule_inputs=[json.loads((FIX/name).read_text(encoding="utf8")) for name in SRC_NAMES]
    rules=[item for part in rule_inputs for item in part["source_rows"]]
    pol=json.loads(POLICY.read_text(encoding="utf8"))
    patch=json.loads(PATCH.read_text(encoding="utf8"))
    inv=json.loads(INV.read_text(encoding="utf8"))
    self.assertEqual((len(rules),len(pol["policies"]),len(pol["rates"])),(226,25,9))
    self.assertEqual(len(patch["proposals"]),3)
    self.assertEqual(inv["scoped_object_counts"]["total"],260)
    self.assertFalse(patch["identity_verified"])
    targets={x["code"] for x in patch["proposals"]}
    self.assertEqual(targets,{"B2B-RULE-AUTH-044","SEC-B2B-AUTH-ABUSE-PROTECTION","SEC-B2B-PASSWORD-CREDENTIAL"})
    self.assertEqual({r["code"] for r in inv["items"] if r["choca"]=="SI"},targets)
    self.assertTrue(all(x["source_state"]=="CANDIDATO" for x in patch["proposals"]))
    self.assertTrue(all(x["code"] not in {r["code"] for r in inv["items"] if r["exclusion"]} for x in patch["proposals"]))
    rule_map={v["source_row"]["codigo"]:v["source_sha256"] for v in rules}
    sec_map={v["source_row"]["policy_code"]:v["source_sha256"] for v in pol["policies"]}
    rate_map={v["source_row"]["policy_code"]:v["source_sha256"] for v in pol["rates"]}
    self.assertEqual(len(rule_map)+len(sec_map)+len(rate_map),260)
    for p in patch["proposals"]:
        self.assertEqual(p["source_sha256"],(rule_map if p["kind"]=="RULE" else sec_map)[p["code"]])
        if p["kind"]=="SECURITY_POLICY":
            self.assertEqual(set(p["parameter_provenance_patch"]),set(p["changed_config_keys"]))
            self.assertTrue(all(x["value_status"]=="LF_PROVISIONAL" for x in p["parameter_provenance_patch"].values()))
    cname="lf-l41-"+uuid.uuid4().hex[:9]
    process=subprocess.run(["docker","run","-d","--rm","--name",cname,
         "-e","POSTGRES_PASSWORD=postgres","-e","POSTGRES_DB=postgres",image],
         capture_output=True,text=True,timeout=240)
    self.assertEqual(process.returncode,0,process.stderr[-3000:])
    try:
      def sql(src,negative=None):
        p=subprocess.run(["docker","exec","-i",cname,"psql","-q","-t","-A","-X",
            "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
            input=src,text=True,capture_output=True,timeout=300)
        if negative:
            self.assertNotEqual(p.returncode,0,"Expected PostgreSQL negative to reject")
            self.assertIn(negative,p.stderr[-3000:])
        else:
            self.assertEqual(p.returncode,0,p.stderr[-5000:])
        return [z.strip() for z in p.stdout.splitlines() if z.strip()]
      for _ in range(90):
        if subprocess.run(["docker","exec",cname,"pg_isready","-U","postgres"],
          capture_output=True,timeout=10).returncode==0: break
        time.sleep(1)
      else:self.fail("PG_NOT_READY")
      self.assertEqual(sql("SHOW server_version_num;"),[version])
      def ddl(tab):
        schema=[c for c in pol["columns"] if c["tab"]==tab]
        self.assertTrue(schema)
        self.assertTrue(all(re.fullmatch("[a-z0-9_]+",x["col"]) for x in schema))
        self.assertTrue(all(x["typ"] in ("integer","bigint","text","boolean","jsonb","timestamp with time zone") for x in schema))
        return ",".join('"'+x["col"]+'" '+x["typ"] for x in schema)
      setup=["CREATE SCHEMA lf_ops; CREATE SCHEMA extensions; CREATE SCHEMA programacion;",
             "CREATE EXTENSION pgcrypto WITH SCHEMA extensions;"]
      for t in ("reglas","politicas_seguridad","politicas_rate_limit"):
        setup.append("CREATE TABLE lf_ops."+t+"("+ddl(t)+");")
      for part,tablename in ((rules,"reglas"),(pol["policies"],"politicas_seguridad"),(pol["rates"],"politicas_rate_limit")):
        setup += ["INSERT INTO lf_ops."+tablename+" SELECT (jsonb_populate_record(NULL::lf_ops."+
          tablename+","+jb(z["source_row"])+")).*;" for z in part]
      setup += [f["ddl"]+";" for f in pol["guards"]]
      setup += ["CREATE OR REPLACE FUNCTION lf_ops.touch_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$"+
                 "BEGIN NEW.updated_at=clock_timestamp(); RETURN NEW; END;$$;"]
      setup += [x["ddl"]+";" for x in pol["triggers"]]
      sql("\n".join(setup))
      def all_hashes():
        vals=sql("SELECT 'RULE|'||codigo||'|'||encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),'sha256'),'hex') FROM lf_ops.reglas t ORDER BY codigo;"
                 "SELECT 'SEC|'||policy_code||'|'||encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),'sha256'),'hex') FROM lf_ops.politicas_seguridad t ORDER BY policy_code;"
                 "SELECT 'RATE|'||policy_code||'|'||encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),'sha256'),'hex') FROM lf_ops.politicas_rate_limit t ORDER BY policy_code;")
        return {k+"|"+n:v for k,n,v in (a.split("|",2) for a in vals)}
      before=all_hashes()
      expected={**{"RULE|"+k:v for k,v in rule_map.items()},
                **{"SEC|"+k:v for k,v in sec_map.items()},
                **{"RATE|"+k:v for k,v in rate_map.items()}}
      self.assertEqual(before,expected,"PREIMAGE_SHA_DRIFT")
      # The actual live-source policy guard must fail on changed config without updated provenance.
      sql("UPDATE lf_ops.politicas_seguridad SET policy_config=policy_config||"+
          jb({"password_failure_policy_code":"AUTH_LOGIN_FAILED_PASSWORD"})+
          " WHERE security_policy_id=22;",negative="PARAMETER_PROVENANCE_REQUIRED")
      self.assertEqual(all_hashes(),before,"INVALID_PROVENANCE_MUTATED_SOURCE")
      tx=["BEGIN;"]
      for item in patch["proposals"]:
        if item["kind"]=="RULE":
            tx.append("UPDATE lf_ops.reglas SET descripcion="+q(item["new_description"])+
             ",valor_config=coalesce(valor_config,'{}'::jsonb)||"+jb(item["config_patch"])+
             " WHERE codigo="+q(item["code"])+" AND estado='CANDIDATO';")
        else:
            tx.append("UPDATE lf_ops.politicas_seguridad SET description="+q(item["new_description"])+
             ",policy_config=policy_config||"+jb(item["config_patch"])+
             ",parameter_provenance=parameter_provenance||"+jb(item["parameter_provenance_patch"])+
             " WHERE policy_code="+q(item["code"])+" AND status='CANDIDATO';")
      for typ,tab,col in (("RULE","reglas","codigo"),("SEC","politicas_seguridad","policy_code"),("RATE","politicas_rate_limit","policy_code")):
        tx.append("SELECT 'DURING|"+typ+"|'||"+col+"||'|'||encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),'sha256'),'hex') FROM lf_ops."+tab+" t ORDER BY "+col+";")
      tx.append("SELECT 'GATES|'||CASE WHEN (SELECT policy_config->>'admin_identity_provider' FROM lf_ops.politicas_seguridad WHERE security_policy_id=24)='PENDING_ADR_003_M1_SPIKE' AND "
       "(SELECT policy_config->>'password_failure_policy_code' FROM lf_ops.politicas_seguridad WHERE security_policy_id=22)='AUTH_LOGIN_FAILED_PASSWORD' AND "
       "(SELECT valor_config->>'sms_contingency_provider' FROM lf_ops.reglas WHERE codigo='B2B-RULE-AUTH-044')='INTICO' AND "
       "(SELECT valor_config->>'sms_contingency_automatic_fallback' FROM lf_ops.reglas WHERE codigo='B2B-RULE-AUTH-044')='DENY' AND "
       "(SELECT count(*) FROM lf_ops.reglas)=226 AND (SELECT count(*) FROM lf_ops.politicas_seguridad)=25 AND "
       "(SELECT count(*) FROM lf_ops.politicas_rate_limit)=9 THEN 'PASS' ELSE 'FAIL' END;")
      tx.append("ROLLBACK;")
      for typ,tab,col in (("RULE","reglas","codigo"),("SEC","politicas_seguridad","policy_code"),("RATE","politicas_rate_limit","policy_code")):
        tx.append("SELECT 'AFTER|"+typ+"|'||"+col+"||'|'||encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),'sha256'),'hex') FROM lf_ops."+tab+" t ORDER BY "+col+";")
      out=sql("\n".join(tx))
      self.assertIn("GATES|PASS",out)
      def parse(prefix):
        return {key+"|"+n:val for key,n,val in
           (a[len(prefix):].split("|",2) for a in out if a.startswith(prefix))}
      during=parse("DURING|");after=parse("AFTER|")
      self.assertEqual(set(during),set(before))
      self.assertEqual(set(after),set(before))
      modified={"RULE|B2B-RULE-AUTH-044","SEC|SEC-B2B-AUTH-ABUSE-PROTECTION","SEC|SEC-B2B-PASSWORD-CREDENTIAL"}
      for key in sorted(before):
        self.assertRegex(during[key],r"^[0-9a-f]{64}$")
        if key in modified:
            self.assertNotEqual(during[key],before[key],"CHANGED_ROW_UNCHANGED:"+key)
            print("LF_L41_SHA|"+image+"|"+key+"|"+before[key]+"|"+during[key]+"|"+after[key]+"|PASS",flush=True)
        else:self.assertEqual(during[key],before[key],"PROTECTED_ROW_DRIFT:"+key)
        self.assertEqual(after[key],before[key],"ROLLBACK_MISMATCH:"+key)
      print("PASS_LF_L41_3_CHANGED_257_PROTECTED_REAL_PROVENANCE_"+image.replace(":","_"),flush=True)
      if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"],"a",encoding="utf8") as f:
          f.write("\n### L41 "+image+" — UPDATE+ROLLBACK (3 rows) \n\n")
          f.write("| Row | SHA before | Inside UPDATE | After rollback | Gate |\n|---|---|---|---|---|\n")
          for key in sorted(modified):
              f.write("| "+key+" | "+before[key]+" | "+during[key]+" | "+after[key]+" | PASS |\n")
    finally:
      subprocess.run(["docker","rm","-f",cname],capture_output=True,text=True,timeout=75)
 def test_pg17_6(self):self.lab("postgres:17.6","170006")
 def test_pg18_7(self):self.lab("postgres:18.7","180007")
if __name__=="__main__": unittest.main()
