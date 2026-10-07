#!/usr/bin/env python3
"""FIXTURES checkpoint only: validate synthetic payload load and disposal, not runtime E2E."""
import json
from pathlib import Path
from contextlib import contextmanager

HERE=Path(__file__).resolve().parent
DATA=json.loads((HERE/"fixtures.json").read_text(encoding="utf-8"))
ALLOWED={"SOURCE_STALE","FULL","BLOCKED","UPSTREAM_MISSING"}

@contextmanager
def disposable_fixture(record):
    scratch={}
    try:
        for field in ("screen","sources","rules"):
            scratch[field]=json.loads(json.dumps(record[field]))
        yield scratch
    finally:
        scratch.clear()
        if scratch:
            raise AssertionError("FIXTURE_CLEANUP_FAILED")

def test():
    cases=DATA["cases"]
    assert DATA["schema_version"]=="IG_M7_10_E2E_FIXTURES_V1"
    assert len(cases)==4 and {case["mode"] for case in cases}==ALLOWED
    assert len({case["test_code"] for case in cases})==len(cases)
    for case in cases:
        assert case["history"]["new_fixture_only"] and case["history"]["historical_run_id"] is None
        assert case["screen"]["is_synthetic"] and case["cleanup"]["mode"]=="ROLLBACK"
        assert case["expected"] and case["rules"] and case["sources"]
        with disposable_fixture(case) as loaded:
            assert loaded["screen"]["identity"]["screen_code"]=="IG_E2E_SANDBOX_SCREEN"
            assert {s["source_kind"] for s in loaded["sources"]}=={"API_DATA_CONTRACT","RULE"}
            assert loaded["rules"][0]["expression"]["field"]=="debt_amount"
        assert loaded=={}
    print(json.dumps({"status":"PASS","test_code":"ENG_M7_10_FIXTURES_SMOKE","test_passed":True,"fixture_count":4,"cleanup_clean":True,"runtime_e2e_executed":False,"synthetic_receipts_created":False},sort_keys=True))

if __name__=="__main__":
    test()
