#!/usr/bin/env python3
"""LF L15: ordered adoption + exact PRE-COMMIT transactional rollback evidence.
Never connect to Supabase: requires isolated PG18 and a disposable empty db.
Stage SQL is verbatim except that its outer BEGIN/COMMIT are controlled here.
Post-COMMIT downgrade is NOT proved and is an explicit PRODUCTION BLOCKER.
"""
from __future__ import annotations
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path
from collections import Counter

ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
BASE=ROOT/"sandbox/lf_contract_gate_test/rule_promotion_v1"
MIG=ROOT/"supabase/migrations"
STAGES=json.loads((HERE/"01_inventory.json").read_text(encoding="utf-8"))["stages"]
L13=HERE/"pinned_l13"
DB="lf_l15_adoption_rollback_pg18"
N=0
RESULTS=[]
L13_SHA256={
 "01_schema.sql":"3c955e96a3995716a9509ce1020ee75f6743527e6165eff8e8f92ec218f96cbf",
 "02_seed_synthetic.sql":"9378a6ee4d00751a00c2189edb8293bd887b4ebfb7c1ed5deb8d7607f73031ca",
 "03_test_cases.sql":"add2dff455df2bf37efae49833735a5d0dec63b5512883ac0f23b70468048370",
 "04_birth_expiry_tests.sql":"01f791b28a7701c004da9132e00d881b59eef707d5a56abd2fbdff20fd660bef",
}
GATE_EXPECTED_MD5={
 "apply":"86b0494984edf95cf0f9c0a0df67000b",
 "capture_record":"89cbfac4162dbc9f8ecca59f2c3ab4c3",
 "citation_verify":"773a62783baa5edbe967200cac66b8c3",
 "l8_guard":"522d12f0843be1da3c785cef3c0bf3fc",
}
L13_STATS_SQL="""SELECT 'L13_STATS|'||jsonb_build_object(
 'all', (SELECT count(*) FROM rule_quality_l13.sandbox_test_results),
 'passed', (SELECT count(*) FROM rule_quality_l13.sandbox_test_results WHERE status='PASS'),
 'lf_rules', (SELECT count(*) FROM rule_quality_l13.rules WHERE project_code='lf'),
 'lf_vigente', (SELECT count(*) FROM rule_quality_l13.rules WHERE project_code='lf' AND state='VIGENTE'),
 'lf_candidato', (SELECT count(*) FROM rule_quality_l13.rules WHERE project_code='lf' AND state='CANDIDATO')
)::text;"""
GATE_MD5_SQL="""SELECT 'GATE_MD5|'||jsonb_build_object(
 'apply',md5(pg_get_functiondef('public.lf_rule_promotion_apply_v1(text)'::regprocedure)),
 'capture_record',md5(pg_get_functiondef('public.lf_rule_promotion_citation_record_v1(text,text,text)'::regprocedure)),
 'citation_verify',md5(pg_get_functiondef('public.lf_rule_promotion_citation_verify_v1(text)'::regprocedure)),
 'l8_guard',md5(pg_get_functiondef('public.lf_rule_promotion_citation_scope_guard_v2()'::regprocedure))
)::text;"""

PGENV=os.environ.copy()
PGENV.update({"PGHOST":os.environ.get("PGHOST","127.0.0.1"),
              "PGPORT":os.environ.get("PGPORT","5432"),
              "PGUSER":os.environ.get("PGUSER","postgres"),
              "PGPASSWORD":os.environ.get("PGPASSWORD","postgres")})

def psql(s,db=DB,timeout=240):
    p=subprocess.run(["psql","-X","-q","-A","-t","-v","ON_ERROR_STOP=1","-d",db],
                     input=s,env=PGENV,text=True,capture_output=True,timeout=timeout)
    if p.returncode:
        raise AssertionError("PG18_L15_SQL_ERROR "+p.stderr[-3500:]+
                             "\nFIRST_COMMANDS="+s[:650])
    rows={}
    for line in p.stdout.splitlines():
        if "|" in line:
            k,v=line.split("|",1)
            try:rows[k]=json.loads(v)
            except (ValueError,TypeError):rows[k]=v
    return rows

def claim(code,valid,details):
    global N
    print("RAW_L15_"+code+" "+json.dumps(details,ensure_ascii=False,sort_keys=True,default=str),flush=True)
    if not valid:
        raise AssertionError("L15_FAIL_"+code+" "+json.dumps(details,ensure_ascii=False,sort_keys=True,default=str)[:5000])
    N+=1
    print("PASS_L15_"+code,flush=True)

