#!/usr/bin/env python3
"""LF #3779: immutable read-only SHA impact preimage + isolated PG17 DDL probe.

No production rule mutation, no new tables in LF, no pretend owner receipts.
Only this test's TEMP tables are created inside a rolled-back PG transaction.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parents[3]
ARTIFACT=ROOT/"sandbox/lf_contract_gate_test/rule_update_general_v1/rule_owner_schema_impact_preimage_20261111.json"
artifact=json.loads(ARTIFACT.read_text(encoding="utf-8"))
assert artifact["schema_version"]=="LF_RULE_OWNER_SCHEMA_IMPACT_PREIMAGE_V1"
assert artifact["assumptions"]=={
    "new_field":"owner_name text",
    "intermediate_value":None,
    "target_owner":"SUPER_ADMIN",
    "target_creator":"ChatGPT",
    "created_by_override_user_declared":True,
    "production_write_executed":False
}
rows=artifact["rules"]
screens=artifact["screens"]
assert artifact["counts"]=={
    "rules":578,"screen_shas":56,"links":6176,
    "linked_rule_ids":514,"unlinked_rules":64
}
assert len(rows)==578 and len(screens)==56
assert len({r["id"] for r in rows})==578
assert len({r["codigo"] for r in rows})==578
assert len({s["codigo"] for s in screens})==56
assert sum(s["links"] for s in screens)==6176
assert sum(r["estado"]=="VIGENTE" for r in rows)==412
assert sum(r["estado"]=="CANDIDATO" for r in rows)==166
fingerprint=hashlib.md5("\n".join(
    f'{r["id"]}:{r["codigo"]}' for r in sorted(rows,key=lambda x:x["id"])
).encode("utf-8")).hexdigest()
assert fingerprint==artifact["source_catalog_md5"]=="c758e1215c5fe5a11d34d42456a09664"
print("PASS_LIVE_578_RULE_PREIMAGE_FINGERPRINT",flush=True)
for label,items,expected in [("RULE",rows,578),("SCREEN",screens,56)]:
    for item in items:
        assert re.fullmatch(r"[0-9a-f]{64}",item["before_sha"])
        assert re.fullmatch(r"[0-9a-f]{64}",item["schema_only_sha"])
        assert re.fullmatch(r"[0-9a-f]{64}",item["final_sha"])
        assert item["before_sha"]!=item["schema_only_sha"]
        assert item["schema_only_sha"]!=item["final_sha"]
        assert item["before_sha"]!=item["final_sha"]
    assert len(items)==expected
    print(f"PASS_{label}_SHA_CHANGED_BY_NULL_SCHEMA_AND_FINAL_ADMIN_VALUES",flush=True)
assert artifact["impact_metrics"]=={
    "rule_schema_only_changes":578,
    "rule_final_changes":578,
    "screen_schema_only_changes":56,
    "screen_final_changes":56
}
assert all(s["links"]>0 for s in screens)
assert all(set(r)=={"id","codigo","estado","before_sha","schema_only_sha","final_sha"} for r in rows)
print("PASS_NO_RULE_CONTENT_EXPOSED_IN_PREIMAGE",flush=True)
print("PASS_SCREEN_LINEAGE_6176_LINKS_56_SCREENS",flush=True)

# Only in an isolated PG17 runner. Never execute SQL against LF.
if not os.environ.get("PGHOST"):
    raise RuntimeError("PG17_ISOLATED_ENVIRONMENT_REQUIRED")
script=r"""
\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE TEMP TABLE test_rule_impact(
 id int PRIMARY KEY,codigo text NOT NULL,estado text NOT NULL,
 created_by text,created_at timestamptz,updated_at timestamptz
);
CREATE TEMP TABLE test_screen_impact(code text,rule_id int);
INSERT INTO test_rule_impact(id,codigo,estado,created_by)
 VALUES(1,'RULE-ONE','VIGENTE','legacy-a'),(2,'RULE-TWO','CANDIDATO','legacy-b');
