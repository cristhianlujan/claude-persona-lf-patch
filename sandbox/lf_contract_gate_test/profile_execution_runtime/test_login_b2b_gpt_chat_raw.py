#!/usr/bin/env python3
"""Canonical Product Director validator on exact un-attested ChatGPT RAW."""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
RAW=Path(__file__).parent/"evidence/login_b2b_gpt_native_ig949_20261030/raw_output.json"
VALIDATOR=ROOT/"profiles/product_director_lf/validators/validate_product_director_output.py"
EXPECTED_SHA="f89053c4123c6215b02f228934c69ae6e7dcd194fc76ff2ee0c82a9f53a41dfa"
ID="EXEC-PROFILE-GATE2-103C8E016D6F6B6ACABEA975"

def run_validator(obj):
    p=subprocess.run([sys.executable,str(VALIDATOR)],input=json.dumps(obj,ensure_ascii=False),text=True,capture_output=True)
    assert p.returncode==0, p.stderr
    return json.loads(p.stdout)

def main():
    data=RAW.read_bytes()
    assert hashlib.sha256(data).hexdigest()==EXPECTED_SHA, "RAW_SOURCE_DRIFT"
    raw=json.loads(data)
    trace=raw["traceability"]
    assert trace["execution_id"]==ID
    assert trace["profile_source_ref"].endswith("@64ea1c4a508e5cf1d874a2e258f37e406e8e4c24/profiles/product_director_lf/SKILL.md")
    assert trace["ig_run_id"]==949 and trace["screen_code"]=="B2B-AUTH-001"
    assert trace["runtime_provider_attested"] is False
    assert trace["real_execution_receipt"] is False
    assert trace["recorded_in_supabase"] is False
    assert trace["independent_semantic_review"]=="NOT_EXECUTED"
    result=run_validator(raw)
    assert result.get("valid") is True, "CANONICAL_VALIDATOR_FAILED "+json.dumps(result,ensure_ascii=False)[:1400]
    assert not result.get("blocking_codes"), result
    negative=json.loads(json.dumps(raw))
    negative["deliverable_created"]["product_decision"]["source_refs"]=[]
    denied=run_validator(negative)
    assert denied.get("valid") is False and denied.get("blocking_codes"),"NEGATIVE_AUTHORITY_NOT_REJECTED"
    print("PASS_PRODUCT_DIRECTOR_RAW_CANONICAL_VALIDATION")
    print("PROVIDER_ATTESTED_FALSE SEMANTIC_JUDGE_NOT_EXECUTED SUPABASE_NOT_RECORDED")

if __name__=="__main__":
    main()