# Catalog hash is built from OIDs, SQL definitions and ACLs. It intentionally
# excludes all L15 transient pg_temp data and pg_stat activity, but includes
# the user schemas, roles and grant-bearing objects touched by these 7 stages.
# Comparisons demand exact category equality, not just a single weak counter.
CATALOG_SQL=r"""
SELECT 'CAT|'||jsonb_build_object(
 'schemas',(SELECT md5(coalesce(jsonb_agg(jsonb_build_array(n.oid::text,n.nspname,
                     n.nspowner::text,n.nspacl::text) ORDER BY n.nspname)::text,'[]'))
    FROM pg_namespace n
    WHERE n.nspname IN ('public','lf_ops','programacion','extensions','rule_quality_l13')),
 'functions',(SELECT md5(coalesce(jsonb_agg(jsonb_build_array(p.oid::text,n.nspname,p.proname,
       pg_get_function_identity_arguments(p.oid),pg_get_functiondef(p.oid),
       p.proowner::text) ORDER BY n.nspname,p.proname,
       pg_get_function_identity_arguments(p.oid))::text,'[]'))
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname IN ('public','lf_ops','programacion','rule_quality_l13')),
 'tables',(SELECT md5(coalesce(jsonb_agg(jsonb_build_array(c.oid::text,n.nspname,
       c.relname,c.relkind,c.relowner::text,c.relpersistence,c.relrowsecurity,
       c.relforcerowsecurity) ORDER BY n.nspname,c.relname,c.relkind)::text,'[]'))
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN ('public','lf_ops','programacion','rule_quality_l13')),
 'columns',(SELECT md5(coalesce(jsonb_agg(jsonb_build_array(c.oid::text,a.attnum,
       a.attname,a.atttypid::text,a.atttypmod,a.attnotnull,a.attisdropped,
       a.attidentity,a.attgenerated,pg_get_expr(d.adbin,d.adrelid))
       ORDER BY n.nspname,c.relname,a.attnum)::text,'[]'))
    FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid
    JOIN pg_namespace n ON n.oid=c.relnamespace
    LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
    WHERE n.nspname IN ('public','lf_ops','programacion','rule_quality_l13') AND a.attnum>0),
 'constraints',(SELECT md5(coalesce(jsonb_agg(jsonb_build_array(k.oid::text,
       k.conname,k.conrelid::text,k.contype,pg_get_constraintdef(k.oid))
       ORDER BY k.conrelid,k.conname)::text,'[]'))
    FROM pg_constraint k JOIN pg_namespace n ON n.oid=k.connamespace
    WHERE n.nspname IN ('public','lf_ops','programacion','rule_quality_l13')),
 'indexes',(SELECT md5(coalesce(jsonb_agg(jsonb_build_array(i.indexrelid::text,
       pg_get_indexdef(i.indexrelid),i.indisvalid,i.indisunique)
       ORDER BY i.indexrelid)::text,'[]'))
    FROM pg_index i JOIN pg_class c ON c.oid=i.indrelid
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN ('public','lf_ops','programacion','rule_quality_l13')),
 'triggers',(SELECT md5(coalesce(jsonb_agg(jsonb_build_array(t.oid::text,
       t.tgname,pg_get_triggerdef(t.oid),t.tgenabled)
       ORDER BY t.tgrelid,t.tgname)::text,'[]'))
    FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN ('public','lf_ops','programacion','rule_quality_l13')),
 'roles',(SELECT md5(coalesce(jsonb_agg(jsonb_build_array(r.oid::text,
       r.rolname,r.rolcanlogin,r.rolinherit,r.rolsuper,r.rolcreatedb,
       r.rolcreaterole,r.rolbypassrls,r.rolconnlimit)
       ORDER BY r.rolname)::text,'[]'))
    FROM pg_roles r WHERE r.rolname IN (
       'anon','authenticated','service_role',
       'lf_rule_citation_source_custodian','lf_rule_citation_step70_bridge')),
 'grants',(SELECT md5(coalesce(jsonb_agg(jsonb_build_array(x.kind,x.name,x.acl)
       ORDER BY x.kind,x.name)::text,'[]')) FROM (
     SELECT 'FUNCTION' AS kind, n.nspname||'.'||p.proname||'('||
          pg_get_function_identity_arguments(p.oid)||')' AS name,
          p.proacl::text AS acl FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
          WHERE n.nspname IN ('public','lf_ops','programacion','rule_quality_l13')
     UNION ALL
     SELECT 'REL',n.nspname||'.'||c.relname,c.relacl::text
       FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
       WHERE n.nspname IN ('public','lf_ops','programacion','rule_quality_l13')
     UNION ALL
     SELECT 'SCHEMA',n.nspname,n.nspacl::text FROM pg_namespace n
       WHERE n.nspname IN ('public','lf_ops','programacion','rule_quality_l13','extensions')
     UNION ALL
     SELECT 'COLUMN',n.nspname||'.'||c.relname||'.'||a.attname,a.attacl::text
       FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid
       JOIN pg_namespace n ON n.oid=c.relnamespace
       WHERE n.nspname IN ('public','lf_ops','programacion','rule_quality_l13')
         AND a.attnum>0 AND a.attacl IS NOT NULL
     UNION ALL
     SELECT 'DEFAULT',n.nspname||':'||d.defaclrole::text||':'||d.defaclobjtype::text,
          d.defaclacl::text FROM pg_default_acl d JOIN pg_namespace n
          ON n.oid=d.defaclnamespace
       WHERE n.nspname IN ('public','lf_ops','programacion','rule_quality_l13')
   ) x)
)::text;
"""

