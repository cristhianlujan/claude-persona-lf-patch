#!/usr/bin/env python3
"""LF owner option C: 8 rule UPDATEs + policy25 UPDATE, SHA before/in/after rollback PG17.6/18.7.
Source snapshots from live SELECT; PostgreSQL only in disposable Docker, NEVER live Supabase.
"""
from __future__ import annotations
import json, os, re, shutil, subprocess, time, unittest, uuid
from pathlib import Path
HERE=Path(__file__).resolve().parent
SNAP=HERE/"fixtures/login_b2b_lote2_source_snapshot_20261113.json"
PATCH=HERE/"fixtures/login_b2b_lote2_conflict_only_patch_20261113.json"
POLICY=HERE/"fixtures/login_b2b_lote2_option_c_policy25_20261113.json"
CODES=tuple("B2B-RULE-AUTH-"+n for n in ("013","030","033","034","039","040","041","043"))
PROTECTED=tuple("B2B-RULE-AUTH-"+n for n in ("018","019","020","021","026","047"))
def quote(s): return "'"+str(s).replace("'","''")+"'"
def jsonsql(obj): return quote(json.dumps(obj,ensure_ascii=False,separators=(",",":")))+"::jsonb"
def hashrow(table,predicate):
    return ("SELECT encode(extensions.digest(convert_to(to_jsonb(r)::text,'UTF8'),'sha256'),'hex') "
        "FROM "+table+" r WHERE "+predicate+";")
