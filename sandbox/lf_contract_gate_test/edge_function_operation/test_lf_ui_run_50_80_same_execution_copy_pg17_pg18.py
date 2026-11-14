#!/usr/bin/env python3
"""Exact RUN SELECT-snapshot, native bridge guard, structural continuation 50-80 and ROLLBACK; lab only.

This test does NOT fake model evidence, V3 review, official writer PASS, or terminal closure.
"""
import json,os,shutil,subprocess,time,unittest,uuid
from pathlib import Path
F=Path(__file__).resolve().parent/"fixtures/lf_ui_run_50_80_copy_20261113.json"
def quote(x): return "'"+str(x).replace("'","''")+"'"
def qjson(x): return quote(json.dumps(x,ensure_ascii=False,separators=(",",":")))+"::jsonb"
def hash_expr(alias):
 return "encode(extensions.digest(convert_to(to_jsonb("+alias+")::text,'UTF8'),'sha256'),'hex')"
def steps_hash():
 return """SELECT encode(extensions.digest(convert_to(
 (SELECT jsonb_agg(to_jsonb(s) ORDER BY s.step_order)::text
 FROM public.lf_operation_execution_steps s WHERE execution_id='EXEC-PROFILE-GATE2-5044268025DE35E9E529729F'),
 'UTF8'),'sha256'),'hex');"""
ID="EXEC-PROFILE-GATE2-5044268025DE35E9E529729F"

