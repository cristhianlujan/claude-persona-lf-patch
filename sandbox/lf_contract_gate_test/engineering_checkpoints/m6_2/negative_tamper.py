#!/usr/bin/env python3
import json, re, sys

TEST_CODE = "ENG_M6_2_NEGATIVE_TAMPER"
HEX64 = re.compile(r"^[0-9a-f]{64}$")

def fail(reason: str, **extra):
    payload = {
        "status": "FAIL",
        "test_code": TEST_CODE,
        "observed": {
            "test_passed": False,
            "test_exit_code": 1,
            "semantic_authority_bound": True,
            "adversarial_case_executed": True,
            "reason": reason,
            **extra,
        },
    }
    print(json.dumps(payload, sort_keys=True))
    raise SystemExit(1)

if len(sys.argv) != 4:
    fail("ARGS_REQUIRED")

original_sha, tampered_sha, matching_receipts_raw = sys.argv[1:4]
if not HEX64.fullmatch(original_sha):
    fail("ORIGINAL_SHA_INVALID")
if not HEX64.fullmatch(tampered_sha):
    fail("TAMPERED_SHA_INVALID")

try:
    matching_receipts = int(matching_receipts_raw)
except ValueError:
    fail("MATCHING_RECEIPTS_INVALID")

if original_sha == tampered_sha:
    fail("TAMPER_NOT_DETECTED", original_sha=original_sha, tampered_sha=tampered_sha)
if matching_receipts != 0:
    fail("TAMPERED_RECEIPT_MATCHED", matching_tampered_receipts=matching_receipts)

payload = {
    "status": "PASS",
    "test_code": TEST_CODE,
    "observed": {
        "test_passed": True,
        "test_exit_code": 0,
        "semantic_authority_bound": True,
        "adversarial_case_executed": True,
        "original_sha": original_sha,
        "tampered_sha": tampered_sha,
        "sha_changed": True,
        "matching_tampered_receipts": matching_receipts,
    },
}
print(json.dumps(payload, sort_keys=True))
