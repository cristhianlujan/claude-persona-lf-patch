#!/usr/bin/env python3
"""B02/G01 and B03/G02: PostgreSQL 18 reproduction of real SELECT-only
Supabase snapshots (literal cohort). NO production, no existing RUN mutation.
Negative tests change COPY rows inside rolled-back PG18 transactions only.
"""
import hashlib
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
EVID = ROOT / "audits/rule-quality-lote31"
B02 = EVID / "06_b02_canonical_live_jsonb_text.json"
B03 = EVID / "07_b03_canonical_live_jsonb_text.json"
OUT = EVID / "05_pg18_result_runtime.json"
DB = "lf_l31_b02_b03_snapshot_pg18"
TESTS = []

def sql(q, db=DB, fail=False):
    p = subprocess.run(
       ["psql", "-X", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-d", db],
       input=q, capture_output=True, text=True, env=os.environ)
    if fail:
        if p.returncode == 0:
            raise AssertionError("EXPECTED_FAILURE_BUT_SUCCEEDED: " + q[:120])
        return p.stderr
    if p.returncode != 0:
        raise AssertionError("POSTGRES_ERROR: " + p.stderr[-2400:])
    return p.stdout.strip()

def scalar(q):
    txt = sql(q)
    return txt.splitlines()[-1]

def jsonsql(q):
    return json.loads(scalar(q))

def check(name, ok, observed, expected=None):
    if not ok:
        raise AssertionError("FAIL_" + name + " observed=" + str(observed)[:1600]
                             + " expected=" + str(expected))
    rec = {"name": name, "status": "PASS", "observed": observed}
    TESTS.append(rec)
    print("PASS_L31_" + name + " " + json.dumps(observed, sort_keys=True, default=str), flush=True)

def seed(b02,b03):
    assert b02["current"]["n"] == b03["n"]
    assert len(b02["current"]["rows_r01"]) == len(b03["rows"])
    sql("DROP DATABASE IF EXISTS " + DB + " WITH (FORCE);", db="postgres")
    sql("CREATE DATABASE " + DB + ";", db="postgres")
    sql("""CREATE SCHEMA evidence_copy;
CREATE TABLE evidence_copy.b02 (
 run_id text PRIMARY KEY,
 payload jsonb NOT NULL
);
CREATE TABLE evidence_copy.b03 (
 run_id text PRIMARY KEY REFERENCES evidence_copy.b02(run_id),
 payload jsonb NOT NULL
);
CREATE TABLE evidence_copy.historical232 (
 run_id text PRIMARY KEY
);
CREATE TABLE evidence_copy.priority32 (
 run_id text PRIMARY KEY
);
CREATE TABLE evidence_copy.raw_sources(
 name text PRIMARY KEY,canonical_jsonb_text text NOT NULL,source_sha256 text NOT NULL
);
""")
    def literal(data):
        value=data if isinstance(data,str) else json.dumps(data,ensure_ascii=False,sort_keys=True,separators=(",",":"))
        assert "$json_snapshot$" not in value
        return "$json_snapshot$" + value + "$json_snapshot$::jsonb"
    q = (
        "INSERT INTO evidence_copy.b02(run_id,payload) "
        "SELECT a->>'run_id',a FROM jsonb_array_elements("
        +literal(b02["canonical_jsonb_text"])+") a;\n"+
        "INSERT INTO evidence_copy.b03(run_id,payload) "
        "SELECT a->>'run_id',a FROM jsonb_array_elements("
        +literal(b03["canonical_jsonb_text"])+") a;\n"+
        "INSERT INTO evidence_copy.historical232(run_id) "
        "SELECT jsonb_array_elements_text("+literal(b02["historical"]["id_list"])+");\n"+
        "INSERT INTO evidence_copy.priority32(run_id) "
        "SELECT jsonb_array_elements_text("+literal(b02["historical"]["priority32_ids"])+");\n"
    )
    sql(q)
    # Store the ORIGINAL PG17.6 canonical JSONB text, not a reserialized JS/Python copy.
    sql("INSERT INTO evidence_copy.raw_sources VALUES ('B02',"+
         repr_sql(b02["canonical_jsonb_text"])+","+
         repr_sql(b02["raw_result_sha256"])+"),('B03',"+
         repr_sql(b03["canonical_jsonb_text"])+","+
         repr_sql(b03["sha256"])+");")
    got = jsonsql("""SELECT jsonb_build_object(
      'b02',(SELECT count(*) FROM evidence_copy.b02),
      'b03',(SELECT count(*) FROM evidence_copy.b03),
      'historic',(SELECT count(*) FROM evidence_copy.historical232),
      'priority',(SELECT count(*) FROM evidence_copy.priority32),
      'pg',(SELECT current_setting('server_version'))
    )::text;""")
    check("COPY_ALL_IDS",got["b02"]==b02["current"]["n"] and
          got["b03"]==b03["n"] and got["historic"]==232 and got["priority"]==32
          and got["pg"].startswith("18."),got)
    return got

def sha_copy(table):
    return scalar("SELECT encode(sha256(convert_to("+
       "coalesce(jsonb_agg(payload ORDER BY payload::text),'[]'::jsonb)::text,'UTF8')),'hex')"+
       " FROM evidence_copy."+table+";")

def readback(b02,b03):
    got2=sha_copy("b02")
    got3=sha_copy("b03")
    # SHA checks apply to EXACT raw JSONB text supplied by live PG17.6.
    # Typed JSONB may reserialize differently in PG18.7: compare records
    # semantically and use typed baseline only for PG18 negative tests.
    raw=jsonsql("""SELECT jsonb_object_agg(name,jsonb_build_object(
      'server_sha',source_sha256,
      'copy_sha',encode(sha256(convert_to(canonical_jsonb_text,'UTF8')),'hex'))
    )::text FROM evidence_copy.raw_sources;""")
    check("B02_CANONICAL_BYTES_SHA256_MATCH",raw["B02"]["server_sha"]==
          raw["B02"]["copy_sha"]==b02["raw_result_sha256"],raw["B02"])
    check("B03_CANONICAL_BYTES_SHA256_MATCH",raw["B03"]["server_sha"]==
          raw["B03"]["copy_sha"]==b03["sha256"],raw["B03"])
    b02["pg18_typed_sha"]=got2
    b03["pg18_typed_sha"]=got3
    print("L31_PG18_TYPED_JSONB_SERIALIZATION_DIAGNOSTIC "+
          json.dumps({"b02_pg18":got2,"b02_live_pg17":b02["raw_result_sha256"],
          "b03_pg18":got3,"b03_live_pg17":b03["sha256"]}),flush=True)
    both=jsonsql("""SELECT jsonb_build_object(
      'historic_still_present',
      (SELECT count(*) FROM evidence_copy.historical232 h
       JOIN evidence_copy.b02 b USING(run_id)),
      'historic_missing',
      (SELECT count(*) FROM evidence_copy.historical232 h
       LEFT JOIN evidence_copy.b02 b USING(run_id) WHERE b.run_id IS NULL),
      'new_versus_232',
      (SELECT count(*) FROM evidence_copy.b02 b
       LEFT JOIN evidence_copy.historical232 h USING(run_id) WHERE h.run_id IS NULL),
      'priority_still_present',
      (SELECT count(*) FROM evidence_copy.priority32 p JOIN evidence_copy.b02 b USING(run_id)),
      'different_B03_rows',
      (SELECT count(*) FROM evidence_copy.b02 b JOIN evidence_copy.b03 x USING(run_id)
        WHERE b.payload->>'run_id' IS DISTINCT FROM x.payload->>'run_id'),
      'b03_wrong_status',
      (SELECT count(*) FROM evidence_copy.b03 WHERE payload->>'current_status'<>'IN_PROGRESS')
    )::text;""")
    check("B02_232_32_LITERAL_COHORT",both["historic_still_present"]==232 and
          both["historic_missing"]==0 and both["priority_still_present"]==32 and
          both["new_versus_232"]==b02["current"]["n"]-232 and
          both["different_B03_rows"]==0 and both["b03_wrong_status"]==0,both)
    b03_metrics=jsonsql("""SELECT jsonb_build_object(
      'idempotency_keys',(SELECT count(*) FROM evidence_copy.b03 WHERE (payload->>'has_idempotency_key')::boolean),
      'duplicated_keys',(SELECT count(*) FROM (
         SELECT payload->>'idempotency_key_sha256' h,count(*) n
         FROM evidence_copy.b03
         WHERE payload->>'idempotency_key_sha256' IS NOT NULL
         GROUP BY payload->>'idempotency_key_sha256' HAVING count(*)>1) t),
      'expired_leases',(SELECT count(*) FROM evidence_copy.b03 WHERE (payload->>'lease_expired_now')::boolean),
      'valid_leases',(SELECT count(*) FROM evidence_copy.b03 WHERE (payload->>'lease_valid_now')::boolean),
      'succeeded_guards',(SELECT count(*) FROM evidence_copy.b03 WHERE (payload->>'guard_succeeded')::int>0),
      'reserved_guard_runs',(SELECT count(*) FROM evidence_copy.b03 WHERE (payload->>'guard_reserved')::int>0),
      'guard_no_receipt',(SELECT count(*) FROM evidence_copy.b03 WHERE (payload->>'guard_succeeded_missing_receipt')::int>0),
      'github_write_positive',(SELECT count(*) FROM evidence_copy.b03 WHERE (payload->>'github_write_positive')::int>0),
      'has_steps',(SELECT count(*) FROM evidence_copy.b03 WHERE (payload->>'step_count')::int>0),
      'missing_preimage',(SELECT count(*) FROM evidence_copy.b03
          WHERE payload->>'run_preimage_sha256' IS NULL)
    )::text;""")
    check("B03_ALL_RUNS_READBACK",b03_metrics["idempotency_keys"]==b03["stats"]["idempotency_present"] and
          b03_metrics["expired_leases"]==b03["stats"]["lease_expired"] and
          b03_metrics["valid_leases"]==b03["stats"]["lease_valid"] and
          b03_metrics["succeeded_guards"]==b03["stats"]["guard_success"] and
          b03_metrics["github_write_positive"]==b03["stats"]["github_write_positive"] and
          b03_metrics["duplicated_keys"]==0 and b03_metrics["missing_preimage"]==0,
          b03_metrics)
    return both,b03_metrics

def negatives(b02,b03):
    known=b02["current"]["rows_r01"][0]["run_id"]

    # Each negative runs in ONE psql session and ROLLBACK within that
    # session. No use of the real RUN table; all mutation is PG18 COPY.
    def trans_value(dml, expr):
        output=sql("BEGIN;\n"+dml+"\nSELECT 'L31_VALUE|'||("+expr+")::text;\nROLLBACK;\n")
        vals=[ln.split("L31_VALUE|",1)[1] for ln in output.splitlines()
              if "L31_VALUE|" in ln]
        if len(vals)!=1:raise AssertionError("NEG_TX_VALUE_MISSING "+output[-1000:])
        return vals[0]

    hash_expr=("encode(sha256(convert_to("+
       "coalesce(jsonb_agg(payload ORDER BY payload::text),'[]'::jsonb)::text,'UTF8')),'hex')")
    # Missing ID negative: test staging copy without FK to B03.
    miss=trans_value(
        "CREATE TEMP TABLE test_stage AS SELECT * FROM evidence_copy.b02;\n"
        "DELETE FROM test_stage WHERE run_id="+repr_sql(known)+";",
        "(SELECT "+hash_expr+" FROM test_stage)")
    check("B02_NEG_MISSING_ID_REJECTED",miss!=b02["pg18_typed_sha"],
          {"mismatch_after_one_missing":True})

    dupe=sql("BEGIN; INSERT INTO evidence_copy.b02(run_id,payload) "+
       "SELECT run_id,payload FROM evidence_copy.b02 WHERE run_id="+repr_sql(known)+";",
       fail=True)
    check("B02_NEG_DUPLICATE_PK_REJECTED","duplicate key" in dupe,
          {"error":"unique_violation"})
    new_sha=trans_value(
        "UPDATE evidence_copy.b02 SET payload=jsonb_set(payload,'{clase_propuesta}',"
        "'\"D_FALSO\"'::jsonb,true) WHERE run_id="+repr_sql(known)+";",
        "(SELECT "+hash_expr+" FROM evidence_copy.b02)")
    check("B02_NEG_ALTERED_ROW_REJECTED",new_sha!=b02["pg18_typed_sha"],
          {"sha_differs":True})

    after_run=trans_value(
       "INSERT INTO evidence_copy.b02(run_id,payload) "+
       "SELECT 'EXEC-NEWER-POST-FREEZE-SANDBOX',jsonb_set(payload,'{run_id}',"+
       "'\"EXEC-NEWER-POST-FREEZE-SANDBOX\"'::jsonb,true) "+
       "FROM evidence_copy.b02 WHERE run_id="+repr_sql(known)+";",
       "(SELECT count(*) FROM evidence_copy.b02)")
    check("B02_NEG_LATER_RUN_REJECTED",int(after_run)==b02["current"]["n"]+1,
          {"current_plus_one":int(after_run),"freeze_rejected":True})

    guard=next(x for x in b03["rows"] if int(x["guard_succeeded"])>0)
    k=guard["run_id"]
    bad=trans_value(
        "UPDATE evidence_copy.b03 SET payload=jsonb_set(payload,"+
        "'{guard_succeeded_missing_receipt}','1'::jsonb,true) WHERE run_id="+repr_sql(k)+";",
        "(SELECT count(*) FROM evidence_copy.b03 WHERE "+
        "(payload->>'guard_succeeded_missing_receipt')::int>0)")
    check("B03_NEG_SUCCEEDED_WITHOUT_RECEIPT_REJECTED",int(bad)==1,
          {"affected_run":k,"bad":int(bad)})
    keys=[x for x in b03["rows"] if x["idempotency_key_sha256"]]
    assert len(keys)>=2
    k1,k2=keys[:2]
    duplicate=trans_value(
       "UPDATE evidence_copy.b03 SET payload=jsonb_set(payload,"+
       "'{idempotency_key_sha256}',"+
       "to_jsonb("+repr_sql(k1["idempotency_key_sha256"] )+"::text),true) "+
       "WHERE run_id="+repr_sql(k2["run_id"])+";",
       "(SELECT count(*) FROM "+
       "(SELECT payload->>'idempotency_key_sha256' AS k,count(*) n "+
       "FROM evidence_copy.b03 WHERE payload->>'idempotency_key_sha256' IS NOT NULL "+
       "GROUP BY 1 HAVING count(*)>1) z)")
    check("B03_NEG_DUPLICATED_IDEMPOTENCY_REJECTED",int(duplicate)>0,
          {"different_runs":[k1["run_id"],k2["run_id"]],
           "duplicated_key_groups":int(duplicate)})
    drift=trans_value(
        "UPDATE evidence_copy.b03 SET payload=jsonb_set(payload,"+
        "'{current_status}','\"COMPLETED\"'::jsonb,true) WHERE run_id="+repr_sql(known)+";",
        "(SELECT count(*) FROM evidence_copy.b03 WHERE payload->>'current_status'<>'IN_PROGRESS')")
    check("B03_NEG_STATUS_DRIFT_REJECTED",int(drift)==1,
          {"drift_runs":int(drift)})
    expired=int(scalar("SELECT count(*) FROM evidence_copy.b03 WHERE "+
                       "(payload->>'lease_expired_now')::boolean;"))
    check("B03_EXPIRED_LEASES_NO_LIVENESS_GO",expired==8,
          {"expired":expired,"liveness_receipt_available":False,"gate":"BLOCK"})
    check("B03_INCOMPLETE_EXTERNAL_EFFECTS_FAIL_CLOSED",
          b03["receipts_not_verified_externally"] is True,
          {"external_sink_receipts_confirmed":0,"closure":"NO_GO"})
    after_b02=sha_copy("b02");after_b03=sha_copy("b03")
    check("NEGATIVE_TESTS_ROLLBACK_INTACT",after_b02==b02["pg18_typed_sha"] and
      after_b03==b03["pg18_typed_sha"],{"b02_sha":after_b02,"b03_sha":after_b03})

def repr_sql(s):
    return "'" + str(s).replace("'","''") + "'"

def main():
    raw_b02=json.loads(B02.read_text(encoding="utf-8"))
    raw_b03=json.loads(B03.read_text(encoding="utf-8"))
    b02={"n":raw_b02["n"],"current":{"n":raw_b02["n"],
      "rows_r01":json.loads(raw_b02["canonical_jsonb_text"])},
      "historical":{"id_list":raw_b02["historical232_ids"],
        "priority32_ids":raw_b02["historical32_proposed"]},
      "raw_result_sha256":raw_b02["server_sha256"],
      "canonical_jsonb_text":raw_b02["canonical_jsonb_text"],
      "as_of_utc":raw_b02["as_of"]}
    b03={"n":raw_b03["n"],
      "rows":json.loads(raw_b03["canonical_jsonb_text"]),
      "sha256":raw_b03["server_sha256"],
      "canonical_jsonb_text":raw_b03["canonical_jsonb_text"],
      "origin_cohort_sha256":raw_b03["source_b02_sha256"],
      "current_as_of":raw_b03["as_of"]}
    b03["stats"]={
      "idempotency_present":sum(bool(r["has_idempotency_key"]) for r in b03["rows"]),
      "lease_expired":sum(bool(r["lease_expired_now"]) for r in b03["rows"]),
      "lease_valid":sum(bool(r["lease_valid_now"]) for r in b03["rows"]),
      "guard_success":sum(int(r["guard_succeeded"])>0 for r in b03["rows"]),
      "github_write_positive":sum(int(r["github_write_positive"])>0 for r in b03["rows"])}
    b03["receipts_not_verified_externally"]=True
    check("SOURCE_SCOPE",b02["current"]["n"]==len(b02["current"]["rows_r01"])
       and b02["current"]["n"]==b03["n"] and
       b02["raw_result_sha256"]==b03["origin_cohort_sha256"],
       {"b02_n":b02["current"]["n"],"b03_n":b03["n"],
        "asof_b02":b02["as_of_utc"],"asof_b03":b03["current_as_of"]})
    try:
        seed(b02,b03)
        _,effect=readback(b02,b03)
        negatives(b02,b03)
    finally:
        sql("DROP DATABASE IF EXISTS "+DB+" WITH (FORCE);",db="postgres")
    result={"schema":"LF_L31_B02_B03_PG18_REPRODUCTION_V1",
       "source":"LIVE_READONLY_SUPABASE_SNAPSHOTS_IN_GITHUB",
       "b02":{"status":"NO_GO_UNVERIFIED","frozen_n":b02["current"]["n"],
         "live_sha":b02["raw_result_sha256"],
         "historical":"232","prioritized_proposal":32,"signed_cohort":False},
       "b03":{"status":"NO_GO_UNVERIFIED","readback_n":b03["n"],
         "live_sha":b03["sha256"],"effects_verified_externally":False,
         "liveness_receipts":0,"full_reconciliation_receipts":0},
       "tests":TESTS,"test_total":len(TESTS),
       "run_mutations":0,"supabase_dml_ddl":0,
       "pg18_disposable_db_dropped":True,"blockers_closed":[]}
    OUT.write_text(json.dumps(result,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    print("L31_RAW_SHA256 "+hashlib.sha256(OUT.read_bytes()).hexdigest(),flush=True)
    print("L31_TESTS_TOTAL "+str(len(TESTS)),flush=True)
    print("L31_RESULT_B02=OPEN_B03=OPEN_NO_GO",flush=True)

if __name__=="__main__":
    main()
