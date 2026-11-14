"""Lab-only exact source copies, REAL SQL DML, PostgreSQL 17.6/18.7, ROLLBACK.
Do not confuse isolated test PASS with live Rule-Writer/Governed-Train approval.
"""
import json,re,shutil,subprocess,time,unittest,uuid
from pathlib import Path

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
SRC=HERE/"fixtures/lf_q11_facephi_tokens_source_20261114.json"
MIG=ROOT/"supabase/migrations/20261114100000_lf_q11_facephi_off_ten_existing_token_names_v1.sql"
CODE="SEC-LF-IDV-FACEPHI-OPTIONAL"

def q(x): return "'"+str(x).replace("'","''")+"'"
def jq(x): return q(json.dumps(x,ensure_ascii=False,separators=(",",":")))+"::jsonb"
def h(alias):return "encode(extensions.digest(convert_to(to_jsonb("+alias+")::text,'UTF8'),'sha256'),'hex')"

class TestQ11GovernedCopy(unittest.TestCase):
 def run_case(self,tag,version):
  self.assertTrue(shutil.which("docker"),"DOCKER_REQUIRED")
  data=json.loads(SRC.read_text(encoding="utf8"))
  txt=MIG.read_text(encoding="utf8")
  self.assertTrue(txt.startswith("-- Governed LF DB migration proposal"))
  self.assertEqual(txt.strip().splitlines()[-1].strip(),"COMMIT;")
  self.assertEqual(len(data["tokens"]),10)
  self.assertEqual(len(data["rules"]),5)
  self.assertEqual(len(data["policies"]),2)
  self.assertNotIn("http://",txt)
  self.assertNotIn("https://",txt)
  name="lf-q11-copy-"+uuid.uuid4().hex[:9]
  p=subprocess.run(["docker","run","--rm","-d","--name",name,"-e","POSTGRES_PASSWORD=postgres",
     "-e","POSTGRES_DB=postgres",tag],capture_output=True,text=True,timeout=150)
  self.assertEqual(p.returncode,0,p.stderr[-1200:])
  try:
   def sql(statement,timeout=240):
    p=subprocess.run(["docker","exec","-i",name,"psql","-q","-X","-t","-A",
       "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
       input=statement,capture_output=True,text=True,timeout=timeout)
    self.assertEqual(p.returncode,0,"LAB_SQL_ERROR:"+p.stderr[-1500:])
    return [a.strip() for a in p.stdout.splitlines() if a.strip()]
   for _ in range(90):
    if subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],capture_output=True,timeout=10).returncode==0: break
    time.sleep(1)
   self.assertEqual(sql("show server_version_num;"),[version])
   ddl=["CREATE SCHEMA extensions;","CREATE SCHEMA lf_ops;","CREATE SCHEMA lf_design;",
        "CREATE SCHEMA programacion;","CREATE EXTENSION pgcrypto WITH SCHEMA extensions;"]
   bytable={}
   for c in data["columns"]:
    table=c["table_schema"]+"."+c["table_name"]
    dtype=c["data_type"]
    if dtype=="ARRAY" and c["udt_name"]=="_text": dtype="text[]"
    self.assertRegex(c["column_name"],r"^[a-z][a-z0-9_]*$")
    self.assertIn(dtype,{"text","jsonb","bigint","integer","boolean","uuid","text[]","timestamp with time zone"})
    bytable.setdefault(table,[]).append('"'+c["column_name"]+'" '+dtype)
   for table,cols in bytable.items():
    ddl.append("CREATE TABLE "+table+"("+",".join(cols)+");")
   ddl.append(data["provenance_validator"][0]["def"]+";")
   ddl.append(data["provenance_trigger"][0]["def"]+";")
   ddl.append("""CREATE TRIGGER trg_politicas_seguridad_parameter_provenance
 BEFORE INSERT OR UPDATE ON lf_ops.politicas_seguridad
 FOR EACH ROW EXECUTE FUNCTION programacion.fn_guard_input_parameter_provenance_v1();""")
   sql("\n".join(ddl))
   maps=[("rules","lf_ops.reglas"),("policies","lf_ops.politicas_seguridad"),("tokens","lf_design.spacing_tokens")]
   for bucket,table in maps:
    for row in data[bucket]:
     sql("INSERT INTO "+table+" SELECT (jsonb_populate_record(NULL::"+table+","+jq(row["row"])+")).*;")
   def keyfield(table):
    return {"lf_ops.reglas":"codigo","lf_ops.politicas_seguridad":"policy_code","lf_design.spacing_tokens":"token_name"}[table]
   def ident(table,row):return row["row"][keyfield(table)]
   def rowsha(table,key):
    return sql("SELECT "+h("t")+" FROM "+table+" t WHERE "+keyfield(table)+"="+q(key)+";")[0]
   originals={}
   for bucket,table in maps:
    for row in data[bucket]:
     v=ident(table,row)
     current=rowsha(table,v)
     self.assertEqual(current,row["sha"],"SOURCE_SHA_DRIFT:"+v)
     originals[(table,v)]=current
   self.assertEqual(sql("SELECT COUNT(*) FROM lf_design.spacing_tokens WHERE status='CANDIDATO';"),["10"])
   self.assertEqual(sql("SELECT COUNT(*) FROM lf_ops.politicas_seguridad WHERE policy_code="+q(CODE)+";"),["0"])
   # Run the exact proposed migration as a transaction in the copy; replace
   # ONLY the last COMMIT with measurement + ROLLBACK.
   self.assertTrue(txt.rstrip().endswith("COMMIT;"))
   fragment=txt.rstrip()[:-len("COMMIT;")]
   probes=[
     "SELECT 'INSIDE_PROVIDER|'||"+h("p")+" FROM lf_ops.politicas_seguridad p WHERE policy_code="+q(CODE)+";",
     "SELECT 'INSIDE_EKB|'||COUNT(*) FROM public.lf_error_knowledge WHERE codigo LIKE 'LF-IDV-FACEPHI-DISABLED-GUARD-001' OR codigo='LF-B2B-TOKEN-NAME-DRIFT-001';"
   ]
   for bucket,table in maps:
    for row in data[bucket]:
     key=ident(table,row)
     probes.append("SELECT "+q("INSIDE|"+table+"|"+key+"|")+"||"+h("t")+
       " FROM "+table+" t WHERE "+keyfield(table)+"="+q(key)+";")
   post=[
    "SELECT 'AFTER_PROVIDER|'||COUNT(*) FROM lf_ops.politicas_seguridad WHERE policy_code="+q(CODE)+";",
    "SELECT 'AFTER_EKB|'||COUNT(*) FROM public.lf_error_knowledge WHERE codigo IN ('LF-IDV-FACEPHI-DISABLED-GUARD-001','LF-B2B-TOKEN-NAME-DRIFT-001');"
   ]
   for bucket,table in maps:
    for row in data[bucket]:
     key=ident(table,row)
     post.append("SELECT "+q("AFTER|"+table+"|"+key+"|")+"||"+h("t")+
       " FROM "+table+" t WHERE "+keyfield(table)+"="+q(key)+";")
   result=sql(fragment+"\n"+"\n".join(probes)+"\nROLLBACK;\n"+"\n".join(post)+"\n",timeout=290)
   inside,after={},{}
   for ln in result:
    if ln.startswith("INSIDE|"):
     _,table,key,sha=ln.split("|",3);inside[(table,key)]=sha
    elif ln.startswith("AFTER|"):
     _,table,key,sha=ln.split("|",3);after[(table,key)]=sha
   self.assertEqual(len(inside),17)
   self.assertEqual(len(after),17)
   self.assertEqual(next(x for x in result if x.startswith("INSIDE_EKB|")),"INSIDE_EKB|2")
   self.assertEqual(next(x for x in result if x.startswith("AFTER_EKB|")),"AFTER_EKB|0")
   self.assertEqual(next(x for x in result if x.startswith("AFTER_PROVIDER|")),"AFTER_PROVIDER|0")
   provider=next(x.split("|",1)[1] for x in result if x.startswith("INSIDE_PROVIDER|"))
   self.assertRegex(provider,r"^[0-9a-f]{64}$")
   changed=0
   for table,key in originals:
    self.assertEqual(after[(table,key)],originals[(table,key)],"ROLLBACK_NOT_EXACT:"+key)
    if table=="lf_design.spacing_tokens":
     self.assertEqual(inside[(table,key)],originals[(table,key)],"TOKEN_IDENTITY_CHANGED:"+key)
    else:
     self.assertNotEqual(inside[(table,key)],originals[(table,key)],"PATCH_NOT_APPLIED:"+key)
     changed+=1
     print("LF_Q11_SHA|"+tag+"|"+key+"|"+originals[(table,key)]+"|"+inside[(table,key)]+"|"+after[(table,key)]+"|PASS",flush=True)
   self.assertEqual(changed,7)
   print("LF_Q11_PASS|"+tag+"|7_CHANGED|10_TOKENS_UNCHANGED|1_PROVIDER_INSERTED_ROLLBACK|2_EKB_INSERTED_ROLLBACK|ENABLED_FALSE|NO_API|PASS",flush=True)
  finally:
   subprocess.run(["docker","rm","-f",name],capture_output=True,text=True,timeout=45)
 def test_pg17_6(self):self.run_case("postgres:17.6","170006")
 def test_pg18_7(self):self.run_case("postgres:18.7","180007")

if __name__=="__main__":unittest.main()