class TestUITargetSameRunLab(unittest.TestCase):
 def verify(self,image,expected):
  self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
  data=json.loads(F.read_text(encoding="utf8"))
  self.assertEqual(data["execution_id"],ID)
  self.assertEqual(data["run"]["snapshot"]["status"],"IN_PROGRESS")
  self.assertEqual(len(data["steps"]),7)
  self.assertEqual([x["snapshot"]["step_order"] for x in data["steps"]],[0,10,20,30,40,45,47])
  self.assertEqual([x["step_order"] for x in data["contracts"]],[50,60,70,80])
  self.assertFalse(data["identity_verified"])
  cid="lf-ui-continue-"+uuid.uuid4().hex[:9]
  z=subprocess.run(["docker","run","--rm","-d","--name",cid,"-e","POSTGRES_PASSWORD=postgres",
                    "-e","POSTGRES_DB=postgres",image],capture_output=True,text=True,timeout=240)
  self.assertEqual(z.returncode,0,z.stderr[-800:])
  try:
   def sql(statement):
    z=subprocess.run(["docker","exec","-i",cid,"psql","-q","-X","-t","-A",
      "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
      input=statement,capture_output=True,text=True,timeout=300)
    self.assertEqual(z.returncode,0,"LAB_SQL_ERROR:"+z.stderr[-1900:])
    return [x.strip() for x in z.stdout.splitlines() if x.strip()]
   for _ in range(90):
    if subprocess.run(["docker","exec",cid,"pg_isready","-U","postgres"],capture_output=True,timeout=10).returncode==0:break
    time.sleep(1)
   else:self.fail("PG_NOT_READY")
   self.assertEqual(sql("SHOW server_version_num;"),[expected])
   cols={}
   for c in data["columns"]:
    self.assertRegex(c["tab"],r"^(lf_operation_execution|lf_operation_execution_steps)$")
    self.assertRegex(c["col"],r"^[a-z][a-z0-9_]*$")
    self.assertRegex(c["typ"],r"^(text|integer|bigint|jsonb|timestamp with time zone)$")
    cols.setdefault(c["tab"],[]).append('"'+c["col"]+'" '+c["typ"])
   ddl=["CREATE SCHEMA extensions;","CREATE EXTENSION pgcrypto WITH SCHEMA extensions;"]
   for tab,arr in cols.items():ddl.append("CREATE TABLE public."+tab+"("+",".join(arr)+");")
   sql("\n".join(ddl))
   # Recreate exact SELECT snapshots; verify same PostgreSQL JSONB SHA-256 as Supabase source.
   row=data["run"]
   sql("INSERT INTO public.lf_operation_execution SELECT "+
       "(jsonb_populate_record(NULL::public.lf_operation_execution,"+
       qjson(row["snapshot"])+")).*;")
   for item in data["steps"]:
    sql("INSERT INTO public.lf_operation_execution_steps SELECT "+
        "(jsonb_populate_record(NULL::public.lf_operation_execution_steps,"+
        qjson(item["snapshot"])+")).*;")
   realhash=sql("SELECT "+hash_expr("e")+" FROM public.lf_operation_execution e WHERE execution_id="+quote(ID)+";")[0]
   self.assertEqual(realhash,row["sha256"],"RUN_SOURCE_SHA_MISMATCH")
   for item in data["steps"]:
    h=sql("SELECT "+hash_expr("s")+" FROM public.lf_operation_execution_steps s"+
       " WHERE execution_id="+quote(ID)+" AND step_order="+str(item["snapshot"]["step_order"])+";")
    self.assertEqual(h,[item["sha256"]],"SOURCE_STEP_SHA_MISMATCH_"+item["snapshot"]["step_id"])
   before=sql(steps_hash())[0]
   self.assertEqual(sql("SELECT count(*) FROM public.lf_operation_execution_steps WHERE execution_id="+quote(ID)+";"),["7"])
   # Execute exact current canonical bridge guard, NOT a fake recorder.
   sql(data["canonical_guard_definition"]+";")
   native_code=sql("SELECT public.lf_profile_native_bridge_record_output_v1("+
     quote(ID)+",NULL,NULL,NULL,NULL,NULL)->>'blocking_code';")
   self.assertEqual(native_code,["BLOCK_PROFILE_NATIVE_BRIDGE_OUTPUT_INPUT_INVALID"])
   self.assertEqual(sql(steps_hash()),[before])
   # COPY-ONLY structural rehearsal, explicitly NOT a governed execution. Nothing claims PASS.
   tx=["BEGIN;"]
   for spec in data["contracts"]:
    payload={"lab_only":True,"real_model_output":False,"real_validator_receipt":False,
      "real_v3_review":False,"canonical_required_evidence_keys":spec["required_evidence_keys"],
      "test_only_step_order":spec["step_order"],"evidence_provenance":"SYNTHETIC_SQL_LAB_ONLY"}
    tx.append("INSERT INTO public.lf_operation_execution_steps "
      "(execution_id,step_order,step_id,status,evidence_ref,evidence_payload,observed_at,"
      "created_by_execution_id,created_at) VALUES ("+
      quote(ID)+","+str(spec["step_order"])+","+quote(spec["step_id"])+
      ",'LAB_SIMULATED_NOT_VALIDATED','lab://noncanonical/no-model-output',"+
      qjson(payload)+",now(),"+quote(ID)+",now());")
   tx.append("SELECT 'DURING_COUNT|'||count(*) FROM public.lf_operation_execution_steps WHERE execution_id="+quote(ID)+";")
   tx.append("SELECT 'DURING_SHA|'||encode(extensions.digest(convert_to(jsonb_agg(to_jsonb(s) ORDER BY s.step_order)::text,'UTF8'),'sha256'),'hex') FROM public.lf_operation_execution_steps s WHERE execution_id="+quote(ID)+";")
   tx.append("SELECT 'RUN_STATUS|'||status FROM public.lf_operation_execution WHERE execution_id="+quote(ID)+";")
   for s in data["contracts"]:
    tx.append("SELECT "+quote("DURING_NEW|"+s["step_id"]+"|")+
     "||"+hash_expr("s")+" FROM public.lf_operation_execution_steps s WHERE execution_id="+quote(ID)+
     " AND step_order="+str(s["step_order"])+";")
   tx.append("ROLLBACK;")
   tx.append("SELECT 'AFTER_COUNT|'||count(*) FROM public.lf_operation_execution_steps WHERE execution_id="+quote(ID)+";")
   tx.append("SELECT 'AFTER_SHA|'||encode(extensions.digest(convert_to(jsonb_agg(to_jsonb(s) ORDER BY s.step_order)::text,'UTF8'),'sha256'),'hex') FROM public.lf_operation_execution_steps s WHERE execution_id="+quote(ID)+";")
   for s in data["contracts"]:
    tx.append("SELECT "+quote("AFTER_NEW|"+s["step_id"]+"|")+
      "||coalesce((SELECT "+hash_expr("s")+" FROM public.lf_operation_execution_steps s "+
      "WHERE execution_id="+quote(ID)+" AND step_order="+str(s["step_order"])+"),'ABSENT');")
   result=sql("\n".join(tx))
   values={};newinside={};newafter={}
   for line in result:
    if line.startswith("DURING_NEW|"):
      _,name,h=line.split("|",2);newinside[name]=h
    elif line.startswith("AFTER_NEW|"):
      _,name,h=line.split("|",2);newafter[name]=h
    elif "|" in line:
      k,v=line.split("|",1);values[k]=v
   self.assertEqual(values["DURING_COUNT"],"11")
   self.assertEqual(values["AFTER_COUNT"],"7")
   self.assertEqual(values["RUN_STATUS"],"IN_PROGRESS")
   self.assertNotEqual(before,values["DURING_SHA"])
   self.assertEqual(before,values["AFTER_SHA"])
   for spec in data["contracts"]:
     name=spec["step_id"]
     self.assertRegex(newinside[name],r"^[0-9a-f]{64}$")
     self.assertEqual(newafter[name],"ABSENT")
     print("LF_UI_COPY_STEP|"+image+"|"+name+"|ABSENT|"+newinside[name]+"|ABSENT|LAB_ONLY_PASS",flush=True)
   print("LF_UI_RUN_COPY_ROLLBACK|"+image+"|"+str(realhash)+"|"+
     before+"|"+values["DURING_SHA"]+"|"+values["AFTER_SHA"]+
     "|7>11>7|NATIVE_GUARD_BLOCKED_MISSING_RAW|PASS",flush=True)
   if os.environ.get("GITHUB_STEP_SUMMARY"):
    with open(os.environ["GITHUB_STEP_SUMMARY"],"a",encoding="utf8") as f:
     f.write("\n### UI RUN step50-80 copy only "+image+"\n"+
       "Original RUN SHA: "+realhash+"\n"+
       "Original steps aggregate SHA: "+before+"\n"+
       "Inside structural non-governed SHA: "+values["DURING_SHA"]+"\n"+
       "After ROLLBACK SHA: "+values["AFTER_SHA"]+"\n"+
       "Native no-RAW guard: BLOCK_PROFILE_NATIVE_BRIDGE_OUTPUT_INPUT_INVALID\n")
  finally:
    subprocess.run(["docker","rm","-f",cid],text=True,capture_output=True,timeout=45)
 def test_pg17_6(self):self.verify("postgres:17.6","170006")
 def test_pg18_7(self):self.verify("postgres:18.7","180007")
if __name__=="__main__":unittest.main()