INSERT INTO test_screen_impact VALUES('SCREEN-ONE',1),('SCREEN-ONE',2);
SELECT 'BEFORE_RULE|'||
 encode(extensions.digest(convert_to((to_jsonb(r)-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex')
 FROM test_rule_impact r WHERE codigo='RULE-ONE';
SELECT 'BEFORE_SCREEN|'||
 encode(extensions.digest(convert_to(jsonb_agg(
 (to_jsonb(r)-'created_at'-'updated_at') ORDER BY r.codigo)::text,'UTF8'),'sha256'),'hex')
 FROM test_screen_impact t JOIN test_rule_impact r ON r.id=t.rule_id;
ALTER TABLE test_rule_impact ADD COLUMN owner_name text;
SELECT 'INTERIM_RULE|'||
 encode(extensions.digest(convert_to((to_jsonb(r)-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex')
 FROM test_rule_impact r WHERE codigo='RULE-ONE';
SELECT 'INTERIM_SCREEN|'||
 encode(extensions.digest(convert_to(jsonb_agg(
 (to_jsonb(r)-'created_at'-'updated_at') ORDER BY r.codigo)::text,'UTF8'),'sha256'),'hex')
 FROM test_screen_impact t JOIN test_rule_impact r ON r.id=t.rule_id;
UPDATE test_rule_impact SET owner_name='SUPER_ADMIN',created_by='ChatGPT';
SELECT 'FINAL_RULE|'||
 encode(extensions.digest(convert_to((to_jsonb(r)-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex')
 FROM test_rule_impact r WHERE codigo='RULE-ONE';
SELECT 'FINAL_SCREEN|'||
 encode(extensions.digest(convert_to(jsonb_agg(
 (to_jsonb(r)-'created_at'-'updated_at') ORDER BY r.codigo)::text,'UTF8'),'sha256'),'hex')
 FROM test_screen_impact t JOIN test_rule_impact r ON r.id=t.rule_id;
SELECT 'AFTER_STATUS|'||string_agg(codigo||':'||estado,',' ORDER BY codigo) FROM test_rule_impact;
ROLLBACK;
SELECT 'ROLLED_BACK|'||(to_regclass('pg_temp.test_rule_impact') IS NULL)::text;
"""
env=dict(os.environ)
env.setdefault("PGUSER","postgres")
env.setdefault("PGDATABASE","postgres")
p=subprocess.run(["psql","-X","-q","-A","-t","-v","ON_ERROR_STOP=1"],
                 input=script,env=env,text=True,capture_output=True,timeout=45)
if p.returncode:
    raise AssertionError("PG17_SCHEMA_IMPACT_PROBE_FAILED:"+p.stderr[-1600:])
observed={}
for line in p.stdout.splitlines():
    if "|" in line:
        k,v=line.strip().split("|",1)
        observed[k]=v
for kind in ["RULE","SCREEN"]:
    hashes=[observed[f"{stage}_{kind}"] for stage in ("BEFORE","INTERIM","FINAL")]
    assert len(set(hashes))==3
assert observed["AFTER_STATUS"]=="RULE-ONE:VIGENTE,RULE-TWO:CANDIDATO"
assert observed["ROLLED_BACK"]=="true"
print("PASS_PG17_NULL_COLUMN_CHANGES_WHOLE_ROW_AND_SCREEN_SHA",flush=True)
print("PASS_PG17_ADMIN_VALUES_ADD_SECOND_HASH_CHANGE",flush=True)
print("PASS_PG17_ORIGINAL_STATUSES_PRESERVED",flush=True)
print("PASS_PG17_DDL_AND_DML_ROLLED_BACK_WITHOUT_RESIDUE",flush=True)
print("LF_RULE_OWNER_SCHEMA_IMPACT_ISOLATED_PG17_PASS",flush=True)