def fingerprint():
    return psql(CATALOG_SQL)["CAT"]

def no_tx_outer(content,path):
    # No SQL logic is modified. Only outer transaction wrappers are removed,
    # so SAVEPOINT/ROLLBACK can govern otherwise committed migration files.
    begin=re.findall(r"(?m)^BEGIN\s*;\s*$",content)
    commit=re.findall(r"(?m)^COMMIT\s*;\s*$",content)
    assert len(begin)==len(commit)==1,(path,len(begin),len(commit))
    code=re.sub(r"(?m)^BEGIN\s*;\s*$","",content,count=1)
    code=re.sub(r"(?m)^COMMIT\s*;\s*$","",code,count=1)
    assert not re.search(r"(?m)^(?:BEGIN|COMMIT|ROLLBACK)\s*;\s*$",code),path
    return code

def get_migration(index):
    item=STAGES[index]
    raw=(ROOT/item["path"]).read_bytes()
    if index<6:
        git_blob=hashlib.sha1(b"blob "+str(len(raw)).encode()+b"\0"+raw).hexdigest()
        assert git_blob==item["git_blob_sha1"],(item["id"],git_blob,item["git_blob_sha1"])
        return no_tx_outer(raw.decode("utf-8"),item["path"])
    return "\n".join((L13/x).read_text(encoding="utf-8") for x in (
        "01_schema.sql","02_seed_synthetic.sql","03_test_cases.sql","04_birth_expiry_tests.sql"))

def metrics_sql(stage):
    return """SELECT 'METRICS|'||jsonb_build_object(
      'legacy_7',(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname IN
        ('lf_rule_promotion_request_v1','lf_rule_promotion_decide_v1',
         'lf_rule_promotion_apply_v1','lf_rule_promotion_guard_v1',
         'lf_rule_promotion_apply_batch_v1','lf_rule_promotion_decide_batch_v1',
         'lf_rule_promotion_report_v1')),
      'all_promotion_functions',(SELECT count(*) FROM pg_proc p JOIN pg_namespace n
         ON n.oid=p.pronamespace WHERE n.nspname='public'
         AND p.proname LIKE 'lf_rule_promotion%'),
      'citation_tables',(SELECT count(*) FROM pg_class c JOIN pg_namespace n
          ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r'
          AND c.relname IN('lf_rule_promotion_citation_source_v1',
                           'lf_rule_promotion_citation_capture_v1')),
      'citation_roles',(SELECT count(*) FROM pg_roles WHERE rolname IN
         ('lf_rule_citation_source_custodian','lf_rule_citation_step70_bridge')
         AND NOT rolcanlogin),
      'new_stage_schema',(SELECT count(*) FROM pg_namespace WHERE nspname='rule_quality_l13'),
      'l13_cases',CASE WHEN to_regclass('rule_quality_l13.sandbox_test_results') IS NULL
        THEN 0 ELSE (SELECT count(*) FROM rule_quality_l13.sandbox_test_results) END,
      'l13_rules',CASE WHEN to_regclass('rule_quality_l13.rules') IS NULL
        THEN 0 ELSE (SELECT count(*) FROM rule_quality_l13.rules) END,
      'current_apply_md5',md5(pg_get_functiondef(
          'public.lf_rule_promotion_apply_v1(text)'::regprocedure)),
      'legacy_guard_md5',md5(pg_get_functiondef(
          'public.lf_rule_promotion_guard_v1()'::regprocedure)),
      'legacy_report_md5',md5(pg_get_functiondef(
          'public.lf_rule_promotion_report_v1(integer,integer)'::regprocedure))
    )::text;""".replace(
"""'l13_cases',CASE WHEN to_regclass('rule_quality_l13.sandbox_test_results') IS NULL
        THEN 0 ELSE (SELECT count(*) FROM rule_quality_l13.sandbox_test_results) END,
      'l13_rules',CASE WHEN to_regclass('rule_quality_l13.rules') IS NULL
        THEN 0 ELSE (SELECT count(*) FROM rule_quality_l13.rules) END,""",
"""'l13_cases', (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='rule_quality_l13' AND c.relname='sandbox_test_results'),
      'l13_rules', (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='rule_quality_l13' AND c.relname='rules'),""")

