#!/usr/bin/env python3
"""Isolated positive/negative test of LF #3779 owner assignment migration.

No production database, no external writer, no synthetic human approvals.
Uses the exact frozen id/code scope of 578 original LF rules.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
DATA = ROOT / "sandbox/lf_contract_gate_test/rules_owner_super_admin_v1/rule_scope_preimage_20261110.json"
MIG = ROOT / "supabase/migrations/20261110230000_lf_rule_owner_super_admin_assignment_v1.sql"
data = json.loads(DATA.read_text(encoding="utf-8"))
records = data["rows"]
assert len(records) == data["count"] == 578
assert len({x["codigo"] for x in records}) == 578
fingerprint = hashlib.md5("\n".join(
    f'{x["id"]}:{x["codigo"]}' for x in records
).encode("utf-8")).hexdigest()
assert fingerprint == data["inventory_md5"] == "c758e1215c5fe5a11d34d42456a09664"

def psql(statement=None, filename=None, succeeds=True):
    cmd = ["psql", "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1"]
    if filename is not None:
        cmd.extend(["-f", str(filename)])
    else:
        cmd.extend(["-c", statement])
    env = dict(os.environ)
    env.setdefault("PGHOST", "127.0.0.1")
    env.setdefault("PGUSER", "postgres")
    env.setdefault("PGDATABASE", "postgres")
    p = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=50)
    if succeeds and p.returncode != 0:
        raise AssertionError(f"PSQL_FAILED: {p.stderr[-1400:]}")
    if not succeeds and p.returncode == 0:
        raise AssertionError("EXPECTED_SQL_BLOCK_NOT_RAISED")
    return p.stdout.strip(), p.stderr.strip()

def check(name, sql, expected):
    got, _ = psql(sql)
    if got != str(expected):
        raise AssertionError(f"FAIL_{name}: expected {expected!r}, observed {got!r}")
    print("PASS_" + name, flush=True)

def escape(value):
    return "'" + str(value).replace("'", "''") + "'"

psql("""
CREATE ROLE service_role; CREATE ROLE anon; CREATE ROLE authenticated;
CREATE SCHEMA lf_ops;
CREATE TABLE lf_ops.reglas (
 id integer PRIMARY KEY,
 codigo text NOT NULL UNIQUE,
 categoria text NOT NULL DEFAULT 'SECURITY',
 es_transversal boolean NOT NULL DEFAULT false,
 origen text NOT NULL DEFAULT 'FIXTURE_ONLY',
 created_by text,
 estado text NOT NULL DEFAULT 'CANDIDATO',
 created_at timestamptz DEFAULT now(),
 updated_at timestamptz DEFAULT now()
);
GRANT USAGE ON SCHEMA lf_ops TO service_role,anon,authenticated;
GRANT SELECT ON TABLE lf_ops.reglas TO service_role;
""")
values = ",\n".join(
    f"({int(x['id'])},{escape(x['codigo'])},{escape('Cristhian' if k%2 else 'ChatGPT')})"
    for k,x in enumerate(records)
)
psql("INSERT INTO lf_ops.reglas(id,codigo,created_by) VALUES\n"+values+";")
source_sql = "SELECT md5(string_agg(id::text||':'||codigo,E'\\n' ORDER BY id)) FROM lf_ops.reglas;"
check("FROZEN_SOURCE_FINGERPRINT", source_sql, fingerprint)
raw_checksum_query = ("SELECT md5(string_agg(to_jsonb(r)::text,E'\\n' ORDER BY r.id)) "
                      "FROM lf_ops.reglas r;")
before, _ = psql(raw_checksum_query)

# 1. Guard rejects a changed population before any DDL.
first_id = int(records[0]["id"])
psql(f"DELETE FROM lf_ops.reglas WHERE id={first_id};")
_, err = psql(filename=MIG, succeeds=False)
assert "BLOCK_LF_RULE_OWNER_PREIMAGE_DRIFT" in err, err
print("PASS_POPULATION_DRIFT_FAILS_CLOSED", flush=True)
check("POPULATION_DRIFT_NO_METADATA_TABLE",
    "SELECT to_regclass('lf_ops.reglas_owner_metadata_v1') IS NULL;", "t")
first_code = records[0]["codigo"]
psql(f"INSERT INTO lf_ops.reglas(id,codigo,created_by) "
     f"VALUES ({first_id},{escape(first_code)},'ChatGPT');")

# 2. Guard rejects a swapped code even with 578 records.
psql(f"UPDATE lf_ops.reglas SET codigo='CHANGED-UNAUTHORIZED' WHERE id={first_id};")
_, err = psql(filename=MIG, succeeds=False)
assert "BLOCK_LF_RULE_OWNER_PREIMAGE_DRIFT" in err, err
print("PASS_RULE_CODE_PREIMAGE_DRIFT_FAILS_CLOSED", flush=True)
psql(f"UPDATE lf_ops.reglas SET codigo={escape(first_code)} WHERE id={first_id};")
check("RESTORED_SOURCE_FINGERPRINT", source_sql, fingerprint)
before, _ = psql(raw_checksum_query)

# 3. Positive migration and exact metadata readback.
psql(filename=MIG)
check("BACKFILL_578",
 "SELECT count(*) FROM lf_ops.reglas_owner_metadata_v1;", 578)
check("ALL_OWNER_SUPER_ADMIN",
 "SELECT count(*) FROM lf_ops.reglas_owner_metadata_v1 "
 "WHERE owner_name='SUPER_ADMIN';", 578)
check("ALL_CREATOR_DECLARED_CHATGPT",
 "SELECT count(*) FROM lf_ops.reglas_owner_metadata_v1 "
 "WHERE declared_creator_agent='ChatGPT';", 578)
check("DECLARATION_NOT_AUDIT_ATTESTATION",
 "SELECT count(*) FROM lf_ops.reglas_owner_metadata_v1 "
 "WHERE declaration_basis='USER_DECLARATION_2026_11_10';", 578)
check("VIEW_ALL_578_ACCESSIBLE",
 "SELECT count(*) FROM lf_ops.v_reglas_owner_metadata_v1;", 578)
check("NO_MISSING_OWNER",
 "SELECT count(*) FROM lf_ops.reglas r LEFT JOIN "
 "lf_ops.reglas_owner_metadata_v1 m ON m.regla_id=r.id "
 "WHERE m.regla_id IS NULL;", 0)
check("NO_BUSINESS_APPROVAL_INFERRED",
 "SELECT count(*) FROM lf_ops.v_reglas_owner_metadata_v1 "
 "WHERE business_decision_approval_inferred;", 0)
check("RULE_OWNER_COLUMN_NOT_ADDED",
 "SELECT count(*) FROM information_schema.columns "
 "WHERE table_schema='lf_ops' AND table_name='reglas' "
 "AND column_name LIKE '%owner%';", 0)
check("ACTOR_LEGACY_CREATED_BY_PRESERVED",
 "SELECT count(*) FROM lf_ops.v_reglas_owner_metadata_v1 "
 "WHERE historical_created_by='Cristhian';",
 sum(k%2 for k in range(len(records))))
after, _ = psql(raw_checksum_query)
assert before == after, f"canonical_rule_source_SHA_changed {before} != {after}"
print("PASS_ALL_CANONICAL_RULE_SNAPSHOTS_UNCHANGED", flush=True)
check("ONLY_SERVICE_ROLE_CAN_READ_METADATA",
 "SELECT has_table_privilege('service_role',"
 "'lf_ops.reglas_owner_metadata_v1','SELECT');", "t")
check("ANON_METADATA_READ_DENIED",
 "SELECT has_table_privilege('anon',"
 "'lf_ops.reglas_owner_metadata_v1','SELECT');", "f")
check("AUTHENTICATED_METADATA_READ_DENIED",
 "SELECT has_table_privilege('authenticated',"
 "'lf_ops.reglas_owner_metadata_v1','SELECT');", "f")
check("SERVICE_ROLE_WRITES_NOT_GRANTED",
 "SELECT has_table_privilege('service_role',"
 "'lf_ops.reglas_owner_metadata_v1','UPDATE');", "f")

# 4. Re-applying a migration cannot silently change an existing assignment.
_, err = psql(filename=MIG, succeeds=False)
assert "BLOCK_LF_RULE_OWNER_METADATA_ALREADY_EXISTS" in err, err
print("PASS_NO_SILENT_REASSIGNMENT", flush=True)
check("FINAL_578_RECORDED",
 "SELECT count(*) FROM lf_ops.reglas_owner_metadata_v1;", 578)
print("LF_RULE_OWNER_SUPER_ADMIN_PG17_POSITIVE_NEGATIVE_PASS", flush=True)
