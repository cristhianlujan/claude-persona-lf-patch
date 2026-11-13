#!/usr/bin/env python3
"""L33 PG18 isolated replay of exact 235-ID PG17 Supabase read-only capture.
Proves original UTF-8 SHA and membership; does not reserialize PG18 JSONB
as if it had the same bytes as source, nor pretend effects/sinks were audited.
Only creates/mutates a disposable PostgreSQL 18 database on CI runner.
"""
import csv
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[3]
D=ROOT/"audits/rule-quality-lote33"
RAW=D/"01_supabase_freeze_snapshot_raw.json"
REF=D/"05_reference_cohorts_for_pg18.json"
OUT=D/"06_pg18_execution_result_runtime.json"
DB="lf_l33_b02_frozen_copy_pg18"
checks=[]

def sql(statement, db=DB, expect_fail=False):
    p=subprocess.run(["psql","-X","-A","-t","-v","ON_ERROR_STOP=1","-d",db],
       input=statement,capture_output=True,text=True,env=os.environ)
    if expect_fail:
        if p.returncode==0: raise AssertionError("NEGATIVE_SQL_SUCCEEDED")
        return p.stderr
    if p.returncode!=0:
        raise AssertionError("PG18_SQL_ERROR:"+p.stderr[-2800:])
    return p.stdout.strip()

def scalar(q):
    return sql(q).splitlines()[-1]

def check(name,ok,details=None):
    if not ok: raise AssertionError("FAIL "+name+" "+str(details))
    checks.append({"name":name,"status":"PASS","details":details})
    print("PASS_L33_"+name+" "+json.dumps(details,ensure_ascii=False,sort_keys=True,default=str),flush=True)

def lit(s):
    # Data content is controlled evidence, but escape single quote defensively.
    return "'"+str(s).replace("'","''")+"'"

def tag(s):
    assert "$l33_json_data$" not in s
    return "$l33_json_data$"+s+"$l33_json_data$"

def txvalue(mutation,expression):
    out=sql("BEGIN;\n"+mutation+"\nSELECT 'L33_NEG|'||("+expression+")::text;\nROLLBACK;")
    vals=[line.split("L33_NEG|",1)[1] for line in out.splitlines() if "L33_NEG|" in line]
    if len(vals)!=1:raise AssertionError("NEGATIVE_READBACK_MISSING "+out[-700:])
    return vals[0]