def postcheck(stage,observed):
    return (
      observed["legacy_7"]==7
      and observed["legacy_guard_md5"]=="ee782e4bd0128c80ee13881899c0d74e"
      and (observed["citation_tables"]==2 if stage>=5 else observed["citation_tables"]==0)
      and (observed["citation_roles"]==2 if stage>=5 else observed["citation_roles"]==0)
      and (observed["new_stage_schema"]==1 if stage==7 else observed["new_stage_schema"]==0)
      and (observed["current_apply_md5"]=="86b0494984edf95cf0f9c0a0df67000b" if stage>=5 else True)
    )

def initial():
    psql(f"CREATE DATABASE {DB};",db="postgres")
    psql((BASE/"promotion_pg18_sandbox_fixture.sql").read_text(encoding="utf-8"))
    psql((BASE/"live_promotion_baseline_fixture.sql").read_text(encoding="utf-8"))
    psql("""CREATE TRIGGER trg_lf_rule_promotion_guard_v1
     BEFORE UPDATE OF estado ON lf_ops.reglas FOR EACH ROW
     EXECUTE FUNCTION public.lf_rule_promotion_guard_v1();""")
    psql((BASE/"live_currentness_authority_fixture.sql").read_text(encoding="utf-8"))
    psql((HERE/"00_legacy_7_fixture.sql").read_text(encoding="utf-8"))
    baseline=psql(metrics_sql(0))["METRICS"]
    observed={x:psql("SELECT 'MD5|'||md5(pg_get_functiondef('public."+
                             x+sig+"'::regprocedure));")["MD5"] for x,sig in [
        ("lf_rule_promotion_request_v1","(text,text,text)"),
        ("lf_rule_promotion_decide_v1","(text,text,text,text)"),
        ("lf_rule_promotion_apply_v1","(text)"),
        ("lf_rule_promotion_guard_v1","()")]}
    expected={"lf_rule_promotion_request_v1":"2fcac9f18b1581985af93639e475cd1a",
              "lf_rule_promotion_decide_v1":"16e45f40dad5cecc215a2f978be47728",
              "lf_rule_promotion_apply_v1":"d7fe763c999db6f6259b6b1e2bd69644",
              "lf_rule_promotion_guard_v1":"ee782e4bd0128c80ee13881899c0d74e"}
    claim("SIMULATED_LIVE_SEVEN_4_EXACT_3_STUBS",
      observed==expected and baseline["legacy_7"]==7
      and baseline["citation_tables"]==0 and baseline["citation_roles"]==0,
      {"md5":observed,"expected":expected,"legacy_count":baseline["legacy_7"],
       "stubs_only":["apply_batch","decide_batch","report"],"baseline":baseline})
    return fingerprint(),baseline

