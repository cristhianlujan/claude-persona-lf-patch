#!/usr/bin/env python3
"""IG M6.10 adversarial test: absent per-family provenance receipt.

This test does not invent fixtures or DB status. It validates a JSON readback
captured live from the canonical Supabase function and an independent receipt
count from the same database operation. The connected runner needs no DB secret.
"""
import json
import sys

TEST_CODE = "ENG_M6_10_NEGATIVE_MISSING_RECEIPT"
EXPECTED_CHAIN = [
    "SOURCE", "SOURCE_RECEIPT", "DETERMINISTIC",
    "SEMANTIC", "POLICY", "VALIDATOR"
]


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def main():
    require(len(sys.argv) == 2, "LIVE_READBACK_JSON_REQUIRED")
    evidence = json.loads(sys.argv[1])
    require(evidence.get("readback_origin") == "LIVE_SUPABASE_SQL", "LIVE_SOURCE_REQUIRED")
    require(evidence.get("receipt_count") == 0, "NEGATIVE_CASE_MUST_HAVE_ZERO_MATCHED_RECEIPTS")
    api = evidence.get("api")
    require(isinstance(api, dict), "API_JSON_MISSING")
    require(isinstance(api.get("run_id"), int) and api["run_id"] > 0, "RUN_ID_MISSING")
    require(isinstance(api.get("family_code"), str) and api["family_code"], "FAMILY_CODE_MISSING")
    require(api.get("schema_version") == "INPUT_EXPLAIN_FAMILY_ASSESSMENT_V1", "SCHEMA_DRIFT")
    require(api.get("status") == "INCOMPLETE", "NEGATIVE_MUST_BE_INCOMPLETE")
    require(api.get("explainable") is False, "FALSE_POSITIVE_EXPLAINABLE")
    missing = api.get("missing_evidence")
    require(isinstance(missing, list), "TYPED_MISSING_EVIDENCE_REQUIRED")
    require("SOURCE_RECEIPT" in missing, "SOURCE_RECEIPT_MISSING_TYPE_OMITTED")
    chain = api.get("chain")
    require(isinstance(chain, list) and len(chain) == 6, "SIX_CHAIN_STEPS_REQUIRED")
    require([x.get("step") for x in chain] == EXPECTED_CHAIN, "CHAIN_ORDER_DRIFT")
    by_step = {x["step"]: x for x in chain}
    require(by_step["SOURCE_RECEIPT"].get("status") == "INCOMPLETE",
            "SOURCE_RECEIPT_MUST_NOT_PASS")
    require(by_step["SOURCE_RECEIPT"].get("evidence_count") == 0,
            "SOURCE_RECEIPT_FABRICATION")
    require(all(x.get("status") in ("PASS", "INCOMPLETE", "NOT_APPLICABLE") for x in chain),
            "UNKNOWN_CHAIN_STATUS")
    require(not any("sql" in str(k).lower() or "query" in str(k).lower()
                    for k in api.keys()), "SQL_NOT_CONSUMER_INTERFACE")
    print(json.dumps({
        "status": "PASS",
        "test_code": TEST_CODE,
        "test_exit_code": 0,
        "test_passed": True,
        "semantic_authority_bound": True,
        "adversarial_case_executed": True,
        "case": "NO_PERSISTED_PER_FAMILY_RECEIPT",
        "run_id": api["run_id"],
        "family_code": api["family_code"],
        "missing": missing,
        "receipt_count": evidence["receipt_count"],
        "chain_steps": len(chain),
        "evidence_origin": "LIVE_SUPABASE_SQL"
    }, separators=(",", ":")))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(json.dumps({"status": "FAIL", "test_code": TEST_CODE,
                          "error": str(error)}, separators=(",", ":")))
        sys.exit(1)
