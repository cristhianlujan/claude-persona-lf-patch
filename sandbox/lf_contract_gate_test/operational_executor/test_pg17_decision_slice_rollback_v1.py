#!/usr/bin/env python3
"""Real PostgreSQL 17 rollback test for the LF decision-catalogue slice.

Load exact DDL, SHA guards, and policy resolver from existing LF migrations;
then execute the exact candidate classification + PENDING_AUTHORITY segment
inside BEGIN/ROLLBACK. Never invent an ACTIVE human authority or credentials.
This is a dependency-slice test, NOT full LF-schema E2E or Train apply.
"""
from pathlib import Path
import os
import subprocess

root=Path(__file__).resolve().parents[3]
src=root/"supabase/migrations"
canonical=(src/"20261008072000_human_decision_policy_registry_v1.sql").read_text()
authority=(src/"20261008054500_human_decision_authority_receipt_verifier_v1.sql").read_text()
matches=list(src.glob("*_lf_operational_executor_lane_v1.sql"))
assert len(matches)==1, "BLOCK_OPERATIONAL_SOURCE_NOT_UNIQUE"
candidate=matches[0].read_text()

def take(text: str, start: str, end: str) -> str:
    a=text.index(start)
    b=text.index(end,a)
    assert b>a
    return text[a:b]

ddl=take(canonical,
         "create table if not exists private.lf_human_decision_classes_v1 (",
         "alter table private.lf_human_decision_classes_v1 enable row level security;")
sha_guards=take(canonical,
         "create or replace function private.fn_lf_human_decision_rule_sha_v1(",
         "insert into private.lf_human_decision_classes_v1(")
resolver=take(canonical,
         "create or replace function private.fn_lf_human_decision_resolve_policy_v1(",
         "create or replace function private.fn_lf_human_decision_",
         ) if False else None
# Exact source ends at its own first $function$; use a bounded slice.
a=canonical.index("create or replace function private.fn_lf_human_decision_resolve_policy_v1(")
b=canonical.index("$function$;",a)+len("$function$;")
resolver=canonical[a:b]
auth_table=take(authority,
    "create table if not exists private.lf_human_decision_authority_policies_v1 (",
    "alter table private.lf_human_decision_authority_policies_v1 enable row level security;")
decision=take(candidate,
    "DO $decision_preflight$",
    "INSERT INTO public.lf_operation_registry (")
assert decision.count("PENDING_AUTHORITY")>=2, "BLOCK_PENDING_AUTHORITY_MISSING"
assert "INSERT INTO private.lf_human_decision_authority_policies_v1" not in decision
assert "INSERT INTO private.lf_human_decision_receipts_v1" not in decision
assert "COMMIT;" not in decision, "BLOCK_DECISION_SLICE_CONTAINS_COMMIT"

env=dict(os.environ)
for k,v in (("PGHOST","localhost"),("PGPORT","5432"),
            ("PGUSER","postgres"),("PGDATABASE","postgres")):
    env.setdefault(k,v)
assert env.get("PGPASSWORD"),"BLOCK_EPHEMERAL_PG_PASSWORD_MISSING"

def psql(script: str):
    result=subprocess.run(["psql","-X","-v","ON_ERROR_STOP=1","-tA","--no-psqlrc"],
        input=script,text=True,capture_output=True,env=env,timeout=45)
    if result.returncode:
        raise AssertionError("POSTGRES17_LF_SLICE_FAILED:\n"+result.stderr[-2400:])
    return result.stdout

setup="""
CREATE SCHEMA private;
CREATE SCHEMA extensions;
CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
"""
psql(setup+ddl+sha_guards+auth_table+resolver+"""
INSERT INTO private.lf_human_decision_classes_v1
(decision_class,authority_domain,description,status,created_by_execution_id)
VALUES ('DATA_OPERATIONS','LF_DATA_OPERATIONS','canonical LF class',
        'ACTIVE','TEST_EXISTING_CANONICAL_CLASS');
""")

sql="""BEGIN;
"""+decision+"""
DO $assert$
DECLARE
  route jsonb;
  cnt int;
  blocked boolean:=false;
BEGIN
 SELECT count(*) INTO cnt
 FROM private.lf_human_decision_classification_rules_v1
 WHERE producer_code='LF_OPERATION_EXECUTOR'
   AND subject_type='OPERATIONAL_EXECUTION'
   AND status='ACTIVE' AND decision_class='DATA_OPERATIONS'
   AND rule_sha256=private.fn_lf_human_decision_rule_sha_v1(
        rule_code,producer_code,subject_type,attribute_name,attribute_value,
        decision_class,priority,status);
 IF cnt<>1 THEN RAISE EXCEPTION 'TEST_CANONICAL_CLASSIFICATION_OR_SHA_INVALID'; END IF;
 SELECT count(*) INTO cnt FROM private.lf_human_decision_route_policies_v1
 WHERE producer_code='LF_OPERATION_EXECUTOR'
   AND subject_type='OPERATIONAL_EXECUTION'
   AND status='PENDING_AUTHORITY'
   AND required_authority_ref IS NULL
   AND required_reviewer_role IS NULL
   AND policy_sha256=private.fn_lf_human_decision_route_policy_sha_v1(
     policy_code,decision_class,producer_code,subject_type,authority_domain,
     required_authority_ref,reviewer_role_mode,required_reviewer_role,
     allowed_actions_mode,static_allowed_actions,status,metadata);
 IF cnt<>1 THEN RAISE EXCEPTION 'TEST_PENDING_ROUTE_OR_SHA_INVALID'; END IF;
 route:=private.fn_lf_human_decision_resolve_policy_v1(
   'LF_OPERATION_EXECUTOR','OPERATIONAL_EXECUTION','{}'::jsonb);
 IF route->>'state' IS DISTINCT FROM 'BLOCKED'
    OR route->>'blocker_code' IS DISTINCT FROM 'DECISION_ROUTE_POLICY_NOT_ACTIVE'
 THEN RAISE EXCEPTION 'TEST_UNAUTHORIZED_OPERATIONAL_ROUTE_NOT_BLOCKED:%',route; END IF;
 BEGIN
   UPDATE private.lf_human_decision_route_policies_v1
      SET status='ACTIVE' WHERE producer_code='LF_OPERATION_EXECUTOR'
                               AND subject_type='OPERATIONAL_EXECUTION';
 EXCEPTION WHEN check_violation THEN blocked:=true;
 END;
 IF NOT blocked THEN RAISE EXCEPTION 'TEST_AUTHORITYLESS_ACTIVATION_ACCEPTED'; END IF;
 IF EXISTS(SELECT 1 FROM private.lf_human_decision_authority_policies_v1)
 THEN RAISE EXCEPTION 'TEST_AUTHORITY_WAS_CREATED'; END IF;
END $assert$;
ROLLBACK;
DO $postrollback$
BEGIN
 IF EXISTS(SELECT 1 FROM private.lf_human_decision_classification_rules_v1
           WHERE producer_code='LF_OPERATION_EXECUTOR')
    OR EXISTS(SELECT 1 FROM private.lf_human_decision_route_policies_v1
           WHERE producer_code='LF_OPERATION_EXECUTOR') THEN
     RAISE EXCEPTION 'TEST_DECISION_SLICE_ROLLBACK_FAILED';
 END IF;
END $postrollback$;
"""
psql(sql)
print("PASS_REAL_POSTGRES17_LF_DECISION_SLICE_ROLLBACK "
      "canonical_sha=true pending_authority_only=true "
      "authorityless_activation_blocked=true no_persistence=true")