def main():
    s=json.loads(RAW.read_text(encoding="utf-8"))
    refs=json.loads(REF.read_text(encoding="utf-8"))
    ids=json.loads(s["membership_jsonb_text"])
    pre=json.loads(s["preimage_jsonb_text"])
    prof=json.loads(s["profile61_jsonb_text"])
    check("SOURCE_SNAPSHOT",s["frozen_count"]==235 and s["distinct_count"]==235 and
       s["profile_count_all_statuses"]==61 and len(ids)==len(pre)==235 and
       len(prof)==61 and s["transaction_read_only"]=="on" and
       s["isolation"]=="repeatable read",
       {"count":len(ids),"as_of":s["as_of_utc"],"source_pg":s["pg_version"]})
    check("SOURCE_ORIGINAL_TEXT_SHA",
       hashlib.sha256(s["membership_jsonb_text"].encode()).hexdigest()==s["membership_jsonb_sha256"] and
       hashlib.sha256(s["preimage_jsonb_text"].encode()).hexdigest()==s["preimage_manifest_jsonb_sha256"] and
       hashlib.sha256(s["profile61_jsonb_text"].encode()).hexdigest()==s["profile61_jsonb_sha256"],
       {"membership":s["membership_jsonb_sha256"],
        "preimage":s["preimage_manifest_jsonb_sha256"],
        "profile61":s["profile61_jsonb_sha256"]})
    csv_text="run_id\n"+"\n".join(ids)+"\n"
    check("EXACT_FROZEN_CSV_SHA",
       hashlib.sha256(csv_text.encode()).hexdigest()==s["ids_csv_sha256"],
       {"sha":s["ids_csv_sha256"],"rows":len(ids)})
    assert refs["historic232"]["ids"] and refs["l31_234"]["ids"]
    sql("DROP DATABASE IF EXISTS "+DB+" WITH (FORCE);",db="postgres")
    sql("CREATE DATABASE "+DB+";",db="postgres")
    try:
        sql("""CREATE SCHEMA evidence_copy;
CREATE TABLE evidence_copy.raw_utf8(name text PRIMARY KEY,raw_text text NOT NULL,expected_sha256 text NOT NULL);
CREATE TABLE evidence_copy.frozen(run_id text PRIMARY KEY,operation_code text NOT NULL,
    status text NOT NULL,row_sha256 text NOT NULL,observed_payload jsonb NOT NULL);
CREATE TABLE evidence_copy.profile61(run_id text PRIMARY KEY,operation_code text NOT NULL,
    status text NOT NULL,row_sha256 text NOT NULL);
CREATE TABLE evidence_copy.old232(run_id text PRIMARY KEY);
CREATE TABLE evidence_copy.old234(run_id text PRIMARY KEY);
CREATE TABLE evidence_copy.priority32(run_id text PRIMARY KEY);""")
        statements=[]
        for name,k,sha in [
            ("members","membership_jsonb_text","membership_jsonb_sha256"),
            ("preimage","preimage_jsonb_text","preimage_manifest_jsonb_sha256"),
            ("profile61","profile61_jsonb_text","profile61_jsonb_sha256")
        ]:
            statements.append("INSERT INTO evidence_copy.raw_utf8 VALUES ("+
                lit(name)+","+tag(s[k])+","+lit(s[sha])+");")
        statements.append("INSERT INTO evidence_copy.frozen SELECT x->>'run_id',x->>'operation_code',x->>'status',x->>'row_sha256',x FROM jsonb_array_elements("+tag(s["preimage_jsonb_text"])+"::jsonb) x;")
        statements.append("INSERT INTO evidence_copy.profile61 SELECT x->>'run_id',x->>'operation_code',x->>'status',x->>'row_sha256' FROM jsonb_array_elements("+tag(s["profile61_jsonb_text"])+"::jsonb) x;")
        for table,key in [("old232","historic232"),("old234","l31_234"),("priority32","priority32")]:
            data=json.dumps(refs[key]["ids"],ensure_ascii=False)
            statements.append("INSERT INTO evidence_copy."+table+" SELECT jsonb_array_elements_text("+tag(data)+"::jsonb);")
        sql("\n".join(statements))
        ver=scalar("SELECT current_setting('server_version');")
        check("PG18_REAL_SERVER",ver.startswith("18."),{"server_version":ver})
        pg_hashes=json.loads(scalar("""SELECT jsonb_object_agg(name,
          jsonb_build_object('expected',expected_sha256,
          'real',encode(sha256(convert_to(raw_text,'UTF8')),'hex')))::text
          FROM evidence_copy.raw_utf8;"""))
        check("ORIGINAL_CANONICAL_SOURCE_BYTES_REPLAYED",
          all(v["expected"]==v["real"] for v in pg_hashes.values()),pg_hashes)
        counts=json.loads(scalar("""SELECT jsonb_build_object(
          'frozen',(SELECT count(*) FROM evidence_copy.frozen),
          'profile',(SELECT count(*) FROM evidence_copy.profile61),
          'old232',(SELECT count(*) FROM evidence_copy.old232),
          'old234',(SELECT count(*) FROM evidence_copy.old234),
          'priority32',(SELECT count(*) FROM evidence_copy.priority32))::text;"""))
        check("COPY_COUNTS_235_61_232_234_32",counts==
            {"frozen":235,"profile":61,"old232":232,"old234":234,"priority32":32},counts)
        diff=json.loads(scalar("""SELECT jsonb_build_object(
          'old232_present',(SELECT count(*) FROM evidence_copy.frozen f JOIN evidence_copy.old232 o USING(run_id)),
          'old234_present',(SELECT count(*) FROM evidence_copy.frozen f JOIN evidence_copy.old234 o USING(run_id)),
          'priority32_present',(SELECT count(*) FROM evidence_copy.frozen f JOIN evidence_copy.priority32 o USING(run_id)),
          'new_vs232',(SELECT count(*) FROM evidence_copy.frozen f LEFT JOIN evidence_copy.old232 o USING(run_id) WHERE o.run_id IS NULL),
          'new_vs234',(SELECT count(*) FROM evidence_copy.frozen f LEFT JOIN evidence_copy.old234 o USING(run_id) WHERE o.run_id IS NULL),
          'pr61_in_frozen',(SELECT count(*) FROM evidence_copy.profile61 p JOIN evidence_copy.frozen f USING(run_id)),
          'pr61_outside',(SELECT count(*) FROM evidence_copy.profile61 p LEFT JOIN evidence_copy.frozen f USING(run_id) WHERE f.run_id IS NULL),
          'profile_not_eq',(SELECT count(*) FROM evidence_copy.profile61 WHERE operation_code<>'EJECUCION_PERFIL_LF')
        )::text;"""))
        check("COHORT_MEMBERSHIP_DIFF",diff=={
          "old232_present":232,"old234_present":234,"priority32_present":32,
          "new_vs232":3,"new_vs234":1,"pr61_in_frozen":12,
          "pr61_outside":49,"profile_not_eq":0},diff)
        ro=scalar("""BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SELECT current_setting('transaction_read_only')||':'||
current_setting('transaction_isolation')||':'||
(SELECT count(*) FROM evidence_copy.frozen);
ROLLBACK;""")
        check("READ_ONLY_SQL_CAPTURE_LOGIC_PG18",ro=="on:repeatable read:235",{"readback":ro})
        victim=ids[0]
        missing=int(txvalue("CREATE TEMP TABLE stage AS SELECT * FROM evidence_copy.frozen; DELETE FROM stage WHERE run_id="+lit(victim)+";",
          "(SELECT count(*) FROM stage)"))
        check("NEG_MISSING_ID_DETECTED",missing==234,{"found":missing})
        dup=sql("BEGIN; INSERT INTO evidence_copy.frozen SELECT * FROM evidence_copy.frozen WHERE run_id="+lit(victim)+";",expect_fail=True)
        check("NEG_DUPLICATE_PRIMARY_KEY_BLOCKED","duplicate key" in dup,{"sqlstate":"unique_violation"})
        tamper=int(txvalue("CREATE TEMP TABLE stage AS SELECT * FROM evidence_copy.frozen; UPDATE stage SET row_sha256=repeat('0',64) WHERE run_id="+lit(victim)+";",
          "(SELECT count(*) FROM stage s JOIN evidence_copy.frozen b USING(run_id) WHERE s.row_sha256 IS DISTINCT FROM b.row_sha256)"))
        check("NEG_CHANGED_PREIMAGE_DETECTED",tamper==1,{"mismatch_rows":tamper})
        delta=int(txvalue("CREATE TEMP TABLE stage AS SELECT * FROM evidence_copy.frozen; INSERT INTO stage(run_id,operation_code,status,row_sha256,observed_payload) SELECT 'EXEC-SYNTHETIC-POST-CUT','TEST','IN_PROGRESS',repeat('0',64),'{}'::jsonb;",
          "(SELECT count(*) FROM stage s LEFT JOIN evidence_copy.frozen f USING(run_id) WHERE f.run_id IS NULL)"))
        check("NEG_POST_CUT_NEW_RUN_IS_DELTA",delta==1,{"outside_snapshot_rows":delta})
        check("BASELINE_COPY_INTACT_AFTER_NEGATIVES",
          int(scalar("SELECT count(*) FROM evidence_copy.frozen;"))==235,
          {"copy_rows":235})
        result={"schema":"LF_L33_PG18_COPY_REPLAY_V1","source":"Supabase PG17.6 READ ONLY 235-ID MVCC cut",
          "as_of_utc":s["as_of_utc"],"source_snapshot":s["mvcc_snapshot"],
          "frozen":235,"pr3803_candidate":61,"source_sha256":{
          "membership":s["membership_jsonb_sha256"],
          "preimage":s["preimage_manifest_jsonb_sha256"],
          "csv":s["ids_csv_sha256"]},"pg18_version":ver,
          "tests":checks,"passes":len(checks),"no_live_supabase_mutations":True,
          "b02":"OPEN_PENDING_OPS_SIGNATURE","b03":"OPEN_PENDING_EFFECTS_AND_LIVENESS",
          "pr3803_historical_filter_confirmed_by_owner":False}
        OUT.write_text(json.dumps(result,ensure_ascii=False,indent=2,sort_keys=True)+"\n",encoding="utf-8")
        print("L33_RESULT_SHA256 "+hashlib.sha256(OUT.read_bytes()).hexdigest(),flush=True)
        print("L33_TOTAL_PASS "+str(len(checks)),flush=True)
    finally:
        sql("DROP DATABASE IF EXISTS "+DB+" WITH (FORCE);",db="postgres")
        print("L33_DISPOSABLE_PG18_DATABASE_DROPPED",flush=True)

if __name__=="__main__":
    main()
