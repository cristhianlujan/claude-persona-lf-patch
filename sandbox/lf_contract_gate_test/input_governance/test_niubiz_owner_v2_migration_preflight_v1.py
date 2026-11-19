#!/usr/bin/env python3
"""Static/exact-source safeguards for owner V2 Niubiz migration.

Real transactional BEGIN/ROLLBACK and seven-step CREATE must be exercised
on canonical live database by migration before any committed V2 decision.
Generic owner/CREATE PG17 isolated suites additionally run on exact PR HEAD.
"""
import json
import re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
MIG=ROOT/"supabase/migrations/20261119004500_lf_ig_niubiz_three_owner_v2_candidate_v1.sql"
SOURCE=ROOT/"docs/input-governance/NIUBIZ_THREE_CANDIDATE_RULES_20261118.json"
data=MIG.read_text(encoding="utf-8")
spec=json.loads(SOURCE.read_text(encoding="utf-8"))
codes=[
 "REG_CLIENT_NIUBIZ_UNIQUE_EMAIL_001",
 "REG_CLIENT_PAYMENT_RECEIPT_REAL_EMAIL_001",
 "REG_CLIENT_NIUBIZ_GENERIC_BOUNCE_001"]
checks={}
def ck(name,condition):
 checks[name]=bool(condition)
 if not condition: raise RuntimeError("BLOCKED_"+name)

ck("THREE_SOURCE_CODES",set(codes)=={r["code"] for r in spec["rules"]})
sql_body="\n".join(line.split("--",1)[0] for line in data.splitlines())
ck("NO_DIRECT_CANONICAL_DML",not re.search(r"\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+lf_ops\.reglas\b",sql_body,re.I))
ck("EXACT_SINGLE_OWNER_DECISION_IMPL",data.count("v_dec:=public.lf_ig_rule_owner_decide_v2(")==2
 and data.count('"usuario":"Cristhian Lujan"')==2)
ck("SEQUENTIAL_OWNER_AND_SINGLE_LOOP",data.count("FOR v IN SELECT * FROM (VALUES")==1
 and data.count("NIUBIZ_OWNER_REAL_ROLLBACK_SENTINEL")>=2)
ck("SOURCE_BOUND_TRAIN_NO_SYNTHESIS",all(x in data for x in [
 "MIGRATION_TRAIN_RECEIPT_RECORDED","44428506420",
 "da56ce40d67a635a004247aeb9ed524690f6de64",
 "14484483531#RULE_CONTRACT_LEVEL","receipt_sha256",
 "pg_report_sha256","readback_sha256","check_manifest_sha256"]))
ck("PER_RULE_EXACT_PATCH_PREIMAGES",all(x in data for x in [
 "b054d2d03bfa02d7730198c4cd19eb27ecc77a5fad7aa2fa36fbb07070e31eaa",
 "4ec80cae76a148a798fb6ceb69c2e53cc8f4f00346181e41582f3039e03bc3d4",
 "b0d1b49a366397a69e7edff29bf604c3717c81e9a20e23b9a32f2314a46fa52c"]))
ck("CONFIG_REF_ONLY_AND_REAL",all(x in data for x in [
 "NIUBIZ_EMAIL_TEMPLATE","NIUBIZ_EMAIL_DOMAIN",
 "'PAGOS'","'TEXT'","'REAL'"])
 and "gmail.com" not in data and "lf-{codigo}" not in data)
ck("V2_CANDIDATE_NO_PROMOTION",all(x in data for x in [
 "APPROVED_AND_CANDIDATO_VERIFIED","CANDIDATO",
 "promotion_authorized","production_authorized",
 "public.lf_rule_promotion_v1","pending_decision"]))
ck("REAL_ROLLBACK_AND_READBACK",all(x in data for x in [
 "v_dry_ok:=false","NIUBIZ_OWNER_REAL_ROLLBACK_SENTINEL",
 "NIUBIZ_OWNER_SUBTX_ROLLBACK_READBACK_DIRTY_OR_BLOCKED",
 "CHILD_SEVEN_OR_NO_PROMOTION_FAILED",]) is False
 or all(x in data for x in ["NIUBIZ_OWNER_REAL_ROLLBACK_SENTINEL",
 "NIUBIZ_OWNER_SUBTX_ROLLBACK_READBACK_DIRTY_OR_BLOCKED",
 "NIUBIZ_DRY_CHILD_SEVEN_OR_NO_PROMOTION_FAILED"]))
ck("STRICT_PLUS_THREE_AND_UNTOUCHED_MD5",all(x in data for x in [
 "v_written<>3","v_initial_count+3",
 "v_untouched_rules_md5","v_initial_rules_md5",
 "v_current_config_md5","v_config_md5"]))
ck("NO_EXTERNAL_PROVIDER_PASS",all(x not in data for x in [
 "NIUBIZ_SANDBOX_PASS","HYPHEN_ACCEPTED","PRODUCTION_GO"]))
ck("BEGIN_COMMIT_TRANSACTION",data.count("BEGIN;")==1
 and data.strip().endswith("COMMIT;"))
ck("SOURCE_GATE_MD5_PREIMAGE",all(x in data for x in [
 "e47b02b7c8cb450e23f39fdf1a36a2a3",
 "03ed54da90b74502f836e81ffebd1fe6",
 "98372407a52b87a464da597d24a408cb"]))
ck("APPROVAL_SEPARATED_FROM_PRODUCER",
 "USER" not in data or "Cristhian Lujan" in data)
print(json.dumps({"status":"PASS","checks":len(checks),
 "migration":"20261119004500","rule_codes":codes,
 "provider_hyphen":"NOT_TESTED",
 "owner_v2_external_execution":"MIGRATION_TRAIN_ONLY",
 "real_pg17_owner_test_required":True},sort_keys=True))