def main():
    hashes={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in L13.glob("*.sql")}
    claim("L13_PINNED_SOURCE_HASHES",
       hashes==L13_SHA256,
       {"sha256":hashes,"source_l13_branch":"lf/issue-3779-lote13-family-lifecycle-v1"})
    root_fingerprint,baseline=initial()
    for i,item in enumerate(STAGES):
        # Each stage is tested from its exact prerequisite state, never skipping.
        code="\n".join(get_migration(k) for k in range(i))
        target=get_migration(i)
        # Simpler stable readback across the transaction: emit catalog JSON
        # via replacing the sole CAT prefix in the catalog snapshot query.
        script=f"""BEGIN;
{code}
{CATALOG_SQL.replace("'CAT|'","'BEFORE|'")}
SAVEPOINT l15_target;
{target}
{metrics_sql(i+1)}
{GATE_MD5_SQL if i>=5 else ''}
{L13_STATS_SQL if i==6 else ''}
ROLLBACK TO SAVEPOINT l15_target;
{CATALOG_SQL.replace("'CAT|'","'AFTER|'")}
ROLLBACK;
{CATALOG_SQL.replace("'CAT|'","'ROOT|'")}
"""
        out=psql(script,timeout=270)
        post=out["METRICS"]
        l13_stats=out.get("L13_STATS")
        gate_hashes=out.get("GATE_MD5")
        stage_assert=postcheck(i+1,post)
        if i>=5:
            stage_assert=stage_assert and gate_hashes==GATE_EXPECTED_MD5
        if i==6:
            stage_assert=stage_assert and l13_stats=={
              "all":28,"passed":28,"lf_rules":578,"lf_vigente":412,"lf_candidato":166}
        claim("STAGE_"+item["id"]+"_ROLLBACK_CATALOG_IDENTICAL",
          out["BEFORE"]==out["AFTER"]
          and out["ROOT"]==root_fingerprint
          and stage_assert,
          {"stage":item["label"],"post":post,"gate_md5":gate_hashes,"l13_stats":l13_stats,"cat_before":out["BEFORE"],
           "cat_after":out["AFTER"],"root":out["ROOT"],
           "rollback":"SAVEPOINT_PRECOMMIT","identical":out["BEFORE"]==out["AFTER"]})
        RESULTS.append({"stage":item["id"],"path":item["path"],
          "catalog_before":out["BEFORE"],"catalog_after":out["AFTER"],
          "postcheck":post,"rollback_identical":True})
    full="\n".join(get_migration(k) for k in range(len(STAGES)))
    o=psql(f"""BEGIN;
{full}
{metrics_sql(len(STAGES))}
{L13_STATS_SQL}
{GATE_MD5_SQL}
{CATALOG_SQL.replace("'CAT|'","'FULL_IN_TX|'")}
ROLLBACK;
{CATALOG_SQL.replace("'CAT|'","'AFTER_FULL_ROLLBACK|'")}
{metrics_sql(0)}
""",timeout=400)
    positive=o["METRICS"] if False else o["FULL_IN_TX"]
    check=(o["AFTER_FULL_ROLLBACK"]==root_fingerprint
           and o["L13_STATS"]=={
              "all":28,"passed":28,"lf_rules":578,"lf_vigente":412,"lf_candidato":166}
           and o["GATE_MD5"]==GATE_EXPECTED_MD5
           and o["METRICS"]==baseline)
    claim("FULL_ORDERED_PACKAGE_ROLLBACK_IDENTICAL",check,
      {"catalog_during_full_package":positive,"catalog_after_full":o["AFTER_FULL_ROLLBACK"],
       "original_catalog":root_fingerprint,
       "stage_count":len(STAGES),"legacy_7":"coexist/overridden in same signatures","l13":o["L13_STATS"],"gate_md5":o["GATE_MD5"],"root_metrics":o["METRICS"]})
    claim("POSTCOMMIT_REVERSAL_NOT_CLAIMED",
      True,{"outcome":"BLOCKS_PRODUCTION","reason":"PostgreSQL DROP COLUMN leaves attisdropped catalog marks; not an in-place identical rollback",
            "recovery":"PITR / restore baseline physical backup to isolated clone, verified before production"})
    package={"version":"LF_L15_ADOPTION_ROLLBACK_READBACK_V1",
      "mode":"PG18_CLEAN_SANDBOX_PRECOMMIT_ONLY","all_rollback":True,
      "full_catalog_root":root_fingerprint,"stage_results":RESULTS,
      "full_package_catalog_after":o["AFTER_FULL_ROLLBACK"],
      "postcommit_undo":"NOT_TESTED_BLOCKS_PRODUCTION",
      "live_supabase_mutations":0,"migration_gate_modifications":0,
      "l14_touched":False}
    target=HERE/"l15_adoption_rollback_runtime.json"
    target.write_text(json.dumps(package,ensure_ascii=False,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    print("RAW_L15_REPORT "+json.dumps({"file":str(target),"sha256":hashlib.sha256(target.read_bytes()).hexdigest(),
        "stages":len(STAGES),"catalog_categories":len(root_fingerprint)},sort_keys=True),flush=True)
    print("LF_L15_PG18_PRECOMMIT_ROLLBACK_PASS checks="+str(N)+" stages="+str(len(STAGES)),flush=True)
    print("GLOBAL_PRODUCTION=NO_GO POSTCOMMIT_IN_PLACE_UNDO=NOT_PROVEN NO_LIVE_MUTATIONS=true",flush=True)
if __name__=="__main__":
    main()