class OptionCDeviceTest(unittest.TestCase):
    def trial(self,image,version):
        self.assertTrue(shutil.which("docker"),"Docker required; no live fallback")
        src=json.loads(SNAP.read_text(encoding="utf8"))
        change=json.loads(PATCH.read_text(encoding="utf8"))
        pol=json.loads(POLICY.read_text(encoding="utf8"))
        self.assertEqual(len(src["rules"]),33)
        self.assertEqual(len(change["proposals"]),8)
        self.assertEqual(set(change["conflict_codes"]),set(CODES))
        self.assertEqual(pol["policy_id"],25)
        self.assertEqual(pol["source_status"],"CANDIDATO")
        self.assertFalse(change["owner_decision"]["identity_verified"])
        self.assertFalse(pol["identity_verified"])
        self.assertFalse(set(PROTECTED)&set(change["conflict_codes"]))
        self.assertEqual(change["non_conflicts"],["B2B-RULE-AUTH-035","B2B-RULE-AUTH-038","B2B-RULE-AUTH-042"])
        snapby={v["snapshot"]["codigo"]:v for v in src["rules"]}
        self.assertEqual(snapby["B2B-RULE-AUTH-039"]["snapshot"]["estado"],"VIGENTE")
        self.assertEqual(snapby["B2B-RULE-STATE-001"]["snapshot"]["estado"],"VIGENTE")
        for p in change["proposals"]:
            self.assertEqual(p["source_sha256"],snapby[p["code"]]["sha256"])
            self.assertEqual(p["source_status"],"VIGENTE" if p["code"].endswith("-039") else "CANDIDATO")
            self.assertNotRegex(p["proposed_description"],r"#[a-fA-F0-9]{3,8}\b")
        self.assertEqual(pol["config_patch"]["trusted_device_duration_allowed_days"],[30])
        self.assertEqual(pol["config_patch"]["trusted_device_duration_default_days"],30)
        self.assertIs(pol["config_patch"]["company_configurable"],False)
        self.assertEqual(pol["config_patch"]["always_otp_operations"],["CHANGE_EMAIL","CHANGE_PHONE","ACCESS_RECOVERY"])
        self.assertEqual(set(pol["parameter_provenance_patch"]),set(pol["config_patch"]))
        cname="lf-owner-optionc-"+uuid.uuid4().hex[:10]
        p=subprocess.run(["docker","run","-d","--rm","--name",cname,
          "-e","POSTGRES_PASSWORD=postgres","-e","POSTGRES_DB=postgres",image],
          capture_output=True,text=True,timeout=240)
        self.assertEqual(p.returncode,0,p.stderr[-3000:])
        try:
            def sql(text,expected_error=None):
                s=subprocess.run(["docker","exec","-i",cname,"psql","-X","-q","-A","-t",
                    "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
                    input=text,text=True,capture_output=True,timeout=300)
                if expected_error:
                    self.assertNotEqual(s.returncode,0,"Expected negative SQL to fail")
                    self.assertIn(expected_error,s.stderr)
                else: self.assertEqual(s.returncode,0,s.stderr[-3700:])
                return [x.strip() for x in s.stdout.splitlines() if x.strip()]
            for _ in range(90):
                ready=subprocess.run(["docker","exec",cname,"pg_isready","-U","postgres"],
                     capture_output=True,text=True,timeout=10)
                if ready.returncode==0:break
                time.sleep(1)
            else:self.fail("PG_NOT_READY")
            self.assertEqual(sql("SHOW server_version_num;"),[version])
            def ddl(columns):
                allowed={"integer","bigint","text","jsonb","boolean","timestamp with time zone"}
                self.assertTrue(all(x["typ"] in allowed and re.fullmatch("[a-z0-9_]+",x["col"]) for x in columns))
                return ",".join('"'+x["col"]+'" '+x["typ"] for x in columns)
            setup=["CREATE SCHEMA lf_ops;CREATE SCHEMA extensions; CREATE SCHEMA programacion;",
                "CREATE EXTENSION pgcrypto WITH SCHEMA extensions;",
                "CREATE TABLE lf_ops.reglas("+ddl(src["columns"])+");",
                "CREATE TABLE lf_ops.politicas_seguridad("+ddl(pol["columns"])+");"]
            setup += ["INSERT INTO lf_ops.reglas SELECT (jsonb_populate_record(NULL::lf_ops.reglas,"+
                  jsonsql(x["snapshot"])+")).*;" for x in src["rules"]]
            setup += ["INSERT INTO lf_ops.politicas_seguridad SELECT (jsonb_populate_record(NULL::lf_ops.politicas_seguridad,"+
                 jsonsql(pol["source_snapshot"])+")).*;"]
            # Real live-schema provenance function definitions from read-only pg_get_functiondef.
            setup += [f["ddl"]+";" for f in pol["postgres_live_guards"]["functions"]]
            setup += ["CREATE OR REPLACE FUNCTION lf_ops.touch_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$"
                      "BEGIN NEW.updated_at=clock_timestamp(); RETURN NEW; END;$$;"]
            setup += [t["ddl"]+";" for t in pol["postgres_live_guards"]["triggers"]]
            sql("\n".join(setup))
            byrule={v["snapshot"]["codigo"]:v["sha256"] for v in src["rules"]}
            def read_sha():
                parts=sql("SELECT codigo||'|'||encode(extensions.digest(convert_to(to_jsonb(r)::text,'UTF8'),'sha256'),'hex') "
                         "FROM lf_ops.reglas r ORDER BY codigo;")
                return dict(v.split("|",1) for v in parts)
            baseline=read_sha()
            self.assertEqual(baseline,byrule)
            pol_pre=sql(hashrow("lf_ops.politicas_seguridad","security_policy_id=25"))[0]
            self.assertEqual(pol_pre,pol["source_preimage_sha256"])
            # Negative provenance guard from live code MUST reject policy config changes without provenance.
            sql("UPDATE lf_ops.politicas_seguridad SET policy_config=policy_config||'{\"company_configurable\":false}'::jsonb "
                "WHERE security_policy_id=25;",expected_error="PARAMETER_PROVENANCE_REQUIRED")
            self.assertEqual(sql(hashrow("lf_ops.politicas_seguridad","security_policy_id=25")),[pol_pre])
            tx=["BEGIN;"]
            for entry in change["proposals"]:
                tx.append("UPDATE lf_ops.reglas SET descripcion="+quote(entry["proposed_description"])+
                    ",valor_config=COALESCE(valor_config,'{}'::jsonb)||"+jsonsql(entry["config_patch"])+
                    " WHERE codigo="+quote(entry["code"])+
                    " AND estado="+quote(entry["source_status"])+";")
            tx.append("UPDATE lf_ops.politicas_seguridad SET description="+quote(pol["proposed_description"])+
                ",policy_config=policy_config||"+jsonsql(pol["config_patch"])+
                ",parameter_provenance=parameter_provenance||"+jsonsql(pol["parameter_provenance_patch"])+
                " WHERE security_policy_id=25 AND status='CANDIDATO';")
            tx.append("SELECT 'DURING|'||codigo||'|'||encode(extensions.digest(convert_to(to_jsonb(r)::text,'UTF8'),'sha256'),'hex') "
                      "FROM lf_ops.reglas r ORDER BY codigo;")
            tx.append("SELECT 'DURING|SEC-B2B-TRUSTED-DEVICE|'||encode(extensions.digest("
                      "convert_to(to_jsonb(r)::text,'UTF8'),'sha256'),'hex') "
                      "FROM lf_ops.politicas_seguridad r WHERE security_policy_id=25;")
            tx.append("SELECT 'GATE|'||CASE WHEN "
                  "(SELECT count(*) FROM lf_ops.reglas)=33 AND "
                  "(SELECT count(*) FROM lf_ops.reglas WHERE estado='CANDIDATO')=31 AND "
                  "(SELECT estado FROM lf_ops.reglas WHERE codigo='B2B-RULE-AUTH-039')='VIGENTE' AND "
                  "(SELECT status FROM lf_ops.politicas_seguridad WHERE security_policy_id=25)='CANDIDATO' AND "
                  "(SELECT policy_config->>'trusted_device_duration_fixed_days' FROM lf_ops.politicas_seguridad "
                    "WHERE security_policy_id=25)='30' AND "
                  "(SELECT policy_config->>'company_configurable' FROM lf_ops.politicas_seguridad "
                    "WHERE security_policy_id=25)='false' AND "
                  "(SELECT valor_config->>'token_generation' FROM lf_ops.reglas WHERE codigo='B2B-RULE-AUTH-040')='SERVER_ONLY' AND "
                  "(SELECT valor_config->>'device_last_valid_activity_source' FROM lf_ops.reglas WHERE codigo='B2B-RULE-AUTH-033')='lf_ops.dispositivos_confiables.last_used_at' "
                  "THEN 'PASS' ELSE 'FAIL' END;")
            tx.append("ROLLBACK;")
            tx.append("SELECT 'AFTER|'||codigo||'|'||encode(extensions.digest(convert_to(to_jsonb(r)::text,'UTF8'),'sha256'),'hex') FROM lf_ops.reglas r ORDER BY codigo;")
            tx.append("SELECT 'AFTER|SEC-B2B-TRUSTED-DEVICE|'||encode(extensions.digest(convert_to(to_jsonb(r)::text,'UTF8'),'sha256'),'hex') FROM lf_ops.politicas_seguridad r WHERE security_policy_id=25;")
            out=sql("\n".join(tx))
            self.assertIn("GATE|PASS",out)
            inside=dict(x[len("DURING|"):].split("|",1) for x in out if x.startswith("DURING|"))
            after=dict(x[len("AFTER|"):].split("|",1) for x in out if x.startswith("AFTER|"))
            baseline["SEC-B2B-TRUSTED-DEVICE"]=pol_pre
            self.assertEqual(set(inside),set(baseline));self.assertEqual(set(after),set(baseline))
            affected=set(CODES)|{"SEC-B2B-TRUSTED-DEVICE"}
            for key in sorted(baseline):
                self.assertRegex(inside[key],r"^[0-9a-f]{64}$")
                if key in affected:
                    self.assertNotEqual(inside[key],baseline[key],key)
                    print("LF_OPTION_C_SHA|"+image+"|"+key+"|"+baseline[key]+"|"+inside[key]+"|"+after[key]+"|PASS",flush=True)
                else:self.assertEqual(inside[key],baseline[key],"PROTECTED_CHANGED_"+key)
                self.assertEqual(after[key],baseline[key],"ROLLBACK_NOT_EXACT_"+key)
            print("PASS_OPTION_C_9_CHANGED_25_RULES_PROTECTED_REAL_PROVENANCE_GUARD_"+image.replace(":","_"),flush=True)
            if os.environ.get("GITHUB_STEP_SUMMARY"):
                with open(os.environ["GITHUB_STEP_SUMMARY"],"a",encoding="utf-8") as f:
                    f.write("\n### Option C "+image+" — SHA before/UPDATE/ROLLBACK\n\n")
                    f.write("| Row | Before | During | After rollback | Result |\n|---|---|---|---|---|\n")
                    for key in sorted(affected):
                        f.write("| "+key+" | "+baseline[key]+" | "+inside[key]+" | "+after[key]+" | PASS |\n")
        finally:
            subprocess.run(["docker","rm","-f",cname],capture_output=True,text=True,timeout=75)
    def test_pg17_6(self): self.trial("postgres:17.6","170006")
    def test_pg18_7(self): self.trial("postgres:18.7","180007")
if __name__=="__main__":unittest.main()
